---
name: do-pr
description: Merge a pull request without shipping a regression — risk-tier the change, run layered review (code-review or review → security-review → verify), patch every correctness and high/critical security finding, gate on green build + tests + CI, then merge. Runs interactively or in an autonomous merge loop. Use when the user wants to merge a PR, asks whether a PR is safe or ready to merge, or wants a senior-style pre-merge check of the current branch or a GitHub PR by number.
---

# Do PR

Take a pull request from open to merged without shipping a regression. Inputs: a **GitHub PR by number**, the **current branch**, or — in autonomous mode — the one open PR a merge loop just produced.

The organizing lever is **risk tier** — cheap checks run on every PR, expensive ones scale with risk. One **gate** is absolute: no PR merges while an unpatched high/critical security finding lives in the diff. The agent patches those, not the user.

This skill orchestrates the focused review skills (`/code-review`, `/review`, `/security-review`, `/verify`, `/simplify`) in cheapest-first order. Invoke each at the step that calls for it.

## Modes

- **Interactive** (default) — a human is present. Ask when the target PR is ambiguous; confirm before the final merge.
- **Autonomous** (`auto` argument, e.g. from the merge loop) — no human present. Never prompt. Merge **only** when every gate passes; otherwise leave the PR open and report why. End the run with exactly one sentinel on its own line:
  - `<<<MERGED #N>>>` — merged.
  - `<<<MERGE_BLOCKED #N reason>>>` — a gate failed; PR left open, reason commented on the PR.
  - `<<<NO_OPEN_PR>>>` — no PR to act on.

  **Run every layer to the end in one go.** No layer's output is the deliverable, and no sub-skill
  you invoke (`/security-review` especially) ends the run when it returns — you resume at the next
  layer. Do not pause to report progress, do not stop because checks are still running (wait on
  them: `gh pr checks <#> --watch`), and do not end a turn without a sentinel. Stopping early is
  indistinguishable from failing, so the whole run is discarded and repeated at full cost.

  **Delegate the report-producing layers to subagents.** `/review`, `/code-review`,
  `/security-review` and `/verify` are each built to *finish* with a report, and that terminal
  framing is what ends this run when you invoke them inline — prose reminders have twice failed to
  prevent it. Run each in a subagent instead, so "produce the report and stop" lands on the
  subagent and the findings come back to you as a result to act on. Observed 2026-08-03 in the
  admin loop: one merge log is 54 lines of code review of PR #826, the next is 9 lines of security
  review of PR #834 — both immaculate, both ending mid-pipeline with no sentinel and no merge, each
  discarding a full review.

  The delegation only works if the hand-back is explicit, so tell every such subagent, in its prompt:

  - **It is a reporter, not the decision-maker.** Its job is to find and evidence; yours is to
    triage, patch, gate and merge. It returns findings — it never decides the merge.
  - **It must not act on the PR.** No `gh pr merge`, no `gh pr comment`, no pushing, no editing the
    ticket. If it needs to change a file to prove a finding, it says so and reverts.
  - **It must never write a sentinel.** `<<<MERGED …>>>`, `<<<MERGE_BLOCKED …>>>` and
    `<<<NO_OPEN_PR>>>` are yours alone. The runner greps the whole log line-anchored, so a sentinel
    quoted inside a subagent's report is read as *your* verdict — a stray `MERGE_BLOCKED` in a
    review would stop the loop on a healthy PR.
  - **It returns structured findings**, each with file, line, severity and the concrete failure —
    not a narrative you have to re-read to act on.

  When a subagent returns, you are mid-pipeline by definition. Say which layer just closed and which
  is next before doing anything else; that single line is what makes stopping here feel as wrong as
  it is. A returned report is an input, never an ending.

  **Never end the run while work is in flight** — a CI job, a backgrounded suite, a rebuilding
  container. "I'll check back once CI completes and merge if it's green" is a failed run: nothing
  checks back. Wait, read the result, then merge or block. And never *narrate* a sentinel you are
  not emitting ("…otherwise report `<<<MERGE_BLOCKED …>>>`") — write a sentinel only when it is
  your verdict, on its own line, as the last thing you output.

  **Arming a background watcher and ending the turn is the same failure — and it is the one that
  keeps happening.** The runner spawns you with `claude --print`: single-shot. Your final message
  ends the process, and any Monitor, background Bash task or wake-on-event you armed dies with it.
  There is no next turn to wake into. That escape hatch is real in an interactive session and does
  not exist here. Twice on 2026-08-04 a merge agent hit the Bash timeout on `gh run watch`, armed a
  Monitor, wrote "the monitor will wake me when it reaches a terminal state" and ended the turn —
  PR #849 ($14.18) and PR #850 ($11.36), each burning a full cycle before a retry merged the
  already-green PR in seconds. **When a wait outlives one Bash call, make the call again.** Never
  hand the waiting to anything outside your own turn.

  **Leave the working tree clean.** This skill edits files — it patches findings, corrects docs,
  merges base in — and an autonomous loop re-syncs its worktree at the *start* of the next cycle,
  so anything left uncommitted stops that loop outright with "working tree has uncommitted changes
  — refusing to touch it". Before emitting any sentinel, `git status --porcelain` must be empty:
  commit and push what belongs to the PR, revert what does not. This is not housekeeping — a
  one-line comment edit left behind while reviewing PR #834 is what took the admin loop down, and
  salvage only runs at cycle *end*, so it cannot rescue a tree that is already dirty at startup.

