---
name: do-issue
description: Execute one ready-for-agent ticket end-to-end to done. Use when the user wants to work the next ticket from the issue tracker, or build a specific ticket they name. The executor end of the to-prd → to-issues → triage pipeline.
---

# Do Issue

Build one `ready-for-agent` ticket to done — the executor end of `to-prd` → `to-issues` → `triage`. **One ticket per run**, the same lifecycle every time. End the run only at step 7 *done* or an explicit stop condition (non-AFK ticket, open blocker, `<<<NO_OPEN_ISSUES>>>`, or a decision only a person can make — which you hand back per step 2's *Stopping on a decision*) — a failed gate means fix and re-run, not stop.

## Never end with work in flight

The autonomous runner starts you with `claude --print`: single-shot. Your final message ends the process, and every background Bash task, Monitor, wake-on-event and still-running subagent dies with it. There is no next turn to wake into.

- **Wait for everything you start** — a test run, a rebuilding container, a CI job, a subagent. Read its result and carry on to the end of the lifecycle. "I'll push once the suite reports" leaves nothing committed and no PR, and the loop redoes the whole ticket at full cost.
- **When a wait outlives one Bash call, make the call again.** Never hand the waiting to a Monitor, a background task, or the end of your turn.
- **Commit as soon as the gate is green.** A committed slice survives any later failure; a verified slice held uncommitted can leave an orphaned migration that blocks the loop until a person repairs it.
- **Leave the tree clean.** A dirty tree stops the loop's next sync.

If a job genuinely cannot be waited on, state it as a blocker. The runs behind these rules: [references/incidents.md](references/incidents.md).

The tracker spec — where tickets live, the issue file format, the find-work command, and the triage roles — is defined in `docs/agents/issue-tracker.md` + `docs/agents/triage-labels.md` (reached via the repo's `## Agent skills` block). Read them; this skill does not restate them. If that config is missing, stop and ask the user where the tracker config lives — do not guess a tracker layout.

## Process

### 1. Select the ticket

If the user named a ticket, use it. Otherwise grep the `ready-for-agent` queue and take the **lowest-numbered `NN-*.md`** whose `**Blocked by:**` is `None` or a ticket already marked `done`. The PRD is not a ticket — skip it.

Stop and surface to the user — build nothing — if the ticket is not AFK (`**Triage:** ready-for-human`) or a blocker is still open. If **nothing qualifies** (no `ready-for-agent` ticket with all blockers satisfied), print exactly `<<<NO_OPEN_ISSUES>>>` and stop — nothing else (an autonomous merge loop reads this token to know the backlog is empty).

State the chosen ticket's number and title before going on.

✓ **Done when:** one AFK issue file is chosen, its number and title are stated, and every blocker it names is `done`.

### 2. Read the contract

The ticket's **Agent Brief** (or its *What to build* + *Acceptance criteria*) is **the contract** — the spec you build against. Read it in full, plus the parent PRD for intent and for its *Testing Decisions* (the seams step 4 tests at). Then load the owning context per `docs/agents/domain.md`: the `**App:**`'s `CONTEXT.md` glossary and the ADRs in that area. Work in glossary vocabulary. If the contract contradicts an ADR, stop and surface it instead of overriding.

**Stopping on a decision.** Sometimes the build cannot go on without a person: the contract contradicts an ADR, the code cannot hold what the brief asks for without a scope or product call, or a provider's documentation disproves the brief's premise. When that happens, hand the ticket back before you end the run. Otherwise it stays `ready-for-agent`, the autonomous issue-loop picks the same lowest-numbered ticket every cycle, and it stops after `MAX_FAILS` identical failures while tickets it could build wait behind it. To hand it back:
- Append a dated `## Comments` entry with the evidence (file and symbol names, the command you ran and its result, doc links) and the decision as **2–3 lettered options**, with your recommendation first.
- Flip `**Triage:**` to `ready-for-human` for a product or scope decision, or to `needs-info` when the ticket waits on an outside fact (provider docs, a sandbox result).
- Leave no stray branch: delete an empty local branch you created; push a branch that has real work as `wip/<slug>` and name it in the comment.
- End the run with a short summary. Do not emit `<<<NO_OPEN_ISSUES>>>` — other tickets may still be ready.

A failed gate, a flaky test, or code that is hard to write is **not** a decision. Fix it.

✓ **Done when:** you can restate the acceptance criteria as a checklist, you know the owning context, and you know the PRD's test seams.

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

Implement the slice end-to-end through every layer it touches. Hold to the contract's *Out of scope*; do not gold-plate. Load the build skill with the Skill tool — a skill named only in prose does not load:

- **Feature** → call the Skill tool with "tdd". Hand it the PRD's *Testing Decisions* as the pre-agreed seams. If the slice needs a seam the PRD does not name, use the highest existing seam that reaches the behaviour, and name the new seam in the PR body so review can judge it.
- **Bug** → call the Skill tool with "diagnosing-bugs".
- **Domain work** → also call the Skill tool for each stack skill the ticket or PRD names (`nodejs-backend-patterns`, `react-best-practices`, …).

Test while you build: after each change, run the affected workspace's typecheck and the one test file you are changing, the same way step 5 runs tests. The full gate runs once, in step 5.

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
- Conflicts → call the Skill tool with "resolving-merge-conflicts"; never `--abort` back to the stale base.

After syncing, rebuild and restart the affected Docker services before testing — the containers are still serving pre-merge code.

Discover the repo's quality gate first (`cat package.json`, `ls .github/workflows`), then run it — typecheck · lint · test · build. Check **each acceptance criterion by executing the actual check** (`agent-browser`, `design-review`, a query, a request, a test run) — never by inspecting code or diffs. A criterion you cannot execute stays unchecked: report it as such, do not claim it.

If this ticket adds a DB migration, apply it to **the current worktree's own database** before testing — each worktree runs a separate DB volume, so tests and runtime exercise that stack, not main's.

✓ **Done when:** the branch contains `origin/main`, the gate is green, and every acceptance criterion was confirmed by a command you ran — in that order, on that base.

### 6. Open the PR

Push the branch explicitly (it has no upstream after step 3's `--no-track`), then open the PR:

```bash
git push -u origin HEAD
gh pr create --draft --base main   # use --base <slice-branch> only for a stacked PR
```

**Open it as a draft.** `ci.yml` gates its two expensive jobs — Tests (~14 min) and E2E (~47 min), 61 of the 65 billed minutes per run — on the PR being marked ready for review. Static and Build still run on a draft, so you keep fast typecheck/lint/build feedback. This matters because the merge agent pushes review patches: measured on recent branches, one PR triggered 3 full runs typically and 7 at worst. As a draft that is **one** full run, taken once at the end.

`/do-pr` marks the PR ready before it merges — that is what fires the gated jobs. Never mark it ready yourself here; a PR that is ready before review has been done pays for CI on code the review is about to change.

Write the body in this shape — short prose, in the glossary's words:

```markdown
## Summary

<what the slice does, in 1–3 lines. Add the smallest picture that makes it clear —
a call tree, file tree, component tree or diff sketch — only when the change has structure worth showing.>

Ticket: <path to the ticket file>

## Evidence

- **Before:** <failing test run, output, or screenshot>
  **After:** <passing test run, output, or screenshot>
- <each acceptance criterion> — <the check you ran in step 5, and its result>

## Merge danger

**Door:** <one-way or two-way>
**Blast radius:** <one word>

<optional: what could break, and for whom>
```

- **Evidence** — show the exact test that failed before and passes after (its name and command), or the output; a screenshot when the change is visual and you have one.
- **Door** — two-way when a revert and redeploy undo it completely; one-way when they cannot: a migration that drops or rewrites data, a message or email already sent, a side effect in an external system, a contract other code now depends on.
- **Blast radius** — who or what breaks if it goes wrong: one screen, one app, every tenant, payroll. `do-pr` reads this section and may only raise its risk tier from it.

✓ **Done when:** the PR exists, names the ticket, and its body has all three sections.

### 7. Close the loop in the tracker

In the ticket file: **tick each `## Acceptance criteria` box you confirmed in step 5** (`- [ ]` → `- [x]`), flip `**Triage:**` to `done`, and append a dated `## Comments` line linking the PR. **Never modify the parent PRD.** Then name the tickets this unblocks and stop — the next run takes the next ticket. (Write the tracker file only; do not commit it or run its scripts if the tracker lives in an externally-managed store — follow the repo's tracker config.)

**The ticket file is the record, not the PR body.** Step 5 says a criterion you could not execute stays unchecked — that only means something if this step writes the checked ones back. A ticket closed `done` with every box still `[ ]` reads, months later, as work nobody verified; the proof lives in a PR body no one will reopen. Tick only what you actually executed. Any box still `[ ]` at close gets a `## Comments` line saying which one and why.

✓ **Done when:** the ticket's `**Triage:**` reads `done`, every verified acceptance criterion is `- [x]`, any unverified one is named in `## Comments`, and a `## Comments` entry links the PR.
