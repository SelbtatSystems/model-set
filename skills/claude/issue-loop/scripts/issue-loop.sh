#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# issue loop (ralph loop over ONE tracker folder):
#   each cycle: ff worktree to main → MERGE this loop's open PR → TRIAGE needs-triage →
#   BUILD next ready-for-agent ticket (do-issue) → wait
# all agents are claude; models are per-phase knobs (MAIN_MODEL builds, PR_MODEL merges).
# only branches this loop created are merged — parallel pipelines' PRs are never touched.
# stops on: folder finished (all done, or only human-owned tickets left → NEEDS-HUMAN.md),
#           a blocked PR, an unexpected state, touch .issue-loop-stop, Ctrl-C.
# usage: ~/.codex/skills/issue-loop/scripts/issue-loop.sh <tracker-folder>
# ──────────────────────────────────────────────────────────────
set -uo pipefail   # NOT -e: the loop decides what is fatal, line by line

TRACKER_DIR="${1:-}"

# All relative paths belong to the worktree root. Resolve it before LOG_DIR,
# Docker paths, locks, or tracker state are created so starting the loop from a
# subdirectory cannot silently create a second state directory or break Docker.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'issue-loop: not inside a git worktree\n' >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

# ---- config --------------------------------------------------------------
CYCLE_MINUTES="${CYCLE_MINUTES:-30}"      # wait between cycles (also CI settle time)
MAIN_BRANCH="${MAIN_BRANCH:-main}"        # integration branch: PRs target it, merges land here
BASE_BRANCH="${BASE_BRANCH:-}"            # this worktree's own branch; empty = auto-detect HEAD
LOG_DIR="${LOG_DIR:-./issue-loop-logs}"
STOP_FILE="${STOP_FILE:-.issue-loop-stop}"  # touch it to stop THIS loop only
MAX_FAILS="${MAX_FAILS:-3}"               # consecutive failed cycles → stop
AUTO_MIGRATE="${AUTO_MIGRATE:-1}"         # 1 = apply ledger-pending migrations; 0 = always stop for a human
MAIN_MODEL="${MAIN_MODEL:-fable}"         # build + triage agent model
PR_MODEL="${PR_MODEL:-opus}"              # merge agent model
# Both phases run on the second Claude account by default; pass an empty value to use the
# terminal's own account instead, e.g. MAIN_CONFIG_DIR= PR_CONFIG_DIR= issue-loop.sh <folder>
MAIN_CONFIG_DIR="${MAIN_CONFIG_DIR-$HOME/.claude-max-2}"  # CLAUDE_CONFIG_DIR for build/triage
PR_CONFIG_DIR="${PR_CONFIG_DIR-$HOME/.claude-max-2}"      # CLAUDE_CONFIG_DIR for merge
STATE_FILE="$LOG_DIR/pending-branches"    # branches this loop built, awaiting merge
PARKED_FILE="$LOG_DIR/parked-prs"         # PRs blocked at a gate: surfaced, not retried
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRETTY_SCRIPT="$SCRIPT_DIR/pretty-stream.py"
PRETTY_OUTPUT="${PRETTY_OUTPUT:-1}"       # 1 = condensed trace on screen; 0 = raw agent stream
WORKTREE_LOCK="$LOG_DIR/loop.lock"        # one loop per worktree
LOCK_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/issue-loop"
TRACKER_LOCK="$LOCK_HOME/$(printf '%s' "${TRACKER_DIR:-none}" | tr '/ ' '__').lock"  # one loop per tracker
mkdir -p "$LOG_DIR"; touch "$STATE_FILE" "$PARKED_FILE"
rm -f "$STOP_FILE"

# ---- terminal messaging --------------------------------------------------
if [ -t 1 ]; then
  R='\033[0m'; D='\033[2m'; B='\033[1m'
  BLU='\033[34m'; GRN='\033[32m'; YEL='\033[33m'; RED='\033[31m'; CYN='\033[36m'
else R=''; D=''; B=''; BLU=''; GRN=''; YEL=''; RED=''; CYN=''; fi
ts()     { date '+%Y-%m-%d %H:%M:%S'; }
log()    { printf "${D}[%s]${R} %b\n" "$(ts)" "$1"; }
banner() { printf "\n${B}${BLU}════════════════════════════════════════════════${R}\n${B}${BLU}  %b${R}\n${B}${BLU}════════════════════════════════════════════════${R}\n" "$1"; }
ok()   { printf "${GRN}✓ %b${R}\n" "$1"; }
warn() { printf "${YEL}⚠ %b${R}\n" "$1"; }
err()  { printf "${RED}✗ %b${R}\n" "$1"; }
step() { printf "${CYN}▸ %b${R}\n" "$1"; }

trap 'printf "\n"; warn "Ctrl-C — hard stop."; exit 130' INT
# Locks must not outlive the loop, however it ends (banner, Ctrl-C, crash).
trap 'release_lock "${WORKTREE_LOCK:-}"; release_lock "${TRACKER_LOCK:-}"' EXIT

check_stop() {
  if [ -f "$STOP_FILE" ]; then
    rm -f "$STOP_FILE"
    banner "STOP REQUESTED (touch $STOP_FILE) — exiting gracefully"
    exit 0
  fi
}
stop_loop() { banner "$1"; exit "${2:-0}"; }

