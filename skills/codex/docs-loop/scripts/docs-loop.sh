#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# dual-agent docs loop (ralph loop for the docs-loop skill):
#   each cycle: fast-forward THIS worktree's branch to main → MERGE any open PR → DOCUMENT next unit → wait
#   codex runs $docs-loop (write docs); claude runs /do-pr auto (review+merge)
# invariant: at most ONE open documentation/* PR exists at any time (other PRs are ignored).
# stops on: queue complete, a blocked PR, an unexpected state, ./scripts/stop-loop, Ctrl-C.
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
# Logs live in the vault beside the queue they belong to, NOT in the repo — the vault is
# gitignored and backed up, so run history survives a worktree being deleted and can never
# be committed by accident. Falls back to the worktree only if the vault is not mounted,
# because mkdir -p would otherwise create a real ./memory directory that shadows the symlink.
if [ -z "${LOG_DIR:-}" ]; then
  if [ -d "$WIKI_DIR/AgCore/planning/docs-coverage" ]; then
    LOG_DIR="$WIKI_DIR/AgCore/planning/docs-coverage/loop-logs"
  else
    LOG_DIR="./docs-loop-logs"
  fi
fi
KEEP_RUNS="${KEEP_RUNS:-20}"              # prune run logs older than the newest N (0 = keep all)
MAX_DOCS_FAILS="${MAX_DOCS_FAILS:-3}"     # consecutive non-published outcomes → stop
AUTO_MIGRATE="${AUTO_MIGRATE:-1}"         # 1 = apply purely additive migrations here; 0 = always stop for a human
DOCKER_DIR="${DOCKER_DIR:-./infrastructure/docker}"
DC_ENV_FILE="${DC_ENV_FILE:-../../.env}"  # relative to DOCKER_DIR (matches the dc() helper)
DB_USER="${DB_USER:-agcore_user}"
DB_NAME="${DB_NAME:-agcore_db}"
PULLED_MIGRATIONS=()                      # filled by prep_worktree each sync
DOCS_MODEL="${DOCS_MODEL:-}"              # codex model for the writer ('' = ~/.codex/config.toml default)
DOCS_EFFORT="${DOCS_EFFORT:-}"            # codex reasoning effort ('' = config default)
MERGE_MODEL="${MERGE_MODEL:-sonnet}"      # model for the /do-pr merge agent (docs PRs are mechanical)
MERGE_CONFIG_DIR="${MERGE_CONFIG_DIR:-$HOME/.claude-max-2}"  # claude account for the merge agent only
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

# The agent's FINAL message, extracted from the stream-json log. Merge sentinels are matched
# against THIS, never the raw stream: an agent that merely *narrates* the contract mid-run
# ("...else report <<<MERGE_BLOCKED #N reason>>>") would otherwise read as having emitted it.
# That false positive stopped this loop on a healthy PR (#796, 2026-08-03). The docs phase
# already had this right — it reads codex's -o final file for the same reason.
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
  command -v claude >/dev/null 2>&1 || { err "claude not on PATH"; return 1; }
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
  git fetch origin           2>>"$LOG_DIR/git.log" || { err "fetch failed"; return 1; }
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
migration_is_additive() {
  local sql
  sql=$(sed -e 's/--.*$//' "$1" | tr '\n' ' ')
  ! printf '%s' "$sql" | grep -qiE "$DESTRUCTIVE_SQL"
}

# returns 0 = applied (loop may continue), 2 = needs a human
apply_migrations() {
  [ "$AUTO_MIGRATE" = "1" ] || { warn "AUTO_MIGRATE=0 — leaving migrations to you"; return 2; }
  local f
  for f in "$@"; do
    [ -f "$f" ] || { warn "migration no longer on disk: $f"; return 2; }
    migration_is_additive "$f" || { warn "not purely additive: $f"; return 2; }
  done
  for f in "$@"; do
    step "Applying $(basename "$f") to this worktree's DB…"
    # ON_ERROR_STOP + the migration's own transaction: psql's exit code is the
    # real proof it applied. Nothing here is trusted to an agent's say-so.
    if ! (cd "$DOCKER_DIR" && docker compose --env-file "$DC_ENV_FILE" exec -T postgres \
            psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1) <"$f" >>"$LOG_DIR/db.log" 2>&1; then
      err "migration failed to apply: $f — see $LOG_DIR/db.log"
      return 2
    fi
    ok "applied $(basename "$f")"
  done
  return 0
}

# ---- open docs-PR count on base ------------------------------------------
# Only documentation/* PRs belong to this loop. Unrelated dev PRs from parallel
# worktrees are ignored — they are merged by the main merge loop or a human.
open_pr_count() {
  gh pr list --state open --base "$MAIN_BRANCH" --json headRefName \
    --jq '[.[] | select(.headRefName | startswith("documentation/"))] | length' 2>>"$LOG_DIR/gh.log" || echo "ERR"
}
open_pr_number() {
  gh pr list --state open --base "$MAIN_BRANCH" --json number,headRefName \
    --jq '[.[] | select(.headRefName | startswith("documentation/"))][0].number' 2>>"$LOG_DIR/gh.log"
}

