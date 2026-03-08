#!/bin/bash
# Apply local configs to a project
# Usage: ./scripts/apply-local.sh /path/to/project [--tool claude|gemini|opencode]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
PROJECT_DIR=""
TOOL="claude"

while [[ $# -gt 0 ]]; do
    case $1 in
        --tool)
            TOOL="$2"
            shift 2
            ;;
        *)
            PROJECT_DIR="$1"
            shift
            ;;
    esac
done

if [ -z "$PROJECT_DIR" ]; then
    echo "Usage: $0 /path/to/project [--tool claude|gemini|opencode]"
    echo ""
    echo "Options:"
    echo "  --tool    Which tool config to apply (default: claude)"
    echo ""
    echo "Examples:"
    echo "  $0 ./my-project"
    echo "  $0 ./my-project --tool gemini"
    exit 1
fi

# Resolve to absolute path
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
    echo "Error: Project directory does not exist: $PROJECT_DIR"
    exit 1
}

echo "Applying $TOOL config to: $PROJECT_DIR"
echo ""

# =====================================================
# 1. Copy tool-specific configs
# =====================================================
case $TOOL in
    claude)
        LOCAL_DIR="$REPO_DIR/local/claude"
        CONTEXT_FILE="CLAUDE.md"
        CONTEXT_TEMPLATE="$LOCAL_DIR/CLAUDE.md.template"
        MCP_TEMPLATE="$LOCAL_DIR/.mcp.json.template"

        # Create .claude directory
        mkdir -p "$PROJECT_DIR/.claude"

        # Copy context file if it doesn't exist
        if [ ! -f "$PROJECT_DIR/$CONTEXT_FILE" ]; then
            cp "$CONTEXT_TEMPLATE" "$PROJECT_DIR/$CONTEXT_FILE"
            echo "  Created $CONTEXT_FILE"
        else
            echo "  $CONTEXT_FILE already exists (skipped)"
        fi

        # Copy MCP template
        if [ -f "$MCP_TEMPLATE" ]; then
            cp "$MCP_TEMPLATE" "$PROJECT_DIR/.mcp.json.template"
            echo "  Created .mcp.json.template"
        fi
        ;;

    gemini)
        LOCAL_DIR="$REPO_DIR/local/gemini"
        CONTEXT_FILE="GEMINI.md"
        CONTEXT_TEMPLATE="$LOCAL_DIR/GEMINI.md.template"

        # Create .gemini directory
        mkdir -p "$PROJECT_DIR/.gemini"

        # Copy context file if it doesn't exist
        if [ ! -f "$PROJECT_DIR/$CONTEXT_FILE" ]; then
            cp "$CONTEXT_TEMPLATE" "$PROJECT_DIR/$CONTEXT_FILE"
            echo "  Created $CONTEXT_FILE"
        else
            echo "  $CONTEXT_FILE already exists (skipped)"
        fi
        ;;

    opencode)
        LOCAL_DIR="$REPO_DIR/local/opencode"
        CONTEXT_FILE="AGENT.md"
        CONTEXT_TEMPLATE="$LOCAL_DIR/AGENT.md.template"

        # Create .opencode directory
        mkdir -p "$PROJECT_DIR/.opencode"

        # Copy context file if it doesn't exist
        if [ ! -f "$PROJECT_DIR/$CONTEXT_FILE" ]; then
            cp "$CONTEXT_TEMPLATE" "$PROJECT_DIR/$CONTEXT_FILE"
            echo "  Created $CONTEXT_FILE"
        else
            echo "  $CONTEXT_FILE already exists (skipped)"
        fi
        ;;

    codex)
        LOCAL_DIR="$REPO_DIR/local/codex"
        CONTEXT_FILE="AGENTS.md"
        CONTEXT_TEMPLATE="$LOCAL_DIR/AGENTS.md.template"

        # Create .codex directory
        mkdir -p "$PROJECT_DIR/.codex"

        # Copy AGENTS.md to project root if it doesn't exist
        if [ ! -f "$PROJECT_DIR/$CONTEXT_FILE" ]; then
            cp "$CONTEXT_TEMPLATE" "$PROJECT_DIR/$CONTEXT_FILE"
            echo "  Created $CONTEXT_FILE"
        else
            echo "  $CONTEXT_FILE already exists (skipped)"
        fi
        ;;

    *)
        echo "Error: Unknown tool: $TOOL"
        echo "Supported tools: claude, gemini, opencode, codex"
        exit 1
        ;;
esac

# =====================================================
# 2. Copy ralph directory
# =====================================================
RALPH_SRC="$REPO_DIR/ralph"
RALPH_DST="$PROJECT_DIR/ralph"

if [ ! -d "$RALPH_DST" ]; then
    mkdir -p "$RALPH_DST"
    cp "$RALPH_SRC/prompt.md" "$RALPH_DST/"
    cp "$RALPH_SRC/ralph.sh" "$RALPH_DST/"
    chmod +x "$RALPH_DST/ralph.sh"

    # Create empty prd.json template
    cat > "$RALPH_DST/prd.json" << 'EOF'
{
  "projectName": "Your Project",
  "branchName": "ralph/feature-name",
  "userStories": [
    {
      "id": "US-001",
      "title": "Example Story",
      "description": "As a user, I want to...",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2"
      ],
      "priority": 1,
      "passes": false
    }
  ]
}
EOF

    # Create empty progress.txt
    echo "# Ralph Progress Log" > "$RALPH_DST/progress.txt"
    echo "Started: $(date)" >> "$RALPH_DST/progress.txt"
    echo "---" >> "$RALPH_DST/progress.txt"

    echo "  Created ralph/ directory"
else
    echo "  ralph/ already exists (skipped)"
fi

# =====================================================
# 3. Create project .env template
# =====================================================
if [ ! -f "$PROJECT_DIR/.env.local.example" ]; then
    cat > "$PROJECT_DIR/.env.local.example" << 'EOF'
# Project-specific environment variables
# Copy to .env.local and fill in your values

# Database
POSTGRES_DATABASE_URI=postgresql://user:password@localhost:5432/dbname

# Redis (if using)
REDIS_URL=redis://:password@localhost:6379/0
EOF
    echo "  Created .env.local.example"
fi

echo ""
echo "Applied $TOOL config to $PROJECT_DIR"
echo "  Copied ralph/ to $PROJECT_DIR/ralph"
if [ "$TOOL" = "claude" ]; then
    echo "  Created .mcp.json template"
fi
echo ""
echo "Next steps:"
echo "  1. Edit $PROJECT_DIR/$CONTEXT_FILE with project-specific info"
echo "  2. Edit $PROJECT_DIR/ralph/prd.json with user stories"
if [ "$TOOL" = "claude" ]; then
    echo "  3. Copy .mcp.json.template to .mcp.json and fill in credentials"
fi
