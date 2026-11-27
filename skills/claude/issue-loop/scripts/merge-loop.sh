#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# merge loop (serves the shared PR queue of every build loop, merges only):
#   take the oldest queued PR → check it on GitHub → do-pr auto #N → read GitHub →
#   merged: drop it, sync base + DB · blocked: park it · inconclusive: retry after the
#   others, park after MAX_FAILS attempts · closed: drop it → next PR AT ONCE
# One PR at a time, one merge loop per machine. Only PRs a build loop queued are touched.
# Empty queue: re-read the queue file every MERGE_POLL_MINUTES, no GitHub calls at all.
# stops on: touch .issue-loop-stop, usage limit, dirty tree, GitHub unreachable for
#           NET_MAX_CYCLES cycles, a migration that needs a human, Ctrl-C.
# usage: ~/.claude/skills/issue-loop/scripts/merge-loop.sh        (no arguments)
# ──────────────────────────────────────────────────────────────
set -uo pipefail   # NOT -e: the loop decides what is fatal, line by line

# Carry "issue-loop.sh" in argv[0] so issue-loop.sh's lock check sees this loop as live
# (see build-loop.sh). exec keeps the pid, which is how the second pass knows it happened.
if [ "${ISSUE_LOOP_ARGV0:-}" != "$$" ]; then
  export ISSUE_LOOP_ARGV0=$$
  exec -a "merge-loop.sh[issue-loop.sh]" "$BASH" "${BASH_SOURCE[0]}" "$@"
fi
unset ISSUE_LOOP_ARGV0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'merge-loop: not inside a git worktree\n' >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

PRETTY_SCRIPT="$SCRIPT_DIR/pretty-stream.py"
# shellcheck source=loop-common.sh
. "$SCRIPT_DIR/loop-common.sh"
# shellcheck source=loop-agent.sh
. "$SCRIPT_DIR/loop-agent.sh"

MERGE_POLL_MINUTES="${MERGE_POLL_MINUTES:-5}"   # empty queue: how often to re-read the queue file
LOOP_NAME="merge"
WORKTREE_LOCK="$LOG_DIR/loop.lock"            # one loop per worktree (same file as issue-loop.sh)
MERGE_LOCK="$LOCK_HOME/merge-loop.lock"       # one merge loop per machine (phase 1)
mkdir -p "$LOG_DIR"
rm -f "$STOP_FILE"

trap 'printf "\n"; warn "Ctrl-C — hard stop."; exit 130' INT
trap 'idle_finish; release_lock "${WORKTREE_LOCK:-}"; release_lock "${MERGE_LOCK:-}"' EXIT

# This loop checks out every queued PR's branch, so any of them can explain an orphaned
# migration in this worktree's DB.
inflight_branches() { { queue_lines; parked_lines; } | awk -F'\t' '{ print $3 }'; }

