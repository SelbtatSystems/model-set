#!/usr/bin/env python3
"""
Claude Code Context Monitor
Real-time context usage monitoring with visual indicators and session analytics
"""

import json
import sys
import os
import re
import unicodedata

# Force UTF-8 output on Windows (cp1252 can't handle emoji)
if sys.stdout.encoding != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8")

# ANSI escape pattern for stripping from width calculations
ANSI_RE = re.compile(r"\033\[[^m]*m")
MODEL_COLOR = "\033[38;2;246;226;183m"
USAGE_COLOR = "\033[38;2;226;170;135m"
DIM_COLOR = "\033[90m"
RESET = "\033[0m"


def char_width(ch):
    """Get display width of a character (2 for wide/emoji, 1 otherwise)."""
    eaw = unicodedata.east_asian_width(ch)
    if eaw in ("W", "F"):
        return 2
    # Emoji/symbols in U+1F000-1FFFF render as 2 columns in terminals
    # despite Unicode East_Asian_Width being Neutral (e.g. 🗁 U+1F5C1)
    if ord(ch) >= 0x1F000:
        return 2
    return 1


def visible_width(s):
    """Calculate visible column width, ignoring ANSI codes."""
    stripped = ANSI_RE.sub("", s)
    return sum(char_width(ch) for ch in stripped)


def truncate_to_width(s, max_width):
    """Truncate string with ANSI codes to fit max_width visible columns."""
    width = 0
    i = 0
    while i < len(s):
        # Skip ANSI escape sequences (zero visible width)
        if s[i] == "\033" and i + 1 < len(s) and s[i + 1] == "[":
            j = i + 2
            while j < len(s) and s[j] != "m":
                j += 1
            i = j + 1
            continue
        cw = char_width(s[i])
        if width + cw > max_width:
            break
        width += cw
        i += 1
    return s[:i] + "\033[0m"


# Context window sizes by model keyword (tokens)
MODEL_CONTEXT_WINDOWS = {
    "opus": 250_000,
    "sonnet": 250_000,
    "haiku": 200_000,
}
DEFAULT_CONTEXT_WINDOW = 250_000

CONTEXT_WINDOW_KEYS = {
    "context_window",
    "contextwindow",
    "contextwindowtokens",
    "context_window_tokens",
    "context_window_size",
    "contextwindowsize",
    "max_context_tokens",
    "maxcontexttokens",
    "max_context_window",
    "maxcontextwindow",
}


def get_context_window(model_name):
    """Get context window size for a model name."""
    name_lower = model_name.lower()
    for keyword, size in MODEL_CONTEXT_WINDOWS.items():
        if keyword in name_lower:
            return size
    return DEFAULT_CONTEXT_WINDOW


