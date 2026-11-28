#!/usr/bin/env python3
"""Exercise build-loop.sh, merge-loop.sh and loop-report offline; never launch an agent.

Run: python3 test_build_merge_loops.py
Only the Python standard library, Bash, Git and flock are required. Every test gets its own
temporary directory: a bare "origin", two clones standing in for the build worktree (wt1)
and the merge worktree (wt3), a shared state dir, and fake gh / codex / claude / npm / sleep.

The Codex runners are the primary target. Every test class runs a second time against the
Claude twin with the same fake installed as `claude` on PATH.
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


HERE = Path(__file__).resolve().parent
HOSTS = {"codex": HERE, "claude": HERE.parents[2] / "claude" / "issue-loop" / "scripts"}

MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path(os.environ["LOOP_TEST_ROOT"])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state_path = root / "mock-state.json"
state = json.loads(state_path.read_text())
def save():
    state_path.write_text(json.dumps(state))
def record(**fields):
    with (root / "calls.jsonl").open("a") as stream:
        stream.write(json.dumps(dict(tool=name, args=args, cwd=os.getcwd(), **fields)) + "\n")
def git(*a):
    return subprocess.run(["git", *a], check=True, capture_output=True, text=True).stdout.strip()
FIELD = dict(number="number", headRefName="branch", baseRefName="base", headRefOid="headRefOid", state="state")
if (root / "waited").exists():
    # A PR "merges" on GitHub while the loop waits: this is how a blocker becomes startable.
    for p in state["prs"]:
        if p["number"] in state.get("merge_on_wait", []):
            p["state"] = "MERGED"
if name == "npm":
    record()
    if args == ["run", "db:check"]:
        merged = any(p["state"] == "MERGED" for p in state["prs"])
        sys.exit(1 if state.get("db") == "destructive_after_merge" and merged else 0)
    if args == ["run", "db:status"]:
        print("Baseline launch-v1: ok")
        print("  pending  20260101_drop_things.sql")
        sys.exit(0)
    raise AssertionError("Unexpected npm call: " + repr(args))
if name == "gh":
    record()
    if args == ["auth", "status"]:
        sys.exit(0)
    fields = args[args.index("--json") + 1].split(",") if "--json" in args else []
    jq = args[args.index("--jq") + 1] if "--jq" in args else ""
    def row(p):
        return "\t".join(str(p.get(FIELD[f], "")) for f in fields)
    if args[:2] == ["pr", "list"]:
        prs = [p for p in state["prs"] if p["state"] == "OPEN"]
        if "--head" in args:
            prs = [p for p in prs if p["branch"] == args[args.index("--head") + 1]]
        if "select(.headRefOid" in jq:
            wanted = jq.split('"')[1]
            print("\n".join(p["branch"] for p in prs if p.get("headRefOid") == wanted))
        elif jq.startswith(".[0]"):
            if prs:
                print(row(prs[0]))
        else:
            print("\n".join(row(p) for p in prs))
        sys.exit(0)
    if args[:2] == ["pr", "view"]:
        match = [p for p in state["prs"] if p["number"] == int(args[2])]
        if not match:
            print("no pull requests found", file=sys.stderr)
            sys.exit(1)
        print(row(match[0]))
        sys.exit(0)
    raise AssertionError("Unexpected gh call: " + repr(args))
if name not in ("codex", "claude"):
    raise AssertionError("Unexpected tool: " + name)
if name == "codex" and args == ["login", "status"]:
    record()
    sys.exit(0)
if name == "codex":
    assert args[0] == "exec" and "--json" in args and "--output-last-message" in args, args
    prompt = args[-1]
else:
    assert "--print" in args and "stream-json" in args, args
    prompt = args[args.index("--print") + 1]
phase = "merge" if "do-pr" in prompt[:8] else "build" if "do-issue" in prompt[:10] else "triage" if "triage" in prompt[:8] else "unknown"
branch_now = subprocess.run(["git", "symbolic-ref", "--short", "-q", "HEAD"], capture_output=True, text=True).stdout.strip()
record(prompt=prompt, phase=phase, branch=branch_now,
       compact_window=os.environ.get("CLAUDE_CODE_AUTO_COMPACT_WINDOW"))
assert phase != "unknown", prompt
if state.get("hold_once"):
    (root / "agent-started").touch()
    while not (root / "release").exists():
        time.sleep(0.05)
    state = json.loads(state_path.read_text())
    state["hold_once"] = False
final, rc, limit = "Work complete.", 0, False
def blockers(text):
    line = next((l for l in text.splitlines() if l.startswith("**Blocked by:**")), "")
    return re.findall(r"[0-9]+-[A-Za-z0-9._-]+\.md", line)
if phase == "build":
    mode = state.get("build", "normal")
    issues = pathlib.Path(os.getcwd()) / "tracker" / "issues"
    if mode == "usage_limit":
        limit = True
    elif mode == "fail":
        rc = 17
    else:
        hit = re.search(r"Treat these tickets as NOT done, their PR has not merged: (.*)\.$", prompt)
        not_done = set(hit.group(1).split(", ")) if hit else set()
        def done(n):
            f = issues / n
            return (not f.exists()) or ("**Triage:** done" in f.read_text() and n not in not_done)
        pick = None
        for t in sorted(issues.glob("*.md")):
            text = t.read_text()
            if "**Triage:** ready-for-agent" in text and all(done(b) for b in blockers(text)):
                pick = t
                break
        if pick is None:
            final = "<<<NO_OPEN_ISSUES>>>"
        else:
            pick.write_text(pick.read_text().replace("**Triage:** ready-for-agent", "**Triage:** done"))
            branch = "feature/" + pick.stem
            git("switch", "-C", branch)
            pathlib.Path(pick.stem + ".txt").write_text(pick.stem + "\n")
            git("add", pick.stem + ".txt")
            git("commit", "-q", "-m", "Build " + pick.stem)
            git("push", "-q", "-f", "origin", branch)
            state["prs"].append(dict(number=state["next_pr"], branch=branch, base="main",
                                     state="OPEN", headRefOid=git("rev-parse", "HEAD")))
            state["next_pr"] += 1
elif phase == "triage":
    for t in (pathlib.Path(os.getcwd()) / "tracker" / "issues").glob("*.md"):
        t.write_text(t.read_text().replace("**Triage:** needs-triage", "**Triage:** ready-for-agent"))
elif phase == "merge":
    pr = int(re.search(r"#([0-9]+)", prompt).group(1))
    calls = state.setdefault("merge_calls", {})
    calls[str(pr)] = calls.get(str(pr), 0) + 1
    plan = state.get("merge", {}).get(str(pr), ["merge"])
    outcome = plan[min(calls[str(pr)], len(plan)) - 1]
    target = next(p for p in state["prs"] if p["number"] == pr)
    if outcome == "merge":
        target["state"] = "MERGED"
        final = "Finished."              # GitHub state must win even without a sentinel
    elif outcome == "close":
        target["state"] = "CLOSED"
    elif outcome == "blocked":
        final = "<<<MERGE_BLOCKED #%d approval needed>>>" % pr
    elif outcome == "inconclusive":
        final = "Review incomplete; checks still running."
    elif outcome == "usage_limit":
        limit = True
save()
if name == "codex":
    if limit:
        print(json.dumps(dict(type="turn.failed", error=dict(message="You've hit your usage limit. Try again later."))))
        sys.exit(0)
    pathlib.Path(args[args.index("--output-last-message") + 1]).write_text(final + "\n")
    print(json.dumps(dict(type="turn.completed", usage={})))
else:
    if limit:
        print(json.dumps(dict(type="result", subtype="success", is_error=True,
                              result="You've hit your session limit · resets 5pm")))
        sys.exit(0)
    print(json.dumps(dict(type="result", subtype="success", is_error=False, result=final)))
sys.exit(rc)
'''

# sleep is called once per countdown second, so it is a shell script, not Python.
SLEEP = r'''#!/bin/sh
printf '{"tool":"sleep","args":["%s"]}\n' "$1" >> "$LOOP_TEST_ROOT/calls.jsonl"
touch "$LOOP_TEST_ROOT/waited"
if [ -n "${STOP_AFTER_SLEEPS:-}" ]; then
  n=$(grep -c '"tool":"sleep"' "$LOOP_TEST_ROOT/calls.jsonl")
  [ "$n" -ge "$STOP_AFTER_SLEEPS" ] && touch "$STOP_TARGET"
fi
exit 0
'''


class LoopHarness:
    HOST = "codex"

    def setUp(self):
        self.scripts = HOSTS[self.HOST]
        if not (self.scripts / "build-loop.sh").exists():
            self.skipTest("no %s twin at %s" % (self.HOST, self.scripts))
        self.sigil = "$" if self.HOST == "codex" else "/"
        self.tmp = tempfile.TemporaryDirectory(prefix="build-merge-loop-test-")
        self.addCleanup(self.tmp.cleanup)
        self.top = Path(self.tmp.name)
        self.bin = self.top / "bin"
        self.bin.mkdir()
        for tool in ("codex", "claude", "gh", "npm"):
            (self.bin / tool).write_text(MOCK)
            (self.bin / tool).chmod(0o755)
        (self.bin / "sleep").write_text(SLEEP)
        (self.bin / "sleep").chmod(0o755)
        self.state_dir = self.top / "state"
        (self.top / "home").mkdir()
        self.env = os.environ.copy()
        for key in ("MAIN_MODEL", "PR_MODEL", "MAIN_EFFORT", "PR_EFFORT", "BASE_BRANCH", "MAIN_BRANCH",
                    "MAIN_CONFIG_DIR", "PR_CONFIG_DIR", "STOP_AFTER_SLEEPS", "ISSUE_LOOP_ARGV0",
                    "AGENT_COMPACT_WINDOW", "CLAUDE_CODE_AUTO_COMPACT_WINDOW"):
            self.env.pop(key, None)
        self.env.update(PATH=f"{self.bin}:{os.environ['PATH']}", LOOP_TEST_ROOT=str(self.top),
                        HOME=str(self.top / "home"), LOOP_STATE_DIR=str(self.state_dir),
                        XDG_CACHE_HOME=str(self.top / "cache"),
                        CYCLE_MINUTES="1", MERGE_POLL_MINUTES="1", MAX_FAILS="2", PRETTY_OUTPUT="0",
                        GH_RETRIES="2", GH_RETRY_BASE="0", AUTO_MIGRATE="1",
                        LOG_DIR="./issue-loop-logs", STOP_FILE=".issue-loop-stop",
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null",
                        GIT_AUTHOR_NAME="Loop fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                        GIT_COMMITTER_NAME="Loop fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
        self.origin = self.top / "origin.git"
        self.git(self.top, "init", "-q", "--bare", "--initial-branch=main", str(self.origin))
        self.seed = self.top / "seed"
        self.git(self.top, "clone", "-q", str(self.origin), str(self.seed))
        self.git(self.seed, "switch", "-q", "-c", "main")
        (self.seed / ".gitignore").write_text("tracker/\nissue-loop-logs/\n.issue-loop-stop\ndb/\n")
        self.git(self.seed, "add", ".gitignore")
        self.git(self.seed, "commit", "-q", "-m", "Fixture")
        self.git(self.seed, "push", "-q", "-u", "origin", "main")
        self.wt1 = self.clone("wt1")
        self.wt3 = self.clone("wt3")
        (self.wt1 / "tracker" / "issues").mkdir(parents=True)
        self.state = dict(prs=[dict(number=99, branch="documentation/unrelated", base="main", state="OPEN")],
                          next_pr=10)

    # ---- fixture helpers ----------------------------------------------------
    def git(self, cwd, *args):
        return subprocess.run(["git", *args], cwd=cwd, env=self.env, text=True,
                              capture_output=True, check=True).stdout.strip()

    def clone(self, name):
        path = self.top / name
        self.git(self.top, "clone", "-q", str(self.origin), str(path))
        self.git(path, "switch", "-q", "-c", f"chore/{name}-base")
        return path

    def ticket(self, name, role, blocked_by=(), wt=None):
        lines = [f"# {name}", "", f"**Triage:** {role}"]
        if blocked_by:
            lines.append("**Blocked by:** " + ", ".join(blocked_by))
        ((wt or self.wt1) / "tracker" / "issues" / name).write_text("\n".join(lines) + "\n")

    def role(self, name, wt=None):
        text = ((wt or self.wt1) / "tracker" / "issues" / name).read_text()
        return next(l for l in text.splitlines() if l.startswith("**Triage:**")).split()[-1]

    def pr(self, number, branch, state="OPEN", base="main", push=True):
        if push:
            self.git(self.seed, "switch", "-q", "-c", branch, "origin/main")
            (self.seed / (branch.replace("/", "_") + ".txt")).write_text(branch + "\n")
            self.git(self.seed, "add", ".")
            self.git(self.seed, "commit", "-q", "-m", branch)
            self.git(self.seed, "push", "-q", "origin", branch)
            self.git(self.seed, "switch", "-q", "main")
        self.state["prs"].append(dict(number=number, branch=branch, base=base, state=state))

    def queue(self, *rows):
        """rows: (queued_at, pr, branch, tracker, ticket, worktree)"""
        self.state_dir.mkdir(exist_ok=True)
        with (self.state_dir / "pr-queue.tsv").open("a") as stream:
            for row in rows:
                stream.write("\t".join(str(cell) for cell in row) + "\n")

    def rows(self, name):
        path = self.state_dir / name
        if not path.exists():
            return []
        return [line.split("\t") for line in path.read_text().splitlines() if line.strip()]

    def write_state(self):
        (self.top / "mock-state.json").write_text(json.dumps(self.state))

    def mock_state(self):
        return json.loads((self.top / "mock-state.json").read_text())

    def command(self, runner, wt, args):
        return ["bash", str(self.scripts / runner), *args]

    def run_loop(self, runner, wt, *args, stop_after=None, **env):
        if not (self.top / "mock-state.json").exists():
            self.write_state()
        extra = dict(env, STOP_TARGET=str(wt / ".issue-loop-stop"))
        if stop_after is not None:
            extra["STOP_AFTER_SLEEPS"] = str(stop_after)
        result = subprocess.run(self.command(runner, wt, args), cwd=wt, env=dict(self.env, **extra),
                                text=True, capture_output=True, timeout=120)
        self.output = result.stdout + result.stderr
        self.load_calls()
        self.assertFalse((wt / "issue-loop-logs" / "loop.lock").exists(), self.output)
        self.assertFalse(list((self.top / "cache").rglob("*.lock")), self.output)
        return result.returncode

    def load_calls(self):
        calls = self.top / "calls.jsonl"
        self.calls = [json.loads(l) for l in calls.read_text().splitlines()] if calls.exists() else []
        self.agents = [c for c in self.calls if c["tool"] in ("codex", "claude") and c.get("phase")]
        self.gh = [c["args"] for c in self.calls if c["tool"] == "gh"]

    def sleeps_before(self, index):
        """sleep calls between the start of the run and agent call number <index>."""
        n = 0
        seen = 0
        for call in self.calls:
            if call["tool"] in ("codex", "claude") and call.get("phase"):
                if seen == index:
                    return n
                seen += 1
            elif call["tool"] == "sleep":
                n += 1
        raise AssertionError("fewer than %d agent calls" % (index + 1))

    def metrics(self):
        return self.rows("loop-metrics.tsv")

    def start_holding(self, runner, wt, *args, **env):
        self.state["hold_once"] = True
        self.write_state()
        extra = dict(env, STOP_TARGET=str(wt / ".issue-loop-stop"), STOP_AFTER_SLEEPS="1")
        proc = subprocess.Popen(self.command(runner, wt, args), cwd=wt, env=dict(self.env, **extra),
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        deadline = time.time() + 30
        while not (self.top / "agent-started").exists():
            if proc.poll() is not None or time.time() > deadline:
                proc.kill()
                self.fail("holder never reached its agent: " + (proc.stdout.read() or ""))
            time.sleep(0.05)
        return proc

    def release(self, proc):
        (self.top / "release").touch()
        out, _ = proc.communicate(timeout=120)
        return proc.returncode, out


# ---------------------------------------------------------------------------
class BuildLoopTests(LoopHarness, unittest.TestCase):
    def test_build_queues_its_pr_and_next_cycle_builds_without_waiting(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.ticket("02-beta.md", "ready-for-agent")
        rc = self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=1)
        self.assertEqual(rc, 0, self.output)
        self.assertEqual([c["phase"] for c in self.agents], ["build", "build"], self.output)
        self.assertEqual(self.sleeps_before(1), 0, "second build waited")
        queue = self.rows("pr-queue.tsv")
        self.assertEqual([(r[1], r[2], r[3], r[4], r[5]) for r in queue],
                         [("10", "feature/01-alpha", "tracker", "01-alpha.md", str(self.wt1)),
                          ("11", "feature/02-beta", "tracker", "02-beta.md", str(self.wt1))])
        self.assertRegex(queue[0][0], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertIn("no merge wait", self.output)
        self.assertIn("waiting for 2 queued PR(s) of this tracker to merge", self.output)
        self.assertIn("STOP REQUESTED", self.output)
        self.assertNotIn("ALL ISSUES DONE", self.output)
        self.assertFalse(any("do-pr" in c["prompt"] for c in self.agents))
        self.assertFalse(any(a[:2] == ["pr", "merge"] for a in self.gh))

    def test_build_prompt_is_issue_loop_prompt_plus_one_not_done_line(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.assertEqual(self.run_loop("issue-loop.sh", self.wt1, "tracker", stop_after=1), 0, self.output)
        issue_prompt = next(c["prompt"] for c in self.agents if c["phase"] == "build")
        (self.top / "calls.jsonl").unlink()
        self.ticket("01-alpha.md", "ready-for-agent")
        self.git(self.wt1, "switch", "-q", "chore/wt1-base")
        self.state["next_pr"] = 20
        self.write_state()
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=1), 0, self.output)
        self.assertEqual(self.agents[0]["prompt"], issue_prompt)
        self.assertTrue(issue_prompt.startswith(self.sigil + "do-issue Work tracker"))

    def test_ticket_blocked_by_open_pr_is_skipped_and_named_in_prompt(self):
        self.ticket("01-alpha.md", "done")
        self.ticket("02-beta.md", "ready-for-agent", ["01-alpha.md"])
        self.ticket("03-gamma.md", "ready-for-agent")
        self.pr(5, "feature/01-alpha")
        self.queue(("2026-11-27T09:00:00Z", 5, "feature/01-alpha", "tracker", "01-alpha.md", self.wt1))
        rc = self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=1)
        self.assertEqual(rc, 0, self.output)
        first = self.agents[0]["prompt"]
        self.assertTrue(first.endswith(" Treat these tickets as NOT done, their PR has not merged: 01-alpha.md."), first)
        self.assertEqual(self.role("02-beta.md"), "ready-for-agent")
        self.assertEqual(self.role("03-gamma.md"), "done")
        self.assertEqual([r[1] for r in self.rows("pr-queue.tsv")], ["5", "10"])
        self.assertIn("waiting for 2 queued PR(s)", self.output)
        self.assertIn(["pr", "view", "5", "--json", "state", "--jq", ".state"], self.gh)

    def test_blocked_ticket_becomes_startable_once_its_pr_merged(self):
        self.ticket("01-alpha.md", "done")
        self.ticket("02-beta.md", "ready-for-agent", ["01-alpha.md"])
        self.pr(5, "feature/01-alpha")
        self.queue(("2026-11-27T09:00:00Z", 5, "feature/01-alpha", "tracker", "01-alpha.md", self.wt1))
        self.state["merge_on_wait"] = [5]       # merges on GitHub while the loop waits
        rc = self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=61)
        self.assertEqual(rc, 0, self.output)
        builds = [c for c in self.agents if c["phase"] == "build"]
        self.assertEqual(len(builds), 1, self.output)
        self.assertNotIn("NOT done", builds[0]["prompt"])
        self.assertEqual(self.sleeps_before(0), 60, "it should wait one full cycle, then build")
        self.assertEqual(self.role("02-beta.md"), "done")
        self.assertIn("nothing startable — waiting for 1 queued PR(s)", self.output)

    def test_parked_blocker_pr_also_holds_the_ticket_back(self):
        self.ticket("01-alpha.md", "done")
        self.ticket("02-beta.md", "ready-for-agent", ["01-alpha.md"])
        self.pr(5, "feature/01-alpha")
        self.state_dir.mkdir()
        (self.state_dir / "pr-parked.tsv").write_text(
            "\t".join(["2026-11-27T09:00:00Z", "5", "feature/01-alpha", "tracker", "01-alpha.md",
                       str(self.wt1), "2026-11-27T09:30:00Z", "blocked: approval needed"]) + "\n")
        rc = self.run_loop("build-loop.sh", self.wt1, "tracker")
        self.assertEqual(rc, 2, self.output)
        self.assertEqual(self.agents, [], self.output)
        self.assertIn("FOLDER FINISHED FOR AGENTS — 0 ticket(s) need a human, 1 PR(s) parked", self.output)
        needs = (self.wt1 / "tracker" / "NEEDS-HUMAN.md").read_text()
        self.assertIn("#5 `feature/01-alpha` — blocked: approval needed", needs)

    def test_nothing_startable_keeps_waiting_while_tracker_prs_are_queued(self):
        self.ticket("01-alpha.md", "done")
        self.pr(5, "feature/01-alpha")
        self.queue(("2026-11-27T09:00:00Z", 5, "feature/01-alpha", "tracker", "01-alpha.md", self.wt1))
        rc = self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=150)
        self.assertEqual(rc, 0, self.output)
        self.assertEqual(self.agents, [], self.output)
        self.assertGreaterEqual(self.output.count("waiting for 1 queued PR(s)"), 3, self.output)
        self.assertIn("STOP REQUESTED", self.output)
        self.assertNotIn("TOO MANY CONSECUTIVE FAILURES", self.output)

    def test_folder_finishes_when_only_other_trackers_prs_are_queued(self):
        self.ticket("01-alpha.md", "done")
        self.pr(5, "feature/elsewhere")
        self.queue(("2026-11-27T09:00:00Z", 5, "feature/elsewhere", "other/tracker", "01-alpha.md", self.wt3))
        rc = self.run_loop("build-loop.sh", self.wt1, "tracker")
        self.assertEqual(rc, 0, self.output)
        self.assertIn("ALL ISSUES DONE", self.output)
        self.assertEqual([r[1] for r in self.rows("pr-queue.tsv")], ["5"])

    def test_triage_runs_only_when_nothing_is_startable(self):
        self.ticket("01-alpha.md", "needs-triage")
        rc = self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=1)
        self.assertEqual(rc, 0, self.output)
        self.assertEqual([c["phase"] for c in self.agents], ["triage", "build"], self.output)
        self.assertTrue(self.agents[0]["prompt"].startswith(self.sigil + "triage "))

    def test_usage_limit_stops(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.state["build"] = "usage_limit"
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker"), 75, self.output)
        self.assertEqual(len(self.agents), 1)
        self.assertIn("USAGE LIMIT", self.output)

    def test_dirty_tree_stops_before_any_agent(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        (self.wt1 / ".gitignore").write_text("changed\n")
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker"), 1, self.output)
        self.assertEqual(self.agents, [])
        self.assertIn("GIT STATE NEEDS A HUMAN", self.output)

    def test_unreachable_github_skips_cycles_then_stops(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.git(self.wt1, "remote", "set-url", "origin", str(self.top / "missing.git"))
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker", NET_MAX_CYCLES="2"), 1, self.output)
        self.assertEqual(self.agents, [])
        self.assertIn("git fetch failed, attempt 1/2", self.output)
        self.assertIn("skipping this cycle (1/2 in a row)", self.output)
        self.assertIn("GITHUB UNREACHABLE for 2 cycles in a row", self.output)
        self.assertNotIn("GIT STATE NEEDS A HUMAN", self.output)

    def test_build_failure_stops_at_failure_limit(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.state["build"] = "fail"
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker"), 1, self.output)
        self.assertEqual(len(self.agents), 2, self.output)
        self.assertIn("build agent exited rc=17", self.output)
        self.assertIn("TOO MANY CONSECUTIVE FAILURES", self.output)

    def test_issue_loop_and_build_loop_refuse_each_other_on_one_tracker(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        wt2 = self.clone("wt2")
        (wt2 / "tracker" / "issues").mkdir(parents=True)
        self.ticket("01-alpha.md", "ready-for-agent", wt=wt2)
        for holder, refused in (("build-loop.sh", "issue-loop.sh"), ("issue-loop.sh", "build-loop.sh")):
            for leftover in ("agent-started", "release", "calls.jsonl"):
                (self.top / leftover).unlink(missing_ok=True)
            self.ticket("01-alpha.md", "ready-for-agent")
            self.git(self.wt1, "switch", "-q", "chore/wt1-base")
            proc = self.start_holding(holder, self.wt1, "tracker")
            try:
                result = subprocess.run(self.command(refused, wt2, ["tracker"]), cwd=wt2, env=self.env,
                                        text=True, capture_output=True, timeout=60)
                out = result.stdout + result.stderr
                self.assertEqual(result.returncode, 1, out)
                self.assertIn("is already running on this tracker", out)
                self.assertIn("PRE-FLIGHT FAILED", out)
                lock = list((self.top / "cache").rglob("tracker.lock"))
                self.assertEqual(len(lock), 1, "the refused start removed the owner's lock")
            finally:
                rc, out = self.release(proc)
            self.assertIn(rc, (0, 2), out)

    def test_metrics_lines_for_build_queue_and_idle(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=1), 0, self.output)
        rows = self.metrics()
        self.assertTrue(all(len(r) == 6 for r in rows), rows)
        self.assertTrue(all(r[1] == "build:tracker" and r[2] == str(self.wt1) for r in rows), rows)
        events = [(r[3], r[4]) for r in rows]
        self.assertEqual(events[:3], [("build_start", "-"), ("queued", "#10"), ("build_end:ok", "01-alpha.md")])
        self.assertEqual([e for e, _ in events[-2:]], ["idle_start", "idle_end"])
        self.assertRegex(rows[-1][5], r"^\d+$")


# ---------------------------------------------------------------------------
class MergeLoopTests(LoopHarness, unittest.TestCase):
    def merges(self):
        return [int(c["prompt"].split("#")[1].split()[0]) for c in self.agents if c["phase"] == "merge"]

    def test_oldest_first_across_two_trackers_and_no_wait_between_merges(self):
        for number in (11, 12, 13):
            self.pr(number, f"feature/pr-{number}")
        self.queue(("2026-11-27T10:05:00Z", 12, "feature/pr-12", "trackers/b", "01-b.md", self.top / "wt2"),
                   ("2026-11-27T10:10:00Z", 13, "feature/pr-13", "trackers/a", "02-a.md", self.wt1),
                   ("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        rc = self.run_loop("merge-loop.sh", self.wt3, stop_after=1)
        self.assertEqual(rc, 0, self.output)
        self.assertEqual(self.merges(), [11, 12, 13], self.output)
        self.assertEqual([self.sleeps_before(i) for i in range(3)], [0, 0, 0])
        self.assertEqual(self.rows("pr-queue.tsv"), [])
        self.assertEqual(self.agents[0]["prompt"], self.sigil + "do-pr auto #11")
        self.assertIn("STOP REQUESTED", self.output)

    def test_runner_checks_out_a_branch_this_worktree_never_had(self):
        self.pr(11, "feature/pr-11")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.agents[0]["branch"], "feature/pr-11")
        self.assertEqual(self.git(self.wt3, "symbolic-ref", "--short", "HEAD"), "chore/wt3-base")

    def test_branch_checked_out_in_another_worktree_is_left_queued(self):
        self.pr(11, "feature/pr-11")
        self.pr(12, "feature/pr-12")
        shared = self.top / "wt3-shared"
        self.git(self.wt3, "fetch", "-q", "origin")
        self.git(self.wt3, "worktree", "add", "-q", str(shared), "-b", "feature/pr-11", "origin/feature/pr-11")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", shared),
                   ("2026-11-27T10:01:00Z", 12, "feature/pr-12", "trackers/a", "02-a.md", shared))
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.merges(), [12], self.output)
        self.assertIn(f"feature/pr-11 is checked out in {shared}", self.output)
        self.assertEqual([r[1] for r in self.rows("pr-queue.tsv")], ["11"])

    def test_blocked_is_parked_with_reason_and_next_pr_runs(self):
        self.pr(11, "feature/pr-11")
        self.pr(12, "feature/pr-12")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1),
                   ("2026-11-27T10:05:00Z", 12, "feature/pr-12", "trackers/b", "01-b.md", self.wt1))
        self.state["merge"] = {"11": ["blocked"]}
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.merges(), [11, 12])
        parked = self.rows("pr-parked.tsv")
        self.assertEqual(len(parked), 1)
        self.assertEqual(parked[0][1:6], ["11", "feature/pr-11", "trackers/a", "01-a.md", str(self.wt1)])
        self.assertEqual(parked[0][7], "blocked: approval needed")
        self.assertEqual(self.rows("pr-queue.tsv"), [])
        self.assertEqual(self.mock_state()["prs"][1]["state"], "OPEN")   # parked, never closed

    def test_inconclusive_is_retried_after_the_others_then_parked(self):
        self.pr(11, "feature/pr-11")
        self.pr(12, "feature/pr-12")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1),
                   ("2026-11-27T10:05:00Z", 12, "feature/pr-12", "trackers/b", "01-b.md", self.wt1))
        self.state["merge"] = {"11": ["inconclusive"]}
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.merges(), [11, 12, 11], self.output)
        self.assertIn("RETRY (attempt 2)", self.agents[2]["prompt"])
        self.assertNotIn("RETRY", self.agents[0]["prompt"])
        parked = self.rows("pr-parked.tsv")
        self.assertEqual([(r[1], r[7]) for r in parked], [("11", "inconclusive after 2 attempts")])
        self.assertFalse((self.wt3 / "issue-loop-logs" / "merge-attempts-11").exists())
        self.assertNotIn("REPEATED INCONCLUSIVE", self.output)

    def test_inconclusive_runs_on_several_prs_stop_the_loop(self):
        for number in (11, 12, 13):
            self.pr(number, f"feature/pr-{number}")
            self.queue((f"2026-11-27T10:{number}:00Z", number, f"feature/pr-{number}", "trackers/a", "-", self.wt1))
        self.state["merge"] = {str(n): ["inconclusive"] for n in (11, 12, 13)}
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, MAX_FAILS="3"), 1, self.output)
        self.assertEqual(self.merges(), [11, 12, 13], self.output)
        self.assertIn("REPEATED INCONCLUSIVE MERGES", self.output)
        self.assertEqual(self.rows("pr-parked.tsv"), [])
        self.assertEqual(len(self.rows("pr-queue.tsv")), 3)

    def test_closed_pr_is_removed_without_an_agent(self):
        self.pr(11, "feature/pr-11", state="CLOSED")
        self.pr(12, "feature/pr-12")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1),
                   ("2026-11-27T10:05:00Z", 12, "feature/pr-12", "trackers/a", "02-a.md", self.wt1))
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.merges(), [12])
        self.assertIn("#11 was closed — removing it from the queue", self.output)
        self.assertEqual(self.rows("pr-queue.tsv"), [])
        self.assertEqual(self.rows("pr-parked.tsv"), [])

    def test_pr_merged_by_hand_is_removed_without_an_agent(self):
        self.pr(11, "feature/pr-11", state="MERGED")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.agents, [])
        self.assertIn("#11 is already merged", self.output)
        self.assertEqual(self.rows("pr-queue.tsv"), [])

    def test_branch_mismatch_and_stacked_pr_are_never_run(self):
        self.pr(11, "feature/real-head")
        self.pr(12, "feature/pr-12", base="feature/parent")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/queued-name", "trackers/a", "01-a.md", self.wt1),
                   ("2026-11-27T10:05:00Z", 12, "feature/pr-12", "trackers/a", "02-a.md", self.wt1))
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.agents, [])
        self.assertEqual([(r[1], r[7]) for r in self.rows("pr-parked.tsv")],
                         [("11", "branch mismatch: PR head is feature/real-head, queue says feature/queued-name")])
        self.assertEqual([r[1] for r in self.rows("pr-queue.tsv")], ["12"])
        self.assertIn("targets feature/parent", self.output)

    def test_empty_queue_polls_the_file_without_github_calls(self):
        rc = self.run_loop("merge-loop.sh", self.wt3, stop_after=150)
        self.assertEqual(rc, 0, self.output)
        self.assertEqual(self.gh, [["auth", "status"]])
        self.assertEqual(self.agents, [])
        self.assertGreaterEqual(self.output.count("queue empty — next look"), 1)
        self.assertNotIn("MERGE CYCLE", self.output)
        self.assertFalse(any(c["tool"] == "npm" for c in self.calls))

    def test_pr_not_in_the_queue_is_never_touched(self):
        self.pr(11, "feature/pr-11")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        self.assertEqual(self.merges(), [11])
        self.assertFalse(any("99" in a for a in self.gh), self.gh)
        self.assertFalse(any("#99" in c["prompt"] for c in self.agents))
        self.assertEqual(self.mock_state()["prs"][0]["state"], "OPEN")

    def test_usage_limit_stops_and_keeps_the_pr_queued(self):
        self.pr(11, "feature/pr-11")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        self.state["merge"] = {"11": ["usage_limit"]}
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3), 75, self.output)
        self.assertIn("USAGE LIMIT", self.output)
        self.assertEqual([r[1] for r in self.rows("pr-queue.tsv")], ["11"])
        self.assertEqual(self.rows("pr-parked.tsv"), [])

    def test_dirty_tree_stops_before_any_agent(self):
        self.pr(11, "feature/pr-11")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        (self.wt3 / ".gitignore").write_text("changed\n")
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3), 1, self.output)
        self.assertEqual(self.agents, [])
        self.assertIn("GIT STATE NEEDS A HUMAN", self.output)

    def test_unreachable_github_skips_cycles_then_stops(self):
        self.pr(11, "feature/pr-11")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        self.git(self.wt3, "remote", "set-url", "origin", str(self.top / "missing.git"))
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, NET_MAX_CYCLES="2"), 1, self.output)
        self.assertEqual(self.agents, [])
        self.assertIn("skipping this cycle (1/2 in a row)", self.output)
        self.assertIn("GITHUB UNREACHABLE for 2 cycles in a row", self.output)
        self.assertEqual([r[1] for r in self.rows("pr-queue.tsv")], ["11"])

    def test_destructive_migration_after_a_merge_stops_for_a_human(self):
        self.pr(11, "feature/pr-11")
        self.pr(12, "feature/pr-12")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1),
                   ("2026-11-27T10:05:00Z", 12, "feature/pr-12", "trackers/a", "02-a.md", self.wt1))
        (self.wt3 / "db" / "migrations").mkdir(parents=True)
        (self.wt3 / "db" / "migrations" / "20260101_drop_things.sql").write_text("DROP TABLE things;\n")
        self.state["db"] = "destructive_after_merge"
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3), 0, self.output)
        self.assertEqual(self.merges(), [11])
        self.assertIn("MIGRATION MERGED", self.output)
        self.assertFalse(any(c["tool"] == "npm" and c["args"] == ["run", "db:migrate"] for c in self.calls))

    def test_one_merge_loop_per_machine_and_per_worktree(self):
        self.pr(11, "feature/pr-11")
        self.queue(("2026-11-27T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1))
        proc = self.start_holding("merge-loop.sh", self.wt3)
        try:
            other = subprocess.run(self.command("merge-loop.sh", self.wt1, []), cwd=self.wt1, env=self.env,
                                   text=True, capture_output=True, timeout=60)
            self.assertEqual(other.returncode, 1, other.stdout)
            self.assertIn("on this machine (one merge loop per machine)", other.stdout + other.stderr)
            (self.wt3 / "tracker" / "issues").mkdir(parents=True, exist_ok=True)
            self.ticket("01-alpha.md", "ready-for-agent", wt=self.wt3)
            same = subprocess.run(self.command("issue-loop.sh", self.wt3, ["tracker"]), cwd=self.wt3,
                                  env=self.env, text=True, capture_output=True, timeout=60)
            self.assertEqual(same.returncode, 1, same.stdout)
            self.assertIn("is already running in this worktree", same.stdout + same.stderr)
        finally:
            rc, out = self.release(proc)
        self.assertEqual(rc, 0, out)
        self.assertIn("Merged PR #11", out)

    def test_metrics_lines_for_merges(self):
        self.pr(11, "feature/pr-11")
        self.pr(12, "feature/pr-12")
        self.queue(("2026-01-01T10:00:00Z", 11, "feature/pr-11", "trackers/a", "01-a.md", self.wt1),
                   ("2026-01-01T10:05:00Z", 12, "feature/pr-12", "trackers/a", "02-a.md", self.wt1))
        self.state["merge"] = {"12": ["blocked"]}
        self.assertEqual(self.run_loop("merge-loop.sh", self.wt3, stop_after=1), 0, self.output)
        rows = self.metrics()
        self.assertTrue(all(len(r) == 6 and r[1] == "merge" and r[2] == str(self.wt3) for r in rows), rows)
        self.assertEqual([(r[3], r[4]) for r in rows],
                         [("merge_start", "#11"), ("merge_end:merged", "#11"), ("dequeued:merged", "#11"),
                          ("merge_start", "#12"), ("merge_end:blocked", "#12"), ("dequeued:parked", "#12"),
                          ("idle_start", "-"), ("idle_end", "-")])
        # queued long ago: the wait from queued_at to the merge is in the dequeued line
        self.assertGreater(int(rows[2][5]), 3600)


# ---------------------------------------------------------------------------
class QueueFileTests(LoopHarness, unittest.TestCase):
    def shell(self, script):
        return subprocess.run(["bash", "-c", f'. "{self.scripts}/loop-common.sh"; REPO_ROOT=/wt; LOOP_NAME=test; {script}'],
                              env=self.env, text=True, capture_output=True, timeout=120)

    def test_two_concurrent_writers_never_lose_a_line(self):
        self.state_dir.mkdir()
        writer = 'state_init; for i in $(seq 1 40); do queue_append "$((%d + i))" "feature/w%d-$i" tracker - /wt || exit 1; done'
        procs = [subprocess.Popen(["bash", "-c", f'. "{self.scripts}/loop-common.sh"; ' + writer % (base, base)],
                                  env=self.env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                 for base in (1000, 2000)]
        for proc in procs:
            out, _ = proc.communicate(timeout=120)
            self.assertEqual(proc.returncode, 0, out)
        rows = self.rows("pr-queue.tsv")
        self.assertEqual(len(rows), 80)
        self.assertEqual(sorted(int(r[1]) for r in rows), sorted([1000 + i for i in range(1, 41)] + [2000 + i for i in range(1, 41)]))
        self.assertTrue(all(len(r) == 6 for r in rows))
        self.assertEqual(sorted(p.name for p in self.state_dir.iterdir() if not p.name.startswith(".")),
                         ["loop-metrics.tsv", "pr-parked.tsv", "pr-queue.tsv"])   # no temp files left

    def test_append_refuses_duplicates_and_parked_prs_and_park_moves_the_line(self):
        result = self.shell('state_init; queue_append 5 feature/a tracker 01-a.md /wt; echo "rc=$?"; '
                            'queue_append 5 feature/a tracker 01-a.md /wt; echo "rc=$?"; '
                            'queue_park 5 "blocked: x"; echo "rc=$?"; '
                            'queue_append 5 feature/a tracker 01-a.md /wt; echo "rc=$?"')
        self.assertEqual([l for l in result.stdout.splitlines() if l.startswith("rc=")],
                         ["rc=0", "rc=3", "rc=0", "rc=4"], result.stdout + result.stderr)
        self.assertEqual(self.rows("pr-queue.tsv"), [])
        self.assertEqual(self.rows("pr-parked.tsv")[0][7], "blocked: x")

    def test_twin_libraries_are_identical(self):
        claude = HOSTS["claude"]
        if not (claude / "loop-common.sh").exists():
            self.skipTest("no Claude twin")
        for name in ("loop-common.sh", "loop-report"):
            self.assertEqual((HOSTS["codex"] / name).read_text(), (claude / name).read_text(), name)
        for name in ("build-loop.sh", "merge-loop.sh"):
            codex = (HOSTS["codex"] / name).read_text().replace("~/.codex/", "~/.claude/")
            self.assertEqual(codex, (claude / name).read_text(), name)


# ---------------------------------------------------------------------------
class LoopReportTests(LoopHarness, unittest.TestCase):
    def test_report_prints_every_section_for_the_window(self):
        rows = [
            # an event outside the 7-day window must not count
            ("2026-11-10T08:00:00Z", "build:trackers/a", "/wt1", "build_end:ok", "00-old.md", "100"),
            ("2026-11-25T08:00:00Z", "build:trackers/a", "/wt1", "build_start", "-", "-"),
            ("2026-11-25T09:00:00Z", "build:trackers/a", "/wt1", "queued", "#11", "-"),
            ("2026-11-25T09:00:00Z", "build:trackers/a", "/wt1", "build_end:ok", "01-a.md", "3600"),
            ("2026-11-25T09:10:00Z", "build:trackers/b", "/wt2", "queued", "#12", "-"),
            ("2026-11-25T09:10:00Z", "build:trackers/b", "/wt2", "build_end:ok", "01-b.md", "7200"),
            ("2026-11-25T09:20:00Z", "build:trackers/a", "/wt1", "queued", "#13", "-"),
            ("2026-11-25T09:20:00Z", "build:trackers/a", "/wt1", "build_end:ok", "02-a.md", "1800"),
            ("2026-11-25T09:30:00Z", "merge", "/wt3", "merge_start", "#11", "-"),
            ("2026-11-25T10:00:00Z", "merge", "/wt3", "merge_end:merged", "#11", "1800"),
            ("2026-11-25T10:00:00Z", "merge", "/wt3", "dequeued:merged", "#11", "3600"),
            ("2026-11-25T10:00:00Z", "merge", "/wt3", "merge_start", "#12", "-"),
            ("2026-11-26T10:00:00Z", "merge", "/wt3", "merge_end:merged", "#12", "3000"),
            ("2026-11-26T10:00:00Z", "merge", "/wt3", "dequeued:merged", "#12", "89400"),
            ("2026-11-26T10:00:00Z", "merge", "/wt3", "merge_start", "#13", "-"),
            ("2026-11-26T10:30:00Z", "merge", "/wt3", "merge_end:blocked", "#13", "1800"),
            ("2026-11-26T10:30:00Z", "merge", "/wt3", "dequeued:parked", "#13", "90600"),
            ("2026-11-26T10:30:00Z", "merge", "/wt3", "idle_start", "-", "-"),
            ("2026-11-26T12:30:00Z", "merge", "/wt3", "idle_end", "-", "7200"),
            ("2026-11-25T09:20:00Z", "build:trackers/a", "/wt1", "idle_start", "-", "-"),
            ("2026-11-25T10:20:00Z", "build:trackers/a", "/wt1", "idle_end", "-", "3600"),
        ]
        metrics = self.top / "metrics.tsv"
        metrics.write_text("".join("\t".join(r) + "\n" for r in rows) + "garbage line\n")
        result = subprocess.run(["python3", str(self.scripts / "loop-report"), "--since", "7d",
                                 "--file", str(metrics), "--now", "2026-11-27T12:00:00Z"],
                                text=True, capture_output=True, timeout=30)
        out = result.stdout
        self.assertEqual(result.returncode, 0, out + result.stderr)
        for expected in ("Tickets built and merged per day per tracker",
                         "2026-11-25  trackers/a          2       1",
                         "2026-11-25  trackers/b          1       0",
                         "2026-11-26  trackers/b          0       1",
                         "build time (ok builds)          3    1.0 h    2.0 h",
                         "merge time (merged runs)        2   40.0 m   50.0 m",
                         "queued → merged                 2   12.9 h   24.8 h",
                         "Queue length",
                         "max waiting PRs: 3   time with > 2 waiting: 0.1 %",
                         "stay in phase 1",
                         "Idle time per loop",
                         "build:trackers/a",
                         "merge"):
            self.assertIn(expected, out)
        self.assertNotIn("00-old.md", out)
        self.assertNotIn("2026-11-10", out)

    def test_report_on_missing_file_says_so(self):
        result = subprocess.run(["python3", str(self.scripts / "loop-report"), "--file", str(self.top / "none.tsv")],
                                text=True, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no metrics file", result.stderr)


class ClaudeBuildLoopTests(BuildLoopTests):
    HOST = "claude"

    def agent_args(self, phase):
        return next(c["args"] for c in self.agents if c["phase"] == phase)

    def test_claude_defaults_opus_high_and_400k_compaction(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=1), 0, self.output)
        args = self.agent_args("build")
        self.assertEqual(args[args.index("--model") + 1], "opus")
        self.assertEqual(args[args.index("--effort") + 1], "high")
        self.assertEqual(self.agents[0]["compact_window"], "400000")

    def test_claude_model_effort_and_compaction_can_be_chosen(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.env.update(MAIN_MODEL="fable", MAIN_EFFORT="", AGENT_COMPACT_WINDOW="")
        self.assertEqual(self.run_loop("build-loop.sh", self.wt1, "tracker", stop_after=1), 0, self.output)
        args = self.agent_args("build")
        self.assertEqual(args[args.index("--model") + 1], "fable")
        self.assertNotIn("--effort", args)
        self.assertIsNone(self.agents[0]["compact_window"])

    def test_issue_loop_model_can_be_chosen(self):
        self.ticket("01-alpha.md", "ready-for-agent")
        self.env.update(MAIN_MODEL="fable", MAIN_EFFORT="medium")
        self.assertEqual(self.run_loop("issue-loop.sh", self.wt1, "tracker", stop_after=1), 0, self.output)
        args = self.agent_args("build")
        self.assertEqual(args[args.index("--model") + 1], "fable")
        self.assertEqual(args[args.index("--effort") + 1], "medium")
        self.assertEqual(self.agents[0]["compact_window"], "400000")


class ClaudeMergeLoopTests(MergeLoopTests):
    HOST = "claude"


class ClaudeQueueFileTests(QueueFileTests):
    HOST = "claude"


class ClaudeLoopReportTests(LoopReportTests):
    HOST = "claude"


if __name__ == "__main__":
    unittest.main(verbosity=2)
