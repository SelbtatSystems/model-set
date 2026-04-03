#!/bin/bash
# model-set Setup Script for Unix (macOS/Linux)
# Usage: ./scripts/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
HOME_DIR="$HOME"
CURRENT_DIR="$(pwd)"

ensure_path_entry() {
    local entry="$1"
    case ":$PATH:" in
        *":$entry:"*) ;;
        *)
            export PATH="$entry:$PATH"
            hash -r 2>/dev/null || true
            ;;
    esac
}

persist_user_local_bin_path() {
    local local_bin="$HOME/.local/bin"
    local shell_name rc_file path_line

    [ -d "$local_bin" ] || return 0

    shell_name="$(basename "${SHELL:-bash}")"
    case "$shell_name" in
        zsh) rc_file="$HOME/.zshrc" ;;
        fish) rc_file="" ;;
        *) rc_file="$HOME/.bashrc" ;;
    esac

    if [ -z "$rc_file" ]; then
        echo "    Note: add $local_bin to your shell PATH manually."
        return 0
    fi

    path_line='export PATH="$HOME/.local/bin:$PATH"'
    if [ -f "$rc_file" ] && grep -Fqx "$path_line" "$rc_file"; then
        return 0
    fi

    printf '\n%s\n' "$path_line" >> "$rc_file"
    echo "    Added ~/.local/bin to PATH in $rc_file"
}

echo "model-set Setup"
echo "==============="
echo ""

# =====================================================
# 0. Check Prerequisites
# =====================================================
echo "Checking prerequisites..."

# Python 3 (required for skill scripts)
echo -n "  - Python 3..."
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_VER=$(python3 --version 2>&1)
    echo " ($PYTHON_VER)"
    PYTHON_CMD="python3"
elif command -v python &> /dev/null && python --version 2>&1 | grep -q "Python 3"; then
    PYTHON_VER=$(python --version 2>&1)
    echo " ($PYTHON_VER via 'python')"
    PYTHON_CMD="python"
else
    echo " not found — attempting auto-install..."
    INSTALLED=false

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS — use Homebrew if available, otherwise install Homebrew first
        if command -v brew &> /dev/null; then
            echo "    Installing via Homebrew..."
            brew install python3 && INSTALLED=true
        else
            echo "    Homebrew not found — installing Homebrew first..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && \
                brew install python3 && INSTALLED=true
        fi
    elif command -v apt-get &> /dev/null; then
        echo "    Installing via apt-get..."
        sudo apt-get update -qq && sudo apt-get install -y python3 && INSTALLED=true
    elif command -v dnf &> /dev/null; then
        echo "    Installing via dnf..."
        sudo dnf install -y python3 && INSTALLED=true
    elif command -v yum &> /dev/null; then
        echo "    Installing via yum..."
        sudo yum install -y python3 && INSTALLED=true
    elif command -v pacman &> /dev/null; then
        echo "    Installing via pacman..."
        sudo pacman -S --noconfirm python && INSTALLED=true
    elif command -v zypper &> /dev/null; then
        echo "    Installing via zypper..."
        sudo zypper install -y python3 && INSTALLED=true
    else
        echo ""
        echo "  ERROR: Could not auto-install Python 3 — no supported package manager found."
        echo "  Install manually from https://www.python.org/downloads/ and re-run setup."
        exit 1
    fi

    if $INSTALLED; then
        if command -v python3 &> /dev/null; then
            PYTHON_VER=$(python3 --version 2>&1)
            echo "    Installed: $PYTHON_VER"
            PYTHON_CMD="python3"
        else
            echo "  ERROR: Python 3 installed but not found on PATH. Open a new terminal and re-run setup."
            exit 1
        fi
    else
        echo "  ERROR: Auto-install failed. Install Python 3 manually and re-run setup."
        exit 1
    fi
fi

# jq (required for Claude Code status line)
echo -n "  - jq..."
if command -v jq &> /dev/null; then
    JQ_VER=$(jq --version 2>&1)
    echo " ($JQ_VER)"