# ---- pre-flight ------------------------------------------------------------
preflight() {
  step "Pre-flight checks…"
  [ "$#" -eq 0 ] || { err "usage: merge-loop.sh   (no arguments: it serves $PR_QUEUE)"; return 1; }
  acquire_lock "$WORKTREE_LOCK" "in this worktree" || return 1
  acquire_lock "$MERGE_LOCK"    "on this machine (one merge loop per machine)" || { release_lock "$WORKTREE_LOCK"; return 1; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { err "not inside a git repo"; return 1; }
  if [ -z "$BASE_BRANCH" ]; then
    BASE_BRANCH=$(git symbolic-ref --short -q HEAD) \
      || { err "detached HEAD — checkout a branch for this worktree first"; return 1; }
  fi
  [ "$BASE_BRANCH" = "$MAIN_BRANCH" ] \
    && warn "BASE_BRANCH == ${MAIN_BRANCH}: running on main itself (OK only in the worktree that owns main)."
  command -v python3 >/dev/null 2>&1 || { err "python3 not on PATH"; return 1; }
  [ -r "$SCRIPT_DIR/agent-result.py" ] || { err "agent-result.py is missing"; return 1; }
  command -v flock  >/dev/null 2>&1 || { err "flock not on PATH (util-linux) — the shared PR queue needs it"; return 1; }
  command -v gh     >/dev/null 2>&1 || { err "gh not on PATH";     return 1; }
  agent_preflight || return 1
  gh auth status >/dev/null 2>&1 || { err "gh not authenticated (run: gh auth login)"; return 1; }
  state_init || { err "cannot create the shared state dir: $LOOP_STATE_DIR"; return 1; }
  ok "Pre-flight passed."
}

# ---- queue order -------------------------------------------------------------
attempts_of() { cat "$LOG_DIR/merge-attempts-$1" 2>/dev/null || echo 0; }
# Fewest attempts first, then oldest queued_at, then file order (sort -s). A PR that ended
# inconclusive has one attempt more than the PRs behind it, so they all get their turn before
# it is retried — one PR in an unknown state never holds up the rest of the queue.
ordered_queue() {
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\t%s\n' "$(attempts_of "$(cut -f2 <<< "$line")")" "$line"
  done <<< "$(queue_lines)" | sort -s -t$'\t' -k1,1n -k2,2 | cut -f2-
}

seconds_since_queued() {  # seconds_since_queued <pr>  (empty when the line or date is unknown)
  local at epoch
  at=$(queue_lines | awk -F'\t' -v pr="$1" '$2 == pr { print $1; exit }')
  [ -n "$at" ] || return 0
  epoch=$(date -u -d "$at" +%s 2>/dev/null) || return 0
  echo $(( $(date +%s) - epoch ))
}

# Every removal from the queue goes through here, so the metrics see each one exactly once.
dequeue() {  # dequeue <pr> <merged|closed|parked> [park-reason]
  local pr="$1" why="$2" waited
  waited=$(seconds_since_queued "$pr")
  if [ "$why" = "parked" ]; then
    queue_park "$pr" "$3" || { err "could not park #${pr} in $PR_PARKED — it stays queued"; return 1; }
  else
    queue_remove "$pr" || { err "could not remove #${pr} from $PR_QUEUE — it stays queued"; return 1; }
  fi
  rm -f "$LOG_DIR/merge-attempts-${pr}"
  metric "dequeued:${why}" "#${pr}" "${waited:--}"
}

# Parked PRs that a person merged or closed since. GitHub must answer MERGED or CLOSED
# positively: an empty answer is an outage, and dropping on it would lose a parked PR.
prune_parked() {
  local pr state
  while IFS= read -r pr; do
    [ -n "$pr" ] || continue
    state=$(gh_retry pr view "$pr" --json state --jq .state) || continue
    case "$state" in
      MERGED|CLOSED) log "parked #${pr} is ${state} — unparking"; parked_remove "$pr" ;;
    esac
  done <<< "$(parked_lines | cut -f2)"
}

# ---- checkout ----------------------------------------------------------------
# do-pr runs `gh pr checkout <#>` itself, and that fetches a branch this worktree never had,
# so a fresh merge worktree is fine. What git refuses is checking out a branch ANOTHER
# worktree of the same repository has checked out ("already used by worktree") — a build
# loop that stopped right after its build leaves its PR branch exactly like that. So the
# runner checks that first, then fetches the branch and switches to it before the agent
# starts, so the run never begins on stale or missing code.
# returns 0 = on the branch, 1 = fetch failed (retry later), 2 = checked out elsewhere,
#         3 = git refused the switch (needs a human)
checkout_pr_branch() {  # checkout_pr_branch <branch>
  local branch="$1" other
  other=$(git worktree list --porcelain 2>/dev/null \
    | awk -v ref="branch refs/heads/${branch}" '/^worktree /{ wt = substr($0, 10) } $0 == ref { print wt }' \
    | grep -vFx "$REPO_ROOT" | head -1)
  if [ -n "$other" ]; then
    warn "${branch} is checked out in ${other} — git will not check it out here too; leaving it queued"
    return 2
  fi
  git fetch origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" 2>>"$LOG_DIR/git.log" || {
    warn "could not fetch ${branch} from origin — leaving it queued; see $LOG_DIR/git.log"
    return 1
  }
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    git switch "$branch" 2>>"$LOG_DIR/git.log" || { err "switch to ${branch} failed"; return 3; }
    # Never discard: a local branch ahead of origin holds someone's commits. do-pr decides.
    git merge --ff-only "origin/${branch}" >>"$LOG_DIR/git.log" 2>&1 \
      || warn "local ${branch} differs from origin/${branch} — leaving it as it is for do-pr"
  else
    git switch -c "$branch" --track "origin/${branch}" 2>>"$LOG_DIR/git.log" \
      || { err "could not create ${branch} from origin/${branch}"; return 3; }
  fi
  log "checked out ${branch} at $(git rev-parse --short HEAD)"
  return 0
}

# do-pr leaves the worktree on the PR branch. Go back to the base branch after every attempt,
# so a builder that must touch that branch again is not refused by git.
return_to_base() {
  tree_is_clean || stop_loop "GIT STATE NEEDS A HUMAN — do-pr left uncommitted changes in this worktree" 1
  git switch "$BASE_BRANCH" >/dev/null 2>>"$LOG_DIR/git.log" \
    || stop_loop "GIT STATE NEEDS A HUMAN — cannot switch back to ${BASE_BRANCH}" 1
}

