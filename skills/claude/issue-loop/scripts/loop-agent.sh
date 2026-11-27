# shellcheck shell=bash
# ──────────────────────────────────────────────────────────────
# Claude side of build-loop.sh / merge-loop.sh (sourced, never run).
# Everything that differs from the Codex twin lives here: how a phase is launched,
# where its final answer is, the skill-call literals and the prompt texts. The prompts
# are the ones issue-loop.sh sends, word for word; the build prompt only gains one line
# naming tickets whose PR has not merged yet.
# ──────────────────────────────────────────────────────────────

AGENT_NAME="claude"
MAIN_MODEL="opus"                       # fixed: build + triage coordinators always use Opus
PR_MODEL="opus"                         # fixed: the merge coordinator always uses Opus
# Per-phase thinking level: low|medium|high|xhigh|max. EMPTY IS NOT "no thinking" — the flag
# is then never passed, so the level comes from the account's settings.json `effortLevel`.
MAIN_EFFORT="${MAIN_EFFORT:-}"            # --effort for build + triage
PR_EFFORT="${PR_EFFORT:-}"                # --effort for merge
# Both phases run on the primary Claude account (~/.claude) by default; point a phase at another
# profile to move it, e.g. PR_CONFIG_DIR=~/.claude-max-2 merge-loop.sh
MAIN_CONFIG_DIR="${MAIN_CONFIG_DIR-$HOME/.claude}"  # CLAUDE_CONFIG_DIR for build/triage
PR_CONFIG_DIR="${PR_CONFIG_DIR-$HOME/.claude}"      # CLAUDE_CONFIG_DIR for merge
# Under --print the CLI waits only 10 min after the agent's last turn for background subagents,
# then kills them (wt2, 2026-11-09). 60 min covers a long slice; a hung task still cannot stall.
export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-3600000}"

agent_label() {  # agent_label <main|pr>
  if [ "$1" = "pr" ]; then printf 'claude (%s)' "$PR_MODEL"; else printf 'claude (%s)' "$MAIN_MODEL"; fi
}
skill_call() { printf '/%s' "$1"; }   # skill_call do-issue → /do-issue

agent_preflight() {
  command -v claude >/dev/null 2>&1 || { err "claude not on PATH"; return 1; }
}

agent_banner_lines() {
  log "models: build/triage=${MAIN_MODEL}  merge=${PR_MODEL}  helpers=Opus (frontend/browser=Sonnet 5.5)"
  log "effort: build/triage=${MAIN_EFFORT:-settings.json}  merge=${PR_EFFORT:-settings.json}"
  log "accounts: build/triage=${MAIN_CONFIG_DIR:-terminal default}  merge=${PR_CONFIG_DIR:-terminal default}"
}

