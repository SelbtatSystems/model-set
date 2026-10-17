#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# two-phase Codex docs loop (ralph loop for the docs-loop skill):
#   each cycle: fast-forward THIS worktree's branch to main → MERGE any open PR → DOCUMENT next unit → wait
#   GPT-5.6 Sol runs $docs-loop (write docs); GPT-5.6 Luna runs $do-pr auto (review+merge)
# invariant: at most ONE open documentation/* PR exists at any time (other PRs are ignored).
# stops on: queue complete, an unexpected state, ./scripts/stop-loop, Ctrl-C. A PR blocked at a
# gate is parked and a GitHub outage is retried; each only stops the loop past its own limit.
# sentinel contract lives in the docs-loop SKILL.md — change a sentinel there → change it here too.
# run from the repo root: ~/.codex/skills/docs-loop/scripts/docs-loop.sh
# ──────────────────────────────────────────────────────────────
set -uo pipefail   # NOT -e: the loop decides what is fatal, line by line

# ---- config --------------------------------------------------------------
CYCLE_MINUTES="${CYCLE_MINUTES:-15}"      # wait between cycles (also CI settle time)
MAIN_BRANCH="${MAIN_BRANCH:-main}"        # integration branch: PRs target it, merges land here
BASE_BRANCH="${BASE_BRANCH:-}"            # this worktree's own branch to run on; empty = auto-detect current HEAD
STOP_FILE="${STOP_FILE:-.loop-stop}"      # ./scripts/stop-loop drops this flag
WIKI_DIR="${WIKI_DIR:-./memory}"          # docs coverage queue lives here
# Logs live OUTSIDE the vault and OUTSIDE the repo, in machine-local XDG state. A raw agent
# run stream captures API keys, Postgres DSNs with passwords and JWTs; the vault syncs to the
# owner's server and the repo is public, so neither may hold them. State survives a worktree
# being deleted and can never be committed or synced by accident.
LOG_DIR="${LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agcore/docs-loop-logs}"
KEEP_RUNS="${KEEP_RUNS:-20}"              # prune run logs older than the newest N (0 = keep all)
MAX_DOCS_FAILS="${MAX_DOCS_FAILS:-3}"     # consecutive failed runs (no sentinel, inconclusive merge) → stop
# A blocked unit is a finished run: the agent marked the row and the next unit is different work.
# It gets its own, higher limit — three unrelated blocks (a flaky test twice, a missing fixture)
# stopped the loop on 2026-10-04 while it was otherwise publishing every cycle.
MAX_DOCS_BLOCKED="${MAX_DOCS_BLOCKED:-5}" # consecutive DOCS_BLOCKED units → stop
# One failed fetch is a network blip, not a git problem: a DNS failure on 2026-09-30 stopped the
# loop for 9 h as "GIT STATE NEEDS A HUMAN". Retry next cycle; stop only on a lasting outage.
MAX_NET_FAILS="${MAX_NET_FAILS:-6}"       # consecutive cycles GitHub was unreachable → stop
# A PR blocked at a gate stays open for a human and the loop moves on (as the issue loop does).
# The limit stops a repo-wide outage — e.g. the CI billing block of 2026-09-30 — from piling up
# one parked PR per cycle. Delete a line from PARKED_FILE to hand that PR back to the loop.
MAX_PARKED="${MAX_PARKED:-3}"             # open parked PRs → stop
PARKED_FILE="${PARKED_FILE:-$LOG_DIR/parked-prs}"
MAX_CYCLES="${MAX_CYCLES:-0}"             # 0 = unlimited; positive value stops after that many complete cycles
AUTO_MIGRATE="${AUTO_MIGRATE:-1}"         # 1 = apply purely additive migrations here; 0 = always stop for a human
PULLED_MIGRATIONS=()                      # filled by prep_worktree each sync
DOCS_MODEL="${DOCS_MODEL:-gpt-5.6-sol}"   # codex model for the writer
DOCS_EFFORT="${DOCS_EFFORT:-medium}"      # codex reasoning effort
MERGE_MODEL="${MERGE_MODEL:-gpt-5.6-luna}" # codex model for the independent /do-pr merge pass
MERGE_EFFORT="${MERGE_EFFORT:-high}"      # smaller merge model gets the deeper reasoning pass
PUBLISHED_TOKEN="<<<DOCS_PUBLISHED"       # prefix: skill appends " <unit-id>>>>"
BLOCKED_TOKEN="<<<DOCS_BLOCKED"           # prefix: skill appends " <unit-id> <reason>>>>"
COMPLETE_TOKEN="<<<DOCS_COMPLETE>>>"      # queue AND backlog empty and nothing left to critique
CRITIQUE_TOKEN="<<<DOCS_CRITIQUE_FILED"   # prefix: skill appends " <count>>>>"
ARCHIVED_TOKEN="<<<DOCS_ARCHIVED"         # prefix: skill appends " <user-docu-slug>>>>"
SATURATED_TOKEN="<<<DOCS_SATURATED>>>"    # a critique pass found nothing worth filing
MAX_SATURATIONS="${MAX_SATURATIONS:-2}"   # consecutive saturated critique passes → stop
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRETTY_SCRIPT="$SCRIPT_DIR/pretty-stream.py"
PRETTY_OUTPUT="${PRETTY_OUTPUT:-1}"       # 1 = condensed trace on screen; 0 = raw agent stream
mkdir -p "$LOG_DIR"
rm -f "$STOP_FILE"                        # clear any stale stop flag at startup