# ---- one merge attempt (issue-loop.sh's drain_pending, for one PR) --------------
# Sets LAST_RESULT: merged | closed | blocked | inconclusive | parked (inconclusive, MAX_FAILS hit)
LAST_RESULT=""
MERGED_ANY=0
merge_one() {  # merge_one <pr> <branch>
  local pr="$1" branch="$2" logfile attempts_file attempt started rc prstate secs reason
  logfile="$LOG_DIR/merge-$(date +%Y%m%d-%H%M%S).log"
  # Retry the same PR, reusing only review evidence that still covers its current head.
  attempts_file="$LOG_DIR/merge-attempts-${pr}"
  attempt=$(( $(attempts_of "$pr") + 1 ))
  printf '%s\n' "$attempt" > "$attempts_file"
  [ "$attempt" -gt 1 ] && warn "retrying #${pr} (attempt ${attempt}) — ${RETRY_WARN}"
  step "Launching $(agent_label pr) → $(skill_call do-pr) auto #${pr} (branch ${branch}, attempt ${attempt}) …"
  log "streaming below + → ${D}$logfile${R}"
  started=$(date +%s)
  metric merge_start "#${pr}"
  run_agent pr "$logfile" "$(merge_prompt "$pr" "$attempt")"
  rc=$?
  # Ground truth first: GitHub cannot lie about whether the PR merged; sentinels are only
  # consulted for the not-merged outcomes (models decorate or omit them). An outage reads as
  # "not merged", which is safe: the PR stays queued and the next look asks again.
  prstate=$(gh_retry pr view "$pr" --json state --jq .state) || prstate=""
  secs=$(( $(date +%s) - started ))
  if [ "$prstate" = "MERGED" ]; then
    ok "Merged PR #${pr} (verified on GitHub)."
    metric merge_end:merged "#${pr}" "$secs"
    dequeue "$pr" merged
    MERGED_ANY=1; LAST_RESULT="merged"
  elif [ "$prstate" = "CLOSED" ]; then
    warn "PR #${pr} was closed during the run — removing it from the queue"
    metric merge_end:closed "#${pr}" "$secs"
    dequeue "$pr" closed
    LAST_RESULT="closed"
  elif final_message "$logfile" | grep -qF "<<<MERGE_BLOCKED"; then
    reason=$(final_message "$logfile" \
      | sed -nE 's/.*<<<MERGE_BLOCKED[[:space:]]*(#[0-9]+)?[[:space:]]*([^>]*)>>>.*/\2/p' | head -1)
    err "do-pr blocked PR #${pr} — see its PR comment."
    metric merge_end:blocked "#${pr}" "$secs"
    dequeue "$pr" parked "blocked: ${reason:-at a gate}"
    warn "PR #${pr} parked (blocked at a gate) — continuing with the rest of the queue"
    LAST_RESULT="blocked"
  else
    err "do-pr ended with no sentinel for #${pr} (rc=$rc) — unknown state; the other queued PRs go first"
    metric merge_end:inconclusive "#${pr}" "$secs"
    LAST_RESULT="inconclusive"
    if [ "$attempt" -ge "$MAX_FAILS" ]; then
      dequeue "$pr" parked "inconclusive after ${attempt} attempts"
      warn "PR #${pr} parked after ${attempt} inconclusive attempts — a person has to look"
      LAST_RESULT="parked"
    fi
  fi
}

# ──────────────────────────────────────────────────────────────
preflight "$@" || stop_loop "PRE-FLIGHT FAILED — fix the above and restart" 1

cycle=0
net_fails=0
# Inconclusive runs in a row, and on which PRs. One PR failing again and again is that PR's
# problem: it is parked after MAX_FAILS attempts. Several different PRs failing in a row is
# the agent's or the machine's problem; parking them all would empty the queue into
# pr-parked.tsv within minutes, so the loop stops for a person instead.
inc_streak=0
inc_prs=""
banner "MERGE LOOP STARTING — ${PR_QUEUE}"
log "worktree: ${B}$(pwd)${R}"   # printed loudly: starting in the wrong worktree is easy to miss
log "poll=${MERGE_POLL_MINUTES}m (empty queue)  skip-wait=${CYCLE_MINUTES}m  base=${BASE_BRANCH}  main=${MAIN_BRANCH}"
log "parked PRs: ${PR_PARKED}   metrics: ${LOOP_METRICS}"
agent_banner_lines
log "stop gracefully: ${B}touch ${STOP_FILE}${R}"

