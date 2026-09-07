#!/usr/bin/env python3
"""Exercise the runner with local Git and fake services; never launch an agent.

Run: python3 scripts/test_issue_loop.py
Only the Python standard library, Bash and Git are required. All mutable state,
Git remotes and tool substitutes live in a temporary directory per test.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


RUNNER = Path(__file__).with_name("issue-loop.sh")
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
root = pathlib.Path(os.environ["LOOP_TEST_ROOT"])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state_path = root / "mock-state.json"
state = json.loads(state_path.read_text())
if name == "date":
    if args == ["+%Y%m%d-%H%M%S"]:
        print("20260907-120000")
        sys.exit(0)
    os.execv("/bin/date", ["date", *args])
def save():
    state_path.write_text(json.dumps(state))
def record(**fields):
    with (root / "calls.jsonl").open("a") as stream:
        stream.write(json.dumps(dict(tool=name, args=args, **fields)) + "\n")
if name == "npm":
    record()
    assert args == ["run", "db:check"], args
    sys.exit(0)
if name == "sleep":
    record()
    sys.exit(0)
if name == "gh":
    record()
    if args == ["auth", "status"]:
        sys.exit(0)
    if args[:2] == ["pr", "list"]:
        prs = [p for p in state["prs"] if p["state"] == "OPEN"]
        if "--head" in args:
            branch = args[args.index("--head") + 1]
            prs = [p for p in prs if p["branch"] == branch]
            if prs:
                p = prs[0]
                print(str(p["number"]) + ("\t" + p["base"] if "baseRefName" in " ".join(args) else ""))
        else:
            print("\n".join(p["branch"] for p in prs))
        sys.exit(0)
    if args[:2] == ["pr", "view"]:
        print(next(p["state"] for p in state["prs"] if p["number"] == int(args[2])))
        sys.exit(0)
    raise AssertionError("Unexpected gh mutation: " + repr(args))
if name != "codex":
    raise AssertionError("Unexpected tool: " + name)
if args == ["login", "status"]:
    record()
    sys.exit(1 if state["mode"] == "unauthenticated" else 0)
assert args[0] == "exec", args
assert "--json" in args, args
assert "--output-last-message" in args, args
prompt = sys.stdin.read() if args[-1] == "-" else args[-1]
phase = "merge" if "$do-pr" in prompt else "build" if "$do-issue" in prompt else "triage" if "$triage" in prompt else "unknown"
record(prompt=prompt, phase=phase)
assert phase != "unknown", prompt
final = "Work complete."
rc = 0
mode = state["mode"]
if phase == "build":
    if mode == "build_failure":
        rc = 17
    elif mode == "no_progress":
        pass
    elif mode in ("empty_branch", "pr_without_tracker_update"):
        subprocess.run(["git", "switch", "-C", "feature/test-unit"], check=True, capture_output=True)
        if mode == "pr_without_tracker_update":
            state["prs"].append(dict(number=1, branch="feature/test-unit", base="main", state="OPEN"))
            (root / ".issue-loop-stop").touch()
    elif mode == "stop":
        (root / ".issue-loop-stop").touch()
    else:
        ticket = next(p for p in sorted((root / "tracker").glob("*.md")) if "**Triage:** ready-for-agent" in p.read_text())
        ticket.write_text(ticket.read_text().replace("**Triage:** ready-for-agent", "**Triage:** done"))
        subprocess.run(["git", "switch", "-c", "feature/test-unit"], check=True, capture_output=True)
        state["prs"].append(dict(number=1, branch="feature/test-unit", base="main", state="OPEN"))
elif phase == "triage":
    for ticket in (root / "tracker").glob("*.md"):
        ticket.write_text(ticket.read_text().replace("**Triage:** needs-triage", "**Triage:** ready-for-human"))
elif phase == "merge":
    if mode == "blocked":
        final = "<<<MERGE_BLOCKED #1 approval needed>>>"
    elif mode == "false_blocked":
        print(json.dumps(dict(type="item.completed", item=dict(type="agent_message", text="An example is <<<MERGE_BLOCKED #1 reason>>>"))))
        final = "Review incomplete; checks still running."
    elif mode == "missing_final":
        print(json.dumps(dict(type="item.completed", item=dict(type="agent_message", text="<<<MERGE_BLOCKED #1 unsafe>>>"))))
    elif mode == "merge_failure":
        rc = 19
    elif mode == "startup_failure":
        rc = 23
    else:
        next(p for p in state["prs"] if p["number"] == 1)["state"] = "MERGED"
        # GitHub state must win even when the final answer omits the sentinel.
        final = "Finished."
save()
if mode not in ("missing_final", "startup_failure"):
    pathlib.Path(args[args.index("--output-last-message") + 1]).write_text(final + "\n")
print(json.dumps(dict(type="turn.completed", usage={})))
sys.exit(rc)
'''


class PrettyStreamTests(unittest.TestCase):
    def render(self, *events):
        payload = "\n".join(json.dumps(event) if isinstance(event, dict) else event for event in events) + "\n"
        result = subprocess.run(["python3", str(RUNNER.with_name("pretty-stream.py"))],
                                input=payload, text=True, capture_output=True, check=True)
        self.assertEqual(result.stderr, "")
        return result.stdout

    def test_codex_top_level_error_is_visible_without_false_completion(self):
        output = self.render({"type": "thread.started", "thread_id": "test"},
                             {"type": "error", "message": "Model unavailable"})
        self.assertIn("ERROR Model unavailable", output)
        self.assertNotIn("done", output)

    def test_codex_existing_errors_and_plain_crashes_remain_visible(self):
        output = self.render({"type": "turn.failed", "error": {"message": "Authentication failed"}},
                             {"type": "item.completed", "item": {"type": "error", "message": "Tool failed"}},
                             "Process terminated by signal 15")
        self.assertIn("Authentication failed", output)
        self.assertIn("ERROR Tool failed", output)
        self.assertIn("Process terminated by signal 15", output)
        self.assertNotIn("done", output)

    def test_codex_and_claude_success_and_tool_failure_formats_are_preserved(self):
        output = self.render(
            {"type": "item.started", "item": {"type": "command_execution", "command": "git status"}},
            {"type": "item.completed", "item": {"type": "command_execution", "exit_code": 7, "aggregated_output": "Hidden output"}},
            {"type": "item.completed", "item": {"type": "agent_message", "text": "Review complete."}},
            {"type": "turn.completed", "usage": {"output_tokens": 12}},
            {"type": "system", "subtype": "init", "model": "fixture", "cwd": "/tmp"},
            {"type": "assistant", "message": {"content": [{"type": "text", "text": "Claude text."}]}},
            {"type": "result", "result": "Claude complete.", "num_turns": 2, "total_cost_usd": 0.1},
            {"type": "system", "subtype": "error", "message": "Claude failure"})
        for expected in ("Bash git status", "exit 7", "done Review complete.  [12 output tokens]",
                         "agent fixture in /tmp", "Claude text.", "done Claude complete.  [2 turns $0.10]",
                         "ERROR Claude failure"):
            self.assertIn(expected, output)
        self.assertNotIn("Hidden output", output)


class IssueLoopTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="issue-loop-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "worktree"
        self.root.mkdir()
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        for tool in ("codex", "gh", "npm", "sleep", "date"):
            path = self.bin / tool
            path.write_text(MOCK)
            path.chmod(0o755)
        self.env = os.environ.copy()
        for key in ("MAIN_MODEL", "PR_MODEL", "MAIN_EFFORT", "PR_EFFORT", "BASE_BRANCH", "MAIN_BRANCH", "MAIN_CONFIG_DIR", "PR_CONFIG_DIR"):
            self.env.pop(key, None)
        self.env.update(PATH=f"{self.bin}:{os.environ['PATH']}", LOOP_TEST_ROOT=str(self.root),
                        CYCLE_MINUTES="0", MAX_FAILS="2", PRETTY_OUTPUT="0",
                        LOG_DIR="./issue-loop-logs", STOP_FILE=".issue-loop-stop",
                        AUTO_MIGRATE="1", XDG_CACHE_HOME=str(Path(self.tmp.name) / "cache"),
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
        self.git("init", "--initial-branch=main")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Loop fixture")
        (self.root / ".gitignore").write_text("tracker/\nissue-loop-logs/\nmock-state.json\ncalls.jsonl\n.issue-loop-stop\n")
        self.git("add", ".gitignore")
        self.git("commit", "-m", "Fixture")
        remote = Path(self.tmp.name) / "origin.git"
        self.git("init", "--bare", str(remote))
        self.git("remote", "add", "origin", str(remote))
        self.git("push", "-u", "origin", "main")
        self.git("switch", "-c", "chore/loop-base")
        (self.root / "tracker").mkdir()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, env=self.env,
                              text=True, capture_output=True, check=True)

    def fixture(self, mode="normal", roles=("ready-for-agent",), pending=False):
        for index, role in enumerate(roles):
            (self.root / "tracker" / f"{index:03d}.md").write_text(f"# Ticket {index}\n\n**Triage:** {role}\n")
        prs = [dict(number=99, branch="documentation/unrelated", base="main", state="OPEN")]
        if pending:
            prs.insert(0, dict(number=1, branch="feature/owned", base="main", state="OPEN"))
            logs = self.root / "issue-loop-logs"
            logs.mkdir()
            (logs / "pending-branches").write_text("feature/owned\n")
        (self.root / "mock-state.json").write_text(json.dumps(dict(mode=mode, prs=prs)))

    def run_loop(self, **env):
        result = subprocess.run(["bash", str(RUNNER), "tracker"], cwd=self.root,
                                env=dict(self.env, **env), text=True, capture_output=True, timeout=15)
        self.output = result.stdout + result.stderr
        calls = self.root / "calls.jsonl"
        self.calls = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
        self.agents = [call for call in self.calls if call["tool"] == "codex" and call["args"][0] == "exec"]
        self.assertFalse((self.root / "issue-loop-logs" / "loop.lock").exists(), self.output)
        self.assertFalse(list((Path(self.tmp.name) / "cache").rglob("*.lock")), self.output)
        return result.returncode

    def test_model_effort_literal_skills_build_before_triage_and_owned_merge(self):
        self.fixture(roles=("ready-for-agent", "needs-triage"))
        rc = self.run_loop(MAIN_MODEL="build-model", MAIN_EFFORT="high", PR_MODEL="review-model", PR_EFFORT="xhigh")
        self.assertEqual(rc, 2, self.output)
        self.assertEqual([call["phase"] for call in self.agents], ["build", "merge", "triage"], self.output)
        for call in self.agents:
            merge = call["phase"] == "merge"
            self.assertEqual(call["args"][call["args"].index("--model") + 1], "review-model" if merge else "build-model")
            self.assertIn("model_reasoning_effort=", " ".join(call["args"]))
            self.assertIn("xhigh" if merge else "high", " ".join(call["args"]))
            self.assertNotIn("/do-", call["prompt"])
            self.assertNotIn("/triage", call["prompt"])
        self.assertIn("$do-pr auto #1", self.agents[1]["prompt"])
        self.assertNotIn("#99", self.agents[1]["prompt"])
        self.assertIn("ready-for-human", (self.root / "tracker" / "NEEDS-HUMAN.md").read_text())
        self.assertEqual((self.root / "issue-loop-logs" / "pending-branches").read_text(), "")

    def test_unset_model_and_effort_inherit_codex_configuration(self):
        self.fixture()
        self.assertEqual(self.run_loop(), 0, self.output)
        self.assertEqual(len(self.agents), 2, self.output)
        for call in self.agents:
            self.assertNotIn("--model", call["args"])
            self.assertNotIn("model_reasoning_effort", " ".join(call["args"]))
        self.assertIn("ALL ISSUES DONE", self.output)

    def test_blocked_pr_parks_and_surfaces_to_human(self):
        self.fixture(mode="blocked", roles=("done",), pending=True)
        self.assertEqual(self.run_loop(), 2, self.output)
        self.assertEqual([call["phase"] for call in self.agents], ["merge"])
        self.assertIn("#1 `feature/owned`", (self.root / "tracker" / "NEEDS-HUMAN.md").read_text())
        self.assertEqual((self.root / "issue-loop-logs" / "pending-branches").read_text(), "")

    def test_progress_sentinel_is_ignored_and_pending_pr_prevents_build(self):
        self.fixture(mode="false_blocked", pending=True)
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertEqual([call["phase"] for call in self.agents], ["merge", "merge"], self.output)
        self.assertIn("RETRY", self.agents[1]["prompt"])
        self.assertEqual((self.root / "issue-loop-logs" / "parked-prs").read_text(), "")
        self.assertIn("feature/owned", (self.root / "issue-loop-logs" / "pending-branches").read_text())

    def test_missing_final_does_not_fall_back_to_progress_sentinel(self):
        self.fixture(mode="missing_final", pending=True)
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertEqual(len(self.agents), 2, self.output)
        self.assertEqual((self.root / "issue-loop-logs" / "parked-prs").read_text(), "")

    def test_startup_failure_cannot_reuse_a_stale_final_answer(self):
        self.fixture(mode="startup_failure", pending=True)
        final = self.root / "issue-loop-logs" / "merge-20260907-120000.log.final.txt"
        final.write_text("<<<MERGE_BLOCKED #1 stale answer>>>\n")
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertFalse(final.exists())
        self.assertIn("rc=23", self.output)
        self.assertEqual((self.root / "issue-loop-logs" / "parked-prs").read_text(), "")

    def test_agent_exit_code_survives_stream_pipeline(self):
        self.fixture(mode="build_failure")
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertEqual(len(self.agents), 2, self.output)
        self.assertIn("build agent exited rc=17", self.output)
        self.assertIn("TOO MANY CONSECUTIVE FAILURES", self.output)

    def test_merge_exit_code_survives_stream_pipeline(self):
        self.fixture(mode="merge_failure", pending=True)
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertEqual([call["phase"] for call in self.agents], ["merge", "merge"])
        self.assertIn("rc=19", self.output)

    def test_agent_failure_survives_pretty_renderer(self):
        self.fixture(mode="build_failure")
        self.assertEqual(self.run_loop(PRETTY_OUTPUT="1"), 1, self.output)
        self.assertIn("build agent exited rc=17", self.output)

    def test_no_progress_stops_at_failure_limit(self):
        self.fixture(mode="no_progress")
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertEqual(len(self.agents), 2, self.output)
        self.assertIn("no progress 2/2", self.output)

    def test_empty_branch_is_not_progress_and_stops_at_failure_limit(self):
        self.fixture(mode="empty_branch")
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertEqual([call["phase"] for call in self.agents], ["build", "build"])
        self.assertNotIn("build finished.", self.output)
        self.assertIn("no progress 2/2", self.output)
        self.assertIn("ready-for-agent", (self.root / "tracker" / "000.md").read_text())

    def test_open_pr_counts_as_progress_before_tracker_update(self):
        self.fixture(mode="pr_without_tracker_update")
        self.assertEqual(self.run_loop(), 0, self.output)
        self.assertIn("build finished.", self.output)
        self.assertIn("feature/test-unit", (self.root / "issue-loop-logs" / "pending-branches").read_text())

    def test_stop_request_is_consumed_and_releases_locks(self):
        self.fixture(mode="stop")
        self.assertEqual(self.run_loop(), 0, self.output)
        self.assertEqual(len(self.agents), 1, self.output)
        self.assertIn("STOP REQUESTED", self.output)
        self.assertFalse((self.root / ".issue-loop-stop").exists())

    def test_authentication_failure_stops_before_git_sync_or_agents(self):
        self.fixture(mode="unauthenticated")
        self.assertEqual(self.run_loop(), 1, self.output)
        self.assertEqual(self.agents, [])
        self.assertIn("Codex not authenticated", self.output)
        self.assertFalse(any(call["tool"] == "npm" for call in self.calls))


if __name__ == "__main__":
    unittest.main(verbosity=2)
