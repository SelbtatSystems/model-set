---
name: issue-loop
description: Ralph loop that drives one tracker folder to done — triage needs-triage tickets, build every ready-for-agent ticket via do-issue, merge each resulting PR via do-pr, and surface ready-for-human tickets in NEEDS-HUMAN.md. Use when the user wants a folder of issues worked autonomously ("run the issue loop on <folder>").
disable-model-invocation: true
---

# Issue Loop

A runner script, not an agent playbook: `scripts/issue-loop.sh` orchestrates the existing
`triage`, `do-issue`, and `do-pr` skills over **one tracker folder** until nothing in it is left
for an agent. Start it from the repo root of the worktree that should do the work:

```bash
~/.claude/skills/issue-loop/scripts/issue-loop.sh memory/AgCore/planning/issues/<feature-slug>
```

## Model knobs (per loop instance, nothing global)

| Env | Default | Meaning |
|---|---|---|
| `MAIN_MODEL` | `opus` (fixed) | build coordinator (`do-issue`) and triage coordinator; environment overrides are ignored |
| `PR_MODEL` | `opus` (fixed) | merge coordinator (`do-pr`); environment overrides are ignored |
| `MAIN_CONFIG_DIR` / `PR_CONFIG_DIR` | `$HOME/.claude` | `CLAUDE_CONFIG_DIR` per phase, e.g. `$HOME/.claude-max-2` |
| `CYCLE_MINUTES` | `30` | wait between cycles |

Build, triage and merge coordinators always use Opus. Helpers use Opus at high
effort; only frontend/browser reviews use Sonnet 5.5. `do-pr` uses one Opus
code/spec/standards reviewer and one independent Opus security reviewer, plus
a Sonnet 5.5 browser reviewer when needed. Reviewers do not delegate. The runner
clears the blanket subagent-model environment override so each role keeps its model.

A usage-limit result stops the runner immediately with pending work retained.
Restart after capacity returns. Retry reuses only completed reports matching
both current base and head SHAs; it never assumes a previous review passed.

## What one cycle does

1. Resolve the worktree root, sync its branch ff-only to origin/main, then run the repository's
   migration-ledger check. Ledger-pending migrations are safety-scanned and non-destructive ones
   are applied through `npm run db:migrate`; destructive SQL, a missing one-time baseline, or a
   failed ledger check stops for a human. The loop never executes SQL files directly and ignores
   inert `db/migrations/pre-launch/` history.
2. Merge any open PR this loop previously created (`do-pr auto`, tracked by branch in a state
   file — other pipelines' PRs are never touched).
3. Count the folder's `**Triage:**` lines:
   - `needs-triage` present → run the `triage` skill over the folder (requirements met →
     `ready-for-agent`; not met → `ready-for-human` / `needs-info` with a reason).
   - `ready-for-agent` present → `do-issue` builds the lowest-numbered ticket whose blockers are
     satisfied, from this folder only, and opens a PR.
   - neither → drain remaining PRs and stop: **all-done** (exit 0), or **NEEDS HUMAN** (exit 2)
     when `ready-for-human`/`needs-info` tickets remain.

   Progress is *measured* (a new PR branch, or a ticket leaving `ready-for-agent`), not taken on
   the agent's word — so a refusal ("every remaining ticket is blocked") counts as a stalled cycle
   and stops the loop after `MAX_FAILS` rather than spinning.
4. Every cycle rewrites `<folder>/NEEDS-HUMAN.md` — the standing list of tickets waiting on a
   person (deleted when empty).

## The QA slice closes the folder

`to-issues` publishes every set with a final **QA — full implementation review** ticket, blocked by
all the others, so it runs last. It drives the finished feature in the browser, checks every
acceptance criterion of every ticket in the folder, patches small defects in place, and files what
it can't fix as **new issues in the same folder** — `ready-for-agent` for agent-buildable work,
`ready-for-human` for product/design calls — plus the **implementation report** as a
`ready-for-human` issue.

The loop needs no special handling for any of that: those follow-ups are just more tickets in the
folder, so it keeps cycling (triage → build → merge) until no `ready-for-agent` ticket is left,
then stops — leaving the report and any open decisions listed in `NEEDS-HUMAN.md`.

Run one loop per worktree (each has its own Docker stack + DB). Safe next to the docs loop:
this loop merges only branches it recorded; the docs loop merges only `documentation/*`.
