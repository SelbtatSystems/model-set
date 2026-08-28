#!/usr/bin/env bash
# List live named-eForm links for one exact Organisation legal name in the
# current AgCore worktree database.

set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo 'Usage: resolve-eform-links.sh "<exact Organisation legal name>"' >&2
  exit 1
fi

ORG_LEGAL_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: run from an AgCore checkout/worktree" >&2
  exit 1
fi

RUNTIME="$($SCRIPT_DIR/resolve-worktree-runtime.sh "$REPO_ROOT")"
EFORM_URL="$(printf '%s\n' "$RUNTIME" | sed -n 's/^eform_url=//p')"
ENV_FILE="$REPO_ROOT/.env"
COMPOSE_DIR="$REPO_ROOT/infrastructure/docker"

DB_USER="$(cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" exec -T postgres printenv POSTGRES_USER)"
DB_NAME="$(cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" exec -T postgres printenv POSTGRES_DB)"

SQL="
SELECT
  COALESCE(ei.slug, ei.shared_link_uuid::text),
  o.id,
  o.legal_name,
  COALESCE(o.abn, ''),
  ne.name
FROM organizations o
JOIN named_eform_scopes nes ON nes.org_id = o.id
JOIN named_eforms ne ON ne.id = nes.named_eform_id
JOIN eform_instances ei ON ei.named_eform_id = ne.id
WHERE lower(btrim(o.legal_name)) = lower(btrim(:'org_legal_name'))
  AND ne.lifecycle = 'live'
ORDER BY ne.name, ne.id;
"

ROWS="$(
  printf '%s\n' "$SQL" |
    (cd "$COMPOSE_DIR" && docker compose --env-file "$ENV_FILE" exec -T postgres \
      psql -X -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 \
      -v org_legal_name="$ORG_LEGAL_NAME" -At -F '|')
)"

if [[ -z "$ROWS" ]]; then
  echo "ERROR: no live named eForm found for exact legal name: $ORG_LEGAL_NAME" >&2
  exit 1
fi

while IFS='|' read -r identifier org_id legal_name abn form_name; do
  printf 'eform_url=%s/%s | org_id=%s | legal_name=%s | abn=%s | named_eform=%s\n' \
    "$EFORM_URL" "$identifier" "$org_id" "$legal_name" "$abn" "$form_name"
done <<< "$ROWS"
