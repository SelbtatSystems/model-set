#!/usr/bin/env bash
# Capture backend logs from the current AgCore worktree since an ISO timestamp.
# Prints the output logfile path.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || -z "$1" ]]; then
  echo 'Usage: capture-backend-logs.sh <since-ISO-timestamp> [output-file]' >&2
  exit 1
fi

STARTED_AT="$1"
LOGFILE="${2:-/tmp/eform-sim-backend-$(date +%s).log}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" || ! -f "$REPO_ROOT/.env" ]]; then
  echo "ERROR: run from an AgCore checkout/worktree with a root .env" >&2
  exit 1
fi

(
  cd "$REPO_ROOT/infrastructure/docker"
  docker compose --env-file "$REPO_ROOT/.env" logs \
    --no-color --since "$STARTED_AT" backend
) > "$LOGFILE"

printf '%s\n' "$LOGFILE"
