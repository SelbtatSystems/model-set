#!/usr/bin/env bash
# Resolve the published URLs for the AgCore Docker stack belonging to the
# checkout/worktree from which this script is invoked.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [[ -z "$REPO_ROOT" || ! -d "$REPO_ROOT/infrastructure/docker" ]]; then
  echo "ERROR: run from an AgCore checkout or pass its repo root" >&2
  exit 1
fi

ENV_FILE="$REPO_ROOT/.env"
COMPOSE_DIR="$REPO_ROOT/infrastructure/docker"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE" >&2
  exit 1
fi

published_port() {
  local service="$1"
  local container_port="$2"
  local endpoint

  endpoint="$(
    cd "$COMPOSE_DIR"
    docker compose --env-file "$ENV_FILE" port "$service" "$container_port" 2>/dev/null | head -n 1
  )"
  if [[ ! "$endpoint" =~ :([0-9]+)$ ]]; then
    echo "ERROR: $service is not running with container port $container_port published in this worktree" >&2
    exit 1
  fi
  printf '%s' "${BASH_REMATCH[1]}"
}

BACKEND_PORT="$(published_port backend 3000)"
AGCORE_PORT="$(published_port agcore-web 3001)"
EFORM_PORT="$(published_port myfarmjob-eform-web 3003)"
MYFARMJOB_PORT="$(published_port myfarmjob-web 3002)"

printf 'repo_root=%s\n' "$REPO_ROOT"
printf 'compose_dir=%s\n' "$COMPOSE_DIR"
printf 'backend_url=http://localhost:%s\n' "$BACKEND_PORT"
printf 'agcore_url=http://localhost:%s\n' "$AGCORE_PORT"
printf 'eform_url=http://localhost:%s\n' "$EFORM_PORT"
printf 'myfarmjob_url=http://localhost:%s\n' "$MYFARMJOB_PORT"
printf 'test_docs_dir=%s/test-docs\n' "$REPO_ROOT"
