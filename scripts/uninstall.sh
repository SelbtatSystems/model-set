#!/bin/bash
# model-set Uninstall Script for Unix (macOS/Linux)
# Reverses everything done by setup.sh
# Usage: ./scripts/uninstall.sh [--force]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
HOME_DIR="$HOME"
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --force|-f) FORCE=true ;;
    esac
done

echo "model-set Uninstall"
echo "==================="
echo ""
echo "This will remove all configs, symlinks, and CLI tools installed by setup.sh."
echo "Repo directory: $REPO_DIR"
echo ""

if ! $FORCE; then
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

# Check if path is a symlink/junction pointing into this repo
is_repo_link() {
    local path="$1"
    [ -L "$path" ] && return 0
    # On MINGW, -L doesn't detect junctions; compare canonical paths
    if [ -d "$path" ] && command -v cygpath &> /dev/null; then
        local real_path
        real_path="$(cd "$path" 2>/dev/null && pwd -W 2>/dev/null || cygpath -w "$path" 2>/dev/null)"
        local real_target
        real_target="$(cygpath -w "$REPO_DIR" 2>/dev/null)"
        if [[ "$real_path" == "$real_target"* ]] && [ "$real_path" != "$(cygpath -w "$path" 2>/dev/null)" ]; then
            return 0
        fi
    fi
    return 1
}

# Remove a symlink/junction, but only if it points into this repo
remove_repo_symlink() {
    local link="$1"
    if is_repo_link "$link"; then
        # On MINGW, junctions must be removed with cmd rmdir
        if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "mingw"* ]]; then
            powershell -NoProfile -Command "(Get-Item '$(cygpath -w "$link")').Delete()" > /dev/null 2>&1
        else
            rm "$link"
        fi
        echo "  Removed link: $link"

        # Restore backup if it exists
        if [ -e "${link}.backup" ]; then
            mv "${link}.backup" "$link"
            echo "  Restored: ${link}.backup -> $link"
        fi
        return 0
    elif [ -e "$link" ]; then
        echo "  Skipped: $link (not a repo link)"
        return 1
    else
        echo "  Skipped: $link (not found)"
        return 1
    fi
}

# =====================================================
# 1. Generated config files
# =====================================================
echo "Removing generated config files..."

if [ -f "$HOME_DIR/.mcp.json" ]; then
    rm "$HOME_DIR/.mcp.json"
    echo "  Removed: ~/.mcp.json"
else
    echo "  Skipped: ~/.mcp.json (not found)"
fi

CODEX_CONFIG="$REPO_DIR/global/codex/config.toml"
if [ -f "$CODEX_CONFIG" ]; then
    rm "$CODEX_CONFIG"
    echo "  Removed: global/codex/config.toml"
else
    echo "  Skipped: global/codex/config.toml (not found)"
fi

echo ""

# =====================================================
# 2. MCP servers
# =====================================================
echo "Removing MCP servers..."

if command -v claude &> /dev/null; then
    claude mcp remove stitch -s user 2>/dev/null && \
        echo "  Removed stitch from Claude Code (user scope)" || \
        echo "  Skipped: stitch not found in Claude Code"
else
    echo "  Skipped: claude not installed"
fi

GEMINI_STITCH="$HOME_DIR/.gemini/extensions/Stitch"
if [ -d "$GEMINI_STITCH" ]; then
    rm -rf "$GEMINI_STITCH"
    echo "  Removed: ~/.gemini/extensions/Stitch"
else
    echo "  Skipped: ~/.gemini/extensions/Stitch (not found)"
fi

echo ""

# =====================================================
# 3. Home directory symlinks
# =====================================================
echo "Removing home directory symlinks..."

for tool in .claude .gemini .opencode .codex; do
    link="$HOME_DIR/$tool"

    # Case 1: entire dir is a symlink/junction to repo
    if is_repo_link "$link"; then
        remove_repo_symlink "$link"
    elif [ -d "$link" ]; then
        # Case 2: real dir with skills-only symlink/junction inside
        if is_repo_link "$link/skills"; then
            remove_repo_symlink "$link/skills"
        fi
    fi
done

echo ""

# =====================================================
# 4. Copied files (context-monitor in real ~/.claude)
# =====================================================
echo "Removing copied files..."