else
    echo " not found — attempting auto-install..."
    INSTALLED=false

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install jq && INSTALLED=true
        fi
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y jq && INSTALLED=true
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y jq && INSTALLED=true
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq && INSTALLED=true
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm jq && INSTALLED=true
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y jq && INSTALLED=true
    fi

    if $INSTALLED && command -v jq &> /dev/null; then
        echo "    Installed: $(jq --version 2>&1)"
    else
        echo "  WARNING: Could not auto-install jq. Status line will not work."
        echo "  Install manually: https://jqlang.github.io/jq/download/"
    fi
fi

echo ""

# =====================================================
# 1. Create Global Symlinks
# =====================================================
# NOTE: Symlinks MUST be created before CLI tools are installed.
# CLI installers (e.g. Claude Code) create ~/.claude as a real directory,
# which prevents the full-directory symlink from being established later.
echo "Creating global config symlinks..."

is_repo_link() {
    # Check if path is a symlink/junction pointing into this repo.
    # -L works on real Unix; on MINGW it doesn't detect junctions,
    # so we also compare canonical paths (junction resolves to target).
    local path="$1"
    [ -L "$path" ] && return 0
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

create_symlink() {
    local link="$1"
    local target="$2"

    if is_repo_link "$link"; then
        echo "  $link -> already linked"
        return
    fi

    if [ -e "$link" ]; then
        echo "  $link -> backing up existing to ${link}.backup"
        mv "$link" "${link}.backup"
    fi

    mkdir -p "$(dirname "$link")"

    # On MINGW/Windows, ln -s silently copies instead of symlinking.
    # Use cmd junctions which actually work.
    if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "mingw"* ]]; then
        local win_link win_target
        win_link="$(cygpath -w "$link")"
        win_target="$(cygpath -w "$target")"
        powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$win_link' -Target '$win_target'" > /dev/null 2>&1
        echo "  $link -> $target (junction)"
    else
        ln -s "$target" "$link"
        echo "  $link -> $target"
    fi
}

# Link a tool's config directory.
# Always creates a full symlink → repo/global/<tool>.
# Backs up any existing real directory to <dir>.backup.
link_tool_config() {
    local config_dir="$1"   # e.g. ~/.claude
    local repo_global="$2"  # e.g. repo/global/claude

    if is_repo_link "$config_dir"; then
        echo "  $config_dir -> already linked"
        return
    fi

    if [ -e "$config_dir" ]; then
        echo "  $config_dir -> backing up existing to ${config_dir}.backup"
        rm -rf "${config_dir}.backup"
        mv "$config_dir" "${config_dir}.backup"
    fi

    mkdir -p "$(dirname "$config_dir")"

    if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "mingw"* ]]; then
        local win_link win_target
        win_link="$(cygpath -w "$config_dir")"
        win_target="$(cygpath -w "$repo_global")"
        powershell -NoProfile -Command "New-Item -ItemType Junction -Path '$win_link' -Target '$win_target'" > /dev/null 2>&1
        echo "  $config_dir -> $repo_global (junction)"
    else
        ln -s "$repo_global" "$config_dir"
        echo "  $config_dir -> $repo_global"
    fi
}

# Always ensure skills symlinks exist inside repo global dirs
# (used when the full-dir symlink path is taken on a new machine)
create_symlink "$REPO_DIR/global/claude/skills"   "$REPO_DIR/skills"
create_symlink "$REPO_DIR/global/gemini/skills"   "$REPO_DIR/skills"
create_symlink "$REPO_DIR/global/opencode/skills" "$REPO_DIR/skills"
create_symlink "$REPO_DIR/global/codex/skills"    "$REPO_DIR/skills"
# Link tool config dirs (always full symlink, backup existing)
link_tool_config "$HOME_DIR/.claude"   "$REPO_DIR/global/claude"
link_tool_config "$HOME_DIR/.gemini"   "$REPO_DIR/global/gemini"
link_tool_config "$HOME_DIR/.opencode" "$REPO_DIR/global/opencode"
link_tool_config "$HOME_DIR/.codex"    "$REPO_DIR/global/codex"

