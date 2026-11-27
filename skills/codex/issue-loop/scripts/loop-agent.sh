# shellcheck shell=bash
# ──────────────────────────────────────────────────────────────
# Codex side of build-loop.sh / merge-loop.sh (sourced, never run).
# Everything that differs from the Claude twin lives here: how a phase is launched,
# where its final answer is, the skill-call literals and the prompt texts. The prompts
# are the ones issue-loop.sh sends, word for word; the build prompt only gains one line
# naming tickets whose PR has not merged yet.
# ──────────────────────────────────────────────────────────────

AGENT_NAME="codex"
MAIN_MODEL="${MAIN_MODEL:-}"             # empty = current Codex configuration
MAIN_EFFORT="${MAIN_EFFORT:-}"           # build + triage reasoning effort
PR_MODEL="${PR_MODEL:-}"                 # empty = current Codex configuration
PR_EFFORT="${PR_EFFORT:-}"               # merge reasoning effort

agent_label() {  # agent_label <main|pr>
  if [ "$1" = "pr" ]; then printf 'codex (%s, %s)' "${PR_MODEL:-configured model}" "${PR_EFFORT:-configured effort}"
  else printf 'codex (%s, %s)' "${MAIN_MODEL:-configured model}" "${MAIN_EFFORT:-configured effort}"; fi
}
skill_call() { printf '$%s' "$1"; }   # skill_call do-issue → $do-issue

agent_preflight() {
  command -v codex  >/dev/null 2>&1 || { err "codex not on PATH"; return 1; }
  codex login status >/dev/null 2>&1 || { err "Codex not authenticated (run: codex login)"; return 1; }
}

agent_banner_lines() {
  log "runtime: codex  login/config: current Codex environment"
  log "models: build/triage=${MAIN_MODEL:-configured default} (${MAIN_EFFORT:-configured effort})  merge=${PR_MODEL:-configured default} (${PR_EFFORT:-configured effort})"
}

# Claude-only housekeeping (orphaned agent-browser Chromes); nothing to do for Codex.
agent_cycle_housekeeping() { return 0; }

# Completion markers belong only to Codex's final answer, never progress/tool output.
# Missing output remains inconclusive; it is not evidence of success or a blocked PR.
final_message() {  # final_message <jsonl-logfile>
  [ -f "$1.final.txt" ] && cat "$1.final.txt"
}

run_agent() {  # run_agent <main|pr> <logfile> <prompt>
  local phase="$1" logfile="$2" prompt="$3" model effort
  if [ "$phase" = "pr" ]; then model="$PR_MODEL"; effort="$PR_EFFORT"
  else model="$MAIN_MODEL"; effort="$MAIN_EFFORT"; fi
  local model_args=()
  [ -n "$model" ] && model_args+=(--model "$model")
  [ -n "$effort" ] && model_args+=(-c "model_reasoning_effort=$effort")
  # A reused log name must not leave a previous run's verdict after a startup failure.
  rm -f "$logfile.final.txt"
  # Docker and the external vault need the existing unattended development permissions.
  codex exec --json --sandbox danger-full-access -c approval_policy=never \
    "${model_args[@]}" --cd "$REPO_ROOT" --output-last-message "$logfile.final.txt" \
    "$prompt" </dev/null 2>&1 | tee "$logfile" | render
  local rc=${PIPESTATUS[0]} result_rc
  python3 "$SCRIPT_DIR/agent-result.py" "$logfile"; result_rc=$?
  if [ "$result_rc" -eq 75 ]; then
    stop_loop "USAGE LIMIT — review incomplete; pending PR retained. Resume after capacity returns." 75
  fi
  [ "$rc" -ne 0 ] && return "$rc"
  return "$result_rc"
}

# ---- prompts (issue-loop.sh's texts) ----------------------------------------
triage_prompt() {  # triage_prompt <tracker>
  printf '%s' "\$triage Triage every needs-triage ticket in $1 — that folder only. \
Read AGENTS.md and use the installed Codex triage skill. This invocation authorizes the \
existing autonomous triage workflow; no human is present. Complete the pass in this session. \
Autonomous run, never prompt: when a ticket's requirements are met and it is buildable by an \
agent, flip it to ready-for-agent; when they are not, set ready-for-human (or needs-info) and \
append a one-line dated reason to the ticket's Comments. Change nothing outside that folder."
}

build_prompt() {  # build_prompt <tracker> <not-done-tickets, comma-separated or empty>
  local p
  p="\$do-issue Work $1 — that folder ONLY, ignore every other tracker. \
Read AGENTS.md and follow the installed Codex do-issue skill through verification, PR creation, \
and tracker update. This invocation authorizes that existing autonomous workflow. Wait for every \
started test, CI job and delegated task before your final answer; report an actual blocker when \
you cannot complete it. Pick the ticket yourself: the lowest-numbered ready-for-agent ticket whose '**Blocked by:**' \
entries are all done. If the ticket you would otherwise pick is blocked, do NOT stop — follow its \
blocker chain and build the BLOCKING ticket instead (the deepest one that is itself unblocked and \
ready-for-agent), so the chain clears from the bottom up. Build it end-to-end, opening a draft PR \
against ${MAIN_BRANCH} when the local gate is green. Any new issue you need to file belongs in \
that same folder. Only if EVERY ready-for-agent ticket is blocked by something unfinished: change \
nothing and say so."
  [ -n "$2" ] && p="${p} Treat these tickets as NOT done, their PR has not merged: ${2}."
  printf '%s' "$p"
}

merge_prompt() {  # merge_prompt <pr> <attempt>
  local pr="$1" attempt="$2"
  if [ "$attempt" -le 1 ]; then printf '%s' "\$do-pr auto #${pr}"; return; fi
  printf '%s' "\$do-pr auto #${pr} — RETRY (attempt ${attempt}). A previous run attempted \
this PR and ended without merging it and without a sentinel. Read the existing review evidence \
and compare both base and head SHAs. Reuse only complete checks with resolved findings for these \
revisions; complete missing or invalidated do-pr gates. Confirm gh pr view and gh pr checks --watch \
--interval 30; merge only when every do-pr gate passes and emit the sentinel. If you find \
a real blocker, comment it on the PR and emit <<<MERGE_BLOCKED #${pr} reason>>>. End with exactly \
one sentinel — a summary without one is a failed run."
}
RETRY_WARN="checking prior review evidence"
