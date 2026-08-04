#!/usr/bin/env bash
# Reverse scripts/setup.sh.
#
#   ./scripts/uninstall.sh [--force] [--purge-tools]
#
# By default this removes only the links model-set created and the shell block —
# it does not uninstall CLIs or touch your logins, because those are usually
# wanted even after unlinking the config. --purge-tools removes the CLIs too.
#
# Never deletes: your OAuth credentials, session history, or anything in a tool's
# config directory that model-set did not create. Only our own symlinks go.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/manifest.sh
source "$SCRIPT_DIR/lib/manifest.sh"

FORCE=false
PURGE_TOOLS=false
for arg in "$@"; do
  case "$arg" in
    --force)       FORCE=true ;;
    --purge-tools) PURGE_TOOLS=true ;;
    -h|--help)     sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

ok()   { printf '  ok    %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }

if ! $FORCE; then
  echo "This will unlink model-set config from ~/.claude, ~/.codex and ~/.config/opencode."
  $PURGE_TOOLS && echo "It will ALSO uninstall the CLI tools."
  read -rp "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

step "Config files"
removed=0
for entry in "${CONFIG_MANIFEST[@]}"; do
  dest="${entry##*::}"
  src="$REPO_DIR/${entry%%::*}"
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    rm "$dest"
    removed=$((removed + 1))
    # setup backs up a pre-existing real file as <file>.backup; restore it.
    [ -e "$dest.backup" ] && mv "$dest.backup" "$dest" && ok "restored $dest from backup"
  fi
done
ok "$removed config symlinks removed"

step "Skills"
for host in claude codex opencode; do
  dir="${HOST_SKILL_DIRS[$host]}"
  [ -d "$dir" ] || continue
  n=0
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    target="$(readlink -f "$link" 2>/dev/null || true)"
    # Only ours: links into this repo, or into the npm-installed skill packages.
    case "$target" in
      "$REPO_DIR"/skills/*|*/node_modules/@sogni-ai/*) rm "$link"; n=$((n + 1)) ;;
      "") rm "$link"; n=$((n + 1)) ;;   # dangling
    esac
  done
  rmdir "$dir" 2>/dev/null || true
  ok "$host: $n skill links removed"
done

step "Shell block"
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$RC" ] || continue
  if grep -Fq "# >>> model-set >>>" "$RC"; then
    tmp="$(mktemp)"
    sed '/# >>> model-set >>>/,/# <<< model-set <<</d' "$RC" > "$tmp"
    mv "$tmp" "$RC"
    ok "removed model-set block from $RC"
  fi
done

step "Global MCP servers"
if command -v claude >/dev/null; then
  for server in context7 aiguide; do
    claude mcp remove -s user "$server" >/dev/null 2>&1 && ok "unregistered $server" || true
  done
fi

if $PURGE_TOOLS; then
  step "CLI tools"
  for pkg in @openai/codex opencode-ai agent-browser firecrawl-cli @sogni-ai/sogni-creative-agent-skill; do
    npm uninstall -g "$pkg" >/dev/null 2>&1 && ok "removed $pkg" || true
  done
  claude plugin uninstall warp@claude-code-warp -s user >/dev/null 2>&1 && ok "removed warp plugin" || true
  echo "  note: Claude Code itself was installed by claude.ai/install.sh — remove ~/.local/bin/claude"
  echo "        and ~/.local/share/claude manually if you want it gone."
fi

step "Done"
cat <<'EOF'
  Left in place on purpose:
    - OAuth credentials (~/.claude/.credentials.json, ~/.codex/auth.json, ...)
    - session history and any config the tools created themselves
    - the model-set repo itself
EOF
