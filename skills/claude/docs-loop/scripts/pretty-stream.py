#!/usr/bin/env python3
"""Condense an agent's JSON event stream into one line per action.

Understands both feeds used by the loops:
  · Claude Code  --print --output-format stream-json --verbose
  · codex exec   --json

Reads JSONL on stdin, writes a short human-followable trace on stdout:
  · what the agent is thinking (trimmed)
  · every tool call: the tool name and what it is acting on (file, command, pattern)
  · the agent's own text and its final result

Deliberately NOT shown: file contents, command output, diffs, tool results. The full
stream is still written to the loop's log file, so nothing is lost for debugging.
Unparseable lines pass through untouched, so an error message is never swallowed.
"""
import json
import sys

TTY = sys.stdout.isatty()

# Thinking is the line you scan for to know *why* the agent is doing something, so it gets the
# accent colour (magenta, italic) rather than the dim grey everything-else-is-noise treatment.
THINKING = "3;35"
# What the agent SAYS is the narrative of the run, so it is bold rather than a colour —
# it stays legible on any terminal theme and does not compete with the accent used above.
SAYS = "1"


def paint(code, text):
    return f"\033[{code}m{text}\033[0m" if TTY else text


def flat(text, limit):
    """One line, collapsed whitespace, truncated."""
    s = " ".join(str(text).split())
    return s if len(s) <= limit else s[: limit - 1] + "…"


def target_of(name, params):
    """The most useful 'what is it acting on' string for a tool call."""
    if not isinstance(params, dict):
        return ""
    for key in ("file_path", "notebook_path", "path"):
        if params.get(key):
            return flat(params[key], 100)
    if params.get("command"):
        return flat(params["command"], 100)
    if params.get("pattern"):
        where = params.get("path") or params.get("glob") or ""
        return flat(f"{params['pattern']} {where}".strip(), 100)
    for key in ("url", "skill", "description", "query", "prompt", "subagent_type"):
        if params.get(key):
            return flat(params[key], 100)
    return ""


def emit(label, colour, body):
    print(f"{paint(colour, label)} {body}", flush=True)


LAST_MESSAGE = {"text": ""}


def handle_codex(event):
    """codex exec --json: thread./turn./item.* events."""
    kind = event.get("type", "")

    if kind == "thread.started":
        emit("agent", "36", "codex")
        return

    if kind == "turn.completed":
        usage = event.get("usage") or {}
        tokens = usage.get("output_tokens")
        meta = f"  [{tokens} output tokens]" if tokens else ""
        emit("done", "32", flat(LAST_MESSAGE["text"], 200) + meta)
        return

    if kind == "turn.failed":
        emit("ERROR", "31", flat(event.get("error", event), 200))
        return

    if not kind.startswith("item."):
        return

    item = event.get("item", {}) or {}
    itype = item.get("type")

    # Commands are shown when they START, so the screen tracks the agent live.
    if itype == "command_execution":
        if kind == "item.started":
            emit("  →", "33", f"{paint('1', 'Bash')} {flat(item.get('command', ''), 110)}")
        elif kind == "item.completed" and item.get("exit_code") not in (0, None):
            emit("  ✗", "31", f"exit {item.get('exit_code')}")
        return

    if kind != "item.completed":
        return

    if itype == "agent_message":
        text = item.get("text", "")
        LAST_MESSAGE["text"] = text or LAST_MESSAGE["text"]
        if text:
            emit("  »", SAYS, paint(SAYS, flat(text, 160)))
    elif itype == "reasoning":
        thought = flat(item.get("text") or item.get("summary", ""), 140)
        if thought:
            emit("  ·", THINKING, paint(THINKING, thought))
    elif itype == "file_change":
        changes = item.get("changes") or item.get("paths") or item.get("path") or ""
        if isinstance(changes, list):
            changes = ", ".join(str(c.get("path", c)) if isinstance(c, dict) else str(c) for c in changes)
        emit("  →", "33", f"{paint('1', 'Edit')} {flat(changes, 110)}")
    elif itype in ("mcp_tool_call", "web_search", "todo_list"):
        emit("  →", "33", f"{paint('1', itype)} {flat(item.get('query') or item.get('tool') or '', 100)}")
    elif itype == "error":
        emit("ERROR", "31", flat(item.get("message", item), 200))


def handle(event):
    kind = event.get("type", "")
    if kind.startswith(("thread.", "turn.", "item.")):
        handle_codex(event)
        return

    if kind == "system" and event.get("subtype") == "init":
        emit("agent", "36", f"{event.get('model', '?')} in {event.get('cwd', '?')}")
        return

    if kind == "assistant":
        for block in event.get("message", {}).get("content", []):
            btype = block.get("type")
            if btype == "thinking":
                thought = flat(block.get("thinking", ""), 140)
                if thought:
                    emit("  ·", THINKING, paint(THINKING, thought))
            elif btype == "text":
                said = flat(block.get("text", ""), 160)
                if said:
                    emit("  »", SAYS, paint(SAYS, said))
            elif btype == "tool_use":
                name = block.get("name", "?")
                emit("  →", "33", f"{paint('1', name)} {target_of(name, block.get('input'))}")
        return

    if kind == "result":
        cost = event.get("total_cost_usd")
        turns = event.get("num_turns")
        meta = " ".join(
            part
            for part in (
                f"{turns} turns" if turns else "",
                f"${cost:.2f}" if isinstance(cost, (int, float)) else "",
            )
            if part
        )
        emit("done", "32", flat(event.get("result", ""), 200) + (f"  [{meta}]" if meta else ""))
        return

    if kind == "system" and event.get("subtype") == "error":
        emit("ERROR", "31", flat(event.get("message", event), 200))


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except ValueError:
            # Not JSON (a crash message, a stray warning) — show it verbatim.
            print(line, flush=True)
            continue
        try:
            handle(event)
        except Exception as exc:  # never let formatting kill the stream
            print(f"[pretty-stream: {exc}]", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
