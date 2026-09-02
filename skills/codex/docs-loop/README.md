# docs-loop — autonomous documentation sweep

Writes the whole AgCore documentation set, one section per cycle, and merges its own PRs. Two fresh
Codex runs take turns: **GPT-5.6 Sol at medium effort** writes a section, then **GPT-5.6 Luna at
high effort** independently reviews and merges its PR. A queue file in the vault is the memory, so
the loop survives restarts.

## Run it

```bash
cd ~/Projects/agcore-wt3          # any worktree; it uses that worktree's Docker stack + DB
~/.codex/skills/docs-loop/scripts/docs-loop.sh
```

For one verification cycle, run
`MAX_CYCLES=1 ~/.codex/skills/docs-loop/scripts/docs-loop.sh`.

Run it inside **herdr** (see `memory/_cheat-sheets/herdr.md`) — the loop dies with its terminal otherwise.

Stop it gracefully from another terminal:

```bash
cd ~/Projects/agcore-wt3 && ./scripts/stop-loop
```

It finishes the phase it is in (never mid-merge) and exits. Ctrl-C is a hard stop.

### Before the first run

- The worktree must be on a **plain branch**, not a `documentation/*` unit branch — the loop
  fast-forwards its branch to `origin/main` each cycle, which an unmerged unit branch cannot do.
  Convention: `git switch -c docs-loop-base origin/main`.
- Working tree must be **clean** (the loop refuses to touch uncommitted work).
- The worktree's **Docker stack must be up** (`dc up -d`) — every claim gets verified in a browser.
- The worktree's **DB must be current** on `db/migrations/`.
- Needs `gh` authenticated, `codex`, and ImageMagick (`convert`) on PATH.

## One cycle

```
1. SYNC     ff this worktree's branch to origin/main
2. MERGE    if a documentation/* PR is open → Luna $do-pr auto #N  (review, gate, merge)
3. SCAN     codex maps origin/main changes into the maintenance ledger
4. BUILD    codex $docs-loop → ONE coverage, feature, stale-page, screenshot, or prose unit
5. WAIT     CYCLE_MINUTES, then repeat
```

Invariant: **at most one open `documentation/*` PR at a time.** Other branches (`feature/*`,
`fix/*`) are invisible to this loop — they belong to you or another loop.

### The work queue

`memory/AgCore/planning/docs-coverage/QUEUE.md` — one row per unit, statuses
`todo → in-progress → published | blocked | skip`. Built on the first ever run by deriving the
app surface from the route table, nav config, settings registry and docs registry, so coverage is
complete by construction. The last row is a **coverage audit** that re-derives that list and
appends anything missed — the loop only reports complete after an audit that finds nothing.

Edit the queue by hand any time (it is a plain markdown table): reorder rows, flip a `blocked` row
back to `todo`, add a row. The loop re-reads it every cycle.

### The quality backlog

`memory/AgCore/planning/docs-coverage/issues/` — one file per documentation defect or gap, same
format and `**Triage:**` roles as every other AgCore tracker. The queue asks "is every surface
documented at all"; the backlog asks "is what we published any good". Critique passes write it,
build runs consume it, and you can drop an issue in by hand any time.

### The maintenance ledger

`memory/AgCore/planning/docs-coverage/MAINTENANCE.md` inventories every live page, every
screenshot-bearing page, and every folder physically present in `planning/user-docu/`. Each cycle
compares its last scanned commit with `origin/main`, marks affected pages for review, then alternates
between shipped-feature reconciliation and exhaustive page review. The filesystem is the feature
queue; a missing row in `user-docu/README.md` cannot hide a folder.

### What it does when coverage is complete

Coverage finishing starts the maintenance rotation. The feature lane reads one complete
`planning/user-docu/` record, including root tickets and implementation comments, and verifies that
its PRs reached `origin/main`. The page lane takes the oldest stale or never-reviewed page, checks
its prose and screenshots against Docker, and runs every changed page through the humanizer before
the factual recheck. The lanes alternate so neither backlog can starve.