# Keep the vault from growing without bound: each run writes a multi-MB raw agent stream,
# and the vault syncs to a server. Keeps the newest KEEP_RUNS of each kind; the tiny
# *.final.txt sentinels and the append-only git.log/gh.log/db.log are never touched.
prune_old_logs() {
  [ "${KEEP_RUNS:-0}" -gt 0 ] || return 0
  local pattern removed=0 f
  for pattern in 'docs-*.log' 'merge-*.log'; do
    while IFS= read -r f; do
      rm -f "$f" && removed=$((removed+1))
    done < <(find "$LOG_DIR" -maxdepth 1 -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
               | sort -rn | tail -n +$((KEEP_RUNS+1)) | cut -d' ' -f2-)
  done
  [ "$removed" -gt 0 ] && log "pruned ${removed} run log(s), keeping the newest ${KEEP_RUNS} per kind"
  return 0
}

# agent-browser Chromes outlive a run that ends without `agent-browser close` (killed,
# timed out, or it just forgot). Their driver is gone, so they hang under systemd and keep
# whatever the last page does — on 2026-09-27 one sat on a PDF at 100% of a core for 17.5 h,
# holding 2.8 GB, and SIGTERM could not stop it (Chrome's shutdown waits on the busy tab).
# A browser a live run owns always has its agent-browser driver as parent, so it is never
# touched. Machine-wide on purpose: an orphan from any loop or session is equally dead.
REAP_BROWSER_MIN_AGE="${REAP_BROWSER_MIN_AGE:-7200}"   # seconds; younger orphans are left alone
reap_orphan_browsers() {
  local pid parent age reaped=0
  for pid in $(pgrep -f "$HOME/.agent-browser/browsers/[^ ]*/chrome --remote-debugging-port" 2>/dev/null); do
    parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$parent" ] || continue
    [ "$(ps -o comm= -p "$parent" 2>/dev/null)" = systemd ] || continue   # PID 1 or a user subreaper
    age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [ "${age:-0}" -ge "$REAP_BROWSER_MIN_AGE" ] || continue
    # Chrome leads its own process group; killing the group takes the zygote and tabs with it.
    [ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$pid" ] || continue
    kill -KILL -- "-$pid" 2>/dev/null && reaped=$((reaped+1)) \
      && warn "reaped orphaned agent-browser Chrome $pid (running $((age/3600))h, no driver)"
  done
  return 0
}

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

# Screen view: one line per action (tool + file, thinking, text). The RAW stream still goes to
# the log file, so nothing is lost. PRETTY_OUTPUT=0 (or no python3) falls back to the raw stream.
render() {
  if [ "$PRETTY_OUTPUT" = "1" ] && [ -f "$PRETTY_SCRIPT" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$PRETTY_SCRIPT"
  else
    cat
  fi
}

# graceful exit when ./scripts/stop-loop dropped the flag
check_stop() {
  if [ -f "$STOP_FILE" ]; then
    rm -f "$STOP_FILE"
    banner "STOP REQUESTED (./scripts/stop-loop) — exiting gracefully"
    exit 0
  fi
}

# stop the whole loop with a reason (used for fatal / human-needed states)
stop_loop() { banner "$1"; exit "${2:-0}"; }

# visible countdown that ALSO honours the stop flag
countdown() {
  local secs="$1" label="$2"
  while [ "$secs" -gt 0 ]; do
    if [ -f "$STOP_FILE" ]; then printf "\r%*s\r" 60 ""; check_stop; fi
    printf "\r${D}[%s]${R} ${YEL}⏳ %s — %02d:%02d left${R}   " "$(ts)" "$label" $((secs/60)) $((secs%60))
    sleep 1; secs=$((secs-1))
  done
  printf "\r%*s\r" 60 ""
}

# ---- pre-flight: fail fast before burning a cycle ------------------------
preflight() {
  step "Pre-flight checks…"
  case "$MAX_CYCLES" in
    ''|*[!0-9]*) err "MAX_CYCLES must be a non-negative integer"; return 1 ;;
  esac
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { err "not inside a git repo"; return 1; }
  # Run on THIS worktree's branch — never `git switch` to MAIN_BRANCH, which is
  # usually checked out in another worktree (that switch would fail).
  if [ -z "$BASE_BRANCH" ]; then
    BASE_BRANCH=$(git symbolic-ref --short -q HEAD) \
      || { err "detached HEAD — checkout a branch for this worktree first"; return 1; }
  fi
  if [ "$BASE_BRANCH" = "$MAIN_BRANCH" ]; then
    warn "BASE_BRANCH == ${MAIN_BRANCH}: running on main itself (OK only in the worktree that owns main)."
  fi
  case "$BASE_BRANCH" in documentation/*)
    err "HEAD is on unit branch '${BASE_BRANCH}' — switch to your loop base branch first"
    err "(an unmerged unit branch cannot fast-forward to ${MAIN_BRANCH}): git switch docs-loop-base"
    return 1 ;;
  esac
  command -v gh     >/dev/null 2>&1 || { err "gh not on PATH";     return 1; }
  command -v codex  >/dev/null 2>&1 || { err "codex not on PATH";  return 1; }
  command -v convert >/dev/null 2>&1 || { err "ImageMagick 'convert' not on PATH (screenshot annotation)"; return 1; }
  gh auth status >/dev/null 2>&1 || { err "gh not authenticated (run: gh auth login)"; return 1; }
  # the coverage queue's home must be reachable, or the skill silently misfires
  [ -e "$WIKI_DIR/AgCore/planning" ] || { err "$WIKI_DIR/AgCore/planning not reachable (Nextcloud mounted?)"; return 1; }
  ok "Pre-flight passed."
}

# ---- git prep: deterministic, script-side (not trusted to the agent) -----
# Keeps THIS worktree on its own branch (BASE_BRANCH), fast-forwarded to the
# latest integration branch (origin/MAIN_BRANCH). Never checks out MAIN_BRANCH
# itself, so it works inside a git worktree where main is checked out elsewhere.
# returns 1 = fatal (dirty / diverged / git failure), 2 = new migrations pulled (human apply)
prep_worktree() {
  step "Syncing worktree branch '${BASE_BRANCH}' with origin/${MAIN_BRANCH}…"
  if ! git diff --quiet || ! git diff --cached --quiet; then
    err "working tree has uncommitted changes — refusing to touch it (no auto-discard)"
    return 1
  fi
  git switch "$BASE_BRANCH"  2>>"$LOG_DIR/git.log" || { err "switch to $BASE_BRANCH failed"; return 1; }
  # 3, not 1: a failed fetch is GitHub being unreachable, and the caller retries next cycle.
  git fetch origin           2>>"$LOG_DIR/git.log" || { warn "fetch failed — GitHub unreachable? see $LOG_DIR/git.log"; return 3; }
  local before; before=$(git rev-parse HEAD)
  # ff-only: fast-forward our base to the latest main. If it can't (our branch
  # has its own un-merged commits / diverged), that needs a human — never force.
  git merge --ff-only "origin/${MAIN_BRANCH}" 2>>"$LOG_DIR/git.log" \
    || { err "cannot fast-forward ${BASE_BRANCH} to origin/${MAIN_BRANCH} (diverged?) — needs a human"; return 1; }
  ok "'${BASE_BRANCH}' up to date with origin/${MAIN_BRANCH}."
  # Worktree DBs are separate, so a pulled migration must be applied HERE before the
  # loop can trust what it sees. The caller decides how (see apply_migrations).
  mapfile -t PULLED_MIGRATIONS < <(git diff --name-only "$before" HEAD -- db/migrations/ 2>/dev/null)
  if [ "${#PULLED_MIGRATIONS[@]}" -gt 0 ]; then
    warn "New migrations pulled into ${BASE_BRANCH}:"
    printf '    %s\n' "${PULLED_MIGRATIONS[@]}"
    return 2
  fi
  return 0
}

# ---- migrations ----------------------------------------------------------
# The loop is not approving a migration — it already merged through the review gate.
# It is syncing THIS worktree's dev database to code that is already on main, so the
# only thing worth stopping for is what would irreversibly destroy local dev DATA:
# dropping a table/column/schema, truncating, deleting rows, or rewriting a column type.
#
# Dropping a POLICY, FUNCTION, INDEX, TRIGGER or CONSTRAINT loses no rows — and
# drop-and-recreate is the ordinary shape of a policy rewrite, so stopping on those
# stalled the loop twice on migrations that were perfectly safe (2026-07-31).
# Accepted trade-off: a migration that drops policies WITHOUT recreating them would
# quietly reduce RLS coverage on this dev DB and no longer pause the loop.
#
# A MATERIALIZED VIEW is out for the same reason (2026-08-02): it holds only derived rows
# that its own refresh rebuilds, and it cannot be altered in place — so drop-and-recreate is
# the only way to redefine one. Treating that as data loss took every loop on the fleet down
# over a single matview redefinition. A plain VIEW drop still stops the loop; only the
# MATERIALIZED form is exempt.
#
# Still biased to stop: an unrecognised destructive-looking statement counts as unsafe.
# Comments are stripped first so a DROP mentioned in a comment does not halt the loop.
DESTRUCTIVE_SQL='\bDROP[[:space:]]+(TABLE|COLUMN|SCHEMA|DATABASE|SEQUENCE|VIEW|TYPE|EXTENSION|ROLE|USER)\b|\bTRUNCATE\b|\bDELETE[[:space:]]+FROM\b|\bALTER[[:space:]]+COLUMN\b[^;]*\bTYPE\b|\bRENAME\b'
# Only the SQL that runs when the file is applied — comments and CREATE FUNCTION
# bodies removed. A function body is a definition: its DELETE runs when something
# calls the function, never at apply time, so a migration that merely defines a
# retention function deletes nothing. A DO block is the opposite — it executes
# immediately — and deliberately stays in scope, as does everything after a body
# closes. Unbalanced dollar quoting exits 3 rather than silently swallowing the
# rest of the file, so the caller fails closed.
# Ported verbatim from issue-loop.sh on 2026-09-12: the naive text scan this
# replaced refused 31 of the 205 migrations then on main, and stopped the docs
# loop on 20260911_083000_retention_v3_narrow_workspace.sql, whose executable
# half is nothing but CREATE OR REPLACE FUNCTION, REVOKE and GRANT.
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

# returns 0 = applied (loop may continue), 2 = needs a human
apply_migrations() {
  [ "$AUTO_MIGRATE" = "1" ] || { warn "AUTO_MIGRATE=0 — leaving migrations to you"; return 2; }
  local f
  for f in "$@"; do
    [ -f "$f" ] || { warn "migration no longer on disk: $f"; return 2; }
    migration_is_additive "$f" || { warn "not purely additive: $f"; return 2; }
  done
  # Through the ledger, never by piping files into psql: db:migrate applies only what
  # is pending, in one transaction, and records it. Bare psql ran each file outside a
  # transaction (LOCK TABLE / SET LOCAL fail) and left applied files unrecorded.
  step "Applying pending migrations via the ledger (npm run db:migrate)…"
  if ! npm run --silent db:migrate >>"$LOG_DIR/db.log" 2>&1; then
    err "db:migrate failed — see $LOG_DIR/db.log (an 'orphaned' row in npm run db:status needs a human)"
    return 2
  fi
  ok "worktree DB is current with the migration ledger."
  return 0
}

# ---- open docs-PR count on base ------------------------------------------
# Only documentation/* PRs belong to this loop. Unrelated dev PRs from parallel
# worktrees are ignored — they are merged by the main merge loop or a human.
# Open documentation/* PRs, newest first, one number per line. The exit status is gh's, so the
# caller can tell "none open" from "could not ask GitHub".
open_docs_prs() {
  gh pr list --state open --base "$MAIN_BRANCH" --json number,headRefName \
    --jq '.[] | select(.headRefName | startswith("documentation/")) | .number' 2>>"$LOG_DIR/gh.log"
}
# A parked PR waits for a human. It is no longer this loop's queue: it neither counts toward the
# one-open-PR invariant nor gets merged again.
is_parked() { [ -f "$PARKED_FILE" ] && cut -d' ' -f1 "$PARKED_FILE" | grep -qFx "$1"; }
park_pr() {  # park_pr <number> <reason>
  printf '%s %s %s\n' "$1" "$(date '+%F %T')" "$2" >> "$PARKED_FILE"
}

# ---- merge phase (codex $do-pr auto #N) ---------------------------------
# returns 0 = merged, 2 = blocked, 3 = no PR, 1 = unknown/agent failure
run_merge() {
  local pr="$1" logfile="$LOG_DIR/merge-$(date +%Y%m%d-%H%M%S).log"
  local final="${logfile%.log}.final.txt"
  local model_args=()
  [ -n "$MERGE_MODEL" ]  && model_args+=(-m "$MERGE_MODEL")
  [ -n "$MERGE_EFFORT" ] && model_args+=(-c "model_reasoning_effort=$MERGE_EFFORT")
  step "Launching codex → \$do-pr auto #${pr} …"
  log "streaming below + → ${D}$logfile${R}"
  codex exec --json --yolo "${model_args[@]}" -o "$final" \
    "Run the \$do-pr skill in autonomous mode for PR #${pr}. Complete every review, security, \
local gate, runtime, and CI requirement before deciding whether to merge. End with exactly one \
merge sentinel on its own line, as the skill specifies." \
    </dev/null 2>&1 | tee "$logfile" | render
  local rc=${PIPESTATUS[0]}
  local hay="$final"
  # A crashed run writes no final message. Never fall back to the raw stream: it holds the skill
  # file and every tool result, so a sentinel merely quoted there reads as one the agent emitted.
  # That is how a model-capacity failure on 2026-09-14 was mis-read as DOCS COMPLETE and stopped
  # the loop with the queue still full. No final message = unknown state; the caller retries.
  [ -s "$final" ] || hay=/dev/null
  # Ground truth first: models decorate or omit the sentinel, but GitHub cannot lie about
  # whether the PR merged. Sentinels are only consulted for the not-merged outcomes.
  local state; state=$(gh pr view "$pr" --json state --jq .state 2>>"$LOG_DIR/gh.log")
  if   [ "$state" = "MERGED" ];                     then ok "Merged PR #${pr} (verified on GitHub)."; return 0
  elif grep -qF "<<<MERGE_BLOCKED" "$hay"; then err "do-pr blocked PR #${pr}."; return 2
  elif grep -qF "<<<NO_OPEN_PR>>>" "$hay"; then warn "do-pr found no open PR."; return 3
  else err "do-pr ended with no sentinel (rc=$rc) — treating as unknown state";           return 1
  fi
}

# ---- docs phase (codex $docs-loop) ---------------------------------------
# returns 0 = published, 10 = queue complete, 2 = unit blocked, 1 = agent failure
run_docs() {
  local logfile="$LOG_DIR/docs-$(date +%Y%m%d-%H%M%S).log"
  step "Launching codex (yolo) → \$docs-loop …"
  log "streaming below + → ${D}$logfile${R}"
  # --json for the readable trace; -o captures the agent's FINAL message as plain text, which
  # is where the sentinel lives. Reading the sentinel from that file (not the stream) removes
  # the prompt-echo hazard entirely — the prompt is never part of the final message.
  local final="${logfile%.log}.final.txt"
  local model_args=()
  [ -n "$DOCS_MODEL" ]  && model_args+=(-m "$DOCS_MODEL")
  [ -n "$DOCS_EFFORT" ] && model_args+=(-c "model_reasoning_effort=$DOCS_EFFORT")
  codex exec --json --yolo "${model_args[@]}" -o "$final" \
    "Run the \$docs-loop skill. Start with its origin/${MAIN_BRANCH} change-impact scan, update the \
maintenance ledger, then work exactly one unit under its recovery, coverage, alternating feature/page, \
and saturation precedence. Open a PR against ${MAIN_BRANCH} when the local gate is green. \
End with exactly one sentinel on its own line, as the skill specifies." \
    </dev/null 2>&1 | tee "$logfile" | render   # stdin closed: codex waits on a piped stdin otherwise
  local rc=${PIPESTATUS[0]}
  local hay="$final"
  # A crashed run writes no final message. Never fall back to the raw stream: it holds the skill
  # file and every tool result, so a sentinel merely quoted there reads as one the agent emitted.
  # That is how a model-capacity failure on 2026-09-14 was mis-read as DOCS COMPLETE and stopped
  # the loop with the queue still full. No final message = unknown state; the caller retries.
  [ -s "$final" ] || hay=/dev/null
  # Order matters: SATURATED/COMPLETE are exact, the rest are prefixes. A pass that files issues
  # or archives a folder is progress even though it publishes no page.
  if   grep -qF "$COMPLETE_TOKEN"  "$hay"; then                                              return 10
  elif grep -qF "$PUBLISHED_TOKEN" "$hay"; then ok "docs unit published.";                   return 0
  elif grep -qF "$CRITIQUE_TOKEN"  "$hay"; then ok "critique pass filed new issues.";        return 3
  elif grep -qF "$ARCHIVED_TOKEN"  "$hay"; then ok "user-docu folder archived as documented."; return 3
  elif grep -qF "$SATURATED_TOKEN" "$hay"; then warn "critique pass found nothing to file.";  return 11
  elif grep -qF "$BLOCKED_TOKEN"   "$hay"; then warn "docs unit blocked — row marked in queue."; return 2
  else err "docs-loop ended with no sentinel (rc=$rc)";                                      return 1
  fi
}

# ──────────────────────────────────────────────────────────────
preflight || stop_loop "PRE-FLIGHT FAILED — fix the above and restart" 1

cycle=0
docs_fails=0
blocked_runs=0
net_fails=0
saturations=0
banner "DOCS LOOP STARTING"
log "cycle=${CYCLE_MINUTES}m  base=${BASE_BRANCH}  main=${MAIN_BRANCH}  wiki=${WIKI_DIR}"
log "models: writer=${DOCS_MODEL}${DOCS_EFFORT:+ (${DOCS_EFFORT})}  merge=${MERGE_MODEL}${MERGE_EFFORT:+ (${MERGE_EFFORT})}"
log "logs:  ${LOG_DIR}${D}  (keeping newest ${KEEP_RUNS} runs)${R}"
log "limits: failed=${MAX_DOCS_FAILS}  blocked=${MAX_DOCS_BLOCKED}  offline=${MAX_NET_FAILS} cycles  parked=${MAX_PARKED}"
[ -s "$PARKED_FILE" ] && log "parked PRs (delete a line to hand one back): $(cut -d' ' -f1 "$PARKED_FILE" | tr '\n' ' ')"
log "stop gracefully: ${B}./scripts/stop-loop${R}${D}  (from another terminal)${R}"
prune_old_logs

while :; do
  check_stop
  cycle=$((cycle+1))
  banner "CYCLE $cycle  —  $(ts)"
  reap_orphan_browsers

  # ---- sync ----
  prep_worktree; rc=$?
  [ "$rc" -eq 1 ] && stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
  if [ "$rc" -eq 3 ]; then
    net_fails=$((net_fails+1))
    warn "GitHub unreachable ${net_fails}/${MAX_NET_FAILS} — nothing synced, retrying next cycle"
    [ "$net_fails" -ge "$MAX_NET_FAILS" ] \
      && stop_loop "GITHUB UNREACHABLE for ${net_fails} cycles in a row — see $LOG_DIR/git.log" 1
    banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
    countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
    continue
  fi
  if [ "$rc" -eq 2 ]; then
    apply_migrations "${PULLED_MIGRATIONS[@]}" \
      || stop_loop "MIGRATION PULLED — apply it to this worktree's DB, then restart the loop" 0
  fi

  # ---- Phase 1: drain the open documentation/* PR FIRST (invariant: ≤ 1, parked PRs aside) ----
  if ! all_prs=$(open_docs_prs); then
    net_fails=$((net_fails+1))
    warn "gh pr list failed ${net_fails}/${MAX_NET_FAILS} — see $LOG_DIR/gh.log; retrying next cycle"
    [ "$net_fails" -ge "$MAX_NET_FAILS" ] \
      && stop_loop "GITHUB UNREACHABLE for ${net_fails} cycles in a row — see $LOG_DIR/gh.log" 1
    banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
    countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
    continue
  fi
  net_fails=0
  open_prs=(); parked_open=0
  for p in $all_prs; do
    if is_parked "$p"; then parked_open=$((parked_open+1)); else open_prs+=("$p"); fi
  done
  [ "$parked_open" -ge "$MAX_PARKED" ] \
    && stop_loop "TOO MANY PARKED PRS — ${parked_open} documentation PRs wait for a human: $PARKED_FILE" 1
  n=${#open_prs[@]}
  if [ "$n" -gt 1 ]; then stop_loop "INVARIANT BROKEN — ${n} open documentation/* PRs that are not parked (expected ≤1). Human review." 1; fi
  if [ "$n" -eq 1 ]; then
    pr=${open_prs[0]}
    run_merge "$pr"; mrc=$?
    case "$mrc" in
      0) prep_worktree; rc=$?                                     # re-sync to pull the merge
         [ "$rc" -eq 1 ] && stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
         if [ "$rc" -eq 3 ]; then
           # Merged, but the pull failed: never write the next unit on a base without that merge.
           net_fails=$((net_fails+1))
           warn "merged #${pr}, but GitHub became unreachable before the pull ${net_fails}/${MAX_NET_FAILS} — retrying next cycle"
           [ "$net_fails" -ge "$MAX_NET_FAILS" ] \
             && stop_loop "GITHUB UNREACHABLE for ${net_fails} cycles in a row — see $LOG_DIR/git.log" 1
           banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
           countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
           continue
         fi
         if [ "$rc" -eq 2 ]; then
           apply_migrations "${PULLED_MIGRATIONS[@]}" \
             || stop_loop "MIGRATION MERGED — apply it to this worktree's DB, then restart the loop" 0
         fi ;;
      2) park_pr "$pr" "blocked-at-gate"
         parked_open=$((parked_open+1))
         warn "PR #${pr} BLOCKED at a gate — parked (${parked_open}/${MAX_PARKED}); read its PR comment. Moving on."
         [ "$parked_open" -ge "$MAX_PARKED" ] \
           && stop_loop "TOO MANY PARKED PRS — ${parked_open} documentation PRs wait for a human: $PARKED_FILE" 1 ;;
      *) # Inconclusive: agent ended without merging or declaring blocked, but the PR is
         # still open and healthy on GitHub — retry next cycle instead of dying.
         docs_fails=$((docs_fails+1))
         warn "merge inconclusive for PR #${pr} — retry ${docs_fails}/${MAX_DOCS_FAILS} next cycle"
         [ "$docs_fails" -ge "$MAX_DOCS_FAILS" ] \
           && stop_loop "REPEATED INCONCLUSIVE MERGES for PR #${pr} — see $LOG_DIR. Human review." 1
         banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
         countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
         continue ;;
    esac
  fi

  check_stop

  # ---- Phase 2: document the next unit (queue is now clear) ----
  run_docs; drc=$?
  case "$drc" in
    0)  docs_fails=0; blocked_runs=0; saturations=0 ;;
    3)  docs_fails=0; blocked_runs=0; saturations=0 ;;            # critique filed / folder archived
    2)  docs_fails=0                                              # a finished run, not a crash
        blocked_runs=$((blocked_runs+1))
        warn "unit blocked ${blocked_runs}/${MAX_DOCS_BLOCKED} — its row has the reason; next cycle takes other work"
        [ "$blocked_runs" -ge "$MAX_DOCS_BLOCKED" ] \
          && stop_loop "TOO MANY BLOCKED UNITS — ${blocked_runs} in a row; read the blocked reasons in the queue (often one shared cause)" 1 ;;
    10) stop_loop "DOCS COMPLETE — coverage, maintenance, feature, and backlog work are clear; review blocked rows" 0 ;;
    11) saturations=$((saturations+1))                            # a critique pass that found nothing
        warn "critique saturated ${saturations}/${MAX_SATURATIONS}"
        [ "$saturations" -ge "$MAX_SATURATIONS" ] \
          && stop_loop "DOCS SATURATED — ${saturations} critique passes in a row found nothing to file" 0 ;;
    *)  docs_fails=$((docs_fails+1))                              # no sentinel: crashed or cut off
        warn "docs run failed ${docs_fails}/${MAX_DOCS_FAILS} — continuing"
        [ "$docs_fails" -ge "$MAX_DOCS_FAILS" ] && stop_loop "TOO MANY FAILED DOCS RUNS — ${docs_fails} in a row; see $LOG_DIR" 1 ;;
  esac

  if [ "$MAX_CYCLES" -gt 0 ] && [ "$cycle" -ge "$MAX_CYCLES" ]; then
    stop_loop "MAX CYCLES REACHED — completed ${cycle} cycle(s)" 0
  fi

  check_stop
  banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
  countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
done
