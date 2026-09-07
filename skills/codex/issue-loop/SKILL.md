---
name: issue-loop
description: Run the existing triage, do-issue and do-pr workflows over one tracker folder until no agent-workable tickets remain.
---

# Issue loop

`scripts/issue-loop.sh` is the runner. Each phase starts a fresh `codex exec`
session and invokes `$triage`, `$do-issue`, or `$do-pr auto`. Use the existing
repository instructions and those skills for their development and git workflows.

Start from the worktree that will do the work:

```bash
MAIN_MODEL=gpt-6-astra MAIN_EFFORT=high \
PR_MODEL=gpt-6-astra PR_EFFORT=high CYCLE_MINUTES=30 \
  ~/.codex/skills/issue-loop/scripts/issue-loop.sh \
  memory/AgCore/planning/issues/<feature-slug>
```

The example selects Astra/high for both phases. `MAIN_MODEL` / `MAIN_EFFORT`
control build and triage; `PR_MODEL` / `PR_EFFORT` control merge. An empty or unset
value inherits the current Codex configuration. Model availability and supported
efforts depend on the installed CLI and account; an invalid choice is an error,
never a silent model fallback. No global settings or login files are changed.

The runner uses the current Codex login and unattended development permissions
(full filesystem access for Docker and the external vault, no approval prompts).
Normal Codex configuration, AGENTS.md, skills, MCP servers and exec rules stay
loaded. Claude account variables do not select a Codex account.

## One cycle

1. Fast-forward the worktree base branch to `origin/main`, then check the migration
   ledger. Apply eligible pending migrations only through `npm run db:migrate`.
   Preserve the existing destructive-SQL, baseline and owned-orphan checks.
2. Run `$do-pr auto` for open PRs in this loop's pending-branch ledger. Park a PR
   blocked at a review gate and keep working on other tickets. A remaining queued
   PR prevents starting another build.
3. Build ready tickets first. Only when no `ready-for-agent` tickets remain,
   run `$triage` over this folder's `needs-triage` tickets.
4. `$do-issue` builds one eligible ticket, following satisfied blockers within
   this folder, verifies it, opens a PR, and updates the tracker.
5. Refresh `NEEDS-HUMAN.md`, wait `CYCLE_MINUTES` (default 30), and repeat.

The shell measures progress from ticket state and recorded branches. GitHub
confirms merges. Completion markers are read only from each session's final
answer, never its intermediate narration. Existing no-work markers, retry limits,
final PR sweep, and exit codes remain the runner's stop contract.

## QA and handoff

The final QA ticket reviews the whole implementation. Its follow-up tickets stay
in this folder and are picked up by later cycles. The implementation report and
product decisions remain human-owned and appear in `NEEDS-HUMAN.md`.

The loop drains its remaining PRs before finishing: exit 0 when all work is done;
exit 2 when human-owned tickets or parked PRs remain. Other stop banners identify
migration, git, or repeated phase failures. See [README.md](README.md) for the full
operator reference, logs, locks, and restart commands.

Run one loop per worktree and one per tracker. The worktree has its own Docker
stack and DB. Keep the current PR ledger when restarting. The docs loop owns its
own branches; this runner does not take them.