echo ""

# =====================================================
# 2. Install/Update CLI Tools
# =====================================================
echo "Installing/Updating CLI tools..."

# Claude Code
echo -n "  - Claude Code..."
if command -v claude &> /dev/null; then
    echo " (already installed: $(claude --version 2>/dev/null || echo 'unknown'))"
else
    echo " installing..."
    curl -fsSL https://claude.ai/install.sh | bash

    # Claude installs its launcher into ~/.local/bin on Linux/macOS.
    if [ -x "$HOME_DIR/.local/bin/claude" ]; then
        ensure_path_entry "$HOME_DIR/.local/bin"
        persist_user_local_bin_path
    fi

    if command -v claude &> /dev/null; then
        echo "    Installed: $(claude --version 2>/dev/null || echo 'unknown')"
    else
        echo "  ERROR: Claude installed to $HOME_DIR/.local/bin/claude but is not on PATH."
        echo "  Run: export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo "  Then re-run setup."
        exit 1
    fi
fi

# Gemini CLI
echo -n "  - Gemini CLI..."
if command -v gemini &> /dev/null; then
    echo " (already installed)"
else
    echo " installing..."
    npm install -g @google/gemini-cli
    echo "    Installed!"
fi

# open-code
echo -n "  - open-code..."
if command -v opencode &> /dev/null; then
    echo " (already installed)"
else
    echo " installing..."
    if command -v brew &> /dev/null; then
        brew install anomalyco/tap/opencode 2>/dev/null || npm install -g opencode-ai@latest
    else
        npm install -g opencode-ai@latest
    fi
    echo "    Installed!"
fi

# agent-browser
echo -n "  - agent-browser..."
if command -v agent-browser &> /dev/null; then
    echo " (already installed)"
else
    echo " installing..."
    npm install -g agent-browser
    agent-browser install
    echo "    Installed!"
fi

# agent-browser system dependencies (Chromium needs libnspr4, libnss3, etc.)
echo -n "  - agent-browser system deps..."
if npx playwright install-deps chromium 2>/dev/null; then
    echo " installed"
else
    echo " (skipped — may need sudo)"
fi

# Ensure screenshots directory exists
mkdir -p "$REPO_DIR/skills/agent-browser/screenshots"

# Ollama
echo -n "  - Ollama..."
if command -v ollama &> /dev/null; then
    echo " (already installed: $(ollama --version 2>/dev/null || echo 'unknown'))"
else
    echo " installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            brew install ollama
        else
            curl -fsSL https://ollama.com/install.sh | sh
        fi
    else
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    echo "    Installed!"
fi

# Codex CLI
echo -n "  - Codex CLI..."
if command -v codex &> /dev/null; then
    echo " (already installed: $(codex --version 2>/dev/null || echo 'unknown'))"
else
    echo " installing..."
    npm install -g @openai/codex
    echo "    Installed!"
fi

echo ""

# =====================================================
# 3. Setup Stitch MCP (HTTP transport via API key)
# =====================================================
echo "Setting up Stitch MCP..."

STITCH_KEY=$(grep '^STITCH_API_KEY=' "$REPO_DIR/.env" 2>/dev/null | cut -d'=' -f2- | xargs)
if [ -n "$STITCH_KEY" ] && [ "$STITCH_KEY" != "AQ.STITCH_API_KEY" ]; then
    echo "  Stitch API key found in .env"

    # Add Stitch to Claude Code (HTTP transport, user scope)
    if command -v claude &> /dev/null; then
        claude mcp add stitch --transport http https://stitch.googleapis.com/mcp \
            --header "X-Goog-Api-Key: $STITCH_KEY" -s user 2>/dev/null && \
            echo "    Added stitch to Claude Code (user scope)" || \
            echo "    Warning: Failed to add stitch to Claude Code"
    fi

    # Install Stitch extension for Gemini CLI
    if command -v gemini &> /dev/null; then
        gemini extensions install https://github.com/gemini-cli-extensions/stitch --auto-update 2>/dev/null && \
            echo "    Installed stitch extension for Gemini CLI" || \
            echo "    Stitch extension already installed or updated"

        # Configure extension to use API key auth from STITCH_API_KEY
        EXT_DIR="$HOME_DIR/.gemini/extensions/Stitch"
        if [ -f "$EXT_DIR/gemini-extension-apikey.json" ]; then
            sed "s/YOUR_API_KEY/$STITCH_KEY/g" "$EXT_DIR/gemini-extension-apikey.json" > "$EXT_DIR/gemini-extension.json"
            echo "    Configured stitch extension with API key auth"
        fi
    fi
