#!/usr/bin/env bash
# Config-file manifest — the single list of what this repo owns.
#
# Sourced by setup.sh and doctor.sh. Each entry is "<repo-relative>::<target>";
# setup symlinks repo file -> target, doctor verifies the link resolves.
#
# File ownership, not directory ownership: the tools keep their own config
# directories, and we place individual files inside them. Runtime state (sqlite,
# sessions, credentials, logs) therefore never enters the repo. See PLAN.md.
#
# ANYTHING NOT LISTED HERE DOES NOT TRAVEL TO A NEW MACHINE. That is the whole
# failure mode this replaces — claude-update.sh, codex/rules/agents.rules and
# ten skill directories were all untracked and would have been lost.

CONFIG_MANIFEST=(
  "global/claude/CLAUDE.md::$HOME/.claude/CLAUDE.md"
  "global/claude/settings.json::$HOME/.claude/settings.json"
  "global/claude/settings.local.json::$HOME/.claude/settings.local.json"
  "global/claude/scripts/context-monitor.py::$HOME/.claude/scripts/context-monitor.py"
  "global/claude/agents/frontend-review.md::$HOME/.claude/agents/frontend-review.md"
  "global/claude/agents/agent-design-review.md::$HOME/.claude/agents/agent-design-review.md"
  "global/claude/agents/codebase-integrator.md::$HOME/.claude/agents/codebase-integrator.md"
  "scripts/ai-update.sh::$HOME/.local/bin/ai-update"

  "global/codex/AGENTS.md::$HOME/.codex/AGENTS.md"
  "global/codex/config.toml::$HOME/.codex/config.toml"
  "global/codex/rules/default.rules::$HOME/.codex/rules/default.rules"
  "global/codex/rules/agents.rules::$HOME/.codex/rules/agents.rules"

  "global/opencode/opencode.json::$HOME/.config/opencode/opencode.json"
  "global/opencode/AGENTS.md::$HOME/.config/opencode/AGENTS.md"
)

# Where each host expects its skills. Keys must match the hosts named in
# skills/manifest.json.
declare -A HOST_SKILL_DIRS=(
  [claude]="$HOME/.claude/skills"
  [codex]="$HOME/.codex/skills"
  [opencode]="$HOME/.config/opencode/skills"
  [agents]="$HOME/.agents/skills"
)

# Claude Code profiles (CLAUDE_CONFIG_DIR). ~/.claude is the primary — setup.sh
# links skills/agents there — and every other profile mirrors it through
# scripts/sync-claude-profiles.sh, so the three never drift apart again.
CLAUDE_PROFILE_DIRS=(
  "$HOME/.claude"
  "$HOME/.claude-max-1"
  "$HOME/.claude-max-2"
)
