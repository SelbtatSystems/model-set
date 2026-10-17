#!/usr/bin/env bash
# Bring this host's model-set up to date with origin and relink its skills.
# Run it on the host; from the laptop, after a push:
#
#   ssh vps '~/model-set/scripts/sync-host.sh'          [--force: sync under a running loop]
#
# A host keeps some edits to tracked files uncommitted on purpose: its own
# settings.json allow rules and autoMode block, its config.toml trust entries.
# They are stashed, the branch is fast-forwarded, and they are re-applied on
# top. An edit that conflicts with the new commit, or that leaves a JSON file
# invalid, is not forced through: the committed version goes in place and the
# host edit stays in the stash for a person to merge.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
die()  { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

# stash@{n} for a stash commit: `git stash drop` takes only that form.
stash_ref() { git stash list --format='%gd %H' | awk -v h="$1" '$2 == h { print $1 }'; }

# A loop loads skills at the start of every phase; syncing under it mixes old and new.
if ! $FORCE && pgrep -af '(issue|admin|docs)-loop\.sh' >/dev/null; then
  pgrep -af '(issue|admin|docs)-loop\.sh' >&2
  die "a loop is running (above): stop it first, or pass --force"
fi

branch="$(git branch --show-current)"
[ -n "$branch" ] || die "detached HEAD: check out a branch first"
git fetch -q origin "$branch"
before="$(git rev-parse --short HEAD)"

stash=""
if ! git diff --quiet; then
  git stash push -q -m "host-edits-before-sync-$(date +%F-%H%M)"
  stash="$(git rev-parse -q --verify refs/stash)"
  ok "host edits stashed: $(git stash show --name-only "$stash" | tr '\n' ' ')"
fi

if ! git merge -q --ff-only "origin/$branch"; then
  [ -n "$stash" ] && git stash apply -q "$stash" && git stash drop -q "$(stash_ref "$stash")"
  die "cannot fast-forward $branch to origin/$branch (local commits?); host edits restored"
fi
after="$(git rev-parse --short HEAD)"

keep_stash=false
if [ -n "$stash" ]; then
  if ! git stash apply -q "$stash" 2>/dev/null; then
    conflicted="$(git diff --name-only --diff-filter=U)"
    # shellcheck disable=SC2086  # one path per word; tracked config paths have no spaces
    git checkout -q HEAD -- $conflicted
    keep_stash=true
    warn "host edits conflict with the new commit in: $conflicted"
  fi
  git reset -q
  for json in $(git diff --name-only -- '*.json'); do
    if ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$json" 2>/dev/null; then
      git checkout -q HEAD -- "$json"
      keep_stash=true
      warn "host edits left $json invalid"
    fi
  done
  if $keep_stash; then
    warn "committed version in place; merge the host edit from: git stash show -p $(stash_ref "$stash")"
  else
    git stash drop -q "$(stash_ref "$stash")"
    ok "host edits re-applied: $(git diff --name-only | tr '\n' ' ')"
  fi
fi

"$REPO_DIR/scripts/setup.sh" --skills-only | grep -E '^  (ok|warn)' || true
"$REPO_DIR/scripts/lint-skills.sh" | tail -1
ok "model-set $branch: $before -> $after"
