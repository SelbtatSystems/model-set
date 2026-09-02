#!/usr/bin/env bash
# Mirror ~/.claude/skills and ~/.claude/agents into every other Claude profile
# listed in CLAUDE_PROFILE_DIRS (scripts/lib/manifest.sh).
#
# The primary profile (~/.claude) is the source of truth: setup.sh populates it
# from skills/manifest.json. Extra profiles (CLAUDE_CONFIG_DIR=~/.claude-max-N)
# get the same symlinks, pointing at the same targets, so a skill added, removed
# or renamed in model-set shows up identically in every profile.
#
#   - links present in the primary are created/updated in each profile
#   - links absent from the primary are removed from each profile
#   - a real directory in a profile is replaced by the link only when it is
#     byte-identical to the primary's target; otherwise it is left alone and
#     reported, so a local edit is never destroyed silently
#   - skills-lock.json is per-profile runtime state and is never touched
#
# Idempotent. Called at the end of setup.sh; safe to run on its own.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/manifest.sh
source "$SCRIPT_DIR/lib/manifest.sh"

PRIMARY="$HOME/.claude"
KINDS=(skills agents)
KEEP=(skills-lock.json)

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }

keep_name() { local n; for n in "${KEEP[@]}"; do [ "$1" = "$n" ] && return 0; done; return 1; }

changed=0
for profile in "${CLAUDE_PROFILE_DIRS[@]}"; do
  [ "$profile" = "$PRIMARY" ] && continue
  [ -d "$profile" ] || { warn "$profile: profile directory missing — skipped"; continue; }
  for kind in "${KINDS[@]}"; do
    src_dir="$PRIMARY/$kind"; dst_dir="$profile/$kind"
    [ -d "$src_dir" ] || continue
    mkdir -p "$dst_dir"

    # Prune: anything in the profile that the primary does not have.
    for entry in "$dst_dir"/* "$dst_dir"/.[!.]*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      name="$(basename "$entry")"
      keep_name "$name" && continue
      [ -e "$src_dir/$name" ] || [ -L "$src_dir/$name" ] && continue
      if [ -L "$entry" ]; then
        rm "$entry"; ok "$profile/$kind/$name: removed (not in primary)"; changed=$((changed+1))
      else
        warn "$profile/$kind/$name: real file/dir not in primary — left alone"
      fi
    done

    # Mirror: every symlink in the primary, same target.
    for entry in "$src_dir"/*; do
      [ -L "$entry" ] || continue
      name="$(basename "$entry")"
      target="$(readlink "$entry")"
      dest="$dst_dir/$name"
      if [ -L "$dest" ]; then
        [ "$(readlink "$dest")" = "$target" ] && continue
        rm "$dest"
      elif [ -e "$dest" ]; then
        if [ -e "$target" ] && diff -rq "$dest" "$target" >/dev/null 2>&1; then
          rm -r "$dest"; ok "$profile/$kind/$name: identical local copy replaced by link"
        else
          warn "$profile/$kind/$name: local copy differs from $target — left alone"
          continue
        fi
      fi
      ln -s "$target" "$dest"; ok "$profile/$kind/$name -> $target"; changed=$((changed+1))
    done
  done
done
ok "profiles in sync ($changed change(s))"
