#!/usr/bin/env bash
# model-set setup — Linux/macOS.
#
#   ./scripts/setup.sh [--with-ollama] [--with-obsidian] [--no-sogni] [--force]
#
# Installs the agent CLIs and tool CLIs, then links this repo's config files and
# skill sets into place. Idempotent: safe to re-run after `git pull`.
#
# Design notes live in PLAN.md. The two that matter when reading this script:
#
#   * File ownership, not directory ownership. We never symlink a whole config
#     directory — the tools own those, and their runtime state must stay out of
#     the repo. scripts/lib/manifest.sh lists every file we place.
#
#   * No template substitution. Claude, Codex and OpenCode all expand env vars
#     natively, so configs are plain tracked files and secrets are never baked
#     into generated output. Nothing here can go stale on re-run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_DIR/.env"
SKILL_MANIFEST="$REPO_DIR/skills/manifest.json"

# shellcheck source=lib/manifest.sh
source "$SCRIPT_DIR/lib/manifest.sh"

WITH_OLLAMA=false
WITH_OBSIDIAN=false
WITH_SOGNI=true
FORCE=false
# Per-host defaults live in the gitignored .env (e.g. WITH_SOGNI=false on the
# VPS, which never runs sogni). Command-line flags below still win.
if [ -f "$ENV_FILE" ] && grep -q '^WITH_SOGNI=false' "$ENV_FILE"; then WITH_SOGNI=false; fi

for arg in "$@"; do
  case "$arg" in
    --with-ollama)   WITH_OLLAMA=true ;;
    --with-obsidian) WITH_OBSIDIAN=true ;;
    --no-sogni)      WITH_SOGNI=false ;;
    --force)         FORCE=true ;;
    -h|--help)       sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "setup: unknown option '$arg'" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s\n%s\n' "$*" "$(printf '=%.0s' $(seq ${#1}))"; }
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
die()  { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Prerequisites
# ---------------------------------------------------------------------------
step "Prerequisites"

# agent-browser's --with-deps shells out to the system package manager. If sudo
# would block on a password we must find out now, not halfway through a 400 MB
# browser install on an unattended run.
NEED_SUDO=false
if [ "$(id -u)" -ne 0 ]; then
  NEED_SUDO=true
  if ! sudo -n true 2>/dev/null; then
    warn "passwordless sudo unavailable — you may be prompted during system package installs"
    if [ ! -t 0 ]; then
      die "no TTY and no passwordless sudo: run interactively, or pre-authorise with 'sudo -v'"
    fi
  else
    ok "sudo available non-interactively"
  fi
fi

pkg_install() {
  local pkg="$1" sudo_cmd=""
  $NEED_SUDO && sudo_cmd="sudo"
  if   command -v apt-get >/dev/null; then $sudo_cmd apt-get update -qq && $sudo_cmd apt-get install -y "$pkg"
  elif command -v dnf     >/dev/null; then $sudo_cmd dnf install -y "$pkg"
  elif command -v pacman  >/dev/null; then $sudo_cmd pacman -S --noconfirm "$pkg"
  elif command -v zypper  >/dev/null; then $sudo_cmd zypper install -y "$pkg"
  elif command -v brew    >/dev/null; then brew install "$pkg"
  else return 1
  fi
}

require() {
  local bin="$1" pkg="${2:-$1}" why="$3"
  if command -v "$bin" >/dev/null; then
    ok "$bin"
    return
  fi
  say "  ...  $bin missing ($why) — installing"
  pkg_install "$pkg" >/dev/null 2>&1 || die "could not install $pkg; install it manually and re-run"
  command -v "$bin" >/dev/null || die "$pkg installed but $bin is not on PATH — open a new shell and re-run"
  ok "$bin (installed)"
}

require curl    curl    "downloads"
require jq      jq      "reads skills/manifest.json and the Claude status line"
require python3 python3 "skill scripts"
require ffmpeg  ffmpeg  "Sogni video generation"

if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
  say "  ...  node/npm missing — installing"
  pkg_install nodejs >/dev/null 2>&1 || true
  pkg_install npm    >/dev/null 2>&1 || true
  command -v node >/dev/null && command -v npm >/dev/null \
    || die "install Node.js LTS manually and re-run"
fi
ok "node $(node --version), npm $(npm --version)"

# Keep global npm installs in the user's prefix so nothing needs root.
NPM_PREFIX="$(npm prefix -g 2>/dev/null || true)"
if [ -z "$NPM_PREFIX" ] || [ ! -w "$NPM_PREFIX" ]; then
  NPM_PREFIX="$HOME/.npm-global"
  mkdir -p "$NPM_PREFIX"
  npm config set prefix "$NPM_PREFIX" >/dev/null
fi
NPM_BIN="$NPM_PREFIX/bin"
mkdir -p "$NPM_BIN"
case ":$PATH:" in *":$NPM_BIN:"*) ;; *) export PATH="$NPM_BIN:$PATH" ;; esac
ok "npm prefix $NPM_PREFIX"

