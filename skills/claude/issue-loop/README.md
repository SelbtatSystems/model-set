# issue-loop — drive one tracker folder to done

Point it at a folder of issues and it works them all: triages what needs triaging, builds every
`ready-for-agent` ticket, merges each PR, follows up on whatever the closing QA ticket discovers,
and stops when nothing is left for an agent — leaving an implementation report and any open
decisions for you.

All agents are `claude`; you choose the models.

## Run it

```bash
cd ~/Projects/agcore-wt2                                    # one loop per worktree
~/.claude/skills/issue-loop/scripts/issue-loop.sh memory/AgCore/planning/issues/<feature-slug>
```

Run it inside **herdr** (see `memory/_cheat-sheets/herdr.md`) — the loop dies with its terminal otherwise.

Stop it gracefully from another terminal:

```bash
cd ~/Projects/agcore-wt2 && touch .issue-loop-stop
```

It finishes the phase it is in (never mid-merge) and exits. Ctrl-C is a hard stop.

### Coordinator models and accounts

```bash
# Opus builds, triages and coordinates bounded reviews and merges
~/.claude/skills/issue-loop/scripts/issue-loop.sh <folder>

# Fable builds, Opus merges, both at high effort
MAIN_MODEL=fable ~/.claude/skills/issue-loop/scripts/issue-loop.sh <folder>

# Same models, merge phase on the second account
PR_CONFIG_DIR=~/.claude-max-2 \
  ~/.claude/skills/issue-loop/scripts/issue-loop.sh <folder>
```

Coordinators run on `MAIN_MODEL` / `PR_MODEL` (default Opus; `fable` works too). Helpers keep
the model in their agent file, whatever the coordinator runs on: code research on Sonnet 5.5
high (`code-researcher`), browser checks on Sonnet 5.5 high (`frontend-review`), CI waits on
Haiku (`ci-waiter`). `do-pr` picks the code reviewer by risk tier — low: Sonnet high, medium:
Opus medium, high: Opus high — and always runs the Opus high security reviewer. Reviewers do
not delegate. The runner clears the blanket subagent-model environment override so each role
keeps its model.
No nested reviewer trees.

### Before the first run

- Worktree on a **plain branch** (not a leftover feature branch with unmerged commits) and a
  **clean** working tree — the loop fast-forwards to `origin/main` each cycle.
- That worktree's **Docker stack up** and its **DB current** on `db/migrations/`.
- `gh` authenticated and `claude` on PATH.
- The folder must contain tickets with `**Triage:**` lines (the local markdown tracker format).

## One cycle

```
1. SYNC     ff this worktree's branch to origin/main
2. MERGE    for each PR this loop opened earlier → claude /do-pr auto #N
3. TRIAGE   any needs-triage tickets in the folder → claude $triage
4. BUILD    lowest-numbered ready-for-agent ticket whose blockers are satisfied → claude $do-issue
5. WAIT     CYCLE_MINUTES, then repeat
```

The folder's own `**Triage:**` lines decide what happens — the script counts them itself, so no
agent can misreport progress. It only merges PRs from branches **it recorded**
(`issue-loop-logs/pending-branches`), so it never touches the docs loop's or your own PRs.

### Triage behaviour

`needs-triage` tickets get a triage pass first: requirements met and agent-buildable →
`ready-for-agent` (built in the same cycle); not met → `ready-for-human` or `needs-info` with a
dated one-line reason on the ticket.

### The QA ticket closes the folder

`to-issues` ends every published set with a **QA — full implementation review** ticket, blocked by
all the others so it runs last. It drives the finished feature in the browser, checks every
acceptance criterion of every ticket in the folder against the running app, patches small defects
in place, and files what it cannot fix as **new tickets in the same folder** —
`ready-for-agent` for agent-buildable work, `ready-for-human` for product/design calls — then
writes the **implementation report** as a `ready-for-human` ticket.

The loop needs no special handling for that: those follow-ups are just more tickets, so it keeps
cycling until no `ready-for-agent` ticket remains.

### How you find out what needs you

`<folder>/NEEDS-HUMAN.md` — rewritten every cycle, in two sections: **PRs parked at a review gate**
and **tickets waiting on a person** (`ready-for-human` / `needs-info`). Deleted automatically once
nothing is waiting.

### A blocked PR does not stop the loop

When `/do-pr` blocks a PR at its review gate, the loop **parks** it rather than exiting: the branch is
dropped from `pending-branches` so it stops being retried, the PR is listed in `NEEDS-HUMAN.md`, and
the loop moves on to the next buildable ticket. Nothing is closed or discarded — the PR and its branch
are left exactly as they are.

