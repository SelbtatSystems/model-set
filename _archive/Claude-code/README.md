# Claude workspace: agents, skills, and context

Small collection of reusable **agent prompts** + **skill playbooks** intended to be used from an AI coding assistant that supports agent/skill files.

## What's in here

- Agents (ready-to-run personas + process): [`agents/`](agents:1)
  - Design/UI review agent: [`agents/agent-design-review.md`](agents/agent-design-review.md:1)
  - Codebase merge/integration agent: [`agents/codebase-integrator.md`](agents/codebase-integrator.md:1)
- Shared context docs (design principles, snippets): [`agent_context/`](agent_context:1)
  - Design checklist: [`agent_context/design-principles.md`](agent_context/design-principles.md:1)
- Skills (repeatable procedures): [`Skills/`](Skills:1)
  - PRD generator skill: [`Skills/prd/SKILL.md`](Skills/prd/SKILL.md:1)
  - UX redesign skill: [`Skills/ux-redesign/SKILL.md`](Skills/ux-redesign/SKILL.md:1)
  - Agent browser skill: [`Skills/agent-browser/SKILL.md`](Skills/agent-browser/SKILL.md:1)
  - Ralph converter skill: [`Skills/ralph/SKILL.md`](Skills/ralph/SKILL.md:1)
- Ralph autonomous agent: [`ralph/`](ralph:1)
- Repo-level working rules for the assistant: [`CLAUDE.md`](CLAUDE.md:1)
- MCP/tooling configuration (if your assistant uses it): [`.mcp.json`](.mcp.json:1)

---

## Skills Overview

### PRD Generator (`/prd`)
Generates structured Product Requirements Documents for new features.

**Workflow:**
1. Receive feature description
2. Ask 3-5 clarifying questions (with lettered options for quick responses)
3. Generate structured PRD with user stories, acceptance criteria, functional requirements
4. Save to `tasks/prd-[feature-name].md`

**Output includes:** Introduction, goals, user stories with acceptance criteria, functional requirements, non-goals, technical considerations, success metrics.

---

### UX Redesign (`/ux-redesign`)
Comprehensive UI/UX audit and redesign using psychology-backed principles.

