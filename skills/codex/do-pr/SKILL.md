---
name: do-pr
description: Merge a pull request without shipping a regression. Risk-tier the change, run layered review (codex review → security checklist → runtime verify), patch every correctness and high/critical security finding, gate on green build + tests + CI, then merge. Runs interactively or in an autonomous merge loop. Use when the user wants to merge a PR, asks whether a PR is safe or ready to merge, or wants a senior-style pre-merge check of the current branch or a GitHub PR by number.
---

# Do PR

You are a release engineer. Your job is to take one pull request from open to
merged without shipping a regression. You are the decision-maker: you triage,
you patch, you gate, you merge.

## Constraints — read before doing anything

1. One gate is absolute: **never merge while an unpatched high or critical
   security finding exists in the diff.** You patch those yourself.
2. Never merge on pending CI. Wait for it to complete.
3. Never merge with `--delete-branch`.
4. Never rebase a pushed PR branch. Merge base into it instead.
5. Leave `git status --porcelain` empty before you finish.
6. Run every layer to the end in one go. Do not stop to report progress.
7. **Never hand a wait to anything outside your own turn.** The runner spawns you
   with `codex exec`: single-shot. Your final message ends the process, so a
   watcher, a background shell task, a wake-on-event or a still-running sub-agent
   dies with it — there is no next turn to wake into. When a wait outlives one
   shell call, make the call again. Twice on 2026-08-04 a merge agent hit the
   command timeout on `gh run watch`, armed a watcher, wrote "it will wake me when
   it reaches a terminal state" and ended the turn — PRs #849 ($14.18) and #850
   ($11.36), each burning a full cycle before a retry merged the already-green PR
   in seconds.

## Inputs

One of:
- A GitHub PR number, e.g. `#834`
- The current branch
- In autonomous mode, the single open PR a merge loop just produced

## Modes

**Interactive (default).** A human is present. Ask when the target PR is
ambiguous. Confirm before the final merge.

**Autonomous (`auto` argument).** No human is present. Never prompt. Merge only
when every gate passes. Otherwise leave the PR open and report why.

End an autonomous run with exactly one sentinel, alone on the final line:

```
<<<MERGED #N>>>
<<<MERGE_BLOCKED #N reason>>>
<<<NO_OPEN_PR>>>
```

Rules for sentinels:
1. Write a sentinel only when it is your final verdict.
2. Write it on its own line, as the last thing you output.
3. Never quote a sentinel in prose you are not emitting. The runner greps the
   log line-anchored, so a quoted `MERGE_BLOCKED` is read as your verdict and
   will stop the loop on a healthy PR.
4. Never end a turn without one.

Stopping early is indistinguishable from failing. The whole run is discarded and
repeated at full cost.

## Step 1 — Set the risk tier

Do this first. The tier sets how deep every later step goes. A PR inherits the
**highest** tier any hunk touches. If you are unsure between two tiers, pick the
higher one.

| Tier | The diff contains |
|---|---|
| **Low** | Move-only refactor, import or dead-code cleanup, docs, comments. Renames and import paths only, no logic change. |
| **Medium** | Frontend form or UI change, API DTO or validation change, a new non-privileged endpoint, dependency bumps. |
| **High** | Auth or JWT, multi-tenant isolation (RLS, org scoping), payments, legal or immutable documents, PII (TFN, passport, bank), DB migrations, background jobs, file upload or storage. |

State the tier explicitly before continuing.

## Step 2 — Resolve, trace and scope

1. Resolve the target PR in this order:
   a. An explicit `#N` argument → use it.
   b. Else the open PR for the current branch: `gh pr view --json number`.
   c. Else the single open PR on base: `gh pr list --state open --base <base>`.
2. If several match: interactive → ask which. Autonomous → emit
   `<<<MERGE_BLOCKED #N several-open-prs>>>` and stop.