To resume a parked PR after you have fixed or re-scoped it, put its branch back:

```bash
echo <branch> >> issue-loop-logs/pending-branches
```

The trade-off is deliberate: blocked work accumulates while you are away instead of halting the whole
folder. `NEEDS-HUMAN.md` is the thing to read when you come back.

## Knobs

| Env | Default | Meaning |
|---|---|---|
| `MAIN_MODEL` | `opus` | build + triage coordinators; any `claude --model` value, e.g. `fable` |
| `PR_MODEL` | `opus` | merge coordinator |
| `MAIN_EFFORT` / `PR_EFFORT` | `high` | `--effort` per phase; set it empty to let `settings.json` decide |
| `AGENT_COMPACT_WINDOW` | `400000` | context size at which a session compacts (`CLAUDE_CODE_AUTO_COMPACT_WINDOW`); empty = CLI default |
| `MAIN_CONFIG_DIR` / `PR_CONFIG_DIR` | `~/.claude` | Claude account per phase, e.g. `~/.claude-max-2` |
| `CYCLE_MINUTES` | `30` | wait between cycles |
| `MAX_FAILS` | `3` | consecutive failed/stalled cycles before stopping |
| `NET_MAX_CYCLES` | `6` | cycles in a row where `git fetch` fails (after `GH_RETRIES` tries, ~2.5 min) before stopping; one failure only skips that cycle |
| `MAIN_BRANCH` | `main` | branch PRs target |
| `BASE_BRANCH` | *(current HEAD)* | the worktree branch to run on |
| `AUTO_MIGRATE` | `1` | apply **non-data-destroying** merged migrations to this worktree's DB and carry on; `0` = always stop for you |
| `LOG_DIR` | `./issue-loop-logs` | per-run logs (incl. `db.log`) + the pending-branch state file |
| `STOP_FILE` | `.issue-loop-stop` | graceful-stop flag (independent of other loops) |
| `PRETTY_OUTPUT` | `1` | condensed screen trace (tool + file + thinking); `0` shows the raw agent stream |

## What you see while it runs

The screen shows one line per action, not the full agent stream:

```
agent claude-opus-5 in /home/sven/Projects/agcore-wt4
  → Read memory/AgCore/planning/issues/<slug>/03-rls-employments.md
  · Checking whether the policy already exists before adding it
  → Edit db/migrations/20260731_force_rls_employments.sql
  → Bash npm run typecheck
done Opened PR #731  [37 turns $2.14]
```

File contents, command output and diffs are omitted here but written in full to
`issue-loop-logs/`. Set `PRETTY_OUTPUT=0` for the raw stream.

## When it stops

| Banner | Exit | What to do |
|---|---|---|
| `ALL ISSUES DONE` | 0 | Folder fully worked, follow-ups included. |
| `FOLDER FINISHED FOR AGENTS — N ticket(s) need a human, M PR(s) parked` | 2 | Read `NEEDS-HUMAN.md`: parked PRs, the implementation report, and any decisions left to you. |
| `STOP REQUESTED` | 0 | You asked for it. |
| `MIGRATION PULLED` / `MERGED` | 0 | The migration could destroy local dev data (`DROP TABLE/COLUMN/SCHEMA`, `TRUNCATE`, `DELETE FROM`, column-type rewrite, rename), or it failed to apply (see `db.log`). Apply it yourself, then restart. Everything else — including `DROP POLICY`/`FUNCTION`/`INDEX` and `DROP MATERIALIZED VIEW` (derived rows its own refresh rebuilds; it cannot be altered in place) — applies automatically and never stops the loop. |
| `PRE-FLIGHT FAILED` | 1 | Usually a bad folder path, a dirty tree, or a tracker with no `**Triage:**` lines. |
| `GIT STATE NEEDS A HUMAN` | 1 | Diverged branch or uncommitted work. Resolve, restart. |
| `GITHUB UNREACHABLE for N cycles in a row` | 1 | `git fetch` failed `NET_MAX_CYCLES` cycles running (~3 h at 30 m). Check the network and `git.log`, restart. |
| `REPEATED INCONCLUSIVE MERGES` | 1 | Merge agent gave up 3×. Inspect the incomplete gate before restarting. |
| `TOO MANY CONSECUTIVE FAILURES` | 1 | See below. |

**"No progress" warnings** mean the build agent opened no PR and closed no ticket. The usual cause
is that every remaining `ready-for-agent` ticket still has an open `**Blocked by:**` — check those
lines. Three in a row stops the loop rather than spinning.

## Design notes

- **Progress is measured, not claimed**: a cycle counts as progress only if a new PR branch appeared
  or a ticket left `ready-for-agent`. GitHub decides whether a PR merged, not the agent's output.