# ---------------------------------------------------------------------------
# 1. CLI tools
# ---------------------------------------------------------------------------
step "CLI tools"

npm_global() {
  local pkg="$1" bin="$2"
  if command -v "$bin" >/dev/null; then
    npm install -g "$pkg@latest" >/dev/null 2>&1 && ok "$bin (updated)" || ok "$bin (already installed)"
  else
    npm install -g "$pkg@latest" >/dev/null 2>&1 || die "npm install -g $pkg failed"
    ok "$bin (installed)"
  fi
}

if command -v claude >/dev/null; then
  ok "claude $(claude --version 2>/dev/null || echo '')"
else
  curl -fsSL https://claude.ai/install.sh | bash
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
  command -v claude >/dev/null || die "claude installed to ~/.local/bin but is not on PATH"
  ok "claude (installed)"
fi

npm_global "@openai/codex" codex
npm_global "opencode-ai"   opencode
npm_global "agent-browser" agent-browser
npm_global "firecrawl-cli" firecrawl

$WITH_SOGNI && npm_global "@sogni-ai/sogni-creative-agent-skill" sogni-agent

if $WITH_OBSIDIAN; then
  npm_global "obsidian-cli" obsidian
fi

if $WITH_OLLAMA; then
  if command -v ollama >/dev/null; then ok "ollama"
  else curl -fsSL https://ollama.com/install.sh | sh && ok "ollama (installed)"
  fi
fi

# agent-browser needs a browser binary plus system libraries.
say "  ...  agent-browser browser runtime"
if [ "$(uname -s)" = "Linux" ]; then
  agent-browser install --with-deps >/dev/null 2>&1 || warn "browser install reported errors — run 'agent-browser doctor'"
else
  agent-browser install >/dev/null 2>&1 || warn "browser install reported errors"
fi
# Containers and some hardened kernels have no usable sandbox; agent-browser
# then refuses to launch until told so explicitly.
if ! agent-browser doctor >/dev/null 2>&1; then
  mkdir -p "$HOME/.agent-browser"
  if [ -f "$HOME/.agent-browser/config.json" ]; then
    tmp="$(mktemp)"
    jq '.args = "--no-sandbox"' "$HOME/.agent-browser/config.json" > "$tmp" && mv "$tmp" "$HOME/.agent-browser/config.json"
  else
    echo '{ "args": "--no-sandbox" }' > "$HOME/.agent-browser/config.json"
  fi
  agent-browser doctor >/dev/null 2>&1 && ok "agent-browser (needed --no-sandbox)" \
    || warn "agent-browser doctor still failing — run it manually"
else
  ok "agent-browser doctor"
fi
mkdir -p "$HOME/.agent-browser/screenshots"

# Warp plugins.
if claude plugin list 2>/dev/null | grep -q "warp@claude-code-warp"; then
  ok "warp plugin (claude)"
else
  claude plugin marketplace add warpdotdev/claude-code-warp >/dev/null 2>&1 \
    && claude plugin install warp@claude-code-warp -s user >/dev/null 2>&1 \
    && ok "warp plugin (claude, installed)" \
    || warn "warp plugin install failed — run: claude plugin install warp@claude-code-warp"
fi

