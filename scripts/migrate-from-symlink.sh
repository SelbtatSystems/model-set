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

# Filled in by the migration loop, consumed by the legacy skill-copy pass.
config_dirs=()
repo_dirs=()

for agent in claude codex opencode; do
  case "$agent" in
    claude)   config="$HOME/.claude";           tracked=("${claude_tracked[@]}") ;;
    codex)    config="$HOME/.codex";            tracked=("${codex_tracked[@]}") ;;
    opencode) config="$HOME/.config/opencode";  tracked=("${opencode_tracked[@]}") ;;
  esac
  repo_dir="$REPO_DIR/global/$agent"
  old_link="$HOME/.$agent"     # ~/.opencode was the old (wrong) OpenCode path

  # Recorded before the early-exit checks below: the legacy skill-copy pass at
  # the end needs these paths whether or not this tool had anything to migrate.
  config_dirs+=("$config")
  repo_dirs+=("$repo_dir")

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

  # For claude and codex the config directory IS the old symlink. --dry-run only
  # prints the rm above, so the symlink is still there and "$config/$name"
  # resolves straight back through it into the repo — every item would report a
  # collision with itself and the run would claim it moved nothing. After the
  # real rm, $config is a freshly created empty directory, so nothing there can
  # collide anyway. Only opencode has a genuinely separate config directory
  # (~/.opencode -> ~/.config/opencode) where a real collision is possible.
  probe_collisions=true
  if $DRY_RUN && [ "$config" = "$old_link" ]; then
    probe_collisions=false
  fi

  # Move everything that is not ours into the real config directory.
  moved=0
  for item in "$repo_dir"/* "$repo_dir"/.[!.]*; do
    [ -e "$item" ] || continue
    name="$(basename "$item")"
    keep=false
    for t in "${tracked[@]}"; do [ "$name" = "$t" ] && keep=true; done
    $keep && continue
    if $probe_collisions && [ -e "$config/$name" ]; then
      warn "$config/$name already exists — leaving repo copy at $item"
      continue
    fi
    run "mv '$item' '$config/$name'"
    moved=$((moved + 1))
  done
  ok "moved $moved runtime item(s) out of the repo into $config"
done

# ---------------------------------------------------------------------------
# Legacy seeded skill copies
#
# The old layout seeded each host's skills directory with real directories
# copied out of the repo. setup.sh will not overwrite a real directory with a
# symlink — it warns and skips — so these have to go before setup can take over.
#
# A copy is stale if a directory of that name exists under ANY set in skills/,
# including a set that does not feed this host. That last part matters: a
# claude-set skill stranded in the OpenCode directory still has a repo source,
# it is simply not linked there any more, so it must be removed and not
# mistaken for an orphan. Checking only the sets that feed a host reports those
# as orphans, which is wrong.
#
# Anything with no source under any set is a genuine orphan — the repo cannot
# recreate it, so it is reported and never deleted.
# ---------------------------------------------------------------------------
printf '\n%s\n' "legacy skill copies"

has_repo_source() {
  local name="$1" set_dir
  for set_dir in "$REPO_DIR"/skills/*/; do
    if [ -d "$set_dir$name" ]; then return 0; fi
  done
  return 1
}

orphans=0
for i in "${!config_dirs[@]}"; do
  skills_dir="${config_dirs[$i]}/skills"
  # --dry-run only prints the move above, so a destination that does not exist
  # yet has its copies still sitting in the repo. Preview those instead, or the
  # run would report nothing for that host and look falsely clean.
  if [ ! -d "$skills_dir" ] && $DRY_RUN && [ -d "${repo_dirs[$i]}/skills" ]; then
    skills_dir="${repo_dirs[$i]}/skills"
  fi
  [ -d "$skills_dir" ] || continue
  removed=0
  # */ matches directories only, so .system and skills-lock.json are left alone.
  for d in "$skills_dir"/*/; do
    [ -d "$d" ] || continue          # no match: the glob stayed literal
    [ -L "${d%/}" ] && continue      # already a symlink — setup.sh owns it
    name="$(basename "$d")"
    if has_repo_source "$name"; then
      run "rm -rf '${d%/}'"
      removed=$((removed + 1))
    else
      warn "no source under skills/ — not deleted: ${d%/}"
      orphans=$((orphans + 1))
    fi
  done
  ok "removed $removed legacy copy/copies from $skills_dir"
done

if [ "$orphans" -gt 0 ]; then
  warn "$orphans orphan(s) above — move each into skills/claude/ or skills/codex/"
  warn "and commit it, or delete it by hand. setup.sh will leave them untouched."
fi

cat <<'EOF'

Next:
  1. ./scripts/setup.sh          # re-links the tracked files individually
  2. ./scripts/doctor.sh         # verify
  3. Trim the "legacy runtime data" section of .gitignore — those paths no
     longer exist inside the repo.
EOF