else
    echo "  WARNING: No STITCH_API_KEY in .env"
    echo "  Add your Stitch API key to $REPO_DIR/.env"
    echo "  Get one at: https://aistudio.google.com/apikey"
fi

echo ""

# =====================================================
# 4. Check for .env file
# =====================================================
ENV_FILE="$REPO_DIR/.env"
ENV_EXAMPLE="$REPO_DIR/.env.example"

if [ ! -f "$ENV_FILE" ]; then
    echo "WARNING: .env file not found!"
    echo "  Create it from .env.example and fill in your API keys:"
    echo "    cp \"$ENV_EXAMPLE\" \"$ENV_FILE\""
    echo ""
fi

# =====================================================
# 5. Generate ~/.mcp.json from template
# =====================================================
echo "Generating MCP config..."

MCP_TEMPLATE="$REPO_DIR/global/mcp/mcp.json.template"
MCP_OUTPUT="$HOME_DIR/.mcp.json"

if [ -f "$ENV_FILE" ]; then
    if [ -f "$MCP_OUTPUT" ]; then
        echo "  Skipped: $MCP_OUTPUT already exists (not overwriting)"
    else
        # Load .env file and substitute in template
        cp "$MCP_TEMPLATE" "$MCP_OUTPUT"

        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue

            # Remove leading/trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            # Substitute in output file
            if [ -n "$value" ]; then
                sed -i.bak "s|\${$key}|$value|g" "$MCP_OUTPUT"
            fi
        done < "$ENV_FILE"

        rm -f "${MCP_OUTPUT}.bak"
        echo "  Generated: $MCP_OUTPUT"
    fi

    # Generate Codex config.toml from template
    CODEX_TEMPLATE="$REPO_DIR/global/codex/config.toml.template"
    CODEX_OUTPUT="$REPO_DIR/global/codex/config.toml"

    if [ -f "$CODEX_TEMPLATE" ]; then
        cp "$CODEX_TEMPLATE" "$CODEX_OUTPUT"

        while IFS='=' read -r key value; do
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            if [ -n "$value" ]; then
                sed -i.bak "s|\${$key}|$value|g" "$CODEX_OUTPUT"
            fi
        done < "$ENV_FILE"

        rm -f "${CODEX_OUTPUT}.bak"
        echo "  Generated: $CODEX_OUTPUT"
    fi
else
    echo "  Skipped: Create .env file first"
fi

echo ""

