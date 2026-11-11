#!/usr/bin/env bash
# Install the vault librarian pass (librarian-loop.sh, beside this file) as a
# systemd user timer: 03:00, each day.
#
# Install it on ONE machine only. The vault syncs between machines, and two
# librarians that edit the same note make a sync-conflict copy.
#
# The timer runs the script in place, from this model-set checkout. A pull
# that changes the skill changes the next pass; no second install is needed.
#
#   install-timer.sh              # install + enable
#   install-timer.sh --uninstall
#
#   systemctl --user list-timers agcore-librarian.timer     # next run
#   systemctl --user start agcore-librarian.service         # run now
#   ls ~/.local/state/agcore/librarian-loop/logs/           # reports + logs
#
# A user timer runs only while you are logged in; a run missed while the
# machine was off or asleep starts at the next login or wake (Persistent=true).
set -euo pipefail

unit=agcore-librarian
unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user

if [ "${1:-}" = "--uninstall" ]; then
  systemctl --user disable --now "$unit.timer" 2>/dev/null || true
  rm -f "$unit_dir/$unit.service" "$unit_dir/$unit.timer"
  systemctl --user daemon-reload
  echo "Removed $unit."
  exit 0
fi

# The real path, also when this runs through the ~/.codex/skills symlink.
here=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)
vault=${VAULT:-$HOME/Nextcloud/memory}
[ -f "$vault/LIBRARIAN.md" ] || { echo "No vault at $vault — set VAULT."; exit 1; }
codex_bin=$(command -v codex) || { echo "codex not on PATH."; exit 1; }
node_bin=$(command -v node) || { echo "node not on PATH."; exit 1; }

mkdir -p "$unit_dir"

cat > "$unit_dir/$unit.service" <<UNIT
[Unit]
Description=AgCore vault librarian pass (Codex, vault only)

[Service]
Type=oneshot
Environment=VAULT=$vault
Environment=PATH=$(dirname "$codex_bin"):$(dirname "$node_bin"):/usr/local/bin:/usr/bin:/bin
ExecStart=$here/librarian-loop.sh
UNIT

cat > "$unit_dir/$unit.timer" <<UNIT
[Unit]
Description=Run the AgCore vault librarian at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now "$unit.timer"
echo "Installed $unit for $vault (script: $here/librarian-loop.sh)."
systemctl --user list-timers "$unit.timer" --no-pager
