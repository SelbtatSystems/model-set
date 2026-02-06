# Ralph - Autonomous Coding Agent

Long-running AI agent that implements PRD user stories iteratively using Claude Code.

## Quick Start

```bash
# From agcore root directory (Git Bash on Windows)
bash scripts/ralph/ralph.sh

# With custom max iterations (default: 10)
bash scripts/ralph/ralph.sh 20
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                      ralph.sh loop                          │
├─────────────────────────────────────────────────────────────┤
│  for each iteration:                                        │
│    1. Pipe prompt.md to Claude Code                         │
│    2. Claude reads prd.json, finds next story               │
│    3. Claude implements story in agcore codebase            │
│    4. Claude commits, updates prd.json (passes: true)       │
│    5. Claude logs to progress.txt                           │
│    6. Check for <promise>COMPLETE</promise> signal          │
│    7. If not complete, continue to next iteration           │
└─────────────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `ralph.sh` | Main loop script - spawns Claude Code each iteration |
| `prompt.md` | Agent instructions - what Claude does each iteration |
| `prd.json` | User stories with acceptance criteria, priority, pass/fail status |
| `progress.txt` | Cumulative log of completed work + learnings |
| `.last-branch` | Tracks current branch for archiving (auto-generated) |
| `archive/` | Previous runs archived here when branch changes |

## prd.json Structure

```json
{
  "project": "AgCore",
  "branchName": "ralph/eform-system",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a..., I want...",
      "acceptanceCriteria": ["criterion 1", "criterion 2"],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Agent Behavior (per iteration)

1. **Read PRD** - Load prd.json from scripts/ralph/
2. **Check branch** - Checkout/create branch from `branchName`
3. **Pick story** - Highest priority where `passes: false`
4. **Implement** - Make changes to agcore codebase
5. **Quality check** - Run typecheck, lint, tests
6. **Commit** - `feat: [US-XXX] - Story Title`
7. **Update PRD** - Set `passes: true` for completed story
8. **Log progress** - Append to progress.txt with learnings
9. **Check completion** - If all stories pass, output `<promise>COMPLETE</promise>`

## Branch Workflow

- All work happens on the branch specified in `prd.json`
- Changes accumulate on feature branch, not main
- When done, review branch and merge/PR to main
- Changing `branchName` in prd.json triggers auto-archive of previous run

## Archiving

When prd.json's `branchName` changes from previous run:
```
archive/
└── 2026-01-15-eform-system/
    ├── prd.json
    └── progress.txt
```

## Creating a New PRD

1. Edit `prd.json` with new stories and `branchName`
2. Reset or clear `progress.txt`
3. Run `bash scripts/ralph/ralph.sh`

## Stopping Early

- `Ctrl+C` to stop the loop
- Progress is saved - can resume by running again
- Stories with `passes: true` won't be re-implemented

## Requirements

- Git Bash (Windows) or bash shell (Mac/Linux)
- Claude Code CLI installed and authenticated
- `jq` for JSON parsing (used by ralph.sh)