CONTEXT_MONITOR="$HOME_DIR/.claude/scripts/context-monitor.py"
if ! is_repo_link "$HOME_DIR/.claude" && [ -f "$CONTEXT_MONITOR" ]; then
    rm "$CONTEXT_MONITOR"
    echo "  Removed: $CONTEXT_MONITOR"
    # Remove scripts dir if empty
    rmdir "$HOME_DIR/.claude/scripts" 2>/dev/null && \
        echo "  Removed empty dir: ~/.claude/scripts" || true
else
    echo "  Skipped: context-monitor.py (not found or ~/.claude is a symlink)"
fi

echo ""

# =====================================================
# 5. Repo-internal skills/agents symlinks
# =====================================================
echo "Removing repo-internal symlinks..."

for tool in claude gemini opencode codex; do
    link="$REPO_DIR/global/$tool/skills"
    if is_repo_link "$link"; then
        if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "mingw"* ]]; then
            powershell -NoProfile -Command "(Get-Item '$(cygpath -w "$link")').Delete()" > /dev/null 2>&1
        else
            rm "$link"
        fi
        echo "  Removed: global/$tool/skills"
    else
        echo "  Skipped: global/$tool/skills (not a link)"
    fi
done

for tool in claude gemini; do
    link="$REPO_DIR/global/$tool/agents"
    if is_repo_link "$link"; then
        if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "mingw"* ]]; then
            powershell -NoProfile -Command "(Get-Item '$(cygpath -w "$link")').Delete()" > /dev/null 2>&1
        else
            rm "$link"
        fi
        echo "  Removed: global/$tool/agents"
    else
        echo "  Skipped: global/$tool/agents (not a link)"
    fi
done

echo ""

# =====================================================
# 6. Screenshots directory
# =====================================================
echo "Removing screenshots directory..."

SCREENSHOTS_DIR="$REPO_DIR/skills/agent-browser/screenshots"
if [ -d "$SCREENSHOTS_DIR" ]; then
    rm -rf "$SCREENSHOTS_DIR"
    echo "  Removed: skills/agent-browser/screenshots/"
else
    echo "  Skipped: screenshots dir (not found)"
fi

echo ""

# =====================================================
# 7. CLI tools
# =====================================================
echo "Removing CLI tools..."

# Gemini CLI
echo -n "  - Gemini CLI..."
if command -v gemini &> /dev/null; then
    npm uninstall -g @google/gemini-cli 2>/dev/null && echo " removed" || echo " failed"
else
    echo " not installed"
fi

# open-code
echo -n "  - open-code..."
if command -v opencode &> /dev/null; then
    npm uninstall -g opencode-ai 2>/dev/null && echo " removed" || echo " failed"
else
    echo " not installed"
fi

# agent-browser
echo -n "  - agent-browser..."
if command -v agent-browser &> /dev/null; then
    npm uninstall -g agent-browser 2>/dev/null && echo " removed" || echo " failed"
else
    echo " not installed"
fi

# Codex CLI
echo -n "  - Codex CLI..."
if command -v codex &> /dev/null; then
    npm uninstall -g @openai/codex 2>/dev/null && echo " removed" || echo " failed"
else
    echo " not installed"
fi

# Claude Code
echo -n "  - Claude Code..."
if command -v claude &> /dev/null; then
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null && echo " removed" || echo " failed"
else
    echo " not installed"
fi

echo ""

# =====================================================
# 8. Local project folders (opt-in)
# =====================================================
echo "Local project folders..."
echo "  These folders may contain your own work:"
echo "    .claude/  .gemini/  .opencode/  .codex/  ralph/  AGENTS.md"
echo ""

REMOVE_LOCAL=false
if $FORCE; then
    REMOVE_LOCAL=true
else
    read -p "  Remove local project folders from current directory? [y/N] " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]] && REMOVE_LOCAL=true
fi

if $REMOVE_LOCAL; then
    CURRENT_DIR="$(pwd)"
    for dir in .claude .gemini .opencode .codex ralph; do
        target="$CURRENT_DIR/$dir"
        if [ -d "$target" ]; then
            rm -rf "$target"
            echo "  Removed: $dir/"
        fi
    done
    if [ -f "$CURRENT_DIR/AGENTS.md" ]; then
        rm "$CURRENT_DIR/AGENTS.md"
        echo "  Removed: AGENTS.md"
    fi
else
    echo "  Skipped local folder removal."
fi

echo ""

# =====================================================
# Done!
# =====================================================
echo "Uninstall complete!"
echo ""
echo "Verify:"
echo "  command -v claude gemini opencode codex agent-browser"
echo "  ls -la ~/.claude ~/.gemini ~/.opencode ~/.codex"
echo "  ls ~/.mcp.json"
