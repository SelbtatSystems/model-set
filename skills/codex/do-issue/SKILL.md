---
name: do-issue
description: Execute one ready-for-agent ticket end-to-end to done. Use when the user wants to work the next ticket from the issue tracker, or build a specific ticket they name. The executor end of the to-prd → to-issues → triage pipeline.
---

# Do Issue

Build one `ready-for-agent` ticket to done — the executor end of `to-prd` → `to-issues` → `triage`. **One ticket per run**, the same lifecycle every time. End the run only at step 7 *done* or an explicit stop condition (non-AFK ticket, open blocker, `<<<NO_OPEN_ISSUES>>>`) — a failed gate means fix and re-run, not stop.

> **Never end the run while work is in flight.** A backgrounded test run, a rebuilding
> container, a CI job, a delegated sub-agent — none of these is a place to stop and report
> status. Wait for it, read its result, and carry on to the end of the lifecycle. "I'll push
> once the suite reports" is a failed run: the work is uncommitted, no PR exists, and in an
> autonomous loop the whole ticket is redone from scratch at full cost — while the dirty tree
> you left behind stops the loop's next sync entirely. If a job genuinely cannot be waited on,
> that is a blocker to state as one, not a reason to end mid-lifecycle. (Observed twice on
> 2026-08-02: two agents spent $18 between them and shipped nothing.)

> **Arming a background watcher, or delegating and ending the turn, is the same failure — and it
> is the one that keeps happening.** The runner spawns you with `codex exec`: single-shot. Your
> final message ends the process, and any watcher, background shell task, wake-on-event or
> still-running sub-agent dies with it. There is no next turn to wake into. That escape hatch is
> real in an interactive session and does not exist here. On 2026-08-05 a build agent finished
> map-evolution ticket 09 — 816 verified lines, backend e2e 14/14, backend units 1887/1887 — then
> wrote "the only outstanding item is the browser verification agent; I'll commit and PR as soon
> as it reports" and ended the turn. $37.84 spent, nothing committed, no PR, and the loop's ledger
> held a branch that did not exist on the remote. **When a wait outlives one shell call, make the
> call again.** Never hand the waiting to anything outside your own turn.

> **Commit as soon as the gate is green — never hold a verified slice uncommitted while waiting on
> anything.** That one habit turns every failure above into a recoverable one. What made ticket 09
> worse than a lost turn was its migration: already applied to the worktree's database, but absent
> from the base branch once the abandoned unit branch was left behind — an *orphaned* migration,
> which `db:check` fails on. The loop could then not restart to merge the very PR that would have
> cleared it, and a human had to break the deadlock by hand.