Only after every page and feature row is current at the same commit does the loop run a final reader
journey. Two consecutive journeys with nothing to file stop it with `DOCS SATURATED`.

### What each unit does

Reads the complete relevant feature record, verifies merged behaviour against the running app,
compares every embedded image with the current screen, captures replacements with ImageMagick,
writes and humanizes the pages without changing their facts, runs the full local gate (typecheck ·
lint · test · build), then opens a PR. Public pages go to **agcore-landing** (prospect-level
orientation + SEO, per landing ADR 0001); detailed pages go to the gated **agcore-web** hub.

## Knobs

All optional, set on the command line: `MERGE_MODEL=gpt-5.6-sol ~/.codex/.../docs-loop.sh`

| Env | Default | Meaning |
|---|---|---|
| `CYCLE_MINUTES` | `15` | wait between cycles |
| `MAX_CYCLES` | `0` | stop after this many completed cycles; `0` runs continuously |
| `DOCS_MODEL` | `gpt-5.6-sol` | codex model for the writer |
| `DOCS_EFFORT` | `medium` | codex reasoning effort |
| `MERGE_MODEL` | `gpt-5.6-luna` | Codex model for the independent merge review |
| `MERGE_EFFORT` | `high` | reasoning effort for the merge review |
| `MAIN_BRANCH` | `main` | branch PRs target |
| `BASE_BRANCH` | *(current HEAD)* | the worktree branch to run on |
| `MAX_DOCS_FAILS` | `3` | consecutive non-publish cycles before stopping |
| `MAX_SATURATIONS` | `2` | consecutive critique passes finding nothing before the loop stops |
| `AUTO_MIGRATE` | `1` | apply **non-data-destroying** pulled migrations to this worktree's DB and carry on; `0` = always stop for you |
| `LOG_DIR` | `${XDG_STATE_HOME:-$HOME/.local/state}/agcore/docs-loop-logs` | per-run logs (`docs-*.log`, `merge-*.log`, `*.final.txt`, `git.log`, `gh.log`, `db.log`). Lives **outside the vault and the repo**: a raw run stream captures API keys, DSNs with passwords and JWTs, and the vault syncs to the owner's server. Machine-local state, never synced, never committed. |
| `KEEP_RUNS` | `20` | at startup, delete all but the newest N `docs-*.log` and `merge-*.log`. `0` keeps everything. Sentinels and `git/gh/db.log` are never pruned. |
| `PRETTY_OUTPUT` | `1` | condensed screen trace (tool + file + thinking); `0` shows the raw agent stream |

The writer defaults to GPT-5.6 Sol at medium effort. The independent merger defaults to GPT-5.6
Luna at high effort. Override them per run with `DOCS_MODEL` / `DOCS_EFFORT` and `MERGE_MODEL` /
`MERGE_EFFORT`.

## What you see while it runs

One line per action rather than the full agent stream:

```
agent codex
  » I'll verify the kiosk surface before writing the page.
  → Bash docker compose --env-file ../../.env up -d agcore-web
  → Bash convert raw-01.png -crop 900x600+80+120 +repage … 02-clock-on.png
done <<<DOCS_PUBLISHED h-kiosk-field>>>  [41k output tokens]
```

Full streams stay outside the vault at `~/.local/state/agcore/docs-loop-logs/` — they capture secrets (API keys, DSNs with passwords, JWTs), so they must never sync or be committed. Set `PRETTY_OUTPUT=0` for the raw view.

## When it stops

Every stop prints a banner. Exit 0 = fine, 1 = needs you.