# =====================================================
# 6. Ask about Local Folder Setup
# =====================================================
echo "Local folder setup..."
echo "  Current directory: $CURRENT_DIR"
echo ""
echo "  This will create project-specific config folders in your current directory:"
echo "    - .claude/     (Claude Code local config)"
echo "    - .gemini/     (Gemini CLI local config)"
echo "    - .opencode/   (OpenCode local config)"
echo "    - .codex/      (Codex CLI local config)"
echo "    - ralph/       (Ralph autonomous agent)"
echo ""
read -p "  Create local folders in current directory? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "  Creating local folders..."

    # Create .claude local
    if [ ! -d "$CURRENT_DIR/.claude" ]; then
        mkdir -p "$CURRENT_DIR/.claude"
        if [ -f "$REPO_DIR/local/claude/CLAUDE.md.template" ]; then
            cp "$REPO_DIR/local/claude/CLAUDE.md.template" "$CURRENT_DIR/.claude/CLAUDE.md"
        fi
        echo "    Created: .claude/"
    else
        echo "    Exists: .claude/"
    fi

    # Create .gemini local
    if [ ! -d "$CURRENT_DIR/.gemini" ]; then
        mkdir -p "$CURRENT_DIR/.gemini"
        if [ -f "$REPO_DIR/local/gemini/GEMINI.md.template" ]; then
            cp "$REPO_DIR/local/gemini/GEMINI.md.template" "$CURRENT_DIR/.gemini/GEMINI.md"
        fi
        echo "    Created: .gemini/"
    else
        echo "    Exists: .gemini/"
    fi

    # Create .opencode local
    if [ ! -d "$CURRENT_DIR/.opencode" ]; then
        mkdir -p "$CURRENT_DIR/.opencode"
        if [ -f "$REPO_DIR/local/opencode/AGENT.md.template" ]; then
            cp "$REPO_DIR/local/opencode/AGENT.md.template" "$CURRENT_DIR/.opencode/AGENT.md"
        fi
        echo "    Created: .opencode/"
    else
        echo "    Exists: .opencode/"
    fi

    # Create .codex local
    if [ ! -d "$CURRENT_DIR/.codex" ]; then
        mkdir -p "$CURRENT_DIR/.codex"
        echo "    Created: .codex/"
    else
        echo "    Exists: .codex/"
    fi

    # Copy AGENTS.md to project root (Codex reads it from project root)
    if [ ! -f "$CURRENT_DIR/AGENTS.md" ]; then
        if [ -f "$REPO_DIR/local/codex/AGENTS.md.template" ]; then
            cp "$REPO_DIR/local/codex/AGENTS.md.template" "$CURRENT_DIR/AGENTS.md"
            echo "    Created: AGENTS.md"
        fi
    else
        echo "    Exists: AGENTS.md"
    fi

    # Create ralph folder
    if [ ! -d "$CURRENT_DIR/ralph" ]; then
        mkdir -p "$CURRENT_DIR/ralph/archive"
        cp "$REPO_DIR/local/ralph/claude_ralph.sh" "$CURRENT_DIR/ralph/"
        cp "$REPO_DIR/local/ralph/gemini_ralph.sh" "$CURRENT_DIR/ralph/"
        cp "$REPO_DIR/local/ralph/opencode_ralph.sh" "$CURRENT_DIR/ralph/"
        cp "$REPO_DIR/local/ralph/codex_ralph.sh" "$CURRENT_DIR/ralph/"
        cp "$REPO_DIR/local/ralph/prompt.md" "$CURRENT_DIR/ralph/"
        cp "$REPO_DIR/local/ralph/README.md" "$CURRENT_DIR/ralph/"
        chmod +x "$CURRENT_DIR/ralph/"*.sh
        echo "    Created: ralph/"
        echo ""
        echo "  Ralph setup complete! Next steps:"
        echo "    1. Create a plan.md file in ralph/"
        echo "    2. Run: bash ralph/claude_ralph.sh"
    else
        echo "    Exists: ralph/"
    fi
else
    echo "  Skipped local folder creation."
    echo "  Run setup again from your project directory to create local folders."
fi

echo ""

# =====================================================
# Done!
# =====================================================
echo "Setup complete!"
echo ""
echo "Global configs installed:"
echo "  - ~/.claude -> model-set/global/claude"
echo "  - ~/.gemini -> model-set/global/gemini"
echo "  - ~/.opencode -> model-set/global/opencode"
echo "  - ~/.codex -> model-set/global/codex"
echo ""
echo "MCP Servers configured:"
echo "  - stitch (HTTP transport, API key in .env)"
echo "  - context7 (HTTP transport, API key in .env)"
echo "  - aiguide (npx @tigerdata/pg-aiguide, no auth required)"
echo ""

if [ ! -f "$ENV_FILE" ]; then
    echo "Next steps:"
    echo "  1. Create .env file: cp \"$ENV_EXAMPLE\" \"$ENV_FILE\""
    echo "  2. Fill in your API keys (CONTEXT7_API_KEY, etc.)"
    echo "  3. Run setup again to generate ~/.mcp.json"
fi
