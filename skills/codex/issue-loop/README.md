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
| `NET_MAX_CYCLES` | `6` | Cycles in a row where `git fetch` fails (after `GH_RETRIES` tries, ~2.5 min) before stopping; one failure only skips that cycle |
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

The handoff is **build → local CI → draft PR → review and fixes → mark ready →
full CI → merge**. `$do-issue` completes the local gate and opens the draft;
`$do-pr` completes review and fixes before marking it ready and waiting for full CI.

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
| `GITHUB UNREACHABLE for N cycles in a row` | 1 | `git fetch` failed `NET_MAX_CYCLES` cycles running; check the network and `git.log` |
| Repeated failures, inconclusive merges, stuck/unmerged PRs | 1 | Read phase logs and GitHub state before restarting |

## Verify the runner

```bash
bash -n ~/.codex/skills/issue-loop/scripts/issue-loop.sh
python3 ~/.codex/skills/issue-loop/scripts/test_issue_loop.py
```

The integration tests use temporary repositories and fake external commands.
They do not build tickets, contact GitHub or mutate the real database.

## Split runners: build loops + one merge loop

`issue-loop.sh` builds, waits and merges in one row, so the builder is idle while
its PR is reviewed. The split runners take the same skills with the same prompts and
divide the work: each **build loop** only builds, and one **merge loop** runs
`$do-pr auto` on every queued PR, one at a time, oldest first. `issue-loop.sh` is
unchanged and stays the fallback.

```bash
# wt1 and wt2: one build loop per worktree, one tracker each
cd ~/Projects/agcore-wt1
~/.codex/skills/issue-loop/scripts/build-loop.sh memory/AgCore/planning/issues/<feature-slug>

# wt3: the one merge loop of this machine (no arguments)
cd ~/Projects/agcore-wt3
~/.codex/skills/issue-loop/scripts/merge-loop.sh
```

Run each in its own herdr tab. Stop each one with `touch .issue-loop-stop` in its
worktree. The before-starting checks above apply to every worktree.

### Build loop cycle

1. Fast-forward the base branch to `origin/main` and check the migration ledger,
   with the same fetch retry and migration rules as `issue-loop.sh`.
2. Count startable tickets. Triage runs only when nothing is startable.
3. Build one ticket with the `issue-loop.sh` build prompt. When the build opens a
   PR, append it to the PR queue and start the next cycle **at once**.
4. Nothing startable: rewrite `NEEDS-HUMAN.md`, wait `CYCLE_MINUTES`, look again.

The loop never calls `$do-pr` and never waits for a PR of its own.

**Merged-blocker rule.** A blocker counts as done only when its `**Triage:**` is
`done`/`wontfix` and it has no PR in `pr-queue.tsv` or `pr-parked.tsv`, or that PR
is `MERGED` on GitHub. The build prompt then gets one more sentence:
`Treat these tickets as NOT done, their PR has not merged: 03-x.md.`
A blocker that merges while the loop waits makes its ticket startable.

**Folder finished** only when nothing is startable, nothing needs triage, and the
queue holds no PR of this tracker. Before it finishes, the loop queues any open PR
that this run built but did not queue.

### Merge loop cycle

1. Queue empty: read the queue file again every `MERGE_POLL_MINUTES`. No GitHub
   call, no git fetch, no agent.
2. Otherwise sync the base branch and DB, then take the queued PR with the
   **fewest attempts, then the oldest `queued_at`**, across all trackers.
3. Check it on GitHub. Already merged or closed: drop the line. Head branch
   differs from the queue: park it. Base is not `main` (stacked on an unmerged
   parent): leave it queued and take the next one.
4. Fetch the branch and check it out (see below), then run `$do-pr auto #N` with
   the same prompt, retry prompt and `merge-attempts-<pr>` counter as `issue-loop.sh`.
5. Read GitHub. **Merged:** drop the line, sync base and DB. **Blocked** (final
   answer has `<<<MERGE_BLOCKED`): park it with the reason. **Inconclusive:** keep
   it; it now has one attempt more, so the other PRs go first. After `MAX_FAILS`
   attempts it is parked. **Closed:** drop the line.
6. Switch back to the base branch and take the next PR at once.

`$do-pr` runs `gh pr checkout` itself, and that works for a branch the worktree
never had. Git refuses a branch that **another worktree of the same repository** has
checked out, which is the state a build loop leaves when it stops right after a
build. The merge loop checks that first and leaves such a PR queued. It also
fetches and checks out the branch before the agent starts.

Several **different** PRs that end inconclusive in a row (`MAX_FAILS` runs) stop the
loop with `REPEATED INCONCLUSIVE MERGES`. That is an agent or machine problem;
parking every PR would empty the queue.

### Shared state

One directory per machine: `LOOP_STATE_DIR` (default `~/.local/state/agcore`).
Every write takes a `flock` and replaces the file with a temp file + `mv`; two
writers at once never lose a line.

