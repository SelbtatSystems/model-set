#!/usr/bin/env python3
"""
Claude Code Context Monitor
Real-time context usage monitoring with visual indicators and session analytics
"""

import json
import sys
import os
import re
import subprocess

# Force UTF-8 output on Windows (cp1252 can't handle emoji)
if sys.stdout.encoding != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8")


def get_git_status():
    """Get git branch with staged/modified counts."""
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RESET = "\033[0m"

    try:
        subprocess.check_output(
            ["git", "rev-parse", "--git-dir"], stderr=subprocess.DEVNULL
        )
        branch = subprocess.check_output(
            ["git", "branch", "--show-current"], text=True, stderr=subprocess.DEVNULL
        ).strip()

        if not branch:
            return ""

        staged_output = subprocess.check_output(
            ["git", "diff", "--cached", "--numstat"], text=True, stderr=subprocess.DEVNULL
        ).strip()
        modified_output = subprocess.check_output(
            ["git", "diff", "--numstat"], text=True, stderr=subprocess.DEVNULL
        ).strip()

        staged = len(staged_output.split("\n")) if staged_output else 0
        modified = len(modified_output.split("\n")) if modified_output else 0

        git_info = f"{GREEN}+{staged}{RESET}" if staged else ""
        git_info += f"{YELLOW}~{modified}{RESET}" if modified else ""

        suffix = f" {git_info}" if git_info else ""

        return f" \033[90m·\033[0m ├ {branch}{suffix}"

    except Exception:
        return ""


def parse_context_from_transcript(transcript_path):
    """Parse context usage from transcript file."""
    if not transcript_path or not os.path.exists(transcript_path):
        return None

    try:
        with open(transcript_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()

        # Check last 15 lines for context information
        recent_lines = lines[-15:] if len(lines) > 15 else lines

        for line in reversed(recent_lines):
            try:
                data = json.loads(line.strip())

                # Method 1: Parse usage tokens from assistant messages
                if data.get("type") == "assistant":
                    message = data.get("message", {})
                    usage = message.get("usage", {})

                    if usage:
                        input_tokens = usage.get("input_tokens", 0)
                        cache_read = usage.get("cache_read_input_tokens", 0)
                        cache_creation = usage.get("cache_creation_input_tokens", 0)

                        # Estimate context usage (assume 200k context for Claude Sonnet)
                        total_tokens = input_tokens + cache_read + cache_creation
                        if total_tokens > 0:
                            percent_used = min(100, (total_tokens / 200000) * 100)
                            return {
                                "percent": percent_used,
                                "tokens": total_tokens,
                                "method": "usage",
                            }

                # Method 2: Parse system context warnings
                elif data.get("type") == "system_message":
                    content = data.get("content", "")

                    # "Context left until auto-compact: X%"
                    match = re.search(
                        r"Context left until auto-compact: (\d+)%", content
                    )
                    if match:
                        percent_left = int(match.group(1))
                        return {
                            "percent": 100 - percent_left,
                            "warning": "auto-compact",
                            "method": "system",
                        }

                    # "Context low (X% remaining)"
                    match = re.search(r"Context low \((\d+)% remaining\)", content)
                    if match:
                        percent_left = int(match.group(1))
                        return {
                            "percent": 100 - percent_left,
                            "warning": "low",
                            "method": "system",
                        }

            except (json.JSONDecodeError, KeyError, ValueError):
                continue

        return None

    except (FileNotFoundError, PermissionError):
        return None


def get_context_display(context_info):
    """Generate context display with dash-based progress bar."""
    if not context_info:
        return "\033[90m" + "░" * 10 + "\033[0m 0%"

    percent = context_info.get("percent", 0)
    warning = context_info.get("warning")

    # 10 segments, each represents 10% of context
    total = 10
    filled = int((percent / 100) * total)

    # Color for filled segments based on usage level
    if percent >= 75:
        fill_color = "\033[31m"  # Red
    elif percent >= 50:
        fill_color = "\033[33m"  # Orange/yellow
    else:
        fill_color = "\033[32m"  # Green

    reset = "\033[0m"

    bar = f"{fill_color}" + "▓" * filled + f"{reset}\033[90m" + "░" * (total - filled) + f"{reset}"

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

    return f"{bar} {percent:.0f}%{alert}"


def get_directory_display(workspace_data):
    """Get directory display name."""
    current_dir = workspace_data.get("current_dir", "")
    project_dir = workspace_data.get("project_dir", "")

    if current_dir and project_dir:
        if current_dir.startswith(project_dir):
            rel_path = current_dir[len(project_dir) :].lstrip("/")
            return rel_path or os.path.basename(project_dir)
        else:
            return os.path.basename(current_dir)
    elif project_dir:
        return os.path.basename(project_dir)
    elif current_dir:
        return os.path.basename(current_dir)
    else:
        return "unknown"


def main():
    try:
        # Read JSON input from Claude Code
        data = json.load(sys.stdin)

        # Extract information
        model_name = data.get("model", {}).get("display_name", "Claude")
        workspace = data.get("workspace", {})
        transcript_path = data.get("transcript_path", "")

        # Parse context usage
        context_info = parse_context_from_transcript(transcript_path)

        # Build status components
        context_display = get_context_display(context_info)
        directory = get_directory_display(workspace)
        git_status = get_git_status()

        # Combine all components
        status_line = (
            f"{model_name} "
            f"\033[90m·\033[0m {context_display} "
            f"\033[90m·\033[0m "
            f"🗁 {directory}"
            f"{git_status}"
        )

        print(status_line)

    except Exception as e:
        # Fallback display on any error
        print(
            f"Claude \033[90m·\033[0m \033[31m[Error: {str(e)[:20]}]\033[0m \033[90m·\033[0m 🗁 {os.path.basename(os.getcwd())}"
        )


if __name__ == "__main__":
    main()