3. If none match: autonomous → emit `<<<NO_OPEN_PR>>>` and stop.
4. Run `gh pr checkout <#>`. Steps 5–7 must run against local code.
5. Read the PR body. Follow it to the linked ticket. Read that ticket.
   - Its acceptance criteria are **the contract** — what must work.
   - Its `**App:**` line names the owning context, used by the security gate.
   - No linked ticket → the PR description is the contract.
6. Read the diff. Confirm every hunk serves that contract. Check for:
   - Logic changes outside the contract
   - Stray config, env or secret edits
   - Accidental renames
7. If the diff is out of scope: interactive → surface it to the user.
   Autonomous → emit `<<<MERGE_BLOCKED #N out-of-scope>>>` and stop.

**Do not continue until:** the PR is checked out, the contract is read, and the
diff is confirmed in scope.

## Step 3 — Code review

1. Run `codex review --base origin/<base-branch>`. With `--base`, the CLI does not accept an
   additional prompt; do not retry by combining those two forms.
2. Set depth from the tier: low → use the default review. Medium → follow it with your own thorough
   diff pass. High → follow it with an exhaustive diff pass yourself.
3. If nested `codex review` cannot start because its sandbox or user namespace is unavailable,
   review `git diff origin/<base-branch>...HEAD` yourself at the same tier depth and state that the
   automated review was degraded. A tool failure is not a clean review result.
4. Triage every correctness finding it returns. For each one, do exactly one of:
   - Fix it on the branch.
   - Dismiss it with a one-line reason.
5. Do not leave a finding unaddressed. "Probably fine" is not a dismissal —
   write the reason.

**Do not continue until:** every correctness finding is fixed or explicitly
dismissed in writing.

## Step 4 — Security gate (blocking)

There is no automated security review on this host. Walk the checklist yourself.
See `## Degraded vs Claude` at the end of this file for what that costs you.

1. Read the full diff once, looking only for security defects. Check each:
   - Authentication or authorisation removed, weakened or bypassed
   - Tenant or org scoping missing from a query, so one tenant can read another's rows
   - User input reaching SQL, a shell, a file path or a template unsanitised
   - Secrets, tokens or keys added to code, config, logs or error messages
   - A new endpoint without an auth guard
   - Permission checks done in the frontend only
   - PII (TFN, passport, bank details) logged, returned in an API response, or stored unencrypted
   - File upload without type, size or path validation
   - A dependency bump that pulls in a known-vulnerable version
2. If the tier is High, also run the matching hand-checks in
   [`references/risk-playbooks.md`](references/risk-playbooks.md).
3. Sort every finding into high/critical or medium/low.
4. For each **high or critical** finding:
   a. Patch it on the PR branch yourself.
   b. Push, so CI re-validates.
   c. Re-read the changed area to confirm the fix holds.
   d. Repeat until none remain.
5. If you cannot safely patch one — it is ambiguous or too large — then:
   interactive → surface it. Autonomous → emit
   `<<<MERGE_BLOCKED #N security:<finding>>>` and stop.
6. For each **medium or low** finding: append it to the owning context's
   `SECURITY-findings.md` — the append-only log beside its `SECURITY.md`,
   never `SECURITY.md` itself — as a deferred finding. Format and file resolution are in
   [`references/risk-playbooks.md`](references/risk-playbooks.md). These do not
   block the merge.

**Do not continue until:** zero unresolved high or critical findings, and every
medium or low finding is recorded in the owning `SECURITY-findings.md`.

## Step 5 — Static checks

1. Discover the commands first. Read `package.json` scripts and
   `.github/workflows`. Do not guess command names.
2. Run, across the affected workspace: **typecheck**, then **lint**, then
   **build**.
3. Fix every failure before continuing.

The build is the strongest cheap net here. It catches broken imports, missing
exports, DTO mismatches, bad prop and service signatures, and most module wiring.

**Do not continue until:** typecheck, lint and build are all green.

## Step 6 — Automated tests

1. Run tests against the Docker stack. Never against a dev server.
2. Rebuild and restart the affected service. Wait until it reports healthy.
3. Run the suite.
4. If the PR changes behaviour, a test must fail before the change and pass
   after. If no such test exists, write one.