# ---------------------------------------------------------------------------
# 2. Config files
# ---------------------------------------------------------------------------
step "Config files"

link() {
  local src="$1" dest="$2"
  [ -e "$src" ] || { warn "missing in repo: ${src#"$REPO_DIR"/}"; return; }

  # On a machine still using the legacy whole-directory symlink, ~/.claude IS
  # repo/global/claude, so dest and src are literally the same file. Linking
  # would rename the real file to .backup and leave a symlink pointing at
  # itself. Refuse, and say what to run instead.
  if [ -e "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ] && [ ! -L "$dest" ]; then
    warn "$dest is the repo file itself (legacy symlink layout) — run scripts/migrate-from-symlink.sh first"
    return
  fi

  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ] && return 0
    rm "$dest"
  elif [ -e "$dest" ]; then
    if $FORCE; then
      mv "$dest" "$dest.backup"
    else
      warn "$dest exists and is not our symlink — left alone (use --force to replace)"
      return
    fi
  fi
  ln -s "$src" "$dest"
}

for entry in "${CONFIG_MANIFEST[@]}"; do
  link "$REPO_DIR/${entry%%::*}" "${entry##*::}"
done
ok "${#CONFIG_MANIFEST[@]} config files linked"

# ---------------------------------------------------------------------------
# 3. Skills
# ---------------------------------------------------------------------------
# Every host's skills directory is a farm of per-skill symlinks. Per-skill
# rather than one directory link because a host's set is the union of its own
# skills and the shared external ones — and because it is what lets us keep
# Codex-only skills physically invisible to OpenCode.
step "Skills"

[ -f "$SKILL_MANIFEST" ] || die "missing $SKILL_MANIFEST"

# Remove links we previously created that the manifest no longer justifies.
prune_host() {
  local host="$1" dir="${HOST_SKILL_DIRS[$host]}"
  [ -d "$dir" ] || return 0
  local link target
  for link in "$dir"/*; do
    [ -L "$link" ] || continue
    target="$(readlink -f "$link" 2>/dev/null || true)"
    case "$target" in
      "$REPO_DIR"/skills/*) [ -e "$link" ] || rm "$link" ;;
      "") rm "$link" ;;   # dangling
    esac
  done
}

# Returns non-zero when it did not create the link, so callers don't count it.
link_skill() {
  local host="$1" name="$2" src="$3"
  local dir="${HOST_SKILL_DIRS[$host]}"
  mkdir -p "$dir"
  local dest="$dir/$name"
  [ -L "$dest" ] && rm "$dest"
  if [ -e "$dest" ]; then
    warn "$dest is a real directory (legacy seeded copy) — left alone; run scripts/migrate-from-symlink.sh"
    return 1
  fi
  ln -s "$src" "$dest"
}

declare -A linked_count=()
for host in "${!HOST_SKILL_DIRS[@]}"; do
  prune_host "$host"
  linked_count[$host]=0
done

# Own and external sets, driven by skills/manifest.json.
while IFS= read -r set_name; do
  set_dir="$(jq -r --arg s "$set_name" '.sets[$s].dir' "$SKILL_MANIFEST")"
  [ -d "$REPO_DIR/$set_dir" ] || continue
  for skill_path in "$REPO_DIR/$set_dir"/*/; do
    [ -d "$skill_path" ] || continue
    skill="$(basename "$skill_path")"
    # Per-skill override wins over the set default.
    hosts="$(jq -r --arg k "$set_name/$skill" --arg s "$set_name" \
      '(.overrides[$k].hosts // .sets[$s].hosts)[]' "$SKILL_MANIFEST")"
    while IFS= read -r host; do
      [ -n "$host" ] || continue
      [ -n "${HOST_SKILL_DIRS[$host]:-}" ] || { warn "unknown host '$host' for $skill"; continue; }
      link_skill "$host" "$skill" "${skill_path%/}" \
        && linked_count[$host]=$(( linked_count[$host] + 1 ))
    done <<< "$hosts"
  done
done < <(jq -r '.sets | keys[]' "$SKILL_MANIFEST")

# npm-delivered skills: the package is the skill, so link the install directory.
while IFS= read -r npm_skill; do
  pkg="$(jq -r --arg s "$npm_skill" '.npmSkills[$s].package' "$SKILL_MANIFEST")"
  pkg_dir="$NPM_PREFIX/lib/node_modules/$pkg"
  if [ ! -d "$pkg_dir" ]; then
    $WITH_SOGNI && warn "$npm_skill: $pkg not installed — skipped"
    continue
  fi
  while IFS= read -r host; do
    [ -n "${HOST_SKILL_DIRS[$host]:-}" ] || continue
    link_skill "$host" "$npm_skill" "$pkg_dir" \
      && linked_count[$host]=$(( linked_count[$host] + 1 ))
  done < <(jq -r --arg s "$npm_skill" '.npmSkills[$s].hosts[]' "$SKILL_MANIFEST")
done < <(jq -r '.npmSkills | keys[]' "$SKILL_MANIFEST")

for host in claude codex opencode; do
  ok "$host: ${linked_count[$host]} skills -> ${HOST_SKILL_DIRS[$host]}"
done

# Extra Claude profiles (CLAUDE_CONFIG_DIR) mirror the primary — see lib/manifest.sh.
"$SCRIPT_DIR/sync-claude-profiles.sh"

# ---------------------------------------------------------------------------
# 4. Shell environment
# ---------------------------------------------------------------------------
step "Shell environment"

case "$(basename "${SHELL:-bash}")" in
  zsh)  RC="$HOME/.zshrc" ;;
  fish) RC="" ;;
  *)    RC="$HOME/.bashrc" ;;
