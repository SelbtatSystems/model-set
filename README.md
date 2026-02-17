# model-set

Centralized configuration for AI coding assistants: Claude Code, Gemini CLI, OpenCode, and OpenAI Codex CLI.

## Quick Start

### New Machine Setup

```bash
# Clone the repo
git clone https://github.com/SelbtatSystems/model-set.git ~/model-set
cd ~/model-set

# Copy and fill in your API keys
cp .env.example .env
code .env

# Run setup (macOS/Linux)
./scripts/setup.sh

# Run setup (Windows)
.\scripts\setup.ps1
```

The setup script will:
1. Auto-install Python 3 if not found (via Homebrew/apt/dnf/winget/direct download)
2. Install/update CLI tools (Claude Code, Gemini CLI, OpenCode, Codex CLI, agent-browser)
3. Create symlinks from `~/.claude`, `~/.gemini`, `~/.opencode`, `~/.codex` → this repo
4. Install the Stitch extension for Gemini CLI with API key auth (`STITCH_API_KEY`)
5. Generate `~/.mcp.json` and `~/.codex/config.toml` from templates

### Apply to a Project

```bash
# Apply config + ralph to a project
./scripts/apply-local.sh ./my-project --tool claude

# Or on Windows
.\scripts\apply-local.ps1 -ProjectDir .\my-project -Tool claude
```

## Directory Structure

```
model-set/
├── skills/               # Shared skills — available to ALL AI tools
│   ├── agent-browser/    # Browser testing skill + screenshot storage
│   ├── composition-patterns/   # React composition patterns
│   ├── design-md/        # Generate design documents
│   ├── enhance-prompt/   # Improve prompts for Stitch
│   ├── page-redesign/    # Redesign pages via Stitch
│   ├── ralph-plan/       # Sprint planning from PRDs
│   ├── react-best-practices/   # React/Next.js performance (Vercel)
│   ├── react-components/ # Generate React components via Stitch
│   ├── react-native-skills/    # React Native/Expo best practices (Vercel)
│   ├── senior-backend/   # Backend dev (Node, Go, Python, Postgres, GraphQL)
│   ├── skill-creator/    # Create and package new skills (requires Python 3)
│   ├── stitch-loop/      # Iterative Stitch design workflow
│   ├── web-design-guidelines/  # UI/accessibility compliance (Vercel)
│   └── .system/          # Skill installer utilities (requires Python 3)
├── global/               # Symlinked to ~/
│   ├── claude/           # → ~/.claude
│   ├── codex/            # → ~/.codex
│   ├── gemini/           # → ~/.gemini
│   ├── opencode/         # → ~/.opencode
│   └── mcp/              # MCP templates
├── local/                # Project templates (copied, not symlinked)
│   ├── claude/
│   ├── codex/
│   ├── gemini/
│   └── opencode/
├── scripts/              # Setup scripts (setup.sh, setup.ps1)
└── local/ralph/          # Autonomous coding agent templates
```

## Skills

All skills live in `skills/` and are shared across every AI tool via symlinks:

```
~/.claude/skills   → model-set/skills/
~/.gemini/skills   → model-set/skills/
~/.opencode/skills → model-set/skills/
~/.codex/skills    → model-set/skills/
```

### Available Skills

| Skill | Description |
|-------|-------------|
| `agent-browser` | Browser automation for visual testing after frontend changes |
| `composition-patterns` | React composition patterns (compound components, context, render props) |
| `design-md` | Analyze Stitch projects and generate DESIGN.md |
| `enhance-prompt` | Transform vague UI ideas into polished Stitch prompts |
| `page-redesign` | Redesign existing pages via Stitch generation |
| `ralph-plan` | Create sprint plans from PRD files |
| `react-best-practices` | React/Next.js performance optimization (Vercel Engineering) |
| `react-components` | Generate React components from Stitch designs |
| `react-native-skills` | React Native and Expo best practices (Vercel Engineering) |
| `senior-backend` | Backend APIs, DB optimization, security — Node.js, Go, Python, Postgres, GraphQL ¹ |
| `skill-creator` | Create, package, and validate new Claude Code skills ¹ |
| `stitch-loop` | Iterative website building with Stitch |
| `web-design-guidelines` | Review UI for Web Interface Guidelines compliance |

¹ Scripts in these skills require **Python 3** on your `PATH`.

### Adding New Skills

```bash
# Install from GitHub (e.g. from vercel-labs/agent-skills)
cd skills/.system/skill-installer/scripts
python3 install-skill-from-github.py --repo vercel-labs/agent-skills --path skills/your-skill

# Or create manually
mkdir skills/your-skill
# Add SKILL.md with YAML front matter:
# ---
# name: your-skill
# description: What it does and when to use it
# allowed-tools: Bash Read Write
# ---
```

### agent-browser

Browser automation CLI for visual testing. Screenshots save to `skills/agent-browser/screenshots/`.

```bash
agent-browser open http://localhost:3000/path
agent-browser snapshot -i          # Get interactive elements with refs
agent-browser screenshot ~/model-set/skills/agent-browser/screenshots/test.png
agent-browser click @e1            # Interact by ref
agent-browser close
```

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

## Stitch (Gemini CLI Extension)

The Stitch extension is installed at `~/.gemini/extensions/Stitch/` and configured via `STITCH_API_KEY` in `.env`. The setup script handles installation and API key configuration automatically.

```bash
# Manual install if needed
gemini extensions install https://github.com/gemini-cli-extensions/stitch --auto-update
```

`gemini-extension.json` is generated at setup time from the API key template and is not tracked in git.

## Global vs Local Configs

### Global (Symlinked)
- Settings, permissions, themes
- Shared skills (`skills/`)
- MCP servers that apply everywhere (stitch, context7, aiguide)

### Local (Copied per-project)
- CLAUDE.md / GEMINI.md / AGENT.md / AGENTS.md context files
- Project-specific MCP servers (postgres, redis)
- Ralph autonomous agent

## Codex CLI Notes

- **Global config**: `~/.codex/config.toml` (TOML format, generated from template)
- **Global instructions**: `~/.codex/AGENTS.md`
- **Project instructions**: `AGENTS.md` at project root
- **Auth**: Run `codex login` for OAuth, or set `OPENAI_API_KEY` for API key auth
- **MCP**: Configured in `config.toml` `[mcp_servers.*]` sections

## Ralph (Autonomous Agent)

Ralph is an autonomous coding agent that works through user stories in a loop.

### Usage
1. Edit `ralph/plan.md` with your tasks
2. Run with your preferred tool:
```bash
bash ralph/claude_ralph.sh    # Claude Code
bash ralph/gemini_ralph.sh    # Gemini CLI
bash ralph/opencode_ralph.sh  # OpenCode
bash ralph/codex_ralph.sh     # Codex CLI
```
3. Ralph picks the highest priority incomplete story, implements it, runs quality checks, commits, and repeats.

## Updating

```bash
cd ~/model-set
git pull
./scripts/setup.sh  # Re-run to update symlinks and regenerate configs
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
ls -la ~/.claude/skills  # Should point to model-set/skills/
```

### Stitch extension not working in Gemini CLI
Re-run setup — it will regenerate `gemini-extension.json` with your `STITCH_API_KEY`.

### Skill scripts failing with "python3 not found"
The setup script auto-installs Python 3, but if you're running a skill script manually:
- **macOS**: `brew install python3`
- **Ubuntu/Debian**: `sudo apt install python3`
- **Windows**: `winget install Python.Python.3 --silent` then open a new terminal
- **All platforms**: https://www.python.org/downloads/
