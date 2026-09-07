# issue-loop — drive one tracker folder to done

The runner starts fresh Codex sessions for `$triage`, `$do-issue` and `$do-pr auto`.
The existing skills own their git, implementation, verification and merge steps.
The shell owns scheduling, PR ownership, progress checks and stopping.

## Start

```bash
cd ~/Projects/agcore-wt2
MAIN_MODEL=gpt-6-astra MAIN_EFFORT=high \
PR_MODEL=gpt-6-astra PR_EFFORT=high CYCLE_MINUTES=30 \
  ~/.codex/skills/issue-loop/scripts/issue-loop.sh \
  memory/AgCore/planning/issues/<feature-slug>
```

Choose any model available to your Codex account and an effort that model and CLI
support. The example selects Astra/high. Omit any model or effort override to use
your current Codex configuration. No global configuration is changed. An invalid
choice fails; it is never replaced with another model.

Run in a persistent **herdr** terminal (`memory/_cheat-sheets/herdr.md`) so the loop
survives closing the client. Use one loop per worktree and per tracker folder.

Before starting:

- The worktree must be clean and on its own base branch that can fast-forward to
  `origin/main`. Preserve unfinished feature work on its branch.
- Its Docker stack must be running, with a separate DB volume.
- `gh` and `codex` must be on PATH and authenticated (`codex login status`).
- The tracker must contain Markdown tickets with `**Triage:**` lines.

## Settings

| Environment variable | Default | Meaning |
|---|---|---|
| `MAIN_MODEL` | Codex configuration | Build and triage model |
| `MAIN_EFFORT` | Codex configuration | Build and triage reasoning effort |
| `PR_MODEL` | Codex configuration | Review and merge model |
| `PR_EFFORT` | Codex configuration | Review and merge reasoning effort |
| `CYCLE_MINUTES` | `30` | Wait between cycles |
| `MAX_FAILS` | `3` | Consecutive failures or stalls before stopping |
| `MAIN_BRANCH` | `main` | Integration branch |
| `BASE_BRANCH` | Current branch | This worktree's base branch |
| `AUTO_MIGRATE` | `1` | Apply eligible ledger-pending migrations; `0` hands pending work to a human |
| `LOG_DIR` | `./issue-loop-logs` | Streams, command logs and PR state |
| `STOP_FILE` | `.issue-loop-stop` | Graceful stop flag |
| `PRETTY_OUTPUT` | `1` | Condensed terminal trace; `0` shows raw events |

The current Codex login/configuration is used. `MAIN_CONFIG_DIR`, `PR_CONFIG_DIR`
and `CLAUDE_CONFIG_DIR` belonged to the Claude runner and do not select Codex
accounts. The runner uses `--sandbox danger-full-access -c approval_policy=never`
for the existing unattended Docker/vault workflow. It keeps normal user/project
configuration, tools and exec rules loaded.

## Cycle and git workflow

1. Fast-forward the base branch to `origin/main`. Dirty or diverged work stops
   for a human; the loop does not discard it.
2. Check the migration ledger. Apply eligible pending migrations through
   `npm run db:migrate`, then recheck. Never execute SQL files directly. Missing
   baseline, unknown orphans, destructive SQL or a failed check stops the loop.
   Orphans traced to this loop's pending branches retain the existing treatment.
3. Drain this loop's recorded PRs through `$do-pr auto #N`. GitHub confirms
   whether each merged. Review-blocked PRs are parked; unknown results are retried.
   A PR targeting an unmerged parent stays queued. New builds wait while the
   ledger has pending PRs.
4. If no ticket is ready, triage this folder's `needs-triage` tickets. Build-ready
   work takes priority over triage. Requirements that need a person become
   `ready-for-human` or `needs-info`, with a dated reason.
5. Build one eligible ticket through `$do-issue`, including checks, PR creation
   and tracker update. Follow blocker chains only within the selected folder.
6. Update `NEEDS-HUMAN.md`, wait, and repeat.

Progress means a new recorded PR branch or a ticket leaving `ready-for-agent`.
The existing `<<<NO_OPEN_ISSUES>>>` final answer takes the final-drain path. Other
runs without measurable progress count toward `MAX_FAILS`.

PR ownership comes from the branch left checked out, with this worktree's HEAD
reflog as the fallback when the agent switches back. The final sweep covers only
branches visited during this run. Other worktrees' PRs are not adopted. Preserve
`pending-branches` across restarts: deleting it loses the ownership record.

The last QA ticket checks the whole feature. New buildable follow-ups stay in
this folder and run on later cycles. Its implementation report and human decisions
remain listed in `NEEDS-HUMAN.md`.

## Logs and recovery

| File under `LOG_DIR` | Meaning |
|---|---|
| `build-*.log`, `triage-*.log`, `merge-*.log` | Raw Codex JSONL plus stderr |
| `<phase-log>.final.txt` | That session's final answer only |
| `pending-branches` | Branches owned by this loop and awaiting merge |
| `parked-prs` | PRs blocked at a review gate |
| `merge-attempts-<pr>` | Retry count for one PR |
| `git.log`, `gh.log`, `db.log` | Git, GitHub and migration command output |
| `loop.lock` | Worktree loop owner |

A tracker lock also lives under `${XDG_CACHE_HOME:-$HOME/.cache}/issue-loop`.
A refused duplicate start must leave the running owner's locks intact.

The terminal renderer already supports Codex `thread.*`, `turn.*` and `item.*`
events. It condenses tool actions and messages; raw streams retain command output
and diffs. Codex token usage is not a Claude subscription cost estimate.

Read the `.final.txt` file for the verdict. A missing final answer is inconclusive:
inspect the error events, process and exit status. Do not infer a crash from the
absence of a Claude `result` event. Intermediate mentions of a completion marker
are not final verdicts.

A parked PR stays open with its branch intact. Resolve the gate, then requeue it:

```bash
printf '%s\n' 'feature/example-branch' >> issue-loop-logs/pending-branches
```

## Stop and restart

From the worktree:

```bash
touch .issue-loop-stop
```

The loop finishes the current phase and exits at the next stop check. Ctrl-C is
a hard stop. Before restarting, verify its process ended, inspect any unfinished
work, return to the base branch, and keep the same tracker, settings and state.

| Result/banner | Exit | Action |
|---|---|---|
| `ALL ISSUES DONE` | 0 | Feature and follow-ups finished |
| `FOLDER FINISHED FOR AGENTS` | 2 | Read human tickets and parked PRs in `NEEDS-HUMAN.md` |
| `STOP REQUESTED` | 0 | Requested graceful stop |
| Migration state needs a human | 0 | Read `db.log`; use the repository ledger procedure, then restart |
| `PRE-FLIGHT FAILED` | 1 | Fix the reported folder, login or lock problem |
| `GIT STATE NEEDS A HUMAN` | 1 | Resolve dirty or diverged work without discarding it |
| Repeated failures, inconclusive merges, stuck/unmerged PRs | 1 | Read phase logs and GitHub state before restarting |

## Verify the runner

```bash
bash -n ~/.codex/skills/issue-loop/scripts/issue-loop.sh
python3 ~/.codex/skills/issue-loop/scripts/test_issue_loop.py
```

The integration tests use temporary repositories and fake external commands.
They do not build tickets, contact GitHub or mutate the real database.