esac

MARKER="# >>> model-set >>>"
if [ -z "$RC" ]; then
  warn "fish detected — add the block from scripts/setup.sh to config.fish manually"
elif grep -Fq "$MARKER" "$RC" 2>/dev/null; then
  ok "shell block already in $RC"
else
  cat >> "$RC" <<EOF

$MARKER
# Secrets for the MCP servers and tool CLIs.
if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi
# OpenCode also scans ~/.claude/skills and ~/.agents/skills for compatibility,
# which would leak the Claude set into it. It must only see skills/codex.
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1
export OPENCODE_DISABLE_EXTERNAL_SKILLS=1
export PATH="$NPM_BIN:\$HOME/.local/bin:\$PATH"
# <<< model-set <<<
EOF
  ok "added model-set block to $RC"
fi

export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1
export OPENCODE_DISABLE_EXTERNAL_SKILLS=1

if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
  ok ".env loaded"
else
  warn "no .env — copy .env.example to .env and fill it in"
fi

# ---------------------------------------------------------------------------
# 5. Global MCP servers (Claude)
# ---------------------------------------------------------------------------
# Codex and OpenCode take their MCP config from the tracked files we linked
# above. Claude's user scope lives in ~/.claude.json, which also holds runtime
# state and so cannot be a symlink — it has to be registered imperatively.
step "Global MCP servers"

claude_mcp_has() { claude mcp list 2>/dev/null | grep -q "^$1[: ]"; }

if command -v claude >/dev/null; then
  if claude_mcp_has context7; then
    ok "context7 (already registered)"
  else
    claude mcp add -s user --transport http context7 https://mcp.context7.com/mcp \
      --header "CONTEXT7_API_KEY: \${CONTEXT7_API_KEY}" >/dev/null 2>&1 \
      && ok "context7 registered at user scope" \
      || warn "could not register context7 — run 'claude mcp add' manually"
  fi
  if claude_mcp_has aiguide; then
    ok "aiguide (already registered)"
  else
    claude mcp add -s user --transport http aiguide https://mcp.tigerdata.com/docs >/dev/null 2>&1 \
      && ok "aiguide registered at user scope" \
      || warn "could not register aiguide — run 'claude mcp add' manually"
  fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
step "Next steps"
cat <<'EOF'
  Setup cannot log you in — all three agents use OAuth. Do this now:

      claude              # then /login
      codex login
      opencode auth login

  Then verify the install:

      ./scripts/doctor.sh

  Project setup (postgres MCP, local context files):

      ./scripts/apply-local.sh /path/to/project
EOF
