#!/bin/bash
# model-set Setup Script for Unix (macOS/Linux)
# Usage: ./scripts/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
HOME_DIR="$HOME"
CURRENT_DIR="$(pwd)"

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
    echo ""
    echo ""
    echo "  ERROR: Python 3 not found."
    echo "  Skill scripts (skill-creator, senior-backend, skill-installer) require Python 3."
    echo ""
    echo "  Install Python 3:"
    echo "    macOS:  brew install python3"
    echo "    Ubuntu: sudo apt install python3"
    echo "    Other:  https://www.python.org/downloads/"
    echo ""
    echo "  After installing, ensure 'python3' is on your PATH, then re-run setup."
    echo ""
    exit 1
fi

echo ""

# =====================================================
# 1. Install/Update CLI Tools
# =====================================================
echo "Installing/Updating CLI tools..."

# Claude Code
echo -n "  - Claude Code..."
if command -v claude &> /dev/null; then
    echo " (already installed: $(claude --version 2>/dev/null || echo 'unknown'))"
else
    echo " installing..."
    curl -fsSL https://claude.ai/install.sh | bash
    echo "    Installed!"
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
# 2. Setup Stitch MCP (HTTP transport via API key)
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
# 3. Check for .env file
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
# 4. Create Global Symlinks
# =====================================================
echo "Creating global config symlinks..."

create_symlink() {
    local link="$1"
    local target="$2"

    if [ -L "$link" ]; then
        echo "  $link -> already linked"
        return
    fi

    if [ -e "$link" ]; then
        echo "  $link -> backing up existing to ${link}.backup"
        mv "$link" "${link}.backup"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$link")"

    ln -s "$target" "$link"
    echo "  $link -> $target"
}

# Global configs
create_symlink "$HOME_DIR/.claude" "$REPO_DIR/global/claude"
create_symlink "$HOME_DIR/.gemini" "$REPO_DIR/global/gemini"
create_symlink "$HOME_DIR/.opencode" "$REPO_DIR/global/opencode"
create_symlink "$HOME_DIR/.codex" "$REPO_DIR/global/codex"

# Skills symlinks (shared across all tools)
create_symlink "$REPO_DIR/global/claude/skills" "$REPO_DIR/skills"
create_symlink "$REPO_DIR/global/gemini/skills" "$REPO_DIR/skills"
create_symlink "$REPO_DIR/global/opencode/skills" "$REPO_DIR/skills"
create_symlink "$REPO_DIR/global/codex/skills" "$REPO_DIR/skills"

echo ""

# =====================================================
# 5. Generate ~/.mcp.json from template
# =====================================================
echo "Generating MCP config..."

MCP_TEMPLATE="$REPO_DIR/global/mcp/mcp.json.template"
MCP_OUTPUT="$HOME_DIR/.mcp.json"

if [ -f "$ENV_FILE" ]; then
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
