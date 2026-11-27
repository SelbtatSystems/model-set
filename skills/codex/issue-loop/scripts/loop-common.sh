# shellcheck shell=bash
# ──────────────────────────────────────────────────────────────
# Shared by build-loop.sh and merge-loop.sh (sourced, never run).
# This file is identical in the Claude and Codex trees; everything that differs
# between the two agents lives in loop-agent.sh next to it.
#
# issue-loop.sh does NOT source this file. Its copies of the same functions stay
# where they are, so the fallback runner cannot change when this file changes.
# Definitions and defaults only: sourcing it has no side effects (the queue tests
# source it on its own).
# ──────────────────────────────────────────────────────────────

# ---- config shared by both runners ----------------------------------------
CYCLE_MINUTES="${CYCLE_MINUTES:-30}"      # build loop: wait when nothing is startable; both: wait after a skipped cycle
MAIN_BRANCH="${MAIN_BRANCH:-main}"        # integration branch: PRs target it, merges land here
BASE_BRANCH="${BASE_BRANCH:-}"            # this worktree's own branch; empty = auto-detect HEAD
# Same LOG_DIR as issue-loop.sh on purpose: the worktree lock lives in it, and a shared
# lock path is what makes issue-loop.sh and these runners refuse each other in one worktree.
LOG_DIR="${LOG_DIR:-./issue-loop-logs}"
STOP_FILE="${STOP_FILE:-.issue-loop-stop}"  # touch it to stop THIS loop only
MAX_FAILS="${MAX_FAILS:-3}"               # build: consecutive failed cycles; merge: attempts per PR before parking
NET_MAX_CYCLES="${NET_MAX_CYCLES:-6}"     # cycles in a row with GitHub unreachable → stop (~3h at 30m)
GH_RETRIES="${GH_RETRIES:-5}"             # git fetch / gh attempts before declaring GitHub unreachable
GH_RETRY_BASE="${GH_RETRY_BASE:-15}"      # linear backoff seed: 15s, 30s, 45s, 60s → ~2.5min
AUTO_MIGRATE="${AUTO_MIGRATE:-1}"         # 1 = apply ledger-pending migrations; 0 = always stop for a human
PRETTY_OUTPUT="${PRETTY_OUTPUT:-1}"       # 1 = condensed trace on screen; 0 = raw agent stream
# One state directory per machine, shared by every build and merge loop. Tests point it at a
# temporary directory; nothing else should need to move it.
LOOP_STATE_DIR="${LOOP_STATE_DIR:-$HOME/.local/state/agcore}"
PR_QUEUE="$LOOP_STATE_DIR/pr-queue.tsv"        # queued_at  pr  branch  tracker  ticket(s)  worktree
PR_PARKED="$LOOP_STATE_DIR/pr-parked.tsv"      # the queue line + parked_at + reason
LOOP_METRICS="$LOOP_STATE_DIR/loop-metrics.tsv" # time  loop  worktree  event  pr/ticket  seconds
QUEUE_LOCK="$LOOP_STATE_DIR/.pr-queue.lock"     # guards pr-queue.tsv AND pr-parked.tsv together
METRICS_LOCK="$LOOP_STATE_DIR/.loop-metrics.lock"
LOCK_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/issue-loop"   # tracker + machine locks, same dir as issue-loop.sh

# ---- terminal messaging (same helpers and banners as issue-loop.sh) --------
if [ -t 1 ]; then
  R='\033[0m'; D='\033[2m'; B='\033[1m'
  BLU='\033[34m'; GRN='\033[32m'; YEL='\033[33m'; RED='\033[31m'; CYN='\033[36m'
else R=''; D=''; B=''; BLU=''; GRN=''; YEL=''; RED=''; CYN=''; fi
ts()     { date '+%Y-%m-%d %H:%M:%S'; }
utc_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log()    { printf "${D}[%s]${R} %b\n" "$(ts)" "$1"; }
banner() { printf "\n${B}${BLU}════════════════════════════════════════════════${R}\n${B}${BLU}  %b${R}\n${B}${BLU}════════════════════════════════════════════════${R}\n" "$1"; }
ok()   { printf "${GRN}✓ %b${R}\n" "$1"; }
warn() { printf "${YEL}⚠ %b${R}\n" "$1"; }
err()  { printf "${RED}✗ %b${R}\n" "$1"; }
step() { printf "${CYN}▸ %b${R}\n" "$1"; }

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

