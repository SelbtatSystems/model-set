# model-set

Centralized configuration for AI coding assistants: Claude Code, Gemini CLI, open-code, and OpenAI Codex CLI.

## Quick Start

### New Machine Setup

```bash
# Clone the repo
git clone https://github.com/youruser/model-set.git ~/model-set
cd ~/model-set

# Run setup (Windows)
.\scripts\setup.ps1

# Run setup (macOS/Linux)
./scripts/setup.sh
```

The setup script will:
1. Install/update CLI tools (Claude Code, Gemini CLI, open-code, Codex CLI, agent-browser)
2. Create symlinks from `~/.claude`, `~/.gemini`, `~/.opencode`, `~/.codex` to this repo
3. Generate `~/.mcp.json` and `~/.codex/config.toml` from templates (if `.env` exists)

### Configure API Keys

```bash
# Copy the example env file
cp .env.example .env

# Edit with your API keys
code .env  # or your editor

# Re-run setup to generate MCP config
./scripts/setup.sh
```

### Apply to a Project

```bash
# Apply Claude config + ralph to a project
./scripts/apply-local.sh ./my-project --tool claude

# Apply Codex config + ralph to a project
./scripts/apply-local.sh ./my-project --tool codex

# Or on Windows
.\scripts\apply-local.ps1 -ProjectDir .\my-project -Tool claude
.\scripts\apply-local.ps1 -ProjectDir .\my-project -Tool codex
```

## Directory Structure

```
model-set/
├── .agents/skills/       # Shared skills (Stitch integration)
├── agent-browser/        # Browser testing skill
├── global/               # Symlinked to ~/
│   ├── claude/           # -> ~/.claude
│   ├── codex/            # -> ~/.codex
│   ├── gemini/           # -> ~/.gemini
│   ├── opencode/         # -> ~/.opencode
│   └── mcp/              # MCP templates
├── local/                # Project templates (copied, not symlinked)
│   ├── claude/
│   ├── codex/
│   ├── gemini/
│   └── opencode/
├── ralph/                # Autonomous coding agent
├── scripts/              # Setup scripts
└── skills/               # Alias of .agents/skills
```

## Global vs Local Configs

### Global (Symlinked)
- Settings, permissions, themes
- Shared skills (.agents/skills)
- MCP servers that apply everywhere (stitch, context7, aiguide)

### Local (Copied per-project)
- CLAUDE.md / GEMINI.md / AGENT.md / AGENTS.md context files
- Project-specific MCP servers (postgres, redis)
- Ralph autonomous agent

## MCP Servers

### Global MCPs (always available)
| Server | Purpose |
|--------|---------|
| stitch | Generate UI designs from text prompts |
| context7 | Documentation lookup and code context |
| aiguide | PostgreSQL/TimescaleDB documentation search |

### Local MCPs (per-project)
| Server | Purpose |
|--------|---------|
| postgres | Database queries and schema management |
| redis | Cache operations |

## Skills

### Shared Skills (.agents/skills)
- `design-md/` - Generate design documents
- `enhance-prompt/` - Improve prompts
- `react-components/` - Generate React components via Stitch
- `stitch-loop/` - Iterative Stitch design workflow

### agent-browser
Browser automation for visual testing after frontend changes.

```bash
agent-browser open http://localhost:3000/path
agent-browser snapshot -i          # Get interactive elements
agent-browser screenshot ./test.png
agent-browser click @e1            # Interact by ref
agent-browser close
```

## Codex CLI Notes

Codex CLI uses different conventions from the other tools:
- **Global config**: `~/.codex/config.toml` (TOML format, generated from template by setup)
- **Global instructions**: `~/.codex/AGENTS.md` (Markdown)
- **Project instructions**: `AGENTS.md` at project root (not in a subdirectory)
- **Project config**: `.codex/config.toml` for project-specific settings
- **Auth**: Run `codex login` for OAuth, or set `OPENAI_API_KEY` for API key auth
- **MCP**: Configured in `config.toml` `[mcp_servers.*]` sections (not separate .mcp.json)

## Ralph (Autonomous Agent)

Ralph is an autonomous coding agent that works through user stories in a loop.

### Usage
1. Edit `ralph/plan.md` with your tasks
2. Run the loop with your preferred tool:
```bash
bash ralph/claude_ralph.sh    # Claude Code
bash ralph/gemini_ralph.sh    # Gemini CLI
bash ralph/opencode_ralph.sh  # OpenCode
bash ralph/codex_ralph.sh     # Codex CLI
```
3. Ralph will:
   - Pick the highest priority incomplete story
   - Implement it
   - Run quality checks
   - Commit if passing
   - Update progress.txt
   - Repeat until all stories pass

### PRD Format
```json
{
  "projectName": "My Project",
  "branchName": "ralph/feature-name",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add login form",
      "description": "As a user, I want to log in",
      "acceptanceCriteria": ["Form validates email", "Shows error on failure"],
      "priority": 1,
      "passes": false
    }
  ]
}
```

## Adding New Skills

1. Create a directory in `.agents/skills/your-skill/`
2. Add `SKILL.md` with instructions
3. The skill will be available in all tools via symlinks

## Updating

```bash
cd ~/model-set
git pull
./scripts/setup.sh  # Re-run to update symlinks if needed
```

## Troubleshooting

### Symlinks not working on Windows
Run PowerShell as Administrator, or enable Developer Mode in Windows Settings.

### MCP servers not connecting
1. Check `.env` has correct API keys
2. Re-run setup to regenerate `~/.mcp.json`
3. Restart the CLI tool

### Skills not appearing
Verify symlinks exist:
```bash
ls -la ~/.claude/skills  # Should point to model-set/.agents/skills
```
