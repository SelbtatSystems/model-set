#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# build loop (ralph loop over ONE tracker folder, builds only):
#   each cycle: ff worktree to main → TRIAGE only if nothing is startable →
#   BUILD the next startable ticket (do-issue) → queue its PR → next cycle AT ONCE
# No merge phase: merge-loop.sh merges the queued PRs of every build loop, oldest first.
# Waits CYCLE_MINUTES only when nothing is startable. A blocker counts as done only once
# its PR has merged (the merged-blocker rule), so the loop never builds on unmerged code.
# stops on: folder finished (nothing startable, nothing to triage, no PR of this tracker
#           queued), an unexpected state, touch .issue-loop-stop, Ctrl-C.
# usage: ~/.codex/skills/issue-loop/scripts/build-loop.sh <tracker-folder>
# ──────────────────────────────────────────────────────────────
set -uo pipefail   # NOT -e: the loop decides what is fatal, line by line

# issue-loop.sh accepts a lock owner as live only when "issue-loop.sh" is in its command
# line. Re-run this script once with that string in argv[0], so issue-loop.sh refuses a
# build loop on the same worktree or tracker without any change to issue-loop.sh. exec keeps
# the pid, which is how the second pass knows it already happened.
if [ "${ISSUE_LOOP_ARGV0:-}" != "$$" ]; then
  export ISSUE_LOOP_ARGV0=$$
  exec -a "build-loop.sh[issue-loop.sh]" "$BASH" "${BASH_SOURCE[0]}" "$@"
fi
unset ISSUE_LOOP_ARGV0

TRACKER_DIR="${1:-}"
# Before the cd below: a relative script path would not resolve from the worktree root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# All relative paths belong to the worktree root (same reason as issue-loop.sh).
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'build-loop: not inside a git worktree\n' >&2
  exit 1
}
cd "$REPO_ROOT" || exit 1

PRETTY_SCRIPT="$SCRIPT_DIR/pretty-stream.py"
# shellcheck source=loop-common.sh
. "$SCRIPT_DIR/loop-common.sh"
# shellcheck source=loop-agent.sh
. "$SCRIPT_DIR/loop-agent.sh"

# The tracker as the queue records it. The lock name below stays derived from the raw
# argument, exactly as issue-loop.sh derives it, or the two runners would not collide.
TRACKER_KEY="${TRACKER_DIR%/}"; TRACKER_KEY="${TRACKER_KEY#./}"
LOOP_NAME="build:${TRACKER_KEY}"
WORKTREE_LOCK="$LOG_DIR/loop.lock"        # one loop per worktree (same file as issue-loop.sh)
TRACKER_LOCK="$LOCK_HOME/$(printf '%s' "${TRACKER_DIR:-none}" | tr '/ ' '__').lock"  # one loop per tracker
mkdir -p "$LOG_DIR"
rm -f "$STOP_FILE"

trap 'printf "\n"; warn "Ctrl-C — hard stop."; exit 130' INT
# Locks must not outlive the loop, however it ends (banner, Ctrl-C, crash).
trap 'idle_finish; release_lock "${WORKTREE_LOCK:-}"; release_lock "${TRACKER_LOCK:-}"' EXIT

# ---- tracker-folder state (deterministic, script-side; as issue-loop.sh) -----
# Tickets ONLY — the tracker's issues/ dir, never the folder root (PRD.md has a Triage line).
list_role()  { grep -rlE "^\*\*Triage:\*\*[[:space:]]*$1" --include='*.md' \
                 --exclude='NEEDS-HUMAN.md' "$TRACKER_DIR/issues" 2>/dev/null; }
count_role() { list_role "$1" | wc -l | tr -d ' '; }
blocker_names() {  # blocker_names <ticket-file>
  grep -m1 -E '^\*\*Blocked by:\*\*' "$1" 2>/dev/null | grep -oE '[0-9]+-[A-Za-z0-9._-]+\.md' || true
}
is_done() {  # is_done <ticket-basename>
  grep -qE '^\*\*Triage:\*\*[[:space:]]*(done|wontfix)' "$TRACKER_DIR/issues/$1" 2>/dev/null
}

# <basename>\t<role> for every ticket; run_build compares two snapshots to learn which
# ticket the build moved, and that is the ticket the queue line names.
ticket_roles() {
  local f
  for f in "$TRACKER_DIR"/issues/*.md; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "NEEDS-HUMAN.md" ] && continue
    printf '%s\t%s\n' "$(basename "$f")" \
      "$(grep -m1 -E '^\*\*Triage:\*\*' "$f" | sed -E 's/^\*\*Triage:\*\*[[:space:]]*//; s/[[:space:]].*$//')"
  done
}

