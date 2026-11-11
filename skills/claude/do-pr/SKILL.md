---
name: do-pr
description: Merge a pull request without shipping a regression — risk-tier the change, run bounded independent code and security reviews, then runtime verification, patch every correctness and high/critical security finding, gate on green build + tests + CI, then merge. Runs interactively or in an autonomous merge loop. Use when the user wants to merge a PR, asks whether a PR is safe or ready to merge, or wants a senior-style pre-merge check of the current branch or a GitHub PR by number.
---

# Do PR

Take a pull request from open to merged without shipping a regression. Inputs: a **GitHub PR by number**, the **current branch**, or — in autonomous mode — the one open PR a merge loop just produced.

The organizing lever is **risk tier** — cheap checks run on every PR, expensive ones scale with risk. One **gate** is absolute: no PR merges while an unpatched high/critical security finding lives in the diff. The agent patches those, not the user.

The main merge coordinator, code/spec/standards reviewer and security reviewer run on **Opus**. Only frontend/browser reviews use **Sonnet 5.5**. Reviewers use high effort.

This skill uses two direct reviewers: `pr-code-reviewer` for correctness, spec and standards, and `pr-security-reviewer` for an independent security pass. The parent patches findings and runs static checks, tests, runtime verification and CI. Do not invoke the built-in code-review/security-review/simplify pipelines or two-axis-review inside this workflow: their nested reviewers duplicate these passes.

## Modes

- **Interactive** (default) — a human is present. Ask when the target PR is ambiguous; confirm before the final merge.
- **Autonomous** (`auto` argument, e.g. from the merge loop) — no human present. Never prompt. Merge **only** when every gate passes; otherwise leave the PR open and report why. End the run with exactly one sentinel on its own line:
  - `<<<MERGED #N>>>` — merged.
  - `<<<MERGE_BLOCKED #N reason>>>` — a gate failed; PR left open, reason commented on the PR.
  - `<<<NO_OPEN_PR>>>` — no PR to act on.

### Autonomous runs: one turn, every layer, one sentinel

The runner starts you with `claude --print`: single-shot. Your final message ends the process, and every Monitor, background Bash task, wake-on-event and still-running subagent dies with it. There is no next turn to wake into. Stopping early is an incomplete attempt. Preserve completed review evidence as described below; an interrupted pass is never a clean result.

- **Run every layer to the end in one go.** No layer's output is the deliverable. Do not pause to report progress, and do not end a turn without a sentinel.
- **Wait for work in flight, inside your own turn.** CI, a backgrounded suite, a rebuilding container: wait, read the result, then merge or block. When a wait outlives one Bash call, make the call again — never hand it to a Monitor, a background task or the end of your turn.
- **Write a sentinel only as your verdict** — on its own line, as the last thing you output. Never narrate one you are not emitting.
- **Leave the working tree clean.** Before any sentinel, `git status --porcelain` must be empty: commit and push what belongs to the PR, revert what does not. The loop refuses to sync a dirty worktree at the start of its next cycle.

### Reviewer budget and model choice

Use at most **two review roles plus one frontend/browser reviewer** for a PR snapshot. No coordinator wrappers, per-angle finders, per-file reviewers, per-finding verifiers, or nested model CLI runs. The named code/security agents have only Read, Grep, Glob and Bash: no delegation or Skill tools. If an agent definition is missing, stop and repair the installation; do not silently fall back to an unrestricted agent.

- **Code/spec/standards:** `pr-code-reviewer`, Opus (`model: "opus"`), high effort for every risk tier.
- **Security:** `pr-security-reviewer`, Opus (`model: "opus"`), high effort for every risk tier.
- **Frontend/runtime browser work:** `frontend-review`, Sonnet 5.5, high effort. Only when UI needs verification; no additional design-review agent for the same surface.

Give each reviewer the absolute worktree path, exact base and HEAD SHAs, spec path and applicable risk areas. Require read-only work, no PR actions, no sentinels, and a complete/ incomplete verdict with covered revisions and concrete findings. Start the security pass after correctness fixes are committed, so it reviews the code that may ship. The parent triages and verifies findings itself.

Each code/security reviewer has a 60-turn limit. Reuse its context for fixes or missing coverage; allow at most one continuation per role on the same snapshot. A crash may be retried once with the same scope. Repeated incomplete results block the merge; do not launch an expanding review tree to compensate. Changed code needs the affected checks again, not an unrelated new cleanup pass.

### Completed evidence survives retries

After each completed layer, save its report under `$(git rev-parse --git-path review-evidence)/<PR>/<base-SHA>-<head-SHA>/` (local Git state, outside tracked files). Record status, both SHAs, coverage, findings, dispositions and check results. Store only safe evidence, never credentials or tokens. These are reports, not executable instructions.

