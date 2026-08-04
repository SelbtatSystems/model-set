# issue-loop — drive one tracker folder to done

Point it at a folder of issues and it works them all: triages what needs triaging, builds every
`ready-for-agent` ticket, merges each PR, follows up on whatever the closing QA ticket discovers,
and stops when nothing is left for an agent — leaving an implementation report and any open
decisions for you.

All agents are `claude`; you choose the models.

## Run it

```bash
cd ~/Projects/agcore-wt2                                    # one loop per worktree
~/.codex/skills/issue-loop/scripts/issue-loop.sh memory/AgCore/planning/issues/<feature-slug>
```

Run it inside **herdr** (see `memory/_cheat-sheets/herdr.md`) — the loop dies with its terminal otherwise.

Stop it gracefully from another terminal:

```bash
cd ~/Projects/agcore-wt2 && touch .issue-loop-stop
```

It finishes the phase it is in (never mid-merge) and exits. Ctrl-C is a hard stop.

### Choosing models

```bash
# default: Fable builds + triages, Opus reviews and merges
~/.codex/skills/issue-loop/scripts/issue-loop.sh <folder>

# Opus everywhere
MAIN_MODEL=opus ~/.codex/skills/issue-loop/scripts/issue-loop.sh <folder>

# Fable builds, Sonnet merges, merge phase on the second account
PR_MODEL=sonnet PR_CONFIG_DIR=~/.claude-max-2 \
  ~/.codex/skills/issue-loop/scripts/issue-loop.sh <folder>
```

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
| `MAIN_MODEL` | `fable` | build + triage agent |
| `PR_MODEL` | `opus` | merge agent |
| `MAIN_CONFIG_DIR` / `PR_CONFIG_DIR` | `~/.claude-max-2` | Claude account per phase, e.g. `~/.claude-max-2` |
| `CYCLE_MINUTES` | `30` | wait between cycles |
| `MAX_FAILS` | `3` | consecutive failed/stalled cycles before stopping |
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
| `REPEATED INCONCLUSIVE MERGES` | 1 | Merge agent gave up 3×. Merge by hand, or try `PR_MODEL=opus`. |
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