# The merged-blocker rule. do-issue marks a ticket done when it OPENS the PR, so "done" alone
# would let this loop build on code that is not on main yet. A done blocker still counts as
# NOT done while a PR for it sits in the queue or in pr-parked.tsv, unless GitHub says that
# PR is MERGED (merged by hand, or the merge loop has not removed the line yet).
# GitHub is asked only about blockers some ready ticket actually names. An unanswered
# question counts as "not merged": building on an unmerged blocker is the error that costs.
UNMERGED=""      # one ticket basename per line, recomputed every cycle
compute_unmerged() {
  UNMERGED=""
  local blockers f pr tracker tickets t state
  blockers=$(while IFS= read -r f; do [ -n "$f" ] && blocker_names "$f"; done \
               <<< "$(list_role 'ready-for-agent')" | sort -u)
  [ -n "$blockers" ] || return 0
  while IFS=$'\t' read -r _ pr _ tracker tickets _; do
    [ "$tracker" = "$TRACKER_KEY" ] || continue
    for t in ${tickets//,/ }; do
      grep -qFx -- "$t" <<< "$blockers" || continue
      grep -qFx -- "$t" <<< "$UNMERGED" && continue
      is_done "$t" || continue          # still open anyway; do-issue already sees that
      state=$(gh_retry pr view "$pr" --json state --jq .state) || state=""
      [ "$state" = "MERGED" ] && continue
      UNMERGED+="${t}"$'\n'
    done
  done < <(queue_lines; parked_lines)
  return 0
}
unmerged_list() { grep -v '^$' <<< "$UNMERGED" | paste -sd, - | sed 's/,/, /g'; }

# A ready-for-agent ticket is startable only when every ticket its `**Blocked by:**` line names
# is done or wontfix AND not held back by the merged-blocker rule. A named file that no longer
# exists counts as satisfied (renamed or archived), as in issue-loop.sh.
count_startable() {
  local f b open n=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    open=0
    for b in $(blocker_names "$f"); do
      [ -f "$TRACKER_DIR/issues/$b" ] || continue
      if ! is_done "$b" || grep -qFx -- "$b" <<< "$UNMERGED"; then open=1; break; fi
    done
    [ "$open" -eq 0 ] && n=$((n+1))
  done <<< "$(list_role 'ready-for-agent')"
  echo "$n"
}

queued_for_tracker() { queue_lines | awk -F'\t' -v t="$TRACKER_KEY" '$4 == t' | grep -c . ; }
parked_for_tracker() { parked_lines | awk -F'\t' -v t="$TRACKER_KEY" '$4 == t'; }

# Migrations of this worktree's own in-flight PRs explain orphans in this worktree's DB.
inflight_branches() {
  { queue_lines; parked_lines; } | awk -F'\t' -v w="$REPO_ROOT" '$6 == w { print $3 }'
}

# NEEDS-HUMAN.md is the standing surface for tickets waiting on a person, plus this tracker's
# PRs the merge loop parked. Rebuilt each time nothing is startable, deleted when empty.
write_needs_human() {
  local files parked
  files=$( { list_role "ready-for-human"; list_role "needs-info"; } | sort -u )
  parked=$(parked_for_tracker | awk -F'\t' '{ printf "- #%s `%s` — %s (parked %s)\n", $2, $3, $8, $7 }')
  if [ -z "$files" ] && [ -z "$parked" ]; then rm -f "$TRACKER_DIR/NEEDS-HUMAN.md"; return 0; fi
  {
    printf '# Needs a human\n\n'
    printf 'Written by build-loop on %s — work the loop cannot take further.\n\n' "$(ts)"
    if [ -n "$parked" ]; then
      printf '## PRs parked by the merge loop\n\n'
      printf 'Each PR is still open with its branch intact. Read the gate comment on the PR, fix or\n'
      printf 'close it, then move its line from `%s` back to `%s`\n' "$PR_PARKED" "$PR_QUEUE"
      printf '(the first six columns) for the merge loop to take it again.\n\n'
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

# ---- pre-flight ------------------------------------------------------------
preflight() {
  step "Pre-flight checks…"
  [ -n "$TRACKER_DIR" ] || { err "usage: build-loop.sh <tracker-folder>"; return 1; }
  [ -d "$TRACKER_DIR" ] || { err "tracker folder not found: $TRACKER_DIR"; return 1; }
  grep -rqE "^\*\*Triage:\*\*" --include='*.md' "$TRACKER_DIR" 2>/dev/null \
    || { err "no '**Triage:**' lines in $TRACKER_DIR — is this a tracker folder?"; return 1; }
  acquire_lock "$WORKTREE_LOCK" "in this worktree" || return 1
  acquire_lock "$TRACKER_LOCK"  "on this tracker"  || { release_lock "$WORKTREE_LOCK"; return 1; }
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

# ---- PR ownership (as issue-loop.sh, minus its private ledger) ----------------
# Non-zero here means "could not ask GitHub", never "no PRs are open".
open_pr_branches() {
  gh_retry pr list --state open --limit 200 --json headRefName --jq '.[].headRefName' | sort
}
# The branch an open PR carries this local branch's commits on (an agent may push a rework
# with `git push origin HEAD:<pr-branch>`). Prints it and returns 0; prints the local name
# and returns 1 when no open PR holds it.
pr_branch_for() {
  local b="$1" open up sha via_sha
  open=$(open_pr_branches) || { echo "$b"; return 1; }
  if printf '%s\n' "$open" | grep -qFx "$b"; then echo "$b"; return 0; fi
  up=$(git rev-parse --abbrev-ref --symbolic-full-name "${b}@{upstream}" 2>/dev/null)
  up=${up#origin/}
  if [ -n "$up" ] && printf '%s\n' "$open" | grep -qFx "$up"; then echo "$up"; return 0; fi
  sha=$(git rev-parse -q --verify "${b}^{commit}" 2>/dev/null)
  if [ -n "$sha" ]; then
    via_sha=$(gh_retry pr list --state open --limit 200 --json headRefName,headRefOid \
      --jq ".[] | select(.headRefOid == \"${sha}\") | .headRefName" | head -1)
    if [ -n "$via_sha" ]; then echo "$via_sha"; return 0; fi
  fi
  echo "$b"; return 1
}
# Branch names this worktree checked out, from line $1 of its private HEAD reflog onward.
visited_branches() {
  local from="${1:-0}" reflog
  reflog=$(git rev-parse --git-path logs/HEAD)
  [ -r "$reflog" ] || return 0
  tail -n "+$((from + 1))" "$reflog" 2>/dev/null \
    | sed -n 's/.*checkout: moving from .* to \(.*\)$/\1/p' \
    | grep -vFx "$BASE_BRANCH" | grep -Ev '^[0-9a-f]{7,40}$' | grep -Ev '^(origin|upstream)/' \
    | grep -v '^$' | sort -u
}
open_pr_for_branch() {  # prints the PR number or nothing; non-zero = GitHub did not answer
  local pr
  pr=$(gh_retry pr list --state open --head "$1" --json number --jq '.[0].number') || return 1
  [ "$pr" = "null" ] && pr=""
  printf '%s' "$pr"
}

# returns 0 = newly queued, 3 = already queued, 4 = parked. A failed write stops the loop:
# a PR nobody queued is a PR nobody merges.
enqueue_pr() {  # enqueue_pr <pr> <branch> <tickets>
  local pr="$1" branch="$2" tickets="${3:--}" qrc
  queue_append "$pr" "$branch" "$TRACKER_KEY" "$tickets" "$REPO_ROOT"; qrc=$?
  case "$qrc" in
    0) ok "queued PR #${pr} (${branch}, ticket ${tickets}) for the merge loop"; metric queued "#${pr}" ;;
    3) log "PR #${pr} is already in the merge queue" ;;
    4) warn "PR #${pr} is parked — not re-queuing it; a person decides (see $PR_PARKED)" ;;
    *) stop_loop "PR QUEUE WRITE FAILED — PR #${pr} (${branch}) is NOT queued; fix $PR_QUEUE, add it, restart" 1 ;;
  esac
  return "$qrc"
}

# ---- triage phase (as issue-loop.sh) ------------------------------------------
run_triage() {
  local logfile
  logfile="$LOG_DIR/triage-$(date +%Y%m%d-%H%M%S).log"
  step "Launching $(agent_label main) → $(skill_call triage) over ${TRACKER_DIR} …"
  log "streaming below + → ${D}$logfile${R}"
  run_agent main "$logfile" "$(triage_prompt "$TRACKER_DIR")"
  local rc=$?
  [ "$rc" -ne 0 ] && { err "triage agent exited rc=$rc"; return 1; }
  ok "triage pass finished."
  return 0
}
# A pass that moves no ticket out of needs-triage counts as a failure.
triage_pass() {
  local before
  before=$(count_role "needs-triage")
  run_triage || { fails=$((fails+1)); warn "triage failure ${fails}/${MAX_FAILS}"; return; }
  if [ "$(count_role 'needs-triage')" -ge "$before" ]; then
    fails=$((fails+1))
    warn "triage moved no ticket ${fails}/${MAX_FAILS}"
  fi
}

# A build agent that dies after committing and before pushing strands real work on a local
# branch. Push what is committed (never forced), then still score the cycle a failure.
rescue_unpushed_work() {  # rescue_unpushed_work <branch>
  local branch="$1" ahead pr
  [ -n "$branch" ] || return 0
  [ "$branch" = "$BASE_BRANCH" ] && return 0
  [ "$branch" = "$MAIN_BRANCH" ] && return 0
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    warn "${branch} has uncommitted changes — not pushing a half-finished tree; inspect this worktree"
    return 0
  fi
  git fetch -q origin "$branch" >>"$LOG_DIR/git.log" 2>&1 || true
  if git rev-parse --quiet --verify "refs/remotes/origin/${branch}" >/dev/null 2>&1; then
    ahead=$(git rev-list --count "origin/${branch}..${branch}" 2>/dev/null || echo 0)
    [ "${ahead:-0}" -gt 0 ] || return 0
    log "rescuing ${ahead} unpushed commit(s) on ${branch} from the failed build"
  else
    log "rescuing ${branch} — the agent never pushed it at all"
  fi
  if ! git push origin "$branch" >>"$LOG_DIR/git.log" 2>&1; then
    err "could not push ${branch} — see $LOG_DIR/git.log; the commits are safe in this worktree"
    return 0
  fi
  if ! pr=$(open_pr_for_branch "$branch"); then
    warn "pushed ${branch} — could not reach GitHub to see whether a PR points at it"
  elif [ -n "$pr" ]; then
    ok "pushed ${branch} — PR #${pr} now points at it"
    enqueue_pr "$pr" "$branch" "-"
  else
    warn "pushed ${branch} — no PR is open for it, so nothing reviews it until someone opens one"
  fi
  return 0
}

# Tickets the build moved out of ready-for-agent, comma-separated; the ones it marked done
# win over any it moved elsewhere. Empty when the build changed no Triage line.
changed_tickets() {  # changed_tickets <ticket_roles snapshot from before the build>
  local before="$1" name role old done_list="" other=""
  while IFS=$'\t' read -r name role; do
    [ -n "$name" ] || continue
    old=$(awk -F'\t' -v n="$name" '$1 == n { print $2; exit }' <<< "$before")
    [ "$old" = "ready-for-agent" ] && [ "$role" != "ready-for-agent" ] || continue
    if [ "$role" = "done" ]; then done_list+="${done_list:+,}${name}"
    else other+="${other:+,}${name}"; fi
  done <<< "$(ticket_roles)"
  printf '%s' "${done_list:-$other}"
}

# ---- build phase --------------------------------------------------------------
# returns 0 = progress (PR opened or a ticket closed), 1 = agent failure, 4 = no progress,
# 5 = the agent reports nothing it can take
run_build() {
  local logfile before_ready roles_before REFLOG reflog_before head_before sha_before started
  logfile="$LOG_DIR/build-$(date +%Y%m%d-%H%M%S).log"
  before_ready=$(count_role "ready-for-agent")
  roles_before=$(ticket_roles)
  head_before=$(git symbolic-ref --short -q HEAD)
  sha_before=$(git rev-parse -q --verify HEAD)
  REFLOG=$(git rev-parse --git-path logs/HEAD)
  reflog_before=$(wc -l < "$REFLOG" 2>/dev/null || echo 0)
  local not_done; not_done=$(unmerged_list)
  step "Launching $(agent_label main) → $(skill_call do-issue) in ${TRACKER_DIR} …"
  [ -n "$not_done" ] && log "treating as NOT done (PR not merged yet): ${not_done}"
  log "streaming below + → ${D}$logfile${R}"
  started=$(date +%s)
  metric build_start -
  run_agent main "$logfile" "$(build_prompt "$TRACKER_DIR" "$not_done")"
  local rc=$?
  local tickets; tickets=$(changed_tickets "$roles_before")
  local visited; visited=$(visited_branches "$reflog_before")
  [ -n "$visited" ] && BUILT_BRANCHES+="${visited}"$'\n'
  # Which branch carries this build's PR. Primary signal: the branch the agent left HEAD on;
  # fallback: this worktree's private reflog (no other loop can write to it).
  local cur candidates="" b pb
  cur=$(git symbolic-ref --short -q HEAD)
  if [ -n "$cur" ] && [ "$cur" != "$BASE_BRANCH" ]; then
    if [ "$cur" = "$head_before" ] && [ "$(git rev-parse -q --verify HEAD)" = "$sha_before" ]; then
      log "build left HEAD on ${cur}, untouched since before the build — not queuing it"
    else
      candidates=$(pr_branch_for "$cur")
    fi
  else
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      if pb=$(pr_branch_for "$b"); then
        candidates+="${pb}"$'\n'
        warn "agent left HEAD on ${BASE_BRANCH}; found ${pb} in this worktree's reflog"
      fi
    done <<< "$visited"
  fi
  # Queue every open PR this build produced, even when the agent failed afterwards: the PR
  # exists, and the merge loop decides whether it is good enough.
  local opened=0 pr
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if ! pr=$(open_pr_for_branch "$b"); then
      err "could not verify the build's PR on ${b} — see $LOG_DIR/gh.log"
      continue
    fi
    [ -n "$pr" ] || continue
    opened=1
    enqueue_pr "$pr" "$b" "$tickets"
  done <<< "$(sort -u <<< "$candidates")"
  local secs=$(( $(date +%s) - started ))
  if [ "$rc" -ne 0 ]; then
    err "build agent exited rc=$rc"
    rescue_unpushed_work "$cur"
    metric build_end:failed "${tickets:--}" "$secs"
    return 1
  fi
  if final_message "$logfile" | grep -qF '<<<NO_OPEN_ISSUES>>>'; then
    log "agent reports no open issues it can take"
    metric build_end:no_work "${tickets:--}" "$secs"
    return 5
  fi
  # Progress is measured, not claimed: an open PR, or a ticket that left ready-for-agent.
  if [ "$opened" -eq 1 ] || [ "$(count_role 'ready-for-agent')" -lt "$before_ready" ]; then
    ok "build finished."
    metric build_end:ok "${tickets:--}" "$secs"
    return 0
  fi
  warn "build opened no PR and closed no ticket"
  metric build_end:no_progress - "$secs"
  return 4
}

# ---- terminal path: nothing startable, nothing to triage, no PR of ours queued ------------
# Never retires the folder while a PR this run built is open but unqueued: the sweep queues
# it first, and the loop then waits for it like any other queued PR.
finish_tracker() {
  local b pb pr swept=0 n_human n_parked n_ready
  open_pr_branches >/dev/null || {
    warn "GitHub unreachable at the finish line — not retiring the folder; retrying next cycle"
    return 0
  }
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    pb=$(pr_branch_for "$b") || continue
    pr=$(open_pr_for_branch "$pb") || continue
    [ -n "$pr" ] || continue
    if enqueue_pr "$pr" "$pb" "-"; then
      swept=$((swept+1)); warn "final sweep: ${pb} (#${pr}) was built here and is still open — queued it"
    fi
  done <<< "$(sort -u <<< "$BUILT_BRANCHES")"
  if [ "$swept" -gt 0 ]; then
    log "final sweep queued ${swept} PR(s) — waiting for them to merge before finishing"
    return 0
  fi
  write_needs_human
  n_human=$(( $(count_role "ready-for-human") + $(count_role "needs-info") ))
  n_parked=$(parked_for_tracker | grep -c .)
  n_ready=$(count_role "ready-for-agent")
  if [ "$n_human" -gt 0 ] || [ "${n_parked:-0}" -gt 0 ] || [ "$n_ready" -gt 0 ]; then
    stop_loop "FOLDER FINISHED FOR AGENTS — ${n_human} ticket(s) need a human, ${n_parked:-0} PR(s) parked at a gate, ${n_ready} ready ticket(s) still blocked: ${TRACKER_DIR}/NEEDS-HUMAN.md" 2
  fi
  stop_loop "ALL ISSUES DONE — ${TRACKER_DIR} fully worked and every PR merged" 0
}

# Nothing to build this cycle: triage if that can release work, finish if the folder is
# done, otherwise wait for a queued PR of this tracker to merge and unblock something.
nothing_to_build() {  # nothing_to_build <triaged-this-cycle 0|1>
  local n_queued
  if [ "$(count_role 'needs-triage')" -gt 0 ]; then
    [ "$1" = 1 ] || { log "nothing startable; $(count_role 'needs-triage') ticket(s) need triage — triaging"; triage_pass; }
    return 0
  fi
  n_queued=$(queued_for_tracker)
  if [ "$n_queued" -eq 0 ]; then
    log "nothing startable, nothing to triage, no PR of this tracker queued — finishing up"
    finish_tracker
    return 0
  fi
  log "nothing startable — waiting for ${n_queued} queued PR(s) of this tracker to merge"
  idle_begin
}

# ──────────────────────────────────────────────────────────────
preflight || stop_loop "PRE-FLIGHT FAILED — fix the above and restart" 1

cycle=0
fails=0
net_fails=0
# Branches this run's builds checked out; the final sweep queues only these.
BUILT_BRANCHES=""
banner "BUILD LOOP STARTING — ${TRACKER_DIR}"
log "worktree: ${B}$(pwd)${R}"   # printed loudly: starting in the wrong worktree is easy to miss
log "idle wait=${CYCLE_MINUTES}m  base=${BASE_BRANCH}  main=${MAIN_BRANCH}"
log "queue: ${PR_QUEUE}  (merge-loop.sh merges it; this loop never calls do-pr)"
agent_banner_lines
log "stop gracefully: ${B}touch ${STOP_FILE}${R}"
# issue-loop.sh's private ledger is invisible to the merge loop. Say so loudly at the switch.
if [ -s "$LOG_DIR/pending-branches" ]; then
  warn "issue-loop ledger $LOG_DIR/pending-branches still lists: $(tr '\n' ' ' < "$LOG_DIR/pending-branches")"
  warn "the merge loop serves only ${PR_QUEUE} — queue those PRs there or merge them by hand"
fi

while :; do
  check_stop
  cycle=$((cycle+1))
  banner "CYCLE $cycle  —  $(ts)"
  agent_cycle_housekeeping

  prep_worktree; prc=$?
  if [ "$prc" -eq 2 ]; then
    # Unreachable is not a git problem: nothing was touched, so wait a cycle and try again.
    net_fails=$((net_fails+1))
    [ "$net_fails" -ge "$NET_MAX_CYCLES" ] \
      && stop_loop "GITHUB UNREACHABLE for ${net_fails} cycles in a row — check the network and $LOG_DIR/git.log, then restart" 1
    warn "GitHub unreachable — skipping this cycle (${net_fails}/${NET_MAX_CYCLES} in a row)"
    banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
    countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
    continue
  fi
  [ "$prc" -eq 0 ] || stop_loop "GIT STATE NEEDS A HUMAN — stopping" 1
  net_fails=0
  sync_database \
    || stop_loop "DATABASE MIGRATION STATE NEEDS A HUMAN — see $LOG_DIR/db.log, then restart the loop" 0

  # Building comes FIRST; triage runs only when nothing is startable.
  compute_unmerged
  n_startable=$(count_startable)
  triaged=0
  if [ "$n_startable" -eq 0 ] && [ "$(count_role 'needs-triage')" -gt 0 ]; then
    log "nothing startable to build ($(count_role 'ready-for-agent') ready, all blocked); $(count_role 'needs-triage') ticket(s) need triage"
    triage_pass; triaged=1
    compute_unmerged
    n_startable=$(count_startable)   # triage may have just released work
  fi

  if [ "$n_startable" -gt 0 ]; then
    idle_finish
    log "${n_startable} ticket(s) startable (incl. any follow-ups filed by QA)"
    run_build; brc=$?
    case "$brc" in
      0) fails=0
         check_stop
         banner "CYCLE $cycle DONE — next cycle starts now (no merge wait)"
         continue ;;
      5) write_needs_human; nothing_to_build "$triaged" ;;
      4) fails=$((fails+1))
         warn "no progress ${fails}/${MAX_FAILS} — every remaining ready-for-agent ticket may still have an open blocker" ;;
      *) fails=$((fails+1)); warn "build failure ${fails}/${MAX_FAILS} — continuing" ;;
    esac
  else
    write_needs_human
    nothing_to_build "$triaged"
  fi

  [ "$fails" -ge "$MAX_FAILS" ] && stop_loop "TOO MANY CONSECUTIVE FAILURES — stopping" 1

  check_stop
  banner "CYCLE $cycle DONE — waiting ${CYCLE_MINUTES}m"
  countdown $((CYCLE_MINUTES*60)) "until cycle $((cycle+1))"
done