def normalize_token_count(value):
    """Normalize token count values from JSON into positive integers."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value > 0:
        return value
    if isinstance(value, float) and value > 0:
        return int(value)
    if isinstance(value, str):
        text = value.strip().lower().replace(",", "").replace("_", "")
        multiplier = 1
        if text.endswith("k"):
            multiplier = 1_000
            text = text[:-1]
        elif text.endswith("m"):
            multiplier = 1_000_000
            text = text[:-1]
        try:
            parsed = float(text)
        except ValueError:
            return None
        if parsed > 0:
            return int(parsed * multiplier)
    return None


def find_context_window(data):
    """Find a context-window token count in nested status/transcript data."""
    if isinstance(data, dict):
        for key, value in data.items():
            normalized_key = key.lower().replace("-", "_")
            compact_key = normalized_key.replace("_", "")
            if normalized_key in CONTEXT_WINDOW_KEYS or compact_key in CONTEXT_WINDOW_KEYS:
                tokens = normalize_token_count(value)
                if tokens:
                    return tokens
            found = find_context_window(value)
            if found:
                return found
    elif isinstance(data, list):
        for item in data:
            found = find_context_window(item)
            if found:
                return found
    return None


def get_status_model_name(data, fallback):
    """Get the most specific model identifier exposed in status input."""
    model = data.get("model", {})
    if isinstance(model, dict):
        for key in ("id", "name", "model", "display_name"):
            value = model.get(key)
            if isinstance(value, str) and value.strip():
                return value
    return fallback


def format_tokens_compact(tokens):
    """Format token counts as compact uppercase values."""
    if tokens >= 1_000_000:
        value = tokens / 1_000_000
        if value.is_integer():
            return f"{int(value)}M"
        return f"{value:.1f}".rstrip("0").rstrip(".") + "M"
    if tokens >= 1_000:
        return f"{round(tokens / 1_000):.0f}K"
    return str(tokens)


def parse_context_from_transcript(
    transcript_path,
    model_name="",
    context_window=None,
    context_window_locked=False,
):
    """Parse context usage from transcript file."""
    if not transcript_path or not os.path.exists(transcript_path):
        return None

    context_window = context_window or get_context_window(model_name)

    try:
        # Read tail of transcript; tool_result lines can be 10-50KB each,
        # so 8KB often misses the last assistant message — use 64KB
        with open(transcript_path, "rb") as f:
            f.seek(0, 2)  # seek to end
            file_size = f.tell()
            read_size = min(file_size, 65536)
            f.seek(file_size - read_size)
            tail = f.read().decode("utf-8", errors="replace")

        # Split into lines; skip first (potentially partial) line from mid-seek
        lines = tail.splitlines()
        if read_size < file_size:
            lines = lines[1:]
        recent_lines = lines[-50:]

        for line in reversed(recent_lines):
            try:
                data = json.loads(line.strip())
                line_context_window = find_context_window(data)
                if line_context_window:
                    context_window = line_context_window
                    context_window_locked = True

                message = data.get("message", {})
                line_model_name = message.get("model") if isinstance(message, dict) else ""
                if (
                    isinstance(line_model_name, str)
                    and line_model_name.strip()
                    and not context_window_locked
                ):
                    context_window = get_context_window(line_model_name)

                # Method 1: Parse usage tokens from assistant messages
                if data.get("type") == "assistant":
                    usage = message.get("usage", {})

                    if usage:
                        input_tokens = usage.get("input_tokens", 0)
                        cache_read = usage.get("cache_read_input_tokens", 0)
                        cache_creation = usage.get("cache_creation_input_tokens", 0)

                        total_tokens = input_tokens + cache_read + cache_creation
                        if total_tokens > 0:
                            percent_used = min(100, (total_tokens / context_window) * 100)
                            return {
                                "percent": percent_used,
                                "tokens": total_tokens,
                                "context_window": context_window,
                                "method": "usage",
                            }

                # Method 2: Parse system context warnings
                elif data.get("type") == "system_message":
                    content = data.get("content", "")

                    match = re.search(
                        r"Context left until auto-compact: (\d+)%", content
                    )
                    if match:
                        percent_left = int(match.group(1))
                        return {
                            "percent": 100 - percent_left,
                            "tokens": int(context_window * (100 - percent_left) / 100),
                            "context_window": context_window,
                            "warning": "auto-compact",
                            "method": "system",
                        }

                    match = re.search(r"Context low \((\d+)% remaining\)", content)
                    if match:
                        percent_left = int(match.group(1))
                        return {
                            "percent": 100 - percent_left,
                            "tokens": int(context_window * (100 - percent_left) / 100),
                            "context_window": context_window,
                            "warning": "low",
                            "method": "system",
                        }

            except (json.JSONDecodeError, KeyError, ValueError):
                continue

        return None

    except (FileNotFoundError, PermissionError):
        return None


def get_context_display(context_info):
    """Generate context display as used/window - percent."""
    if not context_info:
        context_window = DEFAULT_CONTEXT_WINDOW
        return f"0/{format_tokens_compact(context_window)} - 0%"

    percent = context_info.get("percent", 0)
    warning = context_info.get("warning")
    tokens = context_info.get("tokens", 0)
    context_window = context_info.get("context_window", DEFAULT_CONTEXT_WINDOW)

    # Alert text for critical states
    alert = ""
    if warning == "auto-compact":
        alert = " AUTO-COMPACT!"
    elif warning == "low":
        alert = " LOW!"
    elif percent >= 95:
        alert = " CRIT"
    elif percent >= 90:
        alert = " HIGH"

    return (
        f"{format_tokens_compact(tokens)}/{format_tokens_compact(context_window)}"
        f" - {percent:.0f}%{alert}"
    )


def nested_get(data, path):
    """Read a nested dictionary path."""
    value = data
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value


def normalize_thinking_label(value):
    """Normalize thinking/reasoning mode values into a compact label."""
    if value is None:
        return ""
    if isinstance(value, dict):
        for key in ("effortLevel", "reasoning_effort", "effort", "level", "mode"):
            label = normalize_thinking_label(value.get(key))
            if label:
                return label
        if value.get("enabled") is False:
            return "no-think"
        return ""
    if isinstance(value, bool):
        return "think" if value else "no-think"

    label = str(value).strip()
    if not label:
        return ""

    normalized = label.lower().replace("_", "-")
    if normalized in ("true", "on", "yes", "enabled", "enable"):
        return "think"
    if normalized in ("false", "off", "no", "disabled", "disable", "none"):
        return "no-think"
    return normalized


def get_persistent_effort_level():
    """Read Claude's configured effort level from settings.json."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    settings_paths = [
        os.path.join(os.path.dirname(script_dir), "settings.json"),
        os.path.expanduser("~/.claude/settings.json"),
    ]

    seen = set()
    for path in settings_paths:
        if path in seen:
            continue
        seen.add(path)

        try:
            with open(path, "r", encoding="utf-8") as f:
                settings = json.load(f)
        except (FileNotFoundError, PermissionError, json.JSONDecodeError):
            continue

        for key in ("effortLevel", "reasoning_effort", "effort"):
            label = normalize_thinking_label(settings.get(key))
            if label:
                return label

    return ""