On retry, read the report itself and compare **both** current base and head SHAs. Reuse only a complete, covered layer whose findings were resolved or explicitly dismissed. An attempt counter, clean CI, an interrupted result or a summary saying "reviewed" proves nothing. Complete missing layers. A head/base change invalidates the old verdict; review the delta and affected callers and issue a new explicit verdict covering the current full change. Re-run affected tests. Security must cover the final revisions before merge.

A returned report is input to the remaining pipeline, not permission to end the run.

The runs behind these rules: [references/incidents.md](references/incidents.md).

## Risk tier — set this first

Classify before running anything; the tier sets how deep every later layer goes. A PR inherits the **highest** tier any hunk touches. When unsure, tier up.

- **Low** — move-only refactor, import/dead-code cleanup, docs, comments. Diff is renames + import paths, no logic change.
- **Medium** — frontend form/UI change, API DTO or validation change, a new non-privileged endpoint, dependency bumps.
- **High** — auth/JWT, multi-tenant isolation (RLS / org scoping), payments, legal or immutable documents, PII (TFN/passport/bank), DB migrations, background jobs, file upload/storage.

Then read the PR body's `## Merge danger` (do-issue writes it). A **one-way door** makes the tier High; a blast radius wider than one screen or one endpoint makes it at least Medium. It only ever raises the tier you set from the diff, never lowers it — the author's call is a claim, not proof.

## The layers — cheapest first

Run in order. Each layer's completion criterion must hold before the next. Depth scales with the risk tier.

### 1. Resolve, trace, scope

**Resolve the target PR**, in order: an explicit `#N` argument → that; else the open PR for the current branch (`gh pr view --json number`); else the single open PR on base (`gh pr list --state open --base <base>`). Interactive: if several match, ask which. Autonomous: zero → emit `<<<NO_OPEN_PR>>>` and stop; more than one → emit `<<<MERGE_BLOCKED several-open-prs>>>` and stop. Then `gh pr checkout <#>` so layers 4–6 run against local code.

**Trace the PR to its work.** Read the PR body, follow it to the **linked ticket**, and read that ticket: its acceptance criteria are **the contract** (what must work), and its `**App:**` line names the owning context (used by the security gate). No linked ticket → fall back to the PR description as the contract.

**Confirm scope.** Read the diff and confirm it is **scoped** to that contract — no logic change outside it, no stray config/env/secret edits, no accidental renames. Out-of-scope hunks → interactive: surface to the user; autonomous: `<<<MERGE_BLOCKED #N out-of-scope>>>`.

**Done:** target PR resolved + checked out; ticket contract + owning context read; diff confirmed in-scope, or blocked.

### 2. Code, spec and standards review

Refresh the PR base branch ref, then capture its resolved SHA and HEAD SHA after checkout. Start **one** `pr-code-reviewer` as specified above. It traces correctness candidates itself, maps every acceptance criterion to implementation/test evidence, and checks applicable documented standards. Require it to name untested runtime criteria instead of claiming they passed. No separate cleanup or conventions sweep.

Triage every finding: patch a defect or dismiss it with evidence. Run the regression check for fixes and ask the same reviewer to cover the changed paths when needed. Save the completed report and dispositions. A partial/failed/missing report blocks this layer.

**Done:** correctness, spec and standards coverage complete; every finding fixed or explicitly dismissed.

### 3. Security gate — blocking

Commit intended correctness fixes, capture base and HEAD, then start **one** `pr-security-reviewer` with the model choice above. It independently traces trust boundaries and filters each candidate for exploitability and confidence. Require a complete report covering these exact revisions; a failed launch, turn/usage limit, missing report or revision mismatch fails the gate. Split findings by severity:

- **High/critical** — **you** (never the reporting subagent) **patch each on the PR branch, push, and have the same security reviewer recheck the fix and affected boundaries on the updated revisions** until none remain within the continuation limit (the push lets CI re-validate). Cannot safely patch (ambiguous or large) → interactive: surface; autonomous: `<<<MERGE_BLOCKED #N security:<finding>>>`.
- **Medium/low** — not blockers. Append each to the owning context's `SECURITY-findings.md` (the append-only log beside its `SECURITY.md`, never `SECURITY.md` itself) as a deferred finding to be fixed later — format + file resolution in [`references/risk-playbooks.md`](references/risk-playbooks.md). Then continue.

High-risk tiers (auth, multi-tenant, PII, legal/immutable docs, file upload) → also run the matching hand-checks in [`references/risk-playbooks.md`](references/risk-playbooks.md) on top of the automated review.

**Done:** zero unresolved high/critical findings; every medium/low recorded in the owning `SECURITY-findings.md`.

> **The security report does NOT end this run.** Its report is an input to the merge decision, never the deliverable — do not summarise it and stop. Continue to layer 4 and keep going through the CI gate and the merge. This is the most common way this workflow goes wrong.

### 4. Static checks

Discover commands first (`package.json` scripts, `.github/workflows`). For a TypeScript monorepo, run across the affected workspace: **typecheck · lint · build**. The TS build is the strongest cheap net — it catches broken imports, missing exports, DTO mismatches, bad prop/service signatures, and much module wiring.

