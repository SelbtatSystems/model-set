#!/usr/bin/env bash
# Start a background tail of the backend container logs to a temp file.
# Prints: "<logfile> <pid>" on one line. Kill the pid when done.
#
# Uses docker compose directly with the repo-root .env (the `dc` shell
# function from CLAUDE.md isn't available in a non-interactive script).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ENV_FILE="$REPO_ROOT/.env"
LOG="/tmp/eform-sim-backend-$(date +%s).log"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE" >&2
  exit 1
fi

: > "$LOG"
nohup bash -c \
  "cd '$REPO_ROOT/infrastructure/docker' && docker compose --env-file '$ENV_FILE' logs -f --tail=0 backend" \
  > "$LOG" 2>&1 &
PID=$!
disown "$PID" 2>/dev/null || true

echo "$LOG $PID"