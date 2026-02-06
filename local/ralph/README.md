# Ralph - Autonomous Coding Agent

Long-running AI agent that implements sprint plans iteratively. Supports multiple AI models.

## Quick Start

```bash
# Run with Claude Code
bash claude_ralph.sh

# Run with Gemini CLI
bash gemini_ralph.sh

# Run with OpenCode
bash opencode_ralph.sh

# With custom max iterations (default: 10)
bash claude_ralph.sh 20
```

## Available Scripts

| Script | Model | Permission Flag |
|--------|-------|-----------------|
| `claude_ralph.sh` | Claude Code | `--dangerously-skip-permissions` |
| `gemini_ralph.sh` | Gemini CLI | `--yolo` |
| `opencode_ralph.sh` | OpenCode | `--yolo` |

All scripts are identical except for the model invocation. They all skip permission prompts for autonomous operation.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                      Ralph Loop                             │
├─────────────────────────────────────────────────────────────┤
│  for each iteration:                                        │
│    1. Pipe prompt.md to AI model                            │
│    2. Model reads plan.md, finds next task                  │
│    3. Model implements task in codebase                     │
│    4. Model commits, marks task complete                    │
│    5. Model logs to progress.txt                            │
│    6. Check for <promise>COMPLETE</promise> signal          │
│    7. If not complete, continue to next iteration           │
└─────────────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `claude_ralph.sh` | Main loop script - Claude Code |
| `gemini_ralph.sh` | Main loop script - Gemini CLI |
| `opencode_ralph.sh` | Main loop script - OpenCode |
| `prompt.md` | Agent instructions - what the model does each iteration |
| `plan.md` | Sprint plan - tasks to complete (create this!) |
| `progress.txt` | Cumulative log of completed work (auto-created) |
| `.last-branch` | Tracks current branch for archiving (auto-created) |
| `archive/` | Previous runs archived here when branch changes |

## Setup

Ralph is installed to the root of your project by the model-set setup script:

```bash
# Run from model-set directory
./scripts/setup.sh   # Unix
.\scripts\setup.ps1  # Windows

# Select "Yes" when asked to create local folders
```

This creates the ralph folder in your current working directory.

## Creating a Plan

Create a `plan.md` file with YAML frontmatter:

```markdown
---
branchName: "ralph/feature-name"
projectName: "Feature Name"
totalSprints: 3
startDate: "2026-02-04"
---

# Feature Name Sprint Plan

## Sprint 1: Foundation

- [ ] **1.1** Create database migration
  - **File**: `db/migrations/001_create_table.sql`
  - **Validation**:
    - [ ] Migration runs without errors
    - [ ] Table exists in database

- [ ] **1.2** Create API endpoint
  - **File**: `src/api/endpoint.ts`
  - **Validation**:
    - [ ] Endpoint returns 200
    - [ ] Response matches schema
```

## Agent Behavior (per iteration)

1. **Read Plan** - Load plan.md from ralph directory
2. **Check Branch** - Checkout/create branch from `branchName`
3. **Pick Task** - First task with `- [ ]` (incomplete)
4. **Implement** - Make changes to codebase
5. **Validate** - Run validation steps
6. **Commit** - `feat: 1.1 - Task Title`
7. **Mark Complete** - Change `- [ ]` to `- [x]`
8. **Log Progress** - Append to progress.txt
9. **Check Completion** - If all tasks done, output `<promise>COMPLETE</promise>`

## Branch Workflow

- All work happens on the branch specified in `plan.md`
- Changes accumulate on feature branch, not main
- When done, review branch and merge/PR to main
- Changing `branchName` triggers auto-archive of previous run

## Archiving

When plan.md's `branchName` changes from previous run:

```
archive/
└── 2026-02-04-feature-name/
    ├── plan.md
    └── progress.txt
```

## Stopping Early

- `Ctrl+C` to stop the loop
- Progress is saved - can resume by running again
- Tasks with `- [x]` won't be re-implemented

## Requirements

- Git Bash (Windows) or bash shell (Mac/Linux)
- One of:
  - Claude Code CLI (`claude`)
  - Gemini CLI (`gemini`)
  - OpenCode CLI (`opencode`)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Permission errors | Ensure you're using the right script for your installed CLI |
| Model not found | Install the CLI: `npm install -g @google/gemini-cli` etc. |
| Tasks not completing | Check plan.md validation steps are achievable |
| Infinite loop | Ensure tasks have clear completion criteria |
