#!/usr/bin/env bash
# List the upstream commits each forked skill has not taken yet. Read-only.
#
#   scripts/upstream-drift.sh [--summary] [skill ...]
#
# Every fork records its source in its SKILL.md frontmatter (skills/CONTRACT.md,
# "Upstream forks"):   upstream: <owner>/<repo>@<sha> <path in that repo>
# Upstream clones are cached in ~/.cache/model-set/upstream/ and fetched on each
# run, so the check survives a reboot.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/model-set/upstream"
SUMMARY=false
names=()
for arg in "$@"; do
  case "$arg" in
    --summary) SUMMARY=true ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *)         names+=("$arg") ;;
  esac
done

# skill|owner/repo|sha|path, one per fork.
entries=()
for skill_md in "$REPO_DIR"/skills/*/*/SKILL.md; do
  skill="$(basename "$(dirname "$skill_md")")"
  if [ ${#names[@]} -gt 0 ] && [[ " ${names[*]} " != *" $skill "* ]]; then continue; fi
  line="$(awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { exit } f' "$skill_md" \
            | sed -n -E 's/^[[:space:]]+upstream:[[:space:]]+//p' | head -1)"
  [ -n "$line" ] || continue
  read -r ref path <<< "$line"
  entries+=("$skill|${ref%@*}|${ref#*@}|$path")
done
[ ${#entries[@]} -gt 0 ] || { echo "no forked skill matches"; exit 0; }

for slug in $(printf '%s\n' "${entries[@]}" | cut -d'|' -f2 | sort -u); do
  dir="$CACHE/${slug/\//-}"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" fetch -q origin
  else
    mkdir -p "$CACHE"
    git clone -q "https://github.com/$slug.git" "$dir"
  fi
  git -C "$dir" remote set-head origin --auto > /dev/null
done

current=()
for entry in "${entries[@]}"; do
  IFS='|' read -r skill slug sha path <<< "$entry"
  dir="$CACHE/${slug/\//-}"
  if ! git -C "$dir" cat-file -e "$sha^{commit}" 2>/dev/null; then
    echo "$skill: $sha is not a commit in $slug"
    continue
  fi
  if ! git -C "$dir" cat-file -e "origin/HEAD:$path" 2>/dev/null; then
    echo "$skill: $path is gone upstream (renamed or removed); last change: $(git -C "$dir" log -1 --format='%h %ad %s' --date=short origin/HEAD -- "$path")"
    continue
  fi
  mapfile -t commits < <(git -C "$dir" log --format='%h %ad %s' --date=short "$sha..origin/HEAD" -- "$path")
  if [ ${#commits[@]} -eq 0 ]; then
    current+=("$skill")
  elif $SUMMARY; then
    echo "$skill: ${#commits[@]} upstream commit(s) since $sha"
  else
    echo "$skill: ${#commits[@]} upstream commit(s) since $sha ($slug $path)"
    printf '    %s\n' "${commits[@]}"
  fi
done
[ ${#current[@]} -eq 0 ] || echo "up to date: ${current[*]}"
