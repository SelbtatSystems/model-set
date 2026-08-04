#!/usr/bin/env bash
# Verify a model-set install. Read-only — changes nothing.
#
#   ./scripts/doctor.sh
#
# Exits non-zero if anything required is missing, so it can gate CI or a
# post-provision check on a new server.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SKILL_MANIFEST="$REPO_DIR/skills/manifest.json"

# shellcheck source=lib/manifest.sh
source "$SCRIPT_DIR/lib/manifest.sh"

fails=0
warns=0
ok()   { printf '  ok    %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; fails=$((fails + 1)); }
warn() { printf '  warn  %s\n' "$*"; warns=$((warns + 1)); }
step() { printf '\n%s\n' "$*"; }

step "Commands"
for bin in claude codex opencode agent-browser firecrawl jq node python3 ffmpeg; do
  if command -v "$bin" >/dev/null; then
    ok "$bin"
  else
    bad "$bin not on PATH"
  fi
done
for bin in sogni-agent obsidian ollama; do
  command -v "$bin" >/dev/null && ok "$bin (optional)" || warn "$bin not installed (optional)"
done

step "Config files"
for entry in "${CONFIG_MANIFEST[@]}"; do
  src="$REPO_DIR/${entry%%::*}"
  dest="${entry##*::}"
  if [ ! -e "$src" ]; then
    bad "repo file missing: ${entry%%::*}"
  elif [ ! -L "$dest" ]; then
    if [ -e "$dest" ]; then
      warn "$dest exists but is not our symlink"
    else
      bad "not linked: $dest"
    fi
  elif [ "$(readlink -f "$dest")" != "$(readlink -f "$src")" ]; then
    bad "$dest points elsewhere: $(readlink "$dest")"
  else
    ok "$(basename "$dest") -> ${entry%%::*}"
  fi
done

step "Skills"
if [ ! -f "$SKILL_MANIFEST" ]; then
  bad "missing skills/manifest.json"
else
  for host in claude codex opencode; do
    dir="${HOST_SKILL_DIRS[$host]}"
    if [ ! -d "$dir" ]; then
      bad "$host: no skills directory at $dir"
      continue
    fi
    # Counting entries is not enough: a legacy seeded copy is a real directory
    # that exists, reads correctly and works — and silently is not the repo
    # file, so edits to it never reach git. Only a symlink proves the farm was
    # generated. Symlink targets are not pinned to the repo, because npm-
    # delivered skills legitimately point at ~/.npm-global.
    total=0; broken=0; copies=()
    for entry in "$dir"/*; do
      [ -e "$entry" ] || [ -L "$entry" ] || continue
      if [ -L "$entry" ]; then
        total=$((total + 1))
        [ -e "$entry" ] || broken=$((broken + 1))
      elif [ -d "$entry" ]; then
        copies+=("$(basename "$entry")")
      fi
    done
    if [ "${#copies[@]}" -gt 0 ]; then
      bad "$host: ${#copies[@]} skill(s) are real directories, not symlinks — edits there never reach the repo"
      printf '        %s%s\n' "$(printf '%s ' "${copies[@]:0:4}")" "$([ "${#copies[@]}" -gt 4 ] && printf '+%d more' $(( ${#copies[@]} - 4 )))"
      printf '        delete them, then re-run setup.sh — it refuses to link over a real directory\n'
    fi
    if [ "$broken" -gt 0 ]; then
      bad "$host: $broken of $total skill links are dangling"
    elif [ "$total" -eq 0 ] && [ "${#copies[@]}" -eq 0 ]; then
      bad "$host: no skills linked at $dir"
    elif [ "$total" -gt 0 ]; then
      ok "$host: $total skills linked"
    fi
  done

  # A Codex-only skill leaking into OpenCode is the exact failure the manifest
  # exists to prevent, so check it explicitly rather than trusting the loop above.
  while IFS= read -r key; do
    skill="${key##*/}"
    # -L as well as -e: a dangling link is still a leak, and -e alone can't see it.
    if [ -e "${HOST_SKILL_DIRS[opencode]}/$skill" ] || [ -L "${HOST_SKILL_DIRS[opencode]}/$skill" ]; then
      bad "codex-only skill '$skill' is visible to OpenCode"
    else
      ok "codex-only '$skill' correctly absent from OpenCode"
    fi
  done < <(jq -r '.overrides | to_entries[] | select((.value.hosts // []) | index("opencode") | not) | .key' "$SKILL_MANIFEST" 2>/dev/null)
fi

step "Environment"
if [ -f "$REPO_DIR/.env" ]; then
  ok ".env present"
  set -a; . "$REPO_DIR/.env"; set +a
else
  bad ".env missing — copy .env.example"
fi
for var in CONTEXT7_API_KEY FIRECRAWL_API_KEY SOGNI_API_KEY; do
  [ -n "${!var:-}" ] && ok "$var set" || warn "$var empty"
done
for var in OPENCODE_DISABLE_CLAUDE_CODE_SKILLS OPENCODE_DISABLE_EXTERNAL_SKILLS; do
  [ -n "${!var:-}" ] && ok "$var exported" \
    || warn "$var not set in this shell — open a new shell, or OpenCode will read the Claude skill set"
done

step "MCP"
if command -v claude >/dev/null; then
  mcp_out="$(claude mcp list 2>/dev/null || true)"
  for server in context7 aiguide; do
    grep -q "$server" <<<"$mcp_out" && ok "claude: $server registered" \
      || bad "claude: $server not registered at user scope"
  done
else
  warn "claude not available — skipped MCP check"
fi

step "Authentication"
# OAuth cannot be scripted; a green install with no login is still unusable.
[ -f "$HOME/.claude/.credentials.json" ] && ok "claude logged in" || warn "claude not logged in — run 'claude' then /login"
[ -f "$HOME/.codex/auth.json" ]          && ok "codex logged in"  || warn "codex not logged in — run 'codex login'"
[ -f "$HOME/.local/share/opencode/auth.json" ] && ok "opencode logged in" || warn "opencode not logged in — run 'opencode auth login'"

step "Summary"
if [ "$fails" -eq 0 ]; then
  printf '  PASS — %d warning(s).\n' "$warns"
  exit 0
fi
printf '  FAIL — %d error(s), %d warning(s).\n' "$fails" "$warns"
exit 1