**Workflow:**
1. Analyze current UI (screenshots, code, or description)
2. Identify friction points using cognitive psychology (Hick's Law, Miller's Law, Fitts's Law)
3. Generate prioritized redesign recommendations
4. Output actionable implementation specs

**Covers:** Visual hierarchy, color psychology, Gestalt principles, navigation patterns, micro-interactions, mobile-first design, accessibility.

---

### Agent Browser (`/agent-browser`)
Browser automation CLI for AI agents to visually test frontend changes.

**Use for:** Verifying UI changes, testing interactions, capturing screenshots, form testing.

---

### Ralph Converter (`/ralph`)
Converts PRDs to `prd.json` format for the Ralph autonomous agent system.

**Rules:**
- Each story must be completable in one iteration (one context window)
- Stories ordered by dependency (schema → backend → UI)
- Acceptance criteria must be verifiable
- Always includes "Typecheck passes" criterion

---

## Agent Browser

### Installation

```bash
# Install globally via npm
npm install -g agent-browser

# Download Chromium browser (required)
agent-browser install
```

### How It Works

Agent-browser provides a CLI interface to automate browser interactions. It uses Playwright under the hood and maintains session state between commands.

**Core concept: Element References**

When you run `snapshot -i`, agent-browser returns interactive elements with refs like `@e1`, `@e2`, etc. Use these refs in subsequent commands to interact with specific elements.

```
@e1 [button] "Submit"           # Button with text
@e2 [input type="email"]        # Email input
@e3 [a href="/page"] "Link"     # Anchor link
```

**Important:** Refs invalidate after navigation or dynamic content changes. Always re-snapshot after page changes.

### Command Reference

```bash
# Navigation
agent-browser open <url>           # Open URL
agent-browser open --headed <url>  # Open with visible browser (debugging)
agent-browser back / forward / reload
agent-browser close

# Snapshot & Refs
agent-browser snapshot -i          # Interactive elements only (recommended)
agent-browser snapshot             # Full page structure

# Interaction
agent-browser click @e1            # Click element
agent-browser fill @e2 "text"      # Fill input field
agent-browser type "text"          # Type without targeting element
agent-browser hover @e3
agent-browser check @e4            # Toggle checkbox
agent-browser select @e5 "option"  # Select dropdown option

# Screenshots & Capture
agent-browser screenshot ./path.png
agent-browser screenshot --full    # Full page scroll capture
agent-browser pdf ./path.pdf

# Wait Conditions
agent-browser wait 1000            # Wait milliseconds
agent-browser wait --network       # Wait for network idle
agent-browser wait --url "pattern" # Wait for URL match

# Information
agent-browser get text @e1
agent-browser get title
agent-browser get url

# Sessions (parallel browsers)
agent-browser --session test1 open https://site.com
agent-browser --session test2 open https://other.com

# State Persistence
agent-browser state save ./auth.json
agent-browser state load ./auth.json
```

### Visual Testing Workflow

After every frontend change:

```bash
# 1. Open the changed page
agent-browser open http://localhost:3101/path

# 2. Get page structure & element refs
agent-browser snapshot -i

# 3. Screenshot at desktop width
agent-browser screenshot ./test-desktop.png

# 4. Test interactions
agent-browser click @e1
agent-browser snapshot -i

# 5. Close when done
agent-browser close
```

### Troubleshooting

```bash
# Ref not found - re-snapshot
agent-browser snapshot -i

# Element not visible - scroll first
agent-browser scroll --bottom
agent-browser snapshot -i

# See browser window for debugging
agent-browser open --headed https://site.com
```

---

## Ralph Autonomous Agent

Ralph is a long-running AI agent that implements PRD user stories iteratively using Claude Code. It spawns fresh Claude instances per iteration, each working on one user story until all are complete.

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                      ralph.sh loop                          │
├─────────────────────────────────────────────────────────────┤
│  for each iteration:                                        │
│    1. Pipe prompt.md to Claude Code                         │
│    2. Claude reads prd.json, finds next story               │
│    3. Claude implements story in codebase                   │
│    4. Claude commits, updates prd.json (passes: true)       │
│    5. Claude logs to progress.txt                           │
│    6. Check for <promise>COMPLETE</promise> signal          │
│    7. If not complete, continue to next iteration           │
└─────────────────────────────────────────────────────────────┘
```

### Ralph Directory Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Main loop script. Spawns Claude Code each iteration, checks for completion signal, handles archiving when branch changes. |
| `prompt.md` | Agent instructions read by Claude each iteration. Defines the workflow: read PRD → pick story → implement → commit → update PRD → log progress. |
| `prd.json` | User stories with acceptance criteria, priority, and pass/fail status. Claude picks highest priority `passes: false` story each iteration. |
| `progress.txt` | Cumulative log of completed work. Contains a "Codebase Patterns" section at top for reusable learnings, plus per-story implementation notes. |
| `.last-branch` | Tracks current branch name. When branch changes, triggers auto-archive of previous run. |
| `archive/` | Previous runs stored here as `YYYY-MM-DD-feature-name/` folders with their prd.json and progress.txt. |

### File Details

#### `ralph.sh`
The orchestration script:
1. Checks if branch changed from last run → archives previous run if so
2. Initializes progress.txt if missing
3. Loops up to MAX_ITERATIONS (default 10)
4. Each iteration: pipes prompt.md to Claude Code
5. Checks output for `<promise>COMPLETE</promise>` to know when done
6. Clears Claude context between iterations

```bash
# Run with default 10 iterations
bash ralph/ralph.sh

# Run with custom max
bash ralph/ralph.sh 20
```

#### `prompt.md`
Instructions Claude follows each iteration:
1. Read prd.json and progress.txt
2. Checkout correct branch (from prd.json branchName)
3. Pick highest priority story where `passes: false`
4. Implement that single story
5. Run quality checks (typecheck, lint, test)
6. Commit with message: `feat: [Story ID] - [Story Title]`
7. Update prd.json: set `passes: true`
8. Append progress to progress.txt with learnings
9. If ALL stories pass, output `<promise>COMPLETE</promise>`

#### `prd.json`
The work queue:
```json
{
  "project": "ProjectName",
  "branchName": "ralph/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a [user], I want [feature]",
      "acceptanceCriteria": ["criterion 1", "Typecheck passes"],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

**Key fields:**
- `priority`: Lower = sooner. Claude picks lowest priority where `passes: false`
- `passes`: Set to `true` by Claude after successful implementation
- `notes`: Claude can add implementation notes

#### `progress.txt`
Persistent memory across iterations:
```markdown
## Codebase Patterns
- Use `sql<number>` template for aggregations
- Always use `IF NOT EXISTS` for migrations

---
## 2026-01-15 10:30 - US-001
- Implemented database schema
- Files: src/db/schema.ts, migrations/001.sql
- **Learnings:** Field names must match template exactly
---
```

The "Codebase Patterns" section at top is critical—Claude reads this first each iteration to understand previous learnings.

### Requirements

- Git Bash (Windows) or bash shell (Mac/Linux)
- Claude Code CLI installed and authenticated
- `jq` for JSON parsing

### Usage

1. Create/edit `prd.json` with your user stories
2. Set a unique `branchName`
3. Run `bash ralph/ralph.sh`
4. Monitor progress in `progress.txt`
5. When done, review the feature branch and merge to main

**Stopping early:** `Ctrl+C` stops the loop. Progress is saved—rerun to resume. Stories with `passes: true` won't be reimplemented.

---

## How to use

1. Pick the relevant agent/skill file and use it as the instruction source in your assistant.
   - Example: for UI changes, use [`agents/agent-design-review.md`](agents/agent-design-review.md:1).
   - Example: to spec a feature, follow [`Skills/prd/SKILL.md`](Skills/prd/SKILL.md:1).
   - Example: for autonomous implementation, use the [`ralph/`](ralph:1) system.
2. If an agent references specific tools (e.g. Playwright/MCP), ensure your environment provides them (see each file's frontmatter/tool list).
3. Keep assistant behavior aligned with repo rules in [`CLAUDE.md`](CLAUDE.md:1) (notably: be concise).
