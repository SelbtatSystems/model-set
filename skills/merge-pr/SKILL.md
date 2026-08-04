---
name: merge-pr
description: Merge a pull request without shipping a regression — risk-tier the change, run layered review (code-review or review → security-review → verify), patch every correctness and high/critical security finding, gate on green build + tests + CI, then merge. Runs interactively or in an autonomous merge loop. Use when the user wants to merge a PR, asks whether a PR is safe or ready to merge, or wants a senior-style pre-merge check of the current branch or a GitHub PR by number.
---

# Merge PR

Take a pull request from open to merged without shipping a regression. Inputs: a **GitHub PR by number**, the **current branch**, or — in autonomous mode — the one open PR a merge loop just produced.

The organizing lever is **risk tier** — cheap checks run on every PR, expensive ones scale with risk. One **gate** is absolute: no PR merges while an unpatched high/critical security finding lives in the diff. The agent patches those, not the user.

This skill orchestrates the focused review skills (`/code-review`, `/review`, `/security-review`, `/verify`, `/simplify`) in cheapest-first order. Invoke each at the step that calls for it.

## Modes

- **Interactive** (default) — a human is present. Ask when the target PR is ambiguous; confirm before the final merge.
- **Autonomous** (`auto` argument, e.g. from the merge loop) — no human present. Never prompt. Merge **only** when every gate passes; otherwise leave the PR open and report why. End the run with exactly one sentinel on its own line:
  - `<<<MERGED #N>>>` — merged.
  - `<<<MERGE_BLOCKED #N reason>>>` — a gate failed; PR left open, reason commented on the PR.
  - `<<<NO_OPEN_PR>>>` — no PR to act on.

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

Triage every correctness finding: fix it, or dismiss it with a one-line reason. On low/medium-risk diffs, optionally run `/simplify` for quality-only cleanup (it does not hunt bugs).

**Done:** every correctness finding fixed or explicitly dismissed.

### 3. Security gate — blocking

Run `/security-review` on the branch. Split findings by severity:

- **High/critical** — the agent **patches each on the PR branch, pushes, and re-runs `/security-review`** until none remain (the push lets CI re-validate). Cannot safely patch (ambiguous or large) → interactive: surface; autonomous: `<<<MERGE_BLOCKED #N security:<finding>>>`.
- **Medium/low** — not blockers. Append each to the owning context's `SECURITY.md` as a deferred finding to be fixed later — format + file resolution in [`references/risk-playbooks.md`](references/risk-playbooks.md). Then continue.

High-risk tiers (auth, multi-tenant, PII, legal/immutable docs, file upload) → also run the matching hand-checks in [`references/risk-playbooks.md`](references/risk-playbooks.md) on top of the automated review.

**Done:** zero unresolved high/critical findings; every medium/low recorded in the owning `SECURITY.md`.

### 4. Static checks

Discover commands first (`package.json` scripts, `.github/workflows`). For a TypeScript monorepo, run across the affected workspace: **typecheck · lint · build**. The TS build is the strongest cheap net — it catches broken imports, missing exports, DTO mismatches, bad prop/service signatures, and much module wiring.

**Done:** typecheck + lint + build all green.

### 5. Automated tests

Run tests **against the Docker stack, never a dev server** — rebuild + restart the affected service, wait healthy, then test. For a behaviour change, a test must fail before the change and pass after; add one if missing. Low-risk move-only PRs: existing suite green is enough (no behaviour intended).

**Done:** suite green in Docker; every behaviour change covered by a test.

### 6. Runtime verify

`/verify` — boot the affected service(s) and exercise the real path: happy path + one failure path + one edge case. Watch logs for DI / module-wiring / migration / console errors a green build hides (NestJS provider/controller wiring especially).

High risk → run the domain hand-checks in [`references/risk-playbooks.md`](references/risk-playbooks.md): cross-tenant access, auth boundaries, migration on clean **and** existing DB, API contract front↔back, failure/observability paths.

**Done:** affected path exercised at the depth the risk tier demands, with no runtime errors.

### 7. CI + merge

Wait for CI to **complete** — never merge on pending: `gh pr checks <#> --watch`, bounded by a timeout. Require all green, and the branch up to date with base (rebase/merge base if behind — matters most for migrations and shared files). CI never goes green within the timeout → autonomous: `<<<MERGE_BLOCKED #N ci-timeout>>>`.

State the merge decision plainly: requirement met · diff scoped · build + tests + CI green · runtime path exercised · security gate clean · DB/migration risk handled. Any gate above still red → do not merge (autonomous: `<<<MERGE_BLOCKED #N reason>>>`).

**Never delete the branch at merge.** Deleting a branch auto-closes any open PR stacked on it (one based on it), so a `--delete-branch` merge silently kills dependent PRs. Merge **without** `--delete-branch`; prune merged branches separately, and only ever delete a branch that no open PR still uses as its base.

- **Interactive** — merging is hard to reverse; confirm with the user, then `gh pr merge <#> --merge`.
- **Autonomous** — `gh pr merge <#> --merge`, then emit `<<<MERGED #N>>>`.

**Done:** merged (interactive: on the user's go-ahead); outcome reported — autonomous runs end with exactly one sentinel.

## Reporting

Alongside the standard change summary, report: the **risk tier**, the **security-gate result** (high/critical patched + clean; where medium/low were deferred), and the merge outcome.
