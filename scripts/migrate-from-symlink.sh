#!/usr/bin/env bash
# One-time migration: whole-directory symlinks -> file ownership.
#
#   ./scripts/migrate-from-symlink.sh [--dry-run]
#
# The old layout symlinked entire config directories into this repo:
#
#     ~/.claude   -> model-set/global/claude
#     ~/.codex    -> model-set/global/codex
#     ~/.opencode -> model-set/global/opencode
#
# which dragged sqlite databases, session logs, credentials and caches into a
# git repo. This restores each config directory to a real directory owned by its
# tool, moves the runtime state back into it, and leaves only our tracked files
# in the repo for setup.sh to symlink individually.
#
# RUN THIS WITH ALL AGENTS CLOSED. Claude Code, Codex and OpenCode hold open
# sqlite handles and write session state continuously; moving their config
# directory while one is running will corrupt that session.
#
# A fresh clone on a new machine never needs this — just run setup.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
run()  { if $DRY_RUN; then printf '  would  %s\n' "$*"; else eval "$@"; fi; }

# Files this repo owns per tool — everything else in the old directory is
# runtime state and moves back out to the real config directory.
claude_tracked=(CLAUDE.md settings.json settings.local.json scripts agents)
codex_tracked=(AGENTS.md config.toml rules agents)
opencode_tracked=(opencode.json AGENTS.md)

for agent in claude codex opencode; do
  case "$agent" in
    claude)   config="$HOME/.claude";           tracked=("${claude_tracked[@]}") ;;
    codex)    config="$HOME/.codex";            tracked=("${codex_tracked[@]}") ;;
    opencode) config="$HOME/.config/opencode";  tracked=("${opencode_tracked[@]}") ;;
  esac
  repo_dir="$REPO_DIR/global/$agent"
  old_link="$HOME/.$agent"     # ~/.opencode was the old (wrong) OpenCode path

  printf '\n%s\n' "$agent"

  if [ ! -L "$old_link" ]; then
    ok "no legacy symlink at $old_link — nothing to migrate"
    continue
  fi
  if [ "$(readlink -f "$old_link")" != "$(readlink -f "$repo_dir")" ]; then
    warn "$old_link points outside this repo — left alone"
    continue
  fi

  run "rm '$old_link'"
  run "mkdir -p '$config'"

  # Move everything that is not ours into the real config directory.
  moved=0
  for item in "$repo_dir"/* "$repo_dir"/.[!.]*; do
    [ -e "$item" ] || continue
    name="$(basename "$item")"
    keep=false
    for t in "${tracked[@]}"; do [ "$name" = "$t" ] && keep=true; done
    $keep && continue
    if [ -e "$config/$name" ]; then
      warn "$config/$name already exists — leaving repo copy at $item"
      continue
    fi
    run "mv '$item' '$config/$name'"
    moved=$((moved + 1))
  done
  ok "moved $moved runtime item(s) out of the repo into $config"
done

cat <<'EOF'

Next:
  1. ./scripts/setup.sh          # re-links the tracked files individually
  2. ./scripts/doctor.sh         # verify
  3. Trim the "legacy runtime data" section of .gitignore — those paths no
     longer exist inside the repo.
EOF