- **Only its own PRs**: after each build the loop writes the branch it just produced into
  `issue-loop-logs/pending-branches`, and the merge phase only ever looks up PR numbers for
  branches in that ledger — so the docs loop's PRs, your manual PRs, and other worktrees' PRs are
  invisible to it. The branch is dropped from the ledger once GitHub confirms the merge (or the PR
  is gone). If a build agent pushes and switches back to the base branch, the loop falls back to
  adopting a PR that appeared during that build window — but only if **exactly one** did and it is
  not in the docs loop's `documentation/*` namespace; otherwise it lists them and leaves them to
  you. Deleting `issue-loop-logs/` makes the loop forget pending PRs — merge those by hand.
- **State counting uses `grep`, not `rg`** — `rg` is a shell-level alias here and is not on a bash
  script's PATH.
- **One loop per worktree**: each worktree has its own Docker stack and DB; two loops in one
  worktree would fight over both.

## Split runners: build loops + one merge loop

`issue-loop.sh` builds, waits and merges in one row, so the builder is idle while
its PR is reviewed. The split runners take the same skills with the same prompts and
divide the work: each **build loop** only builds, and one **merge loop** runs
`/do-pr auto` on every queued PR, one at a time, oldest first. `issue-loop.sh` is
unchanged and stays the fallback.

```bash
# wt1 and wt2: one build loop per worktree, one tracker each
cd ~/Projects/agcore-wt1
~/.claude/skills/issue-loop/scripts/build-loop.sh memory/AgCore/planning/issues/<feature-slug>

# wt3: the one merge loop of this machine (no arguments)
cd ~/Projects/agcore-wt3
~/.claude/skills/issue-loop/scripts/merge-loop.sh
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

The loop never calls `/do-pr` and never waits for a PR of its own.

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
4. Fetch the branch and check it out (see below), then run `/do-pr auto #N` with
   the same prompt, retry prompt and `merge-attempts-<pr>` counter as `issue-loop.sh`.
5. Read GitHub. **Merged:** drop the line, sync base and DB. **Blocked** (final
   answer has `<<<MERGE_BLOCKED`): park it with the reason. **Inconclusive:** keep
   it; it now has one attempt more, so the other PRs go first. After `MAX_FAILS`
   attempts it is parked. **Closed:** drop the line.
6. Switch back to the base branch and take the next PR at once.

`/do-pr` runs `gh pr checkout` itself, and that works for a branch the worktree
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
~/.claude/skills/issue-loop/scripts/loop-report --since 7d
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

All `issue-loop.sh` knobs above apply with the same defaults: `MAIN_MODEL` / `PR_MODEL`
(Opus), `AGENT_COMPACT_WINDOW`, `MAIN_EFFORT` / `MAIN_CONFIG_DIR` (build, triage), `PR_EFFORT` / `PR_CONFIG_DIR`
(merge; both accounts default to `~/.claude`), `MAX_FAILS`, `NET_MAX_CYCLES`,
`GH_RETRIES`, `GH_RETRY_BASE`, `AUTO_MIGRATE`, `MAIN_BRANCH`, `BASE_BRANCH`, `LOG_DIR`,
`STOP_FILE`, `PRETTY_OUTPUT`. Differences:

| Environment variable | Default | Meaning |
|---|---|---|
| `CYCLE_MINUTES` | `30` | Build loop: wait when nothing is startable. Both: wait after a cycle skipped because GitHub was unreachable |
| `MAX_FAILS` | `3` | Build loop: failed cycles in a row. Merge loop: attempts per PR before parking it |
| `MERGE_POLL_MINUTES` | `2` | Merge loop: how often it re-reads an empty queue |
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
| `GIT STATE NEEDS A HUMAN` | both | 1 | Dirty or diverged tree; `/do-pr` left changes |
| `GITHUB UNREACHABLE for N cycles in a row` | both | 1 | Check the network and `git.log` |
| `TOO MANY CONSECUTIVE FAILURES` | build | 1 | Read the build logs |
| `REPEATED INCONCLUSIVE MERGES` | merge | 1 | Several PRs failed in a row; read the merge logs |
| `PR QUEUE WRITE FAILED` | build | 1 | Fix `pr-queue.tsv` permissions, queue the named PR, restart |

### Verify the split runners

```bash
python3 ~/.codex/skills/issue-loop/scripts/test_build_merge_loops.py
```

The suite lives in the Codex tree and runs both twins (Codex, and Claude with the same fake as `claude`) against
temporary repositories, fake `gh`, agents, `npm` and `sleep`.