The tracker spec — where tickets live, the issue file format, the find-work command, and the triage roles — is defined in `docs/agents/issue-tracker.md` + `docs/agents/triage-labels.md` (reached via the repo's `## Agent skills` block). Read them; this skill does not restate them. If that config is missing, stop and ask the user where the tracker config lives — do not guess a tracker layout.

## Process

### 1. Select the ticket

If the user named a ticket, use it. Otherwise grep the `ready-for-agent` queue and take the **lowest-numbered `NN-*.md`** whose `**Blocked by:**` is `None` or a ticket already marked `done`. The PRD is not a ticket — skip it.

Stop and surface to the user — build nothing — if the ticket is not AFK (`**Triage:** ready-for-human`) or a blocker is still open. If **nothing qualifies** (no `ready-for-agent` ticket with all blockers satisfied), print exactly `<<<NO_OPEN_ISSUES>>>` and stop — nothing else (an autonomous merge loop reads this token to know the backlog is empty).

✓ **Done when:** one AFK issue file is chosen and every blocker it names is `done`.

### 2. Read the contract

The ticket's **Agent Brief** (or its *What to build* + *Acceptance criteria*) is **the contract** — the spec you build against. Read it in full, plus the parent PRD for intent. Then load the owning context per `docs/agents/domain.md`: the `**App:**`'s `CONTEXT.md` glossary and the ADRs in that area. Work in glossary vocabulary. If the contract contradicts an ADR, stop and surface it instead of overriding.

✓ **Done when:** you can restate the acceptance criteria as a checklist and you know the owning context.

### 3. Branch

Create a fresh `<type>/<desc>` branch **sourced from the latest `origin/main`** — never check out, pull, or commit on `main`/`master` itself. This is the **worktree-safe** rule: a git worktree refuses to check out a branch another worktree already holds, so branch *off* `main` (a ref you read) instead of *switching to* it (a branch you'd occupy). The same flow then runs identically in the primary checkout and in any worktree.

**Always create a new branch — never build on the branch HEAD already sits on.** A run that starts inside a worktree finds that worktree's own long-lived branch checked out, and that branch is usually behind `main`. It is not yours and it is not fresh. Branch anyway, every run, before touching a single file.

**`git fetch` is not optional.** `origin/main` is a *local cache* of the remote, and a stale cache is exactly this bug: branching off an unfetched `origin/main` silently sources week-old code, the build goes green against the wrong base, and the regression only appears after merge. Fetch, then **prove** you are fresh — don't assume it:

```bash
git fetch origin main
git switch --no-track -c <type>/<desc> origin/main

# Prove it: the cached ref matches the real remote AND your HEAD contains it.
[ "$(git rev-parse origin/main)" = "$(git ls-remote origin main | cut -f1)" ] \
  && git merge-base --is-ancestor origin/main HEAD \
  && echo "FRESH — branched from origin/main $(git rev-parse --short origin/main)" \
  || echo "STALE — stop, re-fetch, re-branch. Do not build."
```

The `ls-remote` comparison is the part that matters: an ancestor check *alone* passes trivially when the fetch was skipped, because a stale `origin/main` is trivially an ancestor of itself. Only the remote comparison catches a skipped fetch.

- **Never** run `git switch main` / `git checkout main` / `git pull` on `main` — it collides the instant another worktree has `main` checked out (an intermittent, hard-to-debug failure) and is unnecessary here.
- `--no-track` stops the new branch adopting `main` as its upstream, so a later bare `git push` can't target `main`.
- **Stacked PR** — only when this ticket genuinely needs an unmerged prior slice's code: source off that slice instead (`git switch --no-track -c <type>/<desc> origin/<slice-branch>`), note the dependency, and never let that base branch be deleted while this PR is open. Run the same proof against that slice's branch.

✓ **Done when:** the freshness check printed `FRESH`, on a branch you created in this run — not one you inherited, and never `main` itself.

### 4. Build the tracer bullet

Implement the slice end-to-end through every layer it touches. Delegate to the fitting build skill — `tdd` for a feature, `diagnose` for a `bug`, the stack skills (`nodejs-backend-patterns`, `react-best-practices`, …) for domain work. Hold to the contract's *Out of scope*; do not gold-plate.

✓ **Done when:** every acceptance criterion is satisfied by something you built.

### 5. Go green — verify by running, not reading

**Re-sync first — `main` moved while you were building.** Branching fresh in step 3 only guarantees freshness *at step 3*; a build that takes an hour is testing against an hour-old base. Verifying against a stale base is how a green local run turns into a red CI run, and how an already-fixed bug appears to come back (the running container serves your branch's behind-`main` code):

```bash
git fetch origin main
git merge-base --is-ancestor origin/main HEAD && echo "UP TO DATE" || echo "BEHIND — sync before verifying"
```

If it reports `BEHIND`, sync before running the gate — and re-run the gate afterwards, because the merge can break it:

- **Branch not pushed yet** → `git rebase origin/main` (clean history, safe while the branch is local-only).
- **Branch already pushed** → `git merge origin/main`. Do **not** rebase a pushed branch: it needs a force-push, which is hook-blocked.
- Conflicts → resolve via `resolving-merge-conflicts`; never `--abort` back to the stale base.

After syncing, rebuild and restart the affected Docker services before testing — the containers are still serving pre-merge code.

Discover the repo's quality gate first (`cat package.json`, `ls .github/workflows`), then run it — typecheck · lint · test · build. Check **each acceptance criterion by executing the actual check** (`verify`, `agent-browser`, `design-review`, a query, a request) — never by inspecting code or diffs. A criterion you cannot execute stays unchecked: report it as such, do not claim it.

If this ticket adds a DB migration, apply it to **the current worktree's own database** before testing — each worktree runs a separate DB volume, so tests and runtime exercise that stack, not main's.

✓ **Done when:** the branch contains `origin/main`, the gate is green, and every acceptance criterion was confirmed by a command you ran — in that order, on that base.

### 6. Open the PR

Push the branch explicitly (it has no upstream after step 3's `--no-track`), then open the PR:

```bash
git push -u origin HEAD
gh pr create --base main      # use --base <slice-branch> only for a stacked PR
```

The body restates the slice, lists each acceptance criterion with its verified result, and references the ticket.

✓ **Done when:** the PR exists and names the ticket.

### 7. Close the loop in the tracker

In the ticket file: flip `**Triage:**` to `done` and append a dated `## Comments` line linking the PR. **Never modify the parent PRD.** Then name the tickets this unblocks and stop — the next run takes the next ticket. (Write the tracker file only; do not commit it or run its scripts if the tracker lives in an externally-managed store — follow the repo's tracker config.)

✓ **Done when:** the ticket's `**Triage:**` reads `done` and a `## Comments` entry links the PR.