# agent-browser Chromes outlive a run that ends without `agent-browser close`; their driver is
# gone, so they hang under systemd (one held a core and 2.8 GB for 17.5 h on 2026-09-27).
# A browser a live run owns always has its driver as parent, so it is never touched.
REAP_BROWSER_MIN_AGE="${REAP_BROWSER_MIN_AGE:-7200}"   # seconds; younger orphans are left alone
agent_cycle_housekeeping() {
  local pid parent age
  for pid in $(pgrep -f "$HOME/.agent-browser/browsers/[^ ]*/chrome --remote-debugging-port" 2>/dev/null); do
    parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$parent" ] || continue
    [ "$(ps -o comm= -p "$parent" 2>/dev/null)" = systemd ] || continue   # PID 1 or a user subreaper
    age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [ "${age:-0}" -ge "$REAP_BROWSER_MIN_AGE" ] || continue
    [ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$pid" ] || continue
    kill -KILL -- "-$pid" 2>/dev/null \
      && warn "reaped orphaned agent-browser Chrome $pid (running $((age/3600))h, no driver)"
  done
  return 0
}

# The agent's FINAL message, extracted from the stream-json log. Sentinels are matched against
# THIS, never the raw stream: an agent that merely narrates the contract mid-run would otherwise
# read as having emitted it. Missing or failed terminal results produce no verdict.
final_message() {  # final_message <stream-json-logfile>
  python3 - "$1" <<'PY' 2>/dev/null
import json, sys
out = ""
for line in open(sys.argv[1], errors="replace"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if not isinstance(d, dict):
        continue
    if d.get("type") == "result":
        out = d.get("result", "") if not d.get("is_error") and d.get("subtype", "success") == "success" else ""
        if not isinstance(out, str):
            out = ""
print(out)
PY
}

run_agent() {  # run_agent <main|pr> <logfile> <prompt>
  local phase="$1" logfile="$2" prompt="$3" model cfg effort
  if [ "$phase" = "pr" ]; then model="$PR_MODEL"; cfg="$PR_CONFIG_DIR"; effort="$PR_EFFORT"
  else model="$MAIN_MODEL"; cfg="$MAIN_CONFIG_DIR"; effort="$MAIN_EFFORT"; fi
  local -a eff=()
  [ -n "$effort" ] && eff=(--effort "$effort")
  if [ -n "$cfg" ]; then
    CLAUDE_CONFIG_DIR="$cfg" env -u CLAUDE_CODE_SUBAGENT_MODEL claude --model "$model" "${eff[@]}" --permission-mode bypassPermissions \
      --output-format stream-json --verbose \
      --print "$prompt" </dev/null 2>&1 | tee "$logfile" | render
  else
    env -u CLAUDE_CODE_SUBAGENT_MODEL claude --model "$model" "${eff[@]}" --permission-mode bypassPermissions \
      --output-format stream-json --verbose \
      --print "$prompt" </dev/null 2>&1 | tee "$logfile" | render
  fi
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
  printf '%s' "/triage Triage every needs-triage ticket in $1 — that folder only. \
Autonomous run, never prompt: when a ticket's requirements are met and it is buildable by an \
agent, flip it to ready-for-agent; when they are not, set ready-for-human (or needs-info) and \
append a one-line dated reason to the ticket's Comments. Change nothing outside that folder."
}

build_prompt() {  # build_prompt <tracker> <not-done-tickets, comma-separated or empty>
  local p
  p="/do-issue Work $1 — that folder ONLY, ignore every other tracker. \
Pick the ticket yourself: the lowest-numbered ready-for-agent ticket whose '**Blocked by:**' \
entries are all done. If the ticket you would otherwise pick is blocked, do NOT stop — follow its \
blocker chain and build the BLOCKING ticket instead (the deepest one that is itself unblocked and \
ready-for-agent), so the chain clears from the bottom up. Build it end-to-end, opening a PR \
against ${MAIN_BRANCH} when the local gate is green. Any new issue you need to file belongs in \
that same folder. Only if EVERY ready-for-agent ticket is blocked by something unfinished: change \
nothing and say so."
  [ -n "$2" ] && p="${p} Treat these tickets as NOT done, their PR has not merged: ${2}."
  printf '%s' "$p"
}

merge_prompt() {  # merge_prompt <pr> <attempt>
  local pr="$1" attempt="$2"
  if [ "$attempt" -le 1 ]; then printf '%s' "/do-pr auto #${pr}"; return; fi
  printf '%s' "/do-pr auto #${pr} — RETRY (attempt ${attempt}). A previous run attempted \
this PR and ended without merging it and without a sentinel. Read completed review reports, \
compare both base and head SHAs, and reuse only complete layers with resolved findings. An \
interrupted or usage-limited review is incomplete. Finish missing or invalidated do-pr gates. \
Confirm gh pr view and gh pr checks --watch --interval 30; merge only after every gate passes. If you find \
a real blocker, comment it on the PR and emit <<<MERGE_BLOCKED #${pr} reason>>>. End with exactly \
one sentinel — a summary without one is a failed run."
}
RETRY_WARN="checking completed review evidence"