countdown() {
  local secs="$1" label="$2"
  while [ "$secs" -gt 0 ]; do
    if [ -f "$STOP_FILE" ]; then printf "\r%*s\r" 60 ""; check_stop; fi
    printf "\r${D}[%s]${R} ${YEL}⏳ %s — %02d:%02d left${R}   " "$(ts)" "$label" $((secs/60)) $((secs%60))
    sleep 1; secs=$((secs-1))
  done
  printf "\r%*s\r" 60 ""
}

# Screen view: one line per action (tool + file, thinking, text). The RAW stream still goes to
# the log file, so nothing is lost. PRETTY_OUTPUT=0 (or no python3) falls back to the raw stream.
render() {
  if [ "$PRETTY_OUTPUT" = "1" ] && [ -f "$PRETTY_SCRIPT" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$PRETTY_SCRIPT"
  else
    cat
  fi
}

# The agent's FINAL message, extracted from the stream-json log. Sentinels are matched against
# THIS, never the raw stream: an agent that merely *narrates* the contract mid-run ("...else
# report <<<MERGE_BLOCKED #N reason>>>") would otherwise read as having emitted it. That false
# positive parked a healthy PR and stopped the docs loop on 2026-08-03. Empty output (no result
# line, no python3) means the caller falls back to the whole log — the old, lossy behaviour.
final_message() {  # final_message <stream-json-logfile>
  command -v python3 >/dev/null 2>&1 || { cat "$1"; return; }
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
out = ""
for line in open(sys.argv[1], errors="replace"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") == "result" and isinstance(d.get("result"), str):
        out = d["result"]
print(out)
PY
}

# claude spawn with per-phase model + optional per-phase account.
# stream-json gives structured events to render; --verbose is required for it under --print.
run_claude() {  # run_claude <model> <config-dir-or-empty> <logfile> <prompt>
  local model="$1" cfg="$2" logfile="$3" prompt="$4"
  if [ -n "$cfg" ]; then
    CLAUDE_CONFIG_DIR="$cfg" claude --model "$model" --permission-mode bypassPermissions \
      --output-format stream-json --verbose \
      --print "$prompt" </dev/null 2>&1 | tee "$logfile" | render
  else
    claude --model "$model" --permission-mode bypassPermissions \
      --output-format stream-json --verbose \
      --print "$prompt" </dev/null 2>&1 | tee "$logfile" | render
  fi
  return "${PIPESTATUS[0]}"
}

# ---- tracker-folder state (deterministic, script-side) --------------------
# grep, not rg: `rg` is often a shell-level alias and is NOT on a bash script's PATH.
# NEEDS-HUMAN.md is excluded so the loop never counts its own summary as a ticket.
list_role()  { grep -rlE "^\*\*Triage:\*\*[[:space:]]*$1" --include='*.md' \
                 --exclude='NEEDS-HUMAN.md' "$TRACKER_DIR" 2>/dev/null; }
count_role() { list_role "$1" | wc -l | tr -d ' '; }

# NEEDS-HUMAN.md is the standing surface for tickets waiting on a person.
# It also lists PRs parked at a review gate (see park_blocked_pr), so a blocked PR
# is visible without having to halt the whole folder for it.
write_needs_human() {
  local files parked=""
  files=$( { list_role "ready-for-human"; list_role "needs-info"; } | sort -u )
  [ -s "$PARKED_FILE" ] && parked=$(cat "$PARKED_FILE")
  if [ -z "$files" ] && [ -z "$parked" ]; then rm -f "$TRACKER_DIR/NEEDS-HUMAN.md"; return 0; fi
  {
    printf '# Needs a human\n\n'
    printf 'Written by issue-loop on %s — work the loop cannot take further.\n\n' "$(ts)"
    if [ -n "$parked" ]; then
      printf '## PRs parked at a review gate\n\n'
      printf 'The loop kept building other tickets. Each PR is still open with its branch intact;\n'
      printf 'read the gate comment on the PR, fix or close it, then re-add the branch to\n'
      printf '`%s` for the loop to merge.\n\n' "$STATE_FILE"
      printf '%s\n\n' "$parked"
    fi
    if [ -n "$files" ]; then
      printf '## Tickets waiting on a person\n\n'
      local f
      while IFS= read -r f; do
        printf -- '- **%s** — `%s`\n' "$(basename "$f")" \
          "$(grep -m1 -E '^\*\*Triage:\*\*' "$f" 2>/dev/null | head -1)"
      done <<< "$files"
    fi
  } > "$TRACKER_DIR/NEEDS-HUMAN.md"
  warn "needs a human: $(printf '%s' "$files" | grep -c .) ticket(s), $(printf '%s' "$parked" | grep -c .) parked PR(s) — $TRACKER_DIR/NEEDS-HUMAN.md"
}

# A PR blocked at a review gate is a decision for a person, but it is NOT a reason to
# stop building the other tickets in the folder. Park it: drop it from the merge ledger
# so the loop stops retrying it, record it for NEEDS-HUMAN.md, and carry on. The branch
# and the PR are left untouched — nothing is closed or discarded on an agent's say-so.
park_blocked_pr() {
  local pr="$1" branch="$2"
  rm -f "$LOG_DIR/merge-attempts-${pr}"
  forget_branch "$branch"
  grep -qF "#${pr} " "$PARKED_FILE" 2>/dev/null \
    || printf -- '- #%s `%s` — blocked at a gate on %s\n' "$pr" "$branch" "$(ts)" >> "$PARKED_FILE"
  warn "PR #${pr} parked (blocked at a gate) — continuing with the rest of the folder"
}

# ---- collision locks -------------------------------------------------------
# Two locks, because two different collisions hurt:
#   worktree lock — two loops in one worktree fight over git, Docker and the DB
#   tracker  lock — two loops on one ticket folder build the same tickets twice
# A lock whose owning pid is dead (or is no longer an issue-loop) is stale and gets taken over.
acquire_lock() {  # acquire_lock <lockfile> <description>
  local lock="$1" what="$2" owner
  mkdir -p "$(dirname "$lock")" 2>/dev/null
  if [ -f "$lock" ]; then
    owner=$(head -1 "$lock" 2>/dev/null)
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null \
       && tr '\0' ' ' < "/proc/$owner/cmdline" 2>/dev/null | grep -q "issue-loop.sh"; then
      err "another issue-loop (pid ${owner}) is already running ${what}:"
      sed 's/^/    /' "$lock"
      err "stop it first, or delete the lock if you know it is stale: ${lock}"
      return 1
    fi
    [ -n "$owner" ] && warn "clearing stale lock ${what} (pid ${owner} is gone)"
  fi
  printf '%s\n%s\n%s\n' "$$" "worktree: $(pwd)" "started: $(ts)" > "$lock"
  return 0
}
# Only the owner may release: a REFUSED start must never delete the running loop's lock
# (its exit trap fires too), and a lock taken over after ours went stale is not ours to remove.
release_lock() {
  local lock="${1:-}"
  [ -n "$lock" ] && [ -f "$lock" ] || return 0
  [ "$(head -1 "$lock" 2>/dev/null)" = "$$" ] && rm -f "$lock"
  return 0
}

# ---- pre-flight ------------------------------------------------------------
preflight() {
  step "Pre-flight checks…"
  [ -n "$TRACKER_DIR" ] || { err "usage: issue-loop.sh <tracker-folder>"; return 1; }
  [ -d "$TRACKER_DIR" ] || { err "tracker folder not found: $TRACKER_DIR"; return 1; }
  grep -rqE "^\*\*Triage:\*\*" --include='*.md' "$TRACKER_DIR" 2>/dev/null \
    || { err "no '**Triage:**' lines in $TRACKER_DIR — is this a tracker folder?"; return 1; }
  # Collision guards are LOCK FILES, not process scanning: pgrep both misses duplicates that
  # share a process group and false-positives on any shell whose command line mentions the path.
  acquire_lock "$WORKTREE_LOCK" "in this worktree" || return 1
  acquire_lock "$TRACKER_LOCK"  "on this tracker"  || { release_lock "$WORKTREE_LOCK"; return 1; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { err "not inside a git repo"; return 1; }
  if [ -z "$BASE_BRANCH" ]; then
    BASE_BRANCH=$(git symbolic-ref --short -q HEAD) \
      || { err "detached HEAD — checkout a branch for this worktree first"; return 1; }
  fi
  [ "$BASE_BRANCH" = "$MAIN_BRANCH" ] \
    && warn "BASE_BRANCH == ${MAIN_BRANCH}: running on main itself (OK only in the worktree that owns main)."
  command -v gh     >/dev/null 2>&1 || { err "gh not on PATH";     return 1; }
  command -v claude >/dev/null 2>&1 || { err "claude not on PATH"; return 1; }
  gh auth status >/dev/null 2>&1 || { err "gh not authenticated (run: gh auth login)"; return 1; }
  ok "Pre-flight passed."
}

# ---- git prep (same contract as the other loops) ---------------------------
# returns 1 = fatal (dirty / diverged / git failure)
prep_worktree() {
  step "Syncing worktree branch '${BASE_BRANCH}' with origin/${MAIN_BRANCH}…"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    err "working tree has uncommitted changes — refusing to touch it (no auto-discard)"
    return 1
  fi
  git switch "$BASE_BRANCH"  2>>"$LOG_DIR/git.log" || { err "switch to $BASE_BRANCH failed"; return 1; }
  git fetch origin           2>>"$LOG_DIR/git.log" || { err "fetch failed"; return 1; }
  git merge --ff-only "origin/${MAIN_BRANCH}" 2>>"$LOG_DIR/git.log" \
    || { err "cannot fast-forward ${BASE_BRANCH} to origin/${MAIN_BRANCH} (diverged?) — needs a human"; return 1; }
  ok "'${BASE_BRANCH}' up to date with origin/${MAIN_BRANCH}."
  return 0
}

# ---- migrations ------------------------------------------------------------
# Git path diffs are not migration state: pre-launch history is inert, and a
# directly executed SQL file would bypass the checksum ledger. The tracked
# runner is the sole authority for pending files, advisory locking, transactions,
# and ledger writes. The loop still protects local dev data by handing a pending
# migration with destructive SQL to a human instead of auto-applying it.
DESTRUCTIVE_SQL='\bDROP[[:space:]]+(TABLE|COLUMN|SCHEMA|DATABASE|SEQUENCE|VIEW|TYPE|EXTENSION|ROLE|USER)\b|\bTRUNCATE\b|\bDELETE[[:space:]]+FROM\b|\bALTER[[:space:]]+COLUMN\b[^;]*\bTYPE\b|\bRENAME\b'
# Only the SQL that runs when the file is applied — comments and CREATE FUNCTION
# bodies removed. A function body is a definition: its DELETE runs when something
# calls the function, never at apply time, so a migration that merely defines a
# retention function deletes nothing. A DO block is the opposite — it executes
# immediately — and deliberately stays in scope, as does everything after a body
# closes. Unbalanced dollar quoting exits 3 rather than silently swallowing the
# rest of the file, so the caller fails closed.
# (Stopped wt3 on 2026-08-06: app_purge_usage_events' DELETE FROM, in a migration
# whose executable half is five CREATE TABLEs.)
migration_executable_sql() {
  sed -e 's/--.*$//' "$1" | awk '
    {
      line = $0
      if (inbody) {
        i = index(line, tag)
        if (i == 0) next
        line = substr(line, i + length(tag)); inbody = 0
      }
      if (!pending && toupper(line) ~ /CREATE[ \t]+(OR[ \t]+REPLACE[ \t]+)?FUNCTION/) pending = 1
      if (pending && match(line, /\$[A-Za-z_0-9]*\$/)) {
        tag  = substr(line, RSTART, RLENGTH)
        head = substr(line, 1, RSTART - 1)
        rest = substr(line, RSTART + RLENGTH)
        pending = 0
        i = index(rest, tag)
        # a one-line body: keep whatever follows its closing tag
        if (i > 0) { print head " " substr(rest, i + length(tag)); next }
        inbody = 1; print head; next
      }
      if (pending && line ~ /;[ \t]*$/) pending = 0
      print line
    }
    END { if (inbody) exit 3 }
  '
}

migration_is_additive() {
  local sql
  sql=$(migration_executable_sql "$1") || return 1   # unbalanced $$ — cannot judge it
  ! printf '%s' "$sql" | tr '\n' ' ' | grep -qiE "$DESTRUCTIVE_SQL"
}

# An orphan is a migration the DB has applied but this checkout does not carry.
# Mid-flight that is normal rather than drift: the build agent applies its
# migration while on a unit branch, and the next cycle switches back to the base
# branch, where that file does not exist until the PR merges. Only an orphan we
# cannot trace to a branch this loop is still waiting on is real drift.
# $1 = db:status output.  returns 0 = every orphan is this loop's own work
orphans_are_ours() {
  local orphans=() name branch found
  mapfile -t orphans < <(printf '%s\n' "$1" | sed -n 's/^  orphaned //p')
  [ "${#orphans[@]}" -gt 0 ] || return 0
  [ -s "$STATE_FILE" ] || {
    err "orphaned migration(s) with an empty ledger — nothing this loop built explains them"
    return 1
  }
  for name in "${orphans[@]}"; do
    found=0
    while IFS= read -r branch; do
      [ -n "$branch" ] || continue
      # The unit branch is pushed before it reaches the ledger, so origin/ is the
      # reliable copy; the local ref is checked too in case a push is still pending.
      if git cat-file -e "origin/${branch}:db/migrations/${name}" 2>/dev/null \
        || git cat-file -e "${branch}:db/migrations/${name}" 2>/dev/null; then
        found=1; break
      fi
    done < "$STATE_FILE"
    [ "$found" = 1 ] || {
      err "orphaned migration belongs to no branch this loop is waiting on: $name"
      return 1
    }
  done
  return 0
}

# returns 0 = current/applied, 2 = needs a human
sync_database() {
  step "Checking this worktree's migration ledger…"
  if npm run db:check >>"$LOG_DIR/db.log" 2>&1; then
    ok "database migration ledger is current"
    return 0
  fi

  local status_output
  status_output=$(npm run db:status 2>&1)
  local status_rc=$?
  printf '%s\n' "$status_output" | tee -a "$LOG_DIR/db.log"
  [ "$status_rc" -eq 0 ] || {
    err "cannot read database migration status — see $LOG_DIR/db.log"
    return 2
  }

  if printf '%s\n' "$status_output" | grep -q '^Baseline launch-v1: missing$'; then
    warn "launch-v1 baseline is missing — reconcile drift, then run: npm run db:baseline"
    return 2
  fi

  # Classify orphans before anything else. db:check fails on them, but this
  # loop's own unmerged migration is not a reason to stop: it is the state the
  # loop puts itself in every time it builds one, and the merge phase below is
  # what clears it.
  local orphan_count
  orphan_count=$(printf '%s\n' "$status_output" | grep -c '^  orphaned ')
  if [ "$orphan_count" -gt 0 ]; then
    orphans_are_ours "$status_output" || {
      err "the database records migrations absent from this checkout and from every branch in the ledger — needs a human"
      return 2
    }
    warn "${orphan_count} orphaned migration(s) belong to this loop's unmerged branch(es) — expected until those PRs merge"
  fi

  local pending_migrations=() migration_name migration_path
  mapfile -t pending_migrations < <(printf '%s\n' "$status_output" | sed -n 's/^  pending  //p')
  if [ "${#pending_migrations[@]}" -eq 0 ]; then
    [ "$orphan_count" -gt 0 ] && {
      ok "no pending migrations; only this loop's own unmerged orphans remain"
      return 0
    }
    err "migration check failed but status listed no pending migrations — see $LOG_DIR/db.log"
    return 2
  fi

  # Nothing pending leaves AUTO_MIGRATE nothing to gate, so this sits below the
  # early return above rather than in front of it.
  [ "$AUTO_MIGRATE" = "1" ] || {
    warn "AUTO_MIGRATE=0 — run npm run db:migrate, then npm run db:check"
    return 2
  }
  for migration_name in "${pending_migrations[@]}"; do
    [[ "$migration_name" =~ ^[0-9]{8}_[a-z0-9_]+\.sql$ ]] || {
      err "unexpected pending migration name: $migration_name"
      return 2
    }
    migration_path="db/migrations/$migration_name"
    [ -f "$migration_path" ] || {
      err "pending migration is not a top-level file: $migration_path"
      return 2
    }
    migration_is_additive "$migration_path" || {
      warn "pending migration may alter local dev data: $migration_path"
      return 2
    }
  done

  step "Applying ledger-pending migrations to this worktree's DB…"
  # db:migrate refuses to write while the DB holds any orphan, so tolerating one above is not
  # enough on its own — it has to be told. orphans_are_ours already traced every orphan to a
  # branch this loop is waiting on, and that proof is what the flag stands for; the tool prints
  # each one it applies over. Without it the loop cannot absorb a migration another pipeline
  # merged into main until its own PR lands, which it can never reach, because this function
  # gates the cycle that would merge it. That deadlock stopped wt3 on 2026-08-05.
  local tolerate_orphans=0
  [ "$orphan_count" -gt 0 ] && tolerate_orphans=1
  if ! AGCORE_TOLERATE_ORPHANED_MIGRATIONS="$tolerate_orphans" \
       npm run db:migrate >>"$LOG_DIR/db.log" 2>&1; then
    err "ledger migration failed — see $LOG_DIR/db.log"
    return 2
  fi
  if ! npm run db:check >>"$LOG_DIR/db.log" 2>&1; then
    # A tolerated orphan still fails db:check, so re-read status and prove
    # nothing new appeared rather than trusting the pre-migration classification.
    status_output=$(npm run db:status 2>&1)
    printf '%s\n' "$status_output" | tee -a "$LOG_DIR/db.log"
    if printf '%s\n' "$status_output" | grep -q '^  pending  ' || ! orphans_are_ours "$status_output"; then
      err "database ledger is still not current after migration — see $LOG_DIR/db.log"
      return 2
    fi
  fi
  ok "ledger-pending migrations applied and verified"
  return 0
}

# ---- PR ownership ledger ---------------------------------------------------
# This loop merges ONLY branches recorded here, so a concurrent pipeline's PR
# (docs loop, your own work, another worktree) is never touched.
open_pr_branches() {
  gh pr list --state open --base "$MAIN_BRANCH" --json headRefName \
    --jq '.[].headRefName' 2>>"$LOG_DIR/gh.log" | sort
}
record_branch() {
  local b="$1"
  [ -n "$b" ] || return 0
  grep -qFx "$b" "$STATE_FILE" && return 0
  echo "$b" >> "$STATE_FILE"; log "recorded pending branch: $b"
}
# Branch names this worktree checked out, from line $1 of its private HEAD reflog onward
# (pass 0 for "the whole history"). Detached-HEAD hashes and the base branch are dropped.
visited_branches() {
  local from="${1:-0}" reflog
  reflog=$(git rev-parse --git-path logs/HEAD)
  [ -r "$reflog" ] || return 0
  tail -n "+$((from + 1))" "$reflog" 2>/dev/null \
    | sed -n 's/.*checkout: moving from .* to \(.*\)$/\1/p' \
    | grep -vFx "$BASE_BRANCH" | grep -Ev '^[0-9a-f]{7,40}$' | grep -Ev '^(origin|upstream)/' \
    | grep -v '^$' | sort -u
}
# Rewrite via temp + mv: never truncate the ledger in place, and leave no blank line behind
# (a stray newline would keep the file "non-empty" and re-enter the drain loop forever).
forget_branch() {
  local b="$1" tmp="${STATE_FILE}.tmp"
  grep -vFx "$b" "$STATE_FILE" > "$tmp" 2>/dev/null
  mv "$tmp" "$STATE_FILE"
}

# ---- merge phase: drain PRs on branches THIS loop built --------------------
# returns 0 = nothing left pending, 1 = agent failure, 3 = migration needs a human.
# A PR blocked at a gate is NOT an outcome here: it gets parked and the loop continues.
drain_pending() {
  [ -s "$STATE_FILE" ] || return 0
  # Snapshot the ledger into an array first: the body rewrites $STATE_FILE, and reading a file
  # through an open fd while truncating it skips or garbles later lines.
  local branches=() branch pr had_unknown=0
  mapfile -t branches < "$STATE_FILE"
  for branch in "${branches[@]}"; do
    [ -n "$branch" ] || continue
    pr=$(gh pr list --state open --base "$MAIN_BRANCH" --head "$branch" \
           --json number --jq '.[0].number' 2>>"$LOG_DIR/gh.log")
    if [ -z "$pr" ] || [ "$pr" = "null" ]; then
      log "branch ${branch}: no open PR (merged or closed) — dropping from state"
      forget_branch "$branch"
      continue
    fi
    local logfile="$LOG_DIR/merge-$(date +%Y%m%d-%H%M%S).log"
    # Attempt count per PR. A first attempt runs the full workflow; a retry means a previous
    # agent already reviewed this PR and stopped without merging (its usual failure is treating
    # /security-review's report as the deliverable). Re-running the whole review costs $1.50-$3
    # and re-derives what is already on record, so the retry prompt says so explicitly.
    local attempts_file="$LOG_DIR/merge-attempts-${pr}"
    local attempt=$(( $(cat "$attempts_file" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$attempt" > "$attempts_file"

    local prompt="/do-pr auto #${pr}"
    if [ "$attempt" -gt 1 ]; then
      prompt="/do-pr auto #${pr} — RETRY (attempt ${attempt}). A previous run already reviewed \
this PR and ended without merging it and without a sentinel; its review found nothing blocking. \
Do NOT repeat the full review. Confirm the state yourself (gh pr view / gh pr checks --watch), \
and if every check is green and the PR is mergeable, merge it and emit the sentinel. If you find \
a real blocker, comment it on the PR and emit <<<MERGE_BLOCKED #${pr} reason>>>. End with exactly \
one sentinel — a summary without one is a failed run."
      warn "retrying #${pr} (attempt ${attempt}) — skipping the full re-review"
    fi
    step "Launching claude (${PR_MODEL}) → /do-pr auto #${pr} (branch ${branch}, attempt ${attempt}) …"
    log "streaming below + → ${D}$logfile${R}"
    run_claude "$PR_MODEL" "$PR_CONFIG_DIR" "$logfile" "$prompt"
    local rc=$?
    # Ground truth first: GitHub cannot lie about whether the PR merged; sentinels are only
    # consulted for the not-merged outcomes (models decorate or omit them).
    local prstate; prstate=$(gh pr view "$pr" --json state --jq .state 2>>"$LOG_DIR/gh.log")
    if [ "$prstate" = "MERGED" ]; then
      ok "Merged PR #${pr} (verified on GitHub)."
      rm -f "$attempts_file"
      forget_branch "$branch"
      prep_worktree || return 1
      sync_database || return 3
    elif final_message "$logfile" | grep -qF "<<<MERGE_BLOCKED"; then
      err "do-pr blocked PR #${pr} — see its PR comment."
      park_blocked_pr "$pr" "$branch"
    else
      # One PR in an unknown state must NOT strand the ones queued behind it: the branch
      # stays in the ledger and is retried next cycle, but the rest of the queue still
      # drains now. Returning here let a single early-exiting agent block every other
      # merge this loop had ready (observed 2026-08-01: three PRs stacked up behind one).
      err "do-pr ended with no sentinel for #${pr} (rc=$rc) — unknown state; continuing with the rest"
      had_unknown=1
      continue
    fi
  done
  # Report the unknown outcome only after the whole queue has drained, so the caller's
  # retry accounting is unchanged while the other merges still got their chance.
  [ "$had_unknown" -eq 1 ] && return 1
  return 0
}

# ---- triage phase -----------------------------------------------------------
run_triage() {
  local logfile="$LOG_DIR/triage-$(date +%Y%m%d-%H%M%S).log"
  step "Launching claude (${MAIN_MODEL}) → /triage over ${TRACKER_DIR} …"
  log "streaming below + → ${D}$logfile${R}"
  run_claude "$MAIN_MODEL" "$MAIN_CONFIG_DIR" "$logfile" \
    "/triage Triage every needs-triage ticket in ${TRACKER_DIR} — that folder only. \
Autonomous run, never prompt: when a ticket's requirements are met and it is buildable by an \
agent, flip it to ready-for-agent; when they are not, set ready-for-human (or needs-info) and \
append a one-line dated reason to the ticket's Comments. Change nothing outside that folder."
  local rc=$?
  [ "$rc" -ne 0 ] && { err "triage agent exited rc=$rc"; return 1; }
  ok "triage pass finished."
  return 0
}

# ---- build phase --------------------------------------------------------------
# returns 0 = progress (PR opened or a ticket closed), 1 = agent failure, 4 = no progress
run_build() {
  local logfile="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
  local before_ready before_pending REFLOG reflog_before
  before_ready=$(count_role "ready-for-agent")
  before_pending=$(grep -c . "$STATE_FILE" 2>/dev/null || true)
  # This worktree's private HEAD reflog. No other loop can write to it, so it is proof of what
  # THIS worktree checked out — unlike a time window over `gh pr list`, which is contaminated by
  # every concurrent loop in the repo. See the ownership fallback below.
  REFLOG=$(git rev-parse --git-path logs/HEAD)
  reflog_before=$(wc -l < "$REFLOG" 2>/dev/null || echo 0)
  step "Launching claude (${MAIN_MODEL}) → /do-issue in ${TRACKER_DIR} …"
  log "streaming below + → ${D}$logfile${R}"
  # "lowest-numbered with satisfied blockers" keeps the QA slice (blocked by everything) last,
  # and lets follow-up issues filed by QA be picked up on later cycles.
  run_claude "$MAIN_MODEL" "$MAIN_CONFIG_DIR" "$logfile" \
    "/do-issue Work ${TRACKER_DIR} — that folder ONLY, ignore every other tracker. \
Pick the ticket yourself: the lowest-numbered ready-for-agent ticket whose '**Blocked by:**' \
entries are all done. If the ticket you would otherwise pick is blocked, do NOT stop — follow its \
blocker chain and build the BLOCKING ticket instead (the deepest one that is itself unblocked and \
ready-for-agent), so the chain clears from the bottom up. Build it end-to-end, opening a PR \
against ${MAIN_BRANCH} when the local gate is green. Any new issue you need to file belongs in \
that same folder. Only if EVERY ready-for-agent ticket is blocked by something unfinished: change \
nothing and say so."
  local rc=$?
  # Ownership ledger. Primary signal: the branch the agent left HEAD on.
  local cur; cur=$(git symbolic-ref --short -q HEAD)
  if [ -n "$cur" ] && [ "$cur" != "$BASE_BRANCH" ]; then
    record_branch "$cur"
  else
    # Fallback: the agent pushed and switched back, so HEAD tells us nothing. Ask this worktree's
    # own reflog which branches IT visited during the build and adopt every one that still has an
    # open PR. A concurrent loop's PR can never appear here, so unlike the old "exactly one new PR
    # in the time window" rule this neither swallows another loop's work nor strands our own when
    # two loops happen to open a PR in the same window (that is how #802 and #806 were orphaned).
    local visited open_now b adopted=0
    visited=$(visited_branches "$reflog_before")
    open_now=$(open_pr_branches)
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      if printf '%s\n' "$open_now" | grep -qFx "$b"; then
        record_branch "$b"; adopted=$((adopted+1))
        warn "agent left HEAD on ${BASE_BRANCH}; adopted ${b} from this worktree's reflog"
      fi
    done <<< "$visited"
    if [ "$adopted" -eq 0 ] && [ -n "$visited" ]; then
      warn "agent visited branches with no open PR — nothing to merge: $(tr '\n' ' ' <<< "$visited")"
    fi
  fi
  [ "$rc" -ne 0 ] && { err "build agent exited rc=$rc"; return 1; }
  # The agent says the queue is dry. Trust it over our own grep: the two disagree whenever a
  # ticket's Triage line moved during the run, and scoring that as a failure burns MAX_FAILS
  # cycles and then exits on the wrong banner instead of finishing the tracker cleanly.
  if final_message "$logfile" | grep -qF '<<<NO_OPEN_ISSUES>>>'; then
    log "agent reports no open issues it can take"
    return 5
  fi
  # Progress is measured, not claimed: either a new PR branch exists, or a ticket left
  # ready-for-agent. Without this, a refusal ("all blockers open") would cycle forever.
  local after_ready after_pending
  after_ready=$(count_role "ready-for-agent")
  after_pending=$(grep -c . "$STATE_FILE" 2>/dev/null || true)
  if [ "${after_pending:-0}" -gt "${before_pending:-0}" ] || [ "$after_ready" -lt "$before_ready" ]; then
    ok "build finished."
    return 0
  fi
  warn "build opened no PR and closed no ticket"
  return 4
}

# ---- terminal path: the tracker has no agent-workable ticket left -------------
# Never exits while a PR this worktree built is still open: the ledger is topped up from the
# reflog first, so an ownership miss earlier in the run cannot strand a PR at the finish line.
finish_tracker() {
  local b open_now swept=0 drc n_human n_parked
  open_now=$(open_pr_branches)
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if printf '%s\n' "$open_now" | grep -qFx "$b" && ! grep -qFx "$b" "$STATE_FILE" 2>/dev/null; then
      record_branch "$b"; swept=$((swept+1))
      warn "final sweep: ${b} was built here and is still open — merging before we stop"
    fi
  done <<< "$(visited_branches "$RUN_REFLOG_START")"
  [ "$swept" -gt 0 ] && log "final sweep adopted ${swept} orphaned PR branch(es)"

  drain_pending; drc=$?
  [ "$drc" -eq 1 ] && stop_loop "FINAL MERGE IN UNKNOWN STATE — see $LOG_DIR." 1
  [ "$drc" -eq 3 ] && stop_loop "MIGRATION MERGED — apply it to this worktree's DB, then restart the loop" 0
  # drain_pending parks a blocked PR rather than merging it, so re-check: anything still pending
  # is a PR we own and could not land. Say so instead of claiming the folder is done.
  if [ -s "$STATE_FILE" ]; then
    stop_loop "FOLDER FINISHED BUT PR(S) UNMERGED — still pending: $(tr '\n' ' ' < "$STATE_FILE") — see $LOG_DIR" 1
  fi
  write_needs_human
  n_human=$(( $(count_role "ready-for-human") + $(count_role "needs-info") ))
  n_parked=$(grep -c . "$PARKED_FILE" 2>/dev/null || true)
  if [ "$n_human" -gt 0 ] || [ "${n_parked:-0}" -gt 0 ]; then
    stop_loop "FOLDER FINISHED FOR AGENTS — ${n_human} ticket(s) need a human, ${n_parked:-0} PR(s) parked at a gate: ${TRACKER_DIR}/NEEDS-HUMAN.md" 2
  fi
  stop_loop "ALL ISSUES DONE — ${TRACKER_DIR} fully worked, including follow-ups" 0
}

# ──────────────────────────────────────────────────────────────
preflight || stop_loop "PRE-FLIGHT FAILED — fix the above and restart" 1

cycle=0
fails=0
# Where this run starts in the worktree's HEAD reflog. The final sweep looks only at branches
# visited after this point: sweeping the whole history would adopt long-dead branches this
# worktree once checked out, and auto-merge one if somebody else has a PR open on it.
RUN_REFLOG_START=$(wc -l < "$(git rev-parse --git-path logs/HEAD)" 2>/dev/null || echo 0)
banner "ISSUE LOOP STARTING — ${TRACKER_DIR}"
log "worktree: ${B}$(pwd)${R}"   # printed loudly: starting in the wrong worktree is easy to miss
log "cycle=${CYCLE_MINUTES}m  base=${BASE_BRANCH}  main=${MAIN_BRANCH}"
log "models: build/triage=${MAIN_MODEL}  merge=${PR_MODEL}"
log "accounts: build/triage=${MAIN_CONFIG_DIR:-terminal default}  merge=${PR_CONFIG_DIR:-terminal default}"
log "stop gracefully: ${B}touch ${STOP_FILE}${R}"

while :; do
  check_stop
  cycle=$((cycle+1))
  banner "CYCLE $cycle  —  $(ts)"

  prep_worktree || stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
  sync_database \
    || stop_loop "DATABASE MIGRATION STATE NEEDS A HUMAN — see $LOG_DIR/db.log, then restart the loop" 0

  # Phase 1: merge whatever this loop built earlier
  drain_pending; drc=$?
  [ "$drc" -eq 3 ] && stop_loop "MIGRATION MERGED — apply it to this worktree's DB, then restart the loop" 0
  if [ "$drc" -eq 1 ]; then
    # Inconclusive merge attempt (agent ended without merging or declaring blocked) —
    # the PR is still open on GitHub; retry next cycle instead of dying.
    fails=$((fails+1))
    warn "merge inconclusive — retry ${fails}/${MAX_FAILS} next cycle"
    [ "$fails" -ge "$MAX_FAILS" ] && stop_loop "REPEATED INCONCLUSIVE MERGES — see $LOG_DIR. Human review." 1
    banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
    countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
    continue
  fi

  check_stop

  # Phase 2: folder state decides what happens.
  # Building comes FIRST — triage only runs when there is nothing left to build, so work starts
  # immediately and needs-triage tickets are converted when the ready queue actually runs dry.
  n_ready=$(count_role "ready-for-agent")
  n_triage=$(count_role "needs-triage")
  if [ "$n_ready" -eq 0 ] && [ "$n_triage" -gt 0 ]; then
    log "nothing ready to build; ${n_triage} ticket(s) need triage"
    run_triage || { fails=$((fails+1)); warn "triage failure ${fails}/${MAX_FAILS}"; }
    n_ready=$(count_role "ready-for-agent")   # triage may have just released work
  fi
  write_needs_human

  # One open PR at a time, always ours first. Phase 1 already tried to merge the ledger; a branch
  # still in it merged neither now nor earlier and was not parked (park_blocked_pr forgets the
  # branch), so building a second unit would stack an unmerged PR behind an unmerged PR.
  if [ -s "$STATE_FILE" ]; then
    fails=$((fails+1))
    warn "not starting a new issue ${fails}/${MAX_FAILS} — our PR is still unmerged: $(tr '\n' ' ' < "$STATE_FILE")"
    [ "$fails" -ge "$MAX_FAILS" ] && stop_loop "PR STUCK — $(tr '\n' ' ' < "$STATE_FILE") would not merge over ${MAX_FAILS} cycles; see $LOG_DIR" 1
    banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
    countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
    continue
  fi

  if [ "$n_ready" -gt 0 ]; then
    log "${n_ready} ticket(s) ready for an agent (incl. any follow-ups filed by QA)"
    run_build; brc=$?
    case "$brc" in
      0) fails=0 ;;
      5) log "tracker has nothing left an agent can take — finishing up"
         finish_tracker ;;
      4) fails=$((fails+1))
         warn "no progress ${fails}/${MAX_FAILS} — every remaining ready-for-agent ticket may still have an open blocker" ;;
      *) fails=$((fails+1)); warn "build failure ${fails}/${MAX_FAILS} — continuing" ;;
    esac
  elif [ "$(count_role 'needs-triage')" -eq 0 ]; then
    finish_tracker
  fi

  [ "$fails" -ge "$MAX_FAILS" ] && stop_loop "TOO MANY CONSECUTIVE FAILURES — stopping" 1

  check_stop
  banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
  countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
done