| Banner | What to do |
|---|---|
| `DOCS QUEUE COMPLETE` | Coverage, maintenance, feature, and backlog work are clear. Review any `blocked` rows. |
| `DOCS SATURATED` | Every ledger row is current and two final reader journeys found nothing worth filing. Give it work or leave it stopped. |
| `STOP REQUESTED` | You asked for it. Restart when ready. |
| `MAX CYCLES REACHED` | The requested finite run completed normally. |
| `MIGRATION PULLED` / `MERGED` | The migration could destroy local data (or failed to apply). Apply it to this worktree's DB yourself — see `db.log` — then restart. |
| `PRE-FLIGHT FAILED` | Read the lines above it — usually HEAD on a unit branch, or a dirty tree. |
| `GIT STATE NEEDS A HUMAN` | Branch diverged or uncommitted work present. Resolve, restart. |
| `INVARIANT BROKEN — N open documentation/* PRs` | Two docs PRs exist; merge or close one, restart. |
| `PR #N BLOCKED at a gate` | A real review/CI/security failure. Read the PR comment. |
| `REPEATED INCONCLUSIVE MERGES` | The merge agent gave up 3× on one PR. Inspect its logs or retry with `MERGE_MODEL=gpt-5.6-sol`. |
| `TOO MANY NON-PUBLISHED CYCLES` | 3 blocked/failed units in a row. Check the queue's blocked reasons. |

A single **blocked unit does not stop the loop** — the row gets a reason and the loop moves on.

## Design notes (why it is built this way)

- **No agent state is trusted.** GitHub decides whether a PR merged, git decides what code exists,
  the queue file decides what work remains. Agents only report; the script verifies.
- **Sentinels** (`<<<DOCS_PUBLISHED unit>>>`, `<<<DOCS_BLOCKED unit reason>>>`,
  `<<<DOCS_CRITIQUE_FILED n>>>`, `<<<DOCS_ARCHIVED slug>>>`, `<<<DOCS_SATURATED>>>`,
  `<<<DOCS_COMPLETE>>>`) are how agents talk to the script. The docs phase reads the sentinel from
  codex's **final-message file** (`-o *.final.txt`), so the prompt echo can never be mistaken for a
  result. The merge phase uses its own Codex final-message file, leads with the GitHub state check,
  and consults sentinels only for the not-merged outcomes.
- **One unit per cycle** keeps each agent inside a fresh context and makes any failure cheap.
- **Migrations are classified, not trusted.** Each worktree has its own database, so a migration
  merged elsewhere would otherwise leave this one lagging — and a lagging DB makes the app fail
  *silently* (a missing column returns nothing rather than erroring), which is exactly the state a
  documentation writer must never work from.

  The loop is not *approving* the migration — it merged through the review gate already. It is
  syncing this worktree's dev DB to code that is on main. So the only thing worth stopping for is
  what would irreversibly destroy **local dev data**: `DROP TABLE/COLUMN/SCHEMA/DATABASE/SEQUENCE/
  VIEW/TYPE/EXTENSION/ROLE/USER`, `TRUNCATE`, `DELETE FROM`, a column type rewrite, or a rename.
  Everything else applies and the loop carries on — including `DROP POLICY`, `DROP FUNCTION`,
  `DROP INDEX`, `DROP TRIGGER` and `DROP CONSTRAINT`, which lose no rows and are the ordinary shape
  of a policy rewrite.

  `DROP MATERIALIZED VIEW` is exempt too (since 2026-08-02). A matview holds only derived rows that
  its own refresh rebuilds, and Postgres cannot alter one in place — drop-and-recreate is the only
  way to redefine it. Treating that as data loss took every loop on the fleet down over a single
  matview redefinition. A plain `DROP VIEW` still stops the loop; only the `MATERIALIZED` form is
  exempt.

  Accepted trade-off: a migration that drops policies *without* recreating them would quietly reduce
  RLS coverage on this dev database and no longer pause the loop. The classifier reads SQL text, so
  it stays biased to stop on anything destructive it doesn't recognise. `psql -v ON_ERROR_STOP=1`
  and its exit code are the proof it applied; nothing is taken on an agent's word.
- Changing a sentinel means changing it in **both** `SKILL.md` and this script.
