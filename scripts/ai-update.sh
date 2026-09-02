#!/usr/bin/env bash
# ai-update — bring every agent tool on this machine to its latest version.
#
# One script for every host (laptop, VPS): lives in model-set, linked to
# ~/.local/bin/ai-update by setup.sh (CONFIG_MANIFEST). Interactive by design:
# apt needs sudo, so run it from a terminal, not from an agent.
#
# What it updates
#   apt packages · Claude Code (scripts/claude-update.sh) · the npm agent CLIs
#   · GitHub-release binaries in ~/.local/bin (lazygit, lazydocker, atuin, act,
#   actionlint) · fzf (git checkout) · MinIO mc · uv · starship · ollama
#
# Tools that are not installed on this host are skipped, never installed here —
# installation belongs to model-set/scripts/setup.sh. The npm CLIs are the one
# exception: they are the agent stack itself and every host needs all of them.
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
MODEL_SET="${MODEL_SET:-$HOME/model-set}"

_installed_ver() {
  command -v "$1" >/dev/null 2>&1 || return
  "$1" --version 2>&1 | grep -Po '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
_gh_latest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep -Po '"tag_name": *"v?\K[^"]*'
}
_update_gh_binary() {          # <repo> <cmd> <asset-template with {} for version> [path inside archive]
  local repo=$1 cmd=$2 asset_tpl=$3 inner=${4:-$2}
  local have want asset tmp
  command -v "$cmd" >/dev/null 2>&1 || { printf '  %-11s not installed, skipped\n' "$cmd"; return 0; }
  have=$(_installed_ver "$cmd"); want=$(_gh_latest_tag "$repo")
  if [[ -z $want ]]; then printf '  %-11s could not reach GitHub, skipped\n' "$cmd"; return 1; fi
  if [[ $have == "$want" ]]; then printf '  %-11s %s is current\n' "$cmd" "$have"; return 0; fi
  asset=${asset_tpl//\{\}/$want}
  tmp=$(mktemp -d) || return 1
  if curl -fsSL -o "$tmp/dl.tar.gz" "https://github.com/$repo/releases/download/v$want/$asset" \
     && tar -xzf "$tmp/dl.tar.gz" -C "$tmp" "$inner" \
     && install -m 755 "$tmp/$inner" "$HOME/.local/bin/$cmd"; then
    printf '  %-11s %s -> %s\n' "$cmd" "${have:-none}" "$want"
  else
    printf '  %-11s UPDATE FAILED, kept %s\n' "$cmd" "${have:-none}"
  fi
  rm -rf "$tmp"
}

echo "=== APT packages ==="
if command -v apt-get >/dev/null 2>&1; then sudo apt update && sudo apt upgrade -y; else echo "  no apt on this host, skipped"; fi
echo
echo "=== Claude Code ==="
bash "$MODEL_SET/scripts/claude-update.sh"
echo
echo "=== npm agent CLIs ==="
npm install -g @openai/codex@latest @google/gemini-cli@latest opencode-ai@latest agent-browser@latest firecrawl-cli@latest
echo
echo "=== GitHub release binaries ==="
_update_gh_binary jesseduffield/lazygit    lazygit    'lazygit_{}_linux_x86_64.tar.gz'
_update_gh_binary jesseduffield/lazydocker lazydocker 'lazydocker_{}_Linux_x86_64.tar.gz'
_update_gh_binary atuinsh/atuin            atuin      'atuin-x86_64-unknown-linux-gnu.tar.gz' 'atuin-x86_64-unknown-linux-gnu/atuin'
_update_gh_binary nektos/act               act        'act_Linux_x86_64.tar.gz'
_update_gh_binary rhysd/actionlint         actionlint 'actionlint_{}_linux_amd64.tar.gz'
if [[ -d $HOME/.fzf/.git ]]; then
  before=$(_installed_ver fzf)
  git -C "$HOME/.fzf" pull --quiet --ff-only && "$HOME/.fzf/install" --bin >/dev/null 2>&1
  after=$(_installed_ver fzf)
  [[ $before == "$after" ]] && printf '  %-11s %s is current\n' fzf "$after" || printf '  %-11s %s -> %s\n' fzf "$before" "$after"
else
  printf '  %-11s not a git checkout here, skipped\n' fzf
fi
if command -v mc >/dev/null 2>&1; then
  mc_have=$(mc --version 2>/dev/null | grep -Po 'RELEASE\.\S+'); mc_want=$(_gh_latest_tag minio/mc)
  if [[ -n $mc_want && $mc_have != "$mc_want" ]]; then
    if curl -fsSL -o "$HOME/.local/bin/mc.new" "https://dl.min.io/client/mc/release/linux-amd64/mc"; then
      chmod 755 "$HOME/.local/bin/mc.new" && mv "$HOME/.local/bin/mc.new" "$HOME/.local/bin/mc"
      printf '  %-11s %s -> %s\n' mc "${mc_have:-none}" "$mc_want"
    else rm -f "$HOME/.local/bin/mc.new"; printf '  %-11s UPDATE FAILED, kept %s\n' mc "${mc_have:-none}"; fi
  else printf '  %-11s %s is current\n' mc "$mc_have"; fi
else printf '  %-11s not installed, skipped\n' mc; fi
echo
echo "=== Self-updaters ==="
if command -v uv >/dev/null 2>&1; then uv self update; else printf '  %-11s not installed, skipped\n' uv; fi
if command -v starship >/dev/null 2>&1; then
  sr_have=$(_installed_ver starship); sr_want=$(_gh_latest_tag starship/starship)
  if [[ -n $sr_want && $sr_have != "$sr_want" ]]; then echo "  starship $sr_have -> $sr_want"; curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
  else printf '  %-11s %s is current\n' starship "$sr_have"; fi
else printf '  %-11s not installed, skipped\n' starship; fi
if command -v ollama >/dev/null 2>&1; then
  ol_have=$(_installed_ver ollama); ol_want=$(_gh_latest_tag ollama/ollama)
  if [[ -n $ol_want && $ol_have != "$ol_want" ]]; then echo "  ollama $ol_have -> $ol_want (restarts the ollama service)"; curl -fsSL https://ollama.com/install.sh | sh
  else printf '  %-11s %s is current\n' ollama "$ol_have"; fi
else printf '  %-11s not installed, skipped\n' ollama; fi
echo
echo "=== Versions ==="
for c in claude codex gemini opencode agent-browser firecrawl; do printf '  %-13s %s\n' "$c" "$(command -v "$c" >/dev/null 2>&1 && "$c" --version 2>&1 | head -1 || echo 'not installed')"; done