| File | Columns (tab-separated, no header) | Writers |
|---|---|---|
| `pr-queue.tsv` | `queued_at` (ISO UTC) · `pr` · `branch` · `tracker` · `ticket(s)` (comma-separated, `-` if unknown) · `worktree` | build loops append; only the merge loop removes |
| `pr-parked.tsv` | the six queue columns · `parked_at` · `reason` | merge loop |
| `loop-metrics.tsv` | `time` · `loop` (`build:<tracker>` or `merge`) · `worktree` · `event` · `pr/ticket` · `seconds` | both |

To re-queue a parked PR after you fixed it, move its line back to `pr-queue.tsv`
with only the first six columns. The build loop lists its tracker's parked PRs in
`NEEDS-HUMAN.md`. The merge loop drops a parked line when GitHub says the PR is
merged or closed.

Metrics events: `build_start`, `build_end:<ok|failed|no_progress|no_work>`, `queued`,
`merge_start`, `merge_end:<merged|blocked|inconclusive|closed>`,
`dequeued:<merged|closed|parked>` (seconds = time since `queued_at`), `idle_start`,
`idle_end` (seconds idle). Print the report:

```bash
~/.codex/skills/issue-loop/scripts/loop-report --since 7d
```

It shows tickets built and merged per day per tracker, build and merge time
(median, p90), queued → merged time, the largest number of waiting PRs and the
share of time with more than 2 waiting, and idle time per loop.

### Locks

| Lock | Path | Shared with |
|---|---|---|
| worktree | `$LOG_DIR/loop.lock` | `issue-loop.sh`, both split runners |
| tracker | `${XDG_CACHE_HOME:-~/.cache}/issue-loop/<tracker>.lock` | `issue-loop.sh`, build loop |
| machine | `${XDG_CACHE_HOME:-~/.cache}/issue-loop/merge-loop.lock` | merge loop only |

`issue-loop.sh` and the split runners refuse each other on one worktree or tracker.
`issue-loop.sh` treats a lock as live only when its owner's command line contains
`issue-loop.sh`, so each split runner restarts itself once with that text in its
process name (`build-loop.sh[issue-loop.sh]`, `merge-loop.sh[issue-loop.sh]`).

### Settings

All `issue-loop.sh` settings above apply with the same defaults: `MAIN_MODEL`,
`MAIN_EFFORT` (build, triage), `PR_MODEL`, `PR_EFFORT` (merge), `MAX_FAILS`,
`NET_MAX_CYCLES`, `GH_RETRIES`, `GH_RETRY_BASE`, `AUTO_MIGRATE`, `MAIN_BRANCH`,
`BASE_BRANCH`, `LOG_DIR`, `STOP_FILE`, `PRETTY_OUTPUT`. Differences:

| Environment variable | Default | Meaning |
|---|---|---|
| `CYCLE_MINUTES` | `30` | Build loop: wait when nothing is startable. Both: wait after a cycle skipped because GitHub was unreachable |
| `MAX_FAILS` | `3` | Build loop: failed cycles in a row. Merge loop: attempts per PR before parking it |
| `MERGE_POLL_MINUTES` | `5` | Merge loop: how often it re-reads an empty queue |
| `LOOP_STATE_DIR` | `~/.local/state/agcore` | Queue, parked and metrics files |

Moving a worktree from `issue-loop.sh` to `build-loop.sh`: the merge loop does not
read `issue-loop-logs/pending-branches`. The build loop warns at start when that
ledger is not empty; merge or queue those PRs by hand.

### Banners

| Banner | Runner | Exit | Action |
|---|---|---|---|
| `BUILD LOOP STARTING — <tracker>` / `MERGE LOOP STARTING — <queue>` | both | – | Start |
| `CYCLE N DONE — next cycle starts now (no merge wait)` | build | – | A build finished |
| `MERGE CYCLE N DONE — next PR starts now` | merge | – | One PR attempted |
| `ALL ISSUES DONE` | build | 0 | Folder worked and every PR of it merged |
| `FOLDER FINISHED FOR AGENTS — N ticket(s) need a human, M PR(s) parked at a gate, K ready ticket(s) still blocked` | build | 2 | Read `NEEDS-HUMAN.md` |
| `STOP REQUESTED` | both | 0 | Requested stop |
| `USAGE LIMIT` | both | 75 | Restart after capacity returns; the queue is kept |
| `DATABASE MIGRATION STATE NEEDS A HUMAN` / `MIGRATION MERGED` | both | 0 | Read `db.log`, apply, restart |
| `PRE-FLIGHT FAILED` | both | 1 | Folder, login, `flock` or lock problem |
| `GIT STATE NEEDS A HUMAN` | both | 1 | Dirty or diverged tree; `$do-pr` left changes |
| `GITHUB UNREACHABLE for N cycles in a row` | both | 1 | Check the network and `git.log` |
| `TOO MANY CONSECUTIVE FAILURES` | build | 1 | Read the build logs |
| `REPEATED INCONCLUSIVE MERGES` | merge | 1 | Several PRs failed in a row; read the merge logs |
| `PR QUEUE WRITE FAILED` | build | 1 | Fix `pr-queue.tsv` permissions, queue the named PR, restart |

### Verify the split runners

```bash
python3 ~/.codex/skills/issue-loop/scripts/test_build_merge_loops.py
```

The tests run both twins (Codex, and Claude with the same fake as `claude`) against
temporary repositories, fake `gh`, agents, `npm` and `sleep`.