while :; do
  check_stop
  # Empty queue: read the file only. All loops share one GitHub API quota.
  if [ -z "$(queue_lines)" ]; then
    idle_begin
    countdown $((MERGE_POLL_MINUTES*60)) "queue empty — next look"
    continue
  fi

  cycle=$((cycle+1))
  banner "MERGE CYCLE $cycle  —  $(ts)  ($(queue_lines | grep -c .) queued)"
  agent_cycle_housekeeping

  prep_worktree; prc=$?
  if [ "$prc" -eq 2 ]; then
    net_fails=$((net_fails+1))
    [ "$net_fails" -ge "$NET_MAX_CYCLES" ] \
      && stop_loop "GITHUB UNREACHABLE for ${net_fails} cycles in a row — check the network and $LOG_DIR/git.log, then restart" 1
    warn "GitHub unreachable — skipping this cycle (${net_fails}/${NET_MAX_CYCLES} in a row)"
    banner "MERGE CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
    countdown $((CYCLE_MINUTES*60)) "until the next look"
    continue
  fi
  [ "$prc" -eq 0 ] || stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
  net_fails=0
  sync_database \
    || stop_loop "DATABASE MIGRATION STATE NEEDS A HUMAN — see $LOG_DIR/db.log, then restart the loop" 0
  [ -n "$(parked_lines)" ] && prune_parked

  MERGED_ANY=0; LAST_RESULT=""; ran=""
  mapfile -t lines < <(ordered_queue)
  for line in "${lines[@]}"; do
    IFS=$'\t' read -r _ pr branch _ _ _ <<< "$line"
    [ -n "$pr" ] || continue
    if ! info=$(gh_retry pr view "$pr" --json state,headRefName,baseRefName \
         --jq '"\(.state)\t\(.headRefName)\t\(.baseRefName)"'); then
      warn "could not read #${pr} from GitHub — leaving it queued"
      continue
    fi
    IFS=$'\t' read -r state head base <<< "$info"
    case "$state" in
      # Merged by hand: drop it, and sync main + DB before the next PR runs on stale code.
      MERGED) ok "#${pr} is already merged (outside this loop) — removing it from the queue"
              dequeue "$pr" merged; MERGED_ANY=1; break ;;
      CLOSED) warn "#${pr} was closed — removing it from the queue"
              dequeue "$pr" closed; continue ;;
      OPEN)   ;;
      *)      warn "#${pr} is in state '${state}' — leaving it queued"; continue ;;
    esac
    if [ "$head" != "$branch" ]; then
      warn "#${pr} carries ${head}, the queue says ${branch} — parking it instead of guessing"
      dequeue "$pr" parked "branch mismatch: PR head is ${head}, queue says ${branch}"
      continue
    fi
    # A PR targeting its unmerged parent has no CI to wait for yet: leave it, take the next.
    if [ "$base" != "$MAIN_BRANCH" ]; then
      warn "#${pr} (${branch}) targets ${base}, not ${MAIN_BRANCH} — its parent has not merged; leaving it queued"
      continue
    fi
    checkout_pr_branch "$branch"; crc=$?
    [ "$crc" -eq 3 ] && stop_loop "GIT STATE NEEDS A HUMAN — could not check out ${branch}" 1
    [ "$crc" -eq 0 ] || continue
    idle_finish
    merge_one "$pr" "$branch"
    ran="$pr"
    break
  done

  if [ "$MERGED_ANY" -eq 1 ]; then
    # main moved: bring this worktree's base branch and DB along, same rules as issue-loop.sh.
    prep_worktree; prc=$?
    [ "$prc" -eq 1 ] && stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
    [ "$prc" -eq 2 ] && warn "GitHub unreachable right after a merge — the next cycle syncs again"
    [ "$prc" -eq 0 ] && { sync_database \
      || stop_loop "MIGRATION MERGED — apply it to this worktree's DB, then restart the loop" 0; }
  else
    return_to_base
  fi

  if [ -z "$ran" ]; then
    [ -z "$(queue_lines)" ] && continue     # everything left the queue: back to the cheap poll
    [ "$MERGED_ANY" -eq 1 ] && continue     # synced after a merge done elsewhere: look again now
    idle_begin
    log "no queued PR can be merged right now (stacked, checked out elsewhere, or GitHub silent)"
    banner "MERGE CYCLE $cycle DONE — waiting ${MERGE_POLL_MINUTES}m"
    countdown $((MERGE_POLL_MINUTES*60)) "until the next look"
    continue
  fi

  case "$LAST_RESULT" in
    inconclusive|parked)
      inc_streak=$((inc_streak+1))
      grep -qFx "$ran" <<< "$inc_prs" || inc_prs+="${ran}"$'\n'
      n_inc_prs=$(grep -c . <<< "$inc_prs")
      if [ "$inc_streak" -ge "$MAX_FAILS" ] && [ "$n_inc_prs" -gt 1 ]; then
        stop_loop "REPEATED INCONCLUSIVE MERGES — ${inc_streak} runs in a row on ${n_inc_prs} PRs ended without a verdict; see $LOG_DIR. Human review." 1
      fi ;;
    *) inc_streak=0; inc_prs="" ;;
  esac

  check_stop
  banner "MERGE CYCLE $cycle DONE — next PR starts now"
done