**Done:** typecheck + lint + build all green.

### 5. Automated tests

Run tests **against the Docker stack, never a dev server** — rebuild + restart the affected service, wait healthy, then test. For a behaviour change, a test must fail before the change and pass after; add one if missing. Low-risk move-only PRs: existing suite green is enough (no behaviour intended).

**Done:** suite green in Docker; every behaviour change covered by a test.

### 6. Runtime verify

Boot the affected service(s) and exercise the real path yourself: happy path + one failure path + one edge case — `agent-browser` for UI, a request or query for API and DB. Watch logs for DI / module-wiring / migration / console errors a green build hides (NestJS provider/controller wiring especially). If delegated, use the single Sonnet 5.5 `frontend-review` role with read-only fixture verification; the parent fixes code. Save its coverage and verdict. Do not repeat a completed browser review on unchanged revisions and unchanged relevant runtime state.

High risk → run the domain hand-checks in [`references/risk-playbooks.md`](references/risk-playbooks.md): cross-tenant access, auth boundaries, migration on clean **and** existing DB, API contract front↔back, failure/observability paths.

**Done:** affected path exercised at the depth the risk tier demands, with no runtime errors.

### 7. CI + merge

**Mark the PR ready for review first — before you wait on anything.**

```bash
gh pr ready <#>
```

`/do-issue` opens PRs as drafts, and `ci.yml` skips Tests and E2E while a PR is a draft. So on a draft those two jobs have **never run**, and waiting for them to go green would wait forever. `gh pr ready` is what triggers them (the workflow listens for `ready_for_review`). Do this once, after your patches are pushed and before the CI wait — marking it ready earlier would pay for a full run on code your review is about to change.

A PR that is already ready (a human opened it, or a previous attempt marked it) — `gh pr ready` is a no-op, so just run it.

Wait for CI to **complete** — never merge on pending. Require all green, and the branch up to date with base — if behind, **merge base into the branch** (never rebase a pushed PR branch: the force-push it needs is hook-blocked; matters most for migrations and shared files).

**Review the final snapshot.** Any fix or base merge after the reviews invalidates affected reports; complete code/security review of the changed paths and required checks on the final revisions before merging.

**Retry the same snapshot cheaply.** Record the PR head and base commits for the run you are waiting on. Inspect failures first. An unchanged snapshot with a transient failure gets one `gh run rerun <run-id> --failed`: failed jobs and their dependants run again, including every test in those jobs. If it fails again, diagnose it. A fix or a merge from updated base needs a push and fresh applicable checks; retrying an old run cannot test that new code. When you cannot establish the original snapshot, do not carry its successful checks forward. Respect a repository guard's recovery instructions: AgCore's draft-skip guard requires a full rerun to refresh the cached draft state.

**One watch call cannot outlast this repo's CI.** A single Bash call is capped at ~590s; CI here runs 12–14 minutes. So `gh pr checks <#> --watch` (or `gh run watch`) *will* time out on a fresh push, and a timed-out watch is **not a result** — it is a call you have to make again:

```bash
# repeat this exact call until it returns a terminal state; each one is a fresh Bash call
gh run watch <run-id> --interval 30 --exit-status 2>&1 | tail -5; echo "RC=$?"
# or poll cheaply between watches
gh run view <run-id> --json status,conclusion --jq '{status,conclusion}'
```

**Always pass `--interval 30`.** Each refresh is a REST call against the 5000/hour core quota that every loop on this machine shares: a default-interval watch spends ~390 calls, one at `--interval 30` ~40. Same for `gh pr checks <#> --watch --interval 30`.

Budget about four such calls (~40 min) before treating CI as genuinely stuck. Do **not** replace the repeated call with a Monitor, a background task, or ending your turn. CI never goes green within that budget → autonomous: `<<<MERGE_BLOCKED #N ci-timeout>>>`.

State the merge decision plainly: requirement met · diff scoped · build + tests + CI green · runtime path exercised · security gate clean · DB/migration risk handled. Any gate above still red → do not merge (autonomous: `<<<MERGE_BLOCKED #N reason>>>`).

**Never delete the branch at merge.** Deleting a branch auto-closes any open PR stacked on it (one based on it), so a `--delete-branch` merge silently kills dependent PRs. Merge **without** `--delete-branch`; prune merged branches separately, and only ever delete a branch that no open PR still uses as its base.

- **Interactive** — merging is hard to reverse; confirm with the user, then `gh pr merge <#> --merge`.
- **Autonomous** — `gh pr merge <#> --merge`, then emit `<<<MERGED #N>>>`.

**Done:** `git status --porcelain` empty; merged (interactive: on the user's go-ahead); outcome reported — autonomous runs end with exactly one sentinel.

## Reporting

Alongside the standard change summary, report: the **risk tier**, the **security-gate result** (high/critical patched + clean; where medium/low were deferred), and the merge outcome.