def get_thinking_display(data):
    """Get a compact thinking/reasoning label when Claude exposes one."""
    explicit_effort_paths = [
        # Claude Code passes the live effort here (verified payload, v2.1.142).
        # Must take priority so /model changes reflect without restart.
        ("effort", "level"),
        ("model", "reasoning_effort"),
        ("model", "effortLevel"),
        ("reasoning_effort",),
        ("effortLevel",),
        ("settings", "reasoning_effort"),
        ("settings", "effortLevel"),
    ]

    for path in explicit_effort_paths:
        label = normalize_thinking_label(nested_get(data, path))
        if label:
            return label

    for env_name in ("CLAUDE_CODE_THINKING_STATUS", "CLAUDE_THINKING_STATUS"):
        label = normalize_thinking_label(os.environ.get(env_name))
        if label:
            return label

    label = get_persistent_effort_level()
    if label:
        return label

    generic_thinking_paths = [
        ("model", "thinking"),
        ("model", "thinking_mode"),
        ("thinking",),
        ("thinking_mode",),
        ("settings", "thinking"),
        ("settings", "thinking_mode"),
    ]

    for path in generic_thinking_paths:
        label = normalize_thinking_label(nested_get(data, path))
        if label:
            return label

    return ""


def clean_model_display_name(model_name):
    """Remove Claude's redundant context-window suffix from model display."""
    return re.sub(r"\s*\([^)]*context[^)]*\)", "", model_name, flags=re.IGNORECASE).strip()


def main():
    try:
        # Read JSON input from Claude Code
        data = json.load(sys.stdin)

        # Extract information
        model_name = data.get("model", {}).get("display_name", "Claude")
        model_name = clean_model_display_name(model_name)
        transcript_path = data.get("transcript_path", "")
        status_model_name = get_status_model_name(data, model_name)
        status_context_window = find_context_window(data)
        context_window = status_context_window or get_context_window(status_model_name)

        # Parse context usage
        context_info = parse_context_from_transcript(
            transcript_path,
            status_model_name,
            context_window,
            status_context_window is not None,
        )
        if not context_info:
            context_info = {
                "percent": 0,
                "tokens": 0,
                "context_window": context_window,
                "method": "fallback",
            }

        # Build status components
        context_display = get_context_display(context_info)
        thinking_display = get_thinking_display(data)
        model_display = f"{model_name} {thinking_display}".strip()

        # Combine all components
        status_line = (
            f"{MODEL_COLOR}{model_display}{RESET} "
            f"{DIM_COLOR}·{RESET} "
            f"{USAGE_COLOR}{context_display}{RESET}"
        )

        # Get terminal width; stderr may still be a TTY when stdin/stdout are pipes
        try:
            term_width = os.get_terminal_size(sys.stderr.fileno()).columns
        except (ValueError, OSError):
            term_width = 120

        # Always truncate — width calc can undercount ambiguous chars (▓░├)
        # across terminals; 2-col margin prevents last-char leak
        status_line = truncate_to_width(status_line, term_width - 2)

        print(status_line)

    except Exception as e:
        # Fallback display on any error
        print(
            f"Claude \033[90m·\033[0m \033[31m[Error: {str(e)[:20]}]\033[0m \033[90m·\033[0m 🗁 {os.path.basename(os.getcwd())}"
        )


if __name__ == "__main__":
    main()