## Risk tier — set this first

Classify before running anything; the tier sets how deep every later layer goes. A PR inherits the **highest** tier any hunk touches. When unsure, tier up.

- **Low** — move-only refactor, import/dead-code cleanup, docs, comments. Diff is renames + import paths, no logic change.
- **Medium** — frontend form/UI change, API DTO or validation change, a new non-privileged endpoint, dependency bumps.
- **High** — auth/JWT, multi-tenant isolation (RLS / org scoping), payments, legal or immutable documents, PII (TFN/passport/bank), DB migrations, background jobs, file upload/storage.

## The layers — cheapest first

Run in order. Each layer's completion criterion must hold before the next. Depth scales with the risk tier.

### 1. Resolve, trace, scope

**Resolve the target PR**, in order: an explicit `#N` argument → that; else the open PR for the current branch (`gh pr view --json number`); else the single open PR on base (`gh pr list --state open --base <base>`). Interactive: if several match, ask which. Autonomous: zero → emit `<<<NO_OPEN_PR>>>` and stop; more than one → emit `<<<MERGE_BLOCKED several-open-prs>>>` and stop. Then `gh pr checkout <#>` so layers 4–6 run against local code.

**Trace the PR to its work.** Read the PR body, follow it to the **linked ticket**, and read that ticket: its acceptance criteria are **the contract** (what must work), and its `**App:**` line names the owning context (used by the security gate). No linked ticket → fall back to the PR description as the contract.

**Confirm scope.** Read the diff and confirm it is **scoped** to that contract — no logic change outside it, no stray config/env/secret edits, no accidental renames. Out-of-scope hunks → interactive: surface to the user; autonomous: `<<<MERGE_BLOCKED #N out-of-scope>>>`.

**Done:** target PR resolved + checked out; ticket contract + owning context read; diff confirmed in-scope, or blocked.

### 2. Code review

- A reviewable GitHub PR → `/review <PR#>`.
- Working diff with no PR yet → `/code-review` at effort **medium** (low risk), **high** (medium risk), or **max** (high risk).

Autonomous runs delegate this to a subagent and act on what it returns — see *Modes*. Inline, the
review's own "report and finish" framing ends the whole run here.

**You** triage every correctness finding the review returns — fix it on the branch, or dismiss it with a one-line reason. The subagent only reports; patching is yours. On low/medium-risk diffs, optionally run `/simplify` for quality-only cleanup (it does not hunt bugs).

**Done:** every correctness finding fixed or explicitly dismissed.

### 3. Security gate — blocking

Run `/security-review` on the branch — autonomous: in a subagent, see *Modes*. Split findings by
severity:

- **High/critical** — **you** (never the reporting subagent) **patch each on the PR branch, push, and re-run `/security-review`** — a fresh subagent — until none remain (the push lets CI re-validate). Cannot safely patch (ambiguous or large) → interactive: surface; autonomous: `<<<MERGE_BLOCKED #N security:<finding>>>`.
- **Medium/low** — not blockers. Append each to the owning context's `SECURITY.md` as a deferred finding to be fixed later — format + file resolution in [`references/risk-playbooks.md`](references/risk-playbooks.md). Then continue.