# ---- merge phase (claude /do-pr auto #N) ------------------------------
# returns 0 = merged, 2 = blocked, 3 = no PR, 1 = unknown/agent failure
run_merge() {
  local pr="$1" logfile="$LOG_DIR/merge-$(date +%Y%m%d-%H%M%S).log"
  step "Launching Claude Code → /do-pr auto #${pr} …"
  log "streaming below + → ${D}$logfile${R}"
  CLAUDE_CONFIG_DIR="$MERGE_CONFIG_DIR" claude --model "$MERGE_MODEL" \
    --permission-mode bypassPermissions --output-format stream-json --verbose \
    --print "/do-pr auto #${pr}" </dev/null 2>&1 | tee "$logfile" | render
  local rc=${PIPESTATUS[0]}
  # Ground truth first: models decorate or omit the sentinel, but GitHub cannot lie about
  # whether the PR merged. Sentinels are only consulted for the not-merged outcomes.
  local state; state=$(gh pr view "$pr" --json state --jq .state 2>>"$LOG_DIR/gh.log")
  if   [ "$state" = "MERGED" ];                     then ok "Merged PR #${pr} (verified on GitHub)."; return 0
  elif final_message "$logfile" | grep -qF "<<<MERGE_BLOCKED"; then err "do-pr blocked PR #${pr}."; return 2
  elif final_message "$logfile" | grep -qF "<<<NO_OPEN_PR>>>"; then warn "do-pr found no open PR."; return 3
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
    "Run the \$docs-loop skill: work exactly one unit — the next queue row, else the next \
ready-for-agent issue in docs-coverage/issues, else a critique pass — opening a PR against \
${MAIN_BRANCH} when the local gate is green. \
End with exactly one sentinel on its own line, as the skill specifies." \
    </dev/null 2>&1 | tee "$logfile" | render   # stdin closed: codex waits on a piped stdin otherwise
  local rc=${PIPESTATUS[0]}
  local hay="$final"
  [ -s "$final" ] || hay="$logfile"   # no final message captured → fall back to the raw stream
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
saturations=0
banner "DOCS LOOP STARTING"
log "cycle=${CYCLE_MINUTES}m  base=${BASE_BRANCH}  main=${MAIN_BRANCH}  wiki=${WIKI_DIR}"
log "models: writer=${DOCS_MODEL:-codex default}${DOCS_EFFORT:+ (${DOCS_EFFORT})}  merge=${MERGE_MODEL}"
log "logs:  ${LOG_DIR}${D}  (keeping newest ${KEEP_RUNS} runs)${R}"
log "stop gracefully: ${B}./scripts/stop-loop${R}${D}  (from another terminal)${R}"
prune_old_logs

while :; do
  check_stop
  cycle=$((cycle+1))
  banner "CYCLE $cycle  —  $(ts)"

  # ---- sync ----
  prep_worktree; rc=$?
  [ "$rc" -eq 1 ] && stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
  if [ "$rc" -eq 2 ]; then
    apply_migrations "${PULLED_MIGRATIONS[@]}" \
      || stop_loop "MIGRATION PULLED — apply it to this worktree's DB, then restart the loop" 0
  fi

  # ---- Phase 1: drain any open documentation/* PR FIRST (invariant: ≤ 1) ----
  n=$(open_pr_count)
  if [ "$n" = "ERR" ]; then stop_loop "gh pr list failed — see $LOG_DIR/gh.log" 1; fi
  if [ "$n" -gt 1 ]; then stop_loop "INVARIANT BROKEN — ${n} open documentation/* PRs (expected ≤1). Human review." 1; fi
  if [ "$n" -eq 1 ]; then
    pr=$(open_pr_number)
    run_merge "$pr"; mrc=$?
    case "$mrc" in
      0) prep_worktree; rc=$?                                     # re-sync to pull the merge
         [ "$rc" -eq 1 ] && stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
         if [ "$rc" -eq 2 ]; then
           apply_migrations "${PULLED_MIGRATIONS[@]}" \
             || stop_loop "MIGRATION MERGED — apply it to this worktree's DB, then restart the loop" 0
         fi ;;
      2) stop_loop "PR #${pr} BLOCKED at a gate — see its PR comment + $LOG_DIR. Human review." 1 ;;
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
    0)  docs_fails=0; saturations=0 ;;
    3)  docs_fails=0; saturations=0 ;;                            # critique filed / folder archived
    10) stop_loop "DOCS QUEUE COMPLETE — every unit published or blocked; review blocked rows" 0 ;;
    11) saturations=$((saturations+1))                            # a critique pass that found nothing
        warn "critique saturated ${saturations}/${MAX_SATURATIONS}"
        [ "$saturations" -ge "$MAX_SATURATIONS" ] \
          && stop_loop "DOCS SATURATED — ${saturations} critique passes in a row found nothing to file" 0 ;;
    *)  docs_fails=$((docs_fails+1))                              # blocked and failed both count
        warn "non-published outcome ${docs_fails}/${MAX_DOCS_FAILS} — continuing"
        [ "$docs_fails" -ge "$MAX_DOCS_FAILS" ] && stop_loop "TOO MANY NON-PUBLISHED CYCLES — stopping" 1 ;;
  esac

  check_stop
  banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
  countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
done