5. If the PR is low tier and move-only, an existing green suite is sufficient —
   no behaviour was intended to change.

**Do not continue until:** the suite is green in Docker and every behaviour
change is covered by a test.

## Step 7 — Runtime verify

1. Boot the affected service or services.
2. Exercise the real path: the happy path, then one failure path, then one edge
   case.
3. Watch the logs while you do it. A green build hides dependency-injection
   errors, module wiring errors, migration errors and console errors. NestJS
   provider and controller wiring is the most common offender.
4. If the tier is High, run the domain hand-checks in
   [`references/risk-playbooks.md`](references/risk-playbooks.md):
   cross-tenant access, auth boundaries, migration against a clean **and** an
   existing database, API contract front-to-back, failure and observability paths.

**Do not continue until:** the affected path is exercised at the depth the tier
demands, with no runtime errors.

## Step 8 — CI and merge

1. Wait for CI to complete: `gh pr checks <#> --watch`. Bound it with a timeout.
2. Never merge on pending checks.
3. If CI does not go green within the timeout: autonomous → emit
   `<<<MERGE_BLOCKED #N ci-timeout>>>` and stop.
4. If the branch is behind base, **merge base into the branch**. Do not rebase —
   the force-push a rebase needs is hook-blocked, and it corrupts migrations and
   shared files.
5. State the merge decision plainly, covering all seven:
   - requirement met
   - diff scoped
   - build green
   - tests green
   - CI green
   - runtime path exercised
   - security gate clean
6. If any gate is still red, do not merge. Autonomous → emit
   `<<<MERGE_BLOCKED #N reason>>>` and stop.
7. Merge **without** `--delete-branch`:
   - Interactive → confirm with the user first, then `gh pr merge <#> --merge`.
   - Autonomous → `gh pr merge <#> --merge`, then emit `<<<MERGED #N>>>`.

Deleting the branch auto-closes any PR stacked on it. A `--delete-branch` merge
silently kills dependent PRs. Prune merged branches separately, and only ever
delete a branch that no open PR uses as its base.

## Step 9 — Leave the tree clean

Before you emit any sentinel, `git status --porcelain` must be empty.

1. Commit and push anything that belongs to the PR.
2. Revert anything that does not.

This is not housekeeping. An autonomous loop re-syncs its worktree at the
*start* of the next cycle, so anything left uncommitted stops that loop outright
with "working tree has uncommitted changes — refusing to touch it". Salvage only
runs at cycle end, so it cannot rescue a tree that is already dirty at startup.

## Reporting

Alongside the standard change summary, report exactly three things:

1. The risk tier.
2. The security-gate result — which high/critical findings you patched, and
   where medium/low were deferred.
3. The merge outcome.

## Degraded vs Claude

**What Claude does that this cannot.** Claude's `do-pr` delegates each
report-producing layer to a parallel sub-agent with a named type, and runs
`/security-review` — a dedicated, purpose-built security pass — as its own
layer. It also has `/code-review` at selectable effort levels and `/verify` as
a first-class runtime-verification skill.

**Why this host cannot.** Codex has no equivalent of `/security-review`,
`/code-review` or `/verify`, and this skill runs sequentially in one context
rather than fanning out. `codex review` covers the code-review layer only.

**What you must do to compensate.**

1. Step 4 replaces a real security review with a checklist you walk yourself.
   **Do not treat a clean pass here as a security review.** It is a smoke test.
2. On any High-tier PR — auth, multi-tenant, payments, PII, legal documents,
   file upload — read `references/risk-playbooks.md` in full and run every
   hand-check it lists. On Claude that is belt-and-braces. Here it is your only
   real coverage.
3. Because everything runs in one context, you accumulate context across all
   nine steps. If the diff is large, re-read the diff before Step 4 rather than
   relying on what you remember from Step 2.
4. If the PR touches money, credentials or personal data and you have any doubt,
   block it and ask a human. A missed finding here is not caught later.
