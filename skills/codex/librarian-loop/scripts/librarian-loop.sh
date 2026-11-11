#!/usr/bin/env bash
# One unattended maintenance pass of the memory vault by a Codex librarian.
# The systemd user timer from install-timer.sh (beside this file) starts it at
# 03:00 each day; it is also safe to start by hand.
#
# It maintains the vault and nothing else:
#   - Codex runs in the vault with `--sandbox workspace-write`: it can write
#     only below the vault and the quarantine directory, and it has no network.
#     This script never touches git, and the sandbox keeps the agent out of
#     every code repository.
#   - The agent never deletes. What leaves the vault moves to the quarantine
#     directory (sync-conflict copies, mostly).
#   - The vault has no history, so each pass first saves every markdown note
#     to a snapshot archive. `tar -xzf <snapshot> -C <dir>` gets a note back.
#
#   librarian-loop.sh             # one pass
#   librarian-loop.sh --dry-run   # read-only: report what a pass would do
#
# VAULT         the vault (default: ~/Nextcloud/memory)
# STATE_DIR     logs, reports, snapshots, quarantine
#               (default: ~/.local/state/agcore/librarian-loop — never in the
#               vault: agent logs can hold secrets)
# RUN_MINUTES   hard stop for the agent (default 90)
# CODEX_MODEL   model override (default: the Codex config)
set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

here=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)
vault=${VAULT:-$HOME/Nextcloud/memory}
state_dir=${STATE_DIR:-$HOME/.local/state/agcore/librarian-loop}
run_minutes=${RUN_MINUTES:-90}
skill_file=$here/../SKILL.md
stamp=$(date +%Y%m%d-%H%M%S)
quarantine=$state_dir/quarantine/$stamp

command -v codex >/dev/null 2>&1 || { echo "librarian-loop: codex not on PATH"; exit 1; }
[ -f "$vault/LIBRARIAN.md" ] || { echo "librarian-loop: no vault at $vault"; exit 1; }
[ -f "$skill_file" ] || { echo "librarian-loop: missing $skill_file"; exit 1; }
mkdir -p "$state_dir/logs" "$state_dir/snapshots" "$quarantine"

# One pass at a time: two librarians would write the same files.
exec 9>"$state_dir/lock"
flock -n 9 || { echo "librarian-loop: another pass is running — nothing to do"; exit 0; }

log=$state_dir/logs/$stamp.log
report=$state_dir/logs/$stamp.report.md

if [ "$DRY_RUN" = "1" ]; then
  sandbox=read-only
  mode="DRY RUN. The vault is read-only for you. Change nothing and move nothing.
Do not run scripts/weekly.sh (it writes the catalog); run only
'python3 scripts/wiki_tool.py doctor' and 'python3 scripts/wiki_tool.py lint'.
Do steps 2 to 6 as a survey, and report what a real pass would change."
else
  sandbox=workspace-write
  mode="This is a real, unattended pass."
  # The only undo the vault has. Notes only: images and HTML mockups are not edited.
  tar -czf "$state_dir/snapshots/vault-notes-$stamp.tar.gz" -C "$vault" \
    --exclude='./.obsidian' --exclude='./Images' --exclude='./AgCore/_html' \
    --exclude='*.png' --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.pdf' --exclude='*.html' . \
    || { echo "librarian-loop: snapshot failed — no pass without an undo"; exit 1; }
  # Keep 14 snapshots (two weeks at one pass per day).
  find "$state_dir/snapshots" -name 'vault-notes-*.tar.gz' -printf '%T@ %p\n' \
    | sort -rn | tail -n +15 | cut -d' ' -f2- | xargs -r rm -f
fi

model_args=()
[ -n "${CODEX_MODEL:-}" ] && model_args=(--model "$CODEX_MODEL")

# The skill text without its frontmatter: the pass must not depend on the
# skill being linked into ~/.codex/skills on this machine.
instructions=$(awk 'NR==1 && /^---$/ {skip=1; next} skip && /^---$/ {skip=0; next} !skip' "$skill_file")

echo "librarian-loop: pass $stamp ($sandbox, limit ${run_minutes} min) — log $log"
timeout --signal=INT --kill-after=60 "${run_minutes}m" codex exec \
  --cd "$vault" --skip-git-repo-check \
  --sandbox "$sandbox" --add-dir "$quarantine" \
  "${model_args[@]}" \
  --output-last-message "$report" \
  "$instructions

## Run facts

- $mode
- Now: $(date '+%Y-%m-%d %H:%M %Z').
- Time limit: stop new work after $((run_minutes - 15)) minutes.
- Quarantine directory: $quarantine" \
  < /dev/null > "$log" 2>&1
rc=$?

# An empty quarantine directory says nothing; remove it.
rmdir "$quarantine" 2>/dev/null || true
find "$state_dir/logs" -type f -mtime +30 -delete

if [ -s "$report" ]; then
  cat "$report"
else
  echo "librarian-loop: the agent left no report — see $log"
fi
[ "$rc" -eq 124 ] && echo "librarian-loop: stopped at the ${run_minutes} min limit"
exit "$rc"