High-risk tiers (auth, multi-tenant, PII, legal/immutable docs, file upload) → also run the matching hand-checks in [`references/risk-playbooks.md`](references/risk-playbooks.md) on top of the automated review.

**Done:** zero unresolved high/critical findings; every medium/low recorded in the owning `SECURITY.md`.

> **`/security-review` returning does NOT end this run.** It is one layer of `do-pr`, not the task.
> Its report is an input to the merge decision, never the deliverable — do not summarise it and stop.
> The moment it returns, continue to layer 4 and keep going through the CI gate and the merge. In an
> autonomous run the only acceptable endings are `<<<MERGED #N>>>`, `<<<MERGE_BLOCKED #N reason>>>`
> or `<<<NO_OPEN_PR>>>`; a security summary with no sentinel is a failed run and gets retried from
> scratch at full cost. This is the most common way this workflow goes wrong.

### 4. Static checks

Discover commands first (`package.json` scripts, `.github/workflows`). For a TypeScript monorepo, run across the affected workspace: **typecheck · lint · build**. The TS build is the strongest cheap net — it catches broken imports, missing exports, DTO mismatches, bad prop/service signatures, and much module wiring.

**Done:** typecheck + lint + build all green.

### 5. Automated tests

Run tests **against the Docker stack, never a dev server** — rebuild + restart the affected service, wait healthy, then test. For a behaviour change, a test must fail before the change and pass after; add one if missing. Low-risk move-only PRs: existing suite green is enough (no behaviour intended).

**Done:** suite green in Docker; every behaviour change covered by a test.

### 6. Runtime verify

`/verify` — boot the affected service(s) and exercise the real path: happy path + one failure path + one edge case. Watch logs for DI / module-wiring / migration / console errors a green build hides (NestJS provider/controller wiring especially). Autonomous: in a subagent, see *Modes* — this is the last layer that produces a report, and the one most likely to feel like an ending when it is not.

High risk → run the domain hand-checks in [`references/risk-playbooks.md`](references/risk-playbooks.md): cross-tenant access, auth boundaries, migration on clean **and** existing DB, API contract front↔back, failure/observability paths.

**Done:** affected path exercised at the depth the risk tier demands, with no runtime errors.

### 7. CI + merge

Wait for CI to **complete** — never merge on pending. Require all green, and the branch up to date with base — if behind, **merge base into the branch** (never rebase a pushed PR branch: the force-push it needs is hook-blocked; matters most for migrations and shared files).

**One watch call cannot outlast this repo's CI.** A single Bash call is capped at ~590s; CI here runs 12–14 minutes. So `gh pr checks <#> --watch` (or `gh run watch`) *will* time out on a fresh push, and a timed-out watch is **not a result** — it is a call you have to make again:

```bash
# repeat this exact call until it returns a terminal state; each one is a fresh Bash call
gh run watch <run-id> --exit-status 2>&1 | tail -5; echo "RC=$?"
# or poll cheaply between watches
gh run view <run-id> --json status,conclusion --jq '{status,conclusion}'
```

Budget about four such calls (~40 min) before treating CI as genuinely stuck. Do **not** replace the repeated call with a Monitor, a background task, or ending your turn — see *Never end the run while work is in flight* above. CI never goes green within that budget → autonomous: `<<<MERGE_BLOCKED #N ci-timeout>>>`.

State the merge decision plainly: requirement met · diff scoped · build + tests + CI green · runtime path exercised · security gate clean · DB/migration risk handled. Any gate above still red → do not merge (autonomous: `<<<MERGE_BLOCKED #N reason>>>`).

**Never delete the branch at merge.** Deleting a branch auto-closes any open PR stacked on it (one based on it), so a `--delete-branch` merge silently kills dependent PRs. Merge **without** `--delete-branch`; prune merged branches separately, and only ever delete a branch that no open PR still uses as its base.

- **Interactive** — merging is hard to reverse; confirm with the user, then `gh pr merge <#> --merge`.
- **Autonomous** — `gh pr merge <#> --merge`, then emit `<<<MERGED #N>>>`.

**Done:** `git status --porcelain` empty; merged (interactive: on the user's go-ahead); outcome reported — autonomous runs end with exactly one sentinel.

## Reporting

Alongside the standard change summary, report: the **risk tier**, the **security-gate result** (high/critical patched + clean; where medium/low were deferred), and the merge outcome.
