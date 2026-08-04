#!/usr/bin/env bash
# Apply model-set project-level config to a repo.
#
#   ./scripts/apply-local.sh /path/to/project [--tool claude|codex|opencode] ...
#
# With no --tool, all three are applied. Existing files are never overwritten.
#
# Global config (settings, skills, the context7/aiguide MCP servers) comes from
# setup.sh and is already active everywhere. This adds only what is genuinely
# per-project: the context file each agent reads, and the postgres MCP server,
# whose connection string belongs to the project rather than to model-set.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

PROJECT_DIR=""
TOOLS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --tool) TOOLS+=("$2"); shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) PROJECT_DIR="$1"; shift ;;
  esac
done

[ -n "$PROJECT_DIR" ] || { echo "usage: $0 /path/to/project [--tool claude|codex|opencode]" >&2; exit 2; }
[ -d "$PROJECT_DIR" ] || { echo "no such directory: $PROJECT_DIR" >&2; exit 2; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
[ ${#TOOLS[@]} -gt 0 ] || TOOLS=(claude codex opencode)

ok()   { printf '  ok    %s\n' "$*"; }
skip() { printf '  skip  %s (exists)\n' "$*"; }

# Copy only if absent — this script must be safe to re-run on a live project.
copy_once() {
  local src="$1" dest="$2" label="$3"
  [ -f "$src" ] || return 0
  if [ -e "$dest" ]; then
    skip "$label"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    ok "$label"
  fi
}

echo "Applying to $PROJECT_DIR"

for tool in "${TOOLS[@]}"; do
  case "$tool" in
    claude)
      copy_once "$REPO_DIR/local/claude/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md" "CLAUDE.md"
      copy_once "$REPO_DIR/local/claude/.mcp.json.template" "$PROJECT_DIR/.mcp.json" ".mcp.json (postgres)"
      ;;
    codex)
      copy_once "$REPO_DIR/local/codex/AGENTS.md.template" "$PROJECT_DIR/AGENTS.md" "AGENTS.md"
      ;;
    opencode)
      # OpenCode reads AGENTS.md at the project root — the same file Codex uses.
      copy_once "$REPO_DIR/local/codex/AGENTS.md.template" "$PROJECT_DIR/AGENTS.md" "AGENTS.md (shared with codex)"
      ;;
    *)
      echo "unknown tool: $tool" >&2; exit 2 ;;
  esac
done

# The postgres MCP reads POSTGRES_DATABASE_URI from the environment; .mcp.json
# references it rather than embedding it, so the secret stays in the project.
if [ -f "$PROJECT_DIR/.mcp.json" ] && ! grep -q "POSTGRES_DATABASE_URI" "$PROJECT_DIR/.env" 2>/dev/null; then
  cat >> "$PROJECT_DIR/.env" <<'EOF'

# Consumed by the postgres MCP server in .mcp.json
POSTGRES_DATABASE_URI=postgresql://user:password@localhost:5432/dbname
EOF
  ok "appended POSTGRES_DATABASE_URI placeholder to .env"
fi

cat <<EOF

Next:
  1. Set POSTGRES_DATABASE_URI in $PROJECT_DIR/.env
  2. Set the docker network name in .mcp.json (currently 'your-docker-network')
  3. Make sure .env is gitignored in the project
EOF
