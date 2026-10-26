#!/usr/bin/env python3
"""Offline regression checks for loop result handling and reviewer boundaries."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def runner_dir(host):
    return ROOT / "skills" / host / "issue-loop" / "scripts"


def function(source, name):
    start = source.index(name + "() {")
    return source[start:source.index("\n}\n", start) + 3]


class ResultTests(unittest.TestCase):
    def classifiers(self, events):
        for host in ("claude", "codex"):
            spec = importlib.util.spec_from_file_location("agent_result", runner_dir(host) / "agent-result.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            yield host, module.classify(events)

    def test_real_claude_limit_shape_is_not_success(self):
        events = [dict(type="result", subtype="success", is_error=True,
                       result="You've hit your session limit · resets 5:50pm (Asia/Bangkok)")]
        for host, code in self.classifiers(events):
            self.assertEqual(code, 75, host)

    def test_codex_limit_and_claude_budget_exhaustion(self):
        for event in [dict(type="turn.failed", error=dict(code="usage_limit_exceeded")),
                      dict(type="result", subtype="error_max_budget_usd", is_error=True)]:
            for host, code in self.classifiers([event]):
                self.assertEqual(code, 75, host)

    def test_partial_failed_and_missing_results_are_not_clean(self):
        for events in [[], [dict(type="result", subtype="error_max_turns", is_error=True)],
                       [dict(type="result", is_error=True, result="Model unavailable")],
                       [dict(type="assistant", message=dict(content="Review complete"))],
                       ["not an event"]]:
            for host, code in self.classifiers(events):
                self.assertEqual(code, 1, host)

    def test_quoted_limit_text_does_not_stop_a_successful_run(self):
        events = [dict(type="user", message=dict(content="You've hit your session limit")),
                  dict(type="result", is_error=False, subtype="success", result="Test passed")]
        for host, code in self.classifiers(events):
            self.assertEqual(code, 0, host)

    def test_renderer_marks_error_result_red_instead_of_done(self):
        event = dict(type="result", subtype="success", is_error=True, result="Usage exhausted")
        for host in ("claude", "codex"):
            result = subprocess.run(["python3", str(runner_dir(host) / "pretty-stream.py")],
                                    input=json.dumps(event) + "\n", text=True, capture_output=True, check=True)
            self.assertIn("ERROR", result.stdout)
            self.assertNotIn("done", result.stdout)


class ClaudeLaunchTests(unittest.TestCase):
    def launch(self, event, exit_code=0, profile="", helper="claude-sonnet-5-5"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = (runner_dir("claude") / "issue-loop.sh").read_text()
            stub = root / "claude"
            stub.write_text("#!/usr/bin/env python3\nimport json,os,sys\n"
                            "print(json.dumps({'helper':os.environ.get('CLAUDE_CODE_SUBAGENT_MODEL'),"
                            "'profile':os.environ.get('CLAUDE_CONFIG_DIR'),'args':sys.argv[1:]}))\n"
                            + "print(" + repr(json.dumps(event)) + ")\n"
                            + f"sys.exit({exit_code})\n")
            stub.chmod(0o755)
            script = root / "launch.sh"
            script.write_text('set -uo pipefail\nrender() { cat; }\n'
                              'stop_loop() { echo "$1"; exit "$2"; }\n'
                              + function(source, "run_claude")
                              + '\nrun_claude opus "$TEST_PROFILE" high "$TEST_LOG" "Review fixture"\n'
                              + 'rc=$?\necho "AFTER_LAUNCH rc=$rc"\nexit "$rc"\n')
            return subprocess.run(["bash", str(script)], text=True, capture_output=True,
                                  env=dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                                           SCRIPT_DIR=str(runner_dir("claude")),
                                           REVIEW_HELPER_MODEL=helper, TEST_PROFILE=profile,
                                           TEST_LOG=str(root / "run.log")), timeout=10)

    def test_default_helpers_use_sonnet_with_both_profile_paths(self):
        for profile in ("", "/tmp/test-profile"):
            result = self.launch(dict(type="result", subtype="success", result="Reviewed"), profile=profile)
            self.assertEqual(result.returncode, 0, result.stderr)
            launch = json.loads(result.stdout.splitlines()[0])
            self.assertEqual(launch["helper"], "claude-sonnet-5-5")
            self.assertEqual(launch["args"][launch["args"].index("--model") + 1], "opus")
            if profile:
                self.assertEqual(launch["profile"], profile)

    def test_limit_exits_runner_before_next_phase_even_with_cli_exit_zero(self):
        result = self.launch(dict(type="result", subtype="success", is_error=True,
                                  result="You've hit your session limit · resets 5:50pm"))
        self.assertEqual(result.returncode, 75, result.stderr)
        self.assertIn("USAGE LIMIT", result.stdout)
        self.assertNotIn("AFTER_LAUNCH", result.stdout)

    def test_process_failure_is_preserved_through_both_pipeline_paths(self):
        for profile in ("", "/tmp/test-profile"):
            result = self.launch(dict(type="result", subtype="success", result="Reviewed"),
                                 exit_code=19, profile=profile)
            self.assertEqual(result.returncode, 19, result.stdout + result.stderr)

    def test_error_result_with_zero_exit_is_still_a_failure(self):
        result = self.launch(dict(type="result", subtype="error_max_turns", is_error=True))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)

    def test_failed_final_result_cannot_supply_a_merge_sentinel(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "run.log"
            log.write_text(json.dumps(dict(type="result", is_error=True, subtype="success",
                                           result="<<<MERGE_BLOCKED #1 partial>>>")) + "\n")
            source = (runner_dir("claude") / "issue-loop.sh").read_text()
            script = function(source, "final_message") + '\nfinal_message "$TEST_LOG"\n'
            result = subprocess.run(["bash", "-c", script], env=dict(os.environ, TEST_LOG=str(log)),
                                    text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