# Screen view: one line per action. The RAW stream still goes to the log file.
render() {
  if [ "$PRETTY_OUTPUT" = "1" ] && [ -f "$PRETTY_SCRIPT" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$PRETTY_SCRIPT"
  else
    cat
  fi
}

# ---- collision locks (shared with issue-loop.sh) ----------------------------
# The lock files are the SAME paths issue-loop.sh uses, so the runners refuse each other:
#   worktree lock — $LOG_DIR/loop.lock: two loops in one worktree fight over git, Docker and the DB
#   tracker  lock — one loop per ticket folder, whichever runner it is
# issue-loop.sh treats a lock as live only when its owner's command line contains
# "issue-loop.sh". Each new runner re-executes itself with that string in argv[0]
# (see the top of build-loop.sh), which is how issue-loop.sh refuses them without a change.
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
# Only the owner may release: a REFUSED start must never delete the running loop's lock.
release_lock() {
  local lock="${1:-}"
  [ -n "$lock" ] && [ -f "$lock" ] || return 0
  [ "$(head -1 "$lock" 2>/dev/null)" = "$$" ] && rm -f "$lock"
  return 0
}

# ---- GitHub ------------------------------------------------------------------
# A failed API call and a query that matched nothing both print nothing. Callers MUST tell
# the two apart: reading an outage as "no PR" or "not merged" is how a ledger loses work.
gh_retry() {
  local attempt=1 out rc
  while :; do
    # </dev/null: callers run this inside `while read` loops, and gh must not eat their input.
    out=$(gh "$@" </dev/null 2>>"$LOG_DIR/gh.log"); rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s' "$out"; return 0; fi
    if [ "$attempt" -ge "$GH_RETRIES" ]; then
      err "gh $1 $2 failed ${attempt}x (rc=$rc) — GitHub unreachable; see $LOG_DIR/gh.log"
      return "$rc"
    fi
    warn "gh $1 $2 failed (rc=$rc), attempt ${attempt}/${GH_RETRIES} — retrying in $((attempt*GH_RETRY_BASE))s"
    sleep $((attempt * GH_RETRY_BASE))
    attempt=$((attempt+1))
  done
}

# ---- git prep (same contract as issue-loop.sh) ------------------------------
# git fetch with a linear backoff (~2.5 min over GH_RETRIES attempts). One DNS blip used to
# stop a loop with GIT STATE NEEDS A HUMAN although nothing needed a human (wt3, 2026-11-27).
fetch_retry() {
  local attempt=1
  while :; do
    git fetch origin 2>>"$LOG_DIR/git.log" && return 0
    if [ "$attempt" -ge "$GH_RETRIES" ]; then
      err "git fetch failed ${attempt}x — GitHub unreachable; see $LOG_DIR/git.log"
      return 1
    fi
    warn "git fetch failed, attempt ${attempt}/${GH_RETRIES} — retrying in $((attempt*GH_RETRY_BASE))s"
    sleep $((attempt * GH_RETRY_BASE))
    attempt=$((attempt+1))
  done
}

tree_is_clean() { git diff --quiet && git diff --cached --quiet; }

# returns 1 = fatal (dirty / diverged / git failure); 2 = GitHub unreachable (skip the cycle)
prep_worktree() {
  step "Syncing worktree branch '${BASE_BRANCH}' with origin/${MAIN_BRANCH}…"
  if ! tree_is_clean; then
    err "working tree has uncommitted changes — refusing to touch it (no auto-discard)"
    return 1
  fi
  git switch "$BASE_BRANCH"  2>>"$LOG_DIR/git.log" || { err "switch to $BASE_BRANCH failed"; return 1; }
  fetch_retry || return 2
  git merge --ff-only "origin/${MAIN_BRANCH}" 2>>"$LOG_DIR/git.log" \
    || { err "cannot fast-forward ${BASE_BRANCH} to origin/${MAIN_BRANCH} (diverged?) — needs a human"; return 1; }
  ok "'${BASE_BRANCH}' up to date with origin/${MAIN_BRANCH}."
  return 0
}

# ---- migrations (copied from issue-loop.sh; same stop rules) ----------------
# The tracked runner is the sole authority for pending files, advisory locking, transactions
# and ledger writes. The loop only protects local dev data by handing a pending migration with
# destructive SQL to a human instead of auto-applying it.
DESTRUCTIVE_SQL='\bDROP[[:space:]]+(TABLE|COLUMN|SCHEMA|DATABASE|SEQUENCE|VIEW|TYPE|EXTENSION|ROLE|USER)\b|\bTRUNCATE\b|\bDELETE[[:space:]]+FROM\b|\bALTER[[:space:]]+COLUMN\b[^;]*\bTYPE\b|\bRENAME\b'
# Only the SQL that runs when the file is applied — comments and CREATE FUNCTION bodies
# removed (a function body runs when called, not at apply time). A DO block executes at once
# and stays in scope. Unbalanced dollar quoting exits 3, so the caller fails closed.
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

# An orphan is a migration the DB has applied but this checkout does not carry. Mid-flight
# that is normal: an agent applies a branch's migration, and the base branch lacks the file
# until the PR merges. Only an orphan no in-flight branch explains is real drift.
# inflight_branches is defined by each runner: the build loop's own queued and parked PRs,
# or, for the merge loop, every queued and parked PR (it checks all of them out).
# $1 = db:status output.  returns 0 = every orphan is explained
orphans_are_ours() {
  local orphans=() branches=() name branch found
  mapfile -t orphans < <(printf '%s\n' "$1" | sed -n 's/^  orphaned //p')
  [ "${#orphans[@]}" -gt 0 ] || return 0
  mapfile -t branches < <(inflight_branches | grep -v '^[[:space:]]*$' | sort -u)
  [ "${#branches[@]}" -gt 0 ] || {
    err "orphaned migration(s) with no queued or parked PR — nothing in flight explains them"
    return 1
  }
  for name in "${orphans[@]}"; do
    found=0
    for branch in "${branches[@]}"; do
      if git cat-file -e "origin/${branch}:db/migrations/${name}" 2>/dev/null \
        || git cat-file -e "${branch}:db/migrations/${name}" 2>/dev/null; then
        found=1; break
      fi
    done
    [ "$found" = 1 ] || {
      err "orphaned migration belongs to no queued or parked branch: $name"
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

  local orphan_count
  orphan_count=$(printf '%s\n' "$status_output" | grep -c '^  orphaned ')
  if [ "$orphan_count" -gt 0 ]; then
    orphans_are_ours "$status_output" || {
      err "the database records migrations absent from this checkout and from every queued branch — needs a human"
      return 2
    }
    warn "${orphan_count} orphaned migration(s) belong to queued branch(es) — expected until those PRs merge"
  fi

  local pending_migrations=() migration_name migration_path
  mapfile -t pending_migrations < <(printf '%s\n' "$status_output" | sed -n 's/^  pending  //p')
  if [ "${#pending_migrations[@]}" -eq 0 ]; then
    [ "$orphan_count" -gt 0 ] && {
      ok "no pending migrations; only queued branches' orphans remain"
      return 0
    }
    err "migration check failed but status listed no pending migrations — see $LOG_DIR/db.log"
    return 2
  fi

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
  # db:migrate refuses to write while the DB holds an orphan unless told; orphans_are_ours
  # already traced each one to an in-flight branch, which is what the flag stands for.
  local tolerate_orphans=0
  [ "$orphan_count" -gt 0 ] && tolerate_orphans=1
  if ! AGCORE_TOLERATE_ORPHANED_MIGRATIONS="$tolerate_orphans" \
       npm run db:migrate >>"$LOG_DIR/db.log" 2>&1; then
    err "ledger migration failed — see $LOG_DIR/db.log"
    return 2
  fi
  if ! npm run db:check >>"$LOG_DIR/db.log" 2>&1; then
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

# ---- shared state: PR queue, parked PRs, metrics -----------------------------
# Several loops write these files at once (two builders append, the merge loop removes), so
# every write takes the file's flock and replaces the file with a temp file + mv. Readers
# never lock: mv is atomic, so a reader sees the old file or the new one, never half of one.
# An in-place append (>>) from two processes can interleave or, with a rewrite in between,
# vanish — test_build_merge_loops.py runs two writers at once to prove no line is lost.
state_init() {
  mkdir -p "$LOOP_STATE_DIR" || return 1
  touch "$PR_QUEUE" "$PR_PARKED" "$LOOP_METRICS"
}

with_lock() {  # with_lock <lockfile> <command...>   (runs the command in a subshell)
  local lock="$1"; shift
  (
    flock -w 120 9 || { err "could not take ${lock} within 120s"; exit 1; }
    "$@"
  ) 9>>"$lock"
}

# Replace <file> with: its non-blank lines through <awk-program>, then optional extra lines.
# awk also restores a final newline a hand edit may have dropped.
_rewrite() {  # _rewrite <file> <awk-program> [awk -v assignment...] -- [extra line...]
  local file="$1" prog="$2" tmp; shift 2
  local -a vars=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do vars+=(-v "$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  tmp=$(mktemp "$(dirname "$file")/.$(basename "$file").XXXXXX") || return 1
  if { awk -F'\t' "${vars[@]}" "NF { $prog }" "$file" 2>/dev/null; [ "$#" -gt 0 ] && printf '%s\n' "$@"; true; } > "$tmp" \
     && mv -f "$tmp" "$file"; then
    return 0
  fi
  rm -f "$tmp"; return 1
}

_clean_field() { printf '%s' "$1" | tr '\t\n' '  '; }

# returns 0 = appended, 3 = that PR is already queued, 4 = it is parked (a person decides)
_queue_append_unlocked() {
  local pr="$1" line="$2"
  awk -F'\t' -v pr="$pr" '$2 == pr { found = 1 } END { exit !found }' "$PR_QUEUE" 2>/dev/null && return 3
  awk -F'\t' -v pr="$pr" '$2 == pr { found = 1 } END { exit !found }' "$PR_PARKED" 2>/dev/null && return 4
  _rewrite "$PR_QUEUE" 'print' -- "$line"
}
queue_append() {  # queue_append <pr> <branch> <tracker> <ticket(s)> <worktree>
  local line
  line="$(utc_now)	$1	$(_clean_field "$2")	$(_clean_field "$3")	$(_clean_field "${4:--}")	$(_clean_field "$5")"
  with_lock "$QUEUE_LOCK" _queue_append_unlocked "$1" "$line"
}

queue_remove() {  # queue_remove <pr>   — only the merge loop calls this
  with_lock "$QUEUE_LOCK" _rewrite "$PR_QUEUE" 'if ($2 != pr) print' "pr=$1"
}

# Park = append the queue line (plus when and why) to pr-parked.tsv, then drop it from the
# queue, under one lock. Parked first: a crash in between leaves the PR in both files, which
# is visible; the other order could leave it in neither.
_queue_park_unlocked() {
  local pr="$1" reason="$2" line
  line=$(awk -F'\t' -v pr="$pr" 'NF && $2 == pr { print; exit }' "$PR_QUEUE")
  [ -n "$line" ] || return 1
  _rewrite "$PR_PARKED" 'print' -- "${line}	$(utc_now)	${reason}" || return 1
  _rewrite "$PR_QUEUE" 'if ($2 != pr) print' "pr=$pr"
}
queue_park() {  # queue_park <pr> <reason>
  with_lock "$QUEUE_LOCK" _queue_park_unlocked "$1" "$(_clean_field "$2")"
}

parked_remove() {  # parked_remove <pr>
  with_lock "$QUEUE_LOCK" _rewrite "$PR_PARKED" 'if ($2 != pr) print' "pr=$1"
}

queue_lines()  { awk -F'\t' 'NF >= 6' "$PR_QUEUE" 2>/dev/null; }
parked_lines() { awk -F'\t' 'NF >= 6' "$PR_PARKED" 2>/dev/null; }

# One metrics line per event: time  loop  worktree  event  pr/ticket  seconds.
# LOOP_NAME is set by each runner (build:<tracker> or merge). A failed metrics write never
# stops a loop: the numbers are for the weekly report, not for any decision the loop makes.
metric() {  # metric <event> <ref> [seconds]
  local line
  line="$(utc_now)	$(_clean_field "$LOOP_NAME")	$(_clean_field "$REPO_ROOT")	$1	$(_clean_field "${2:--}")	${3:--}"
  with_lock "$METRICS_LOCK" _rewrite "$LOOP_METRICS" 'print' -- "$line" 2>/dev/null \
    || warn "could not write metrics line: $1 ${2:-}"
  return 0
}

# Idle = the loop is waiting with nothing to do: no startable ticket, or no mergeable PR.
IDLE_SINCE=""
idle_begin() {
  [ -n "$IDLE_SINCE" ] && return 0
  IDLE_SINCE=$(date +%s)
  metric idle_start -
}
idle_finish() {
  [ -n "$IDLE_SINCE" ] || return 0
  metric idle_end - $(( $(date +%s) - IDLE_SINCE ))
  IDLE_SINCE=""
}
