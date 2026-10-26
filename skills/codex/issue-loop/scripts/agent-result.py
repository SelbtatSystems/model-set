#!/usr/bin/env python3
"""Classify terminal Claude/Codex output: 0 complete, 1 failed, 75 usage limit.

Only terminal result/error events count. Quoted tool output and intermediate
assistant text cannot turn a failed run into success or trigger a limit stop.
"""

import json
import re
import sys


LIMIT = re.compile(
    r"(?:hit|reached|exceeded).{0,60}(?:session|usage|rate|spending|budget).{0,20}limit"
    r"|(?:usage|rate|spending|budget)[_ -]limit(?:[_ -]exceeded)?"
    r"|hit your limit|insufficient[_ -]quota|error_max_budget_usd|too many requests",
    re.IGNORECASE,
)


def classify(events):
    terminal = None
    for event in events:
        if not isinstance(event, dict):
            continue
        kind = event.get("type")
        if kind == "result":
            failed = event.get("is_error", False) or event.get("subtype", "success") != "success"
            terminal = (failed, json.dumps(event.get("result", "")) + " "
                        + str(event.get("subtype", "")) + " " + json.dumps(event.get("errors", [])))
        elif kind in ("turn.failed", "error") or (kind == "system" and event.get("subtype") == "error"):
            terminal = (True, json.dumps(event))
        elif kind == "turn.completed":
            terminal = (False, "")
    if terminal is None:
        return 1
    failed, message = terminal
    if failed and LIMIT.search(message):
        return 75
    return 1 if failed else 0


def read_events(path):
    with open(path, errors="replace") as stream:
        for line in stream:
            try:
                yield json.loads(line)
            except ValueError:
                continue


if __name__ == "__main__":
    sys.exit(classify(read_events(sys.argv[1])))
