---
name: do-pr
description: Merge a pull request without shipping a regression. Risk-tier the change, run layered review (codex review → $security-review → runtime verify), patch every correctness and high/critical security finding, gate on green build + tests + CI, then merge. Runs interactively or in an autonomous merge loop. Use when the user wants to merge a PR, asks whether a PR is safe or ready to merge, or wants a senior-style pre-merge check of the current branch or a GitHub PR by number.
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

Then read the PR body's `## Merge danger` section, if it has one:

1. `Door: one-way` → the tier is High.
2. A blast radius wider than one screen or one endpoint → the tier is at least Medium.
3. The section only raises the tier. Never lower the tier from the diff because of it: the author's call is a claim, not proof.

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

Run `$security-review` in a **separate, read-only Codex session**. The reviewer
collects the diff, learns the repository's security patterns, traces candidates,
and filters false positives using that skill's exclusions and confidence cutoff.
Do not substitute a checklist or your earlier code-review conclusions.

1. Finish and commit intended correctness patches from Step 3 first: the security
   skill reviews committed changes only. Resolve the PR's base branch, update its
   remote-tracking ref in this parent session, and capture the base commit SHA and
   `HEAD` SHA. Do not change either revision while the reviewer runs.
2. Start a fresh `codex exec --sandbox read-only -c 'approval_policy="never"'`
   from the checked-out PR repository. Pass `$security-review` literally, the
   resolved base SHA, expected HEAD SHA, and the installed skill path
   `${CODEX_HOME:-$HOME/.codex}/skills/security-review/SKILL.md` in its prompt.
   In shell, use single quotes for the literal `'$security-review'` so `$security`
   is not expanded. Use `--output-last-message` with a fresh temporary report
   path outside the repository. If `PR_MODEL` or `PR_EFFORT` is set by the loop,
   pass it through `--model` or `-c model_reasoning_effort=...`, respectively;
   otherwise retain the user's Codex configuration.
3. Wait within this turn for the process to finish, then read its **final report**.
   Do not treat progress events as a verdict. A nonzero exit, missing/empty final
   report, a `Security review blocked:` report, unresolved base, failed diff,
   revision mismatch, or a reviewer that cannot start is a failed security gate.
   A blocked report can arrive with exit code 0; inspect the report itself.
   Accept only the skill's finding report, exact clean result, or verified
   empty-diff result as a completed review. Retry a transient failure; if it
   persists, interactive → surface it, autonomous → emit
   `<<<MERGE_BLOCKED #N security-review-failed>>>` and stop. Never interpret a
   tool failure as zero findings. Accept an empty-diff result only after
   independently confirming the captured base-to-HEAD diff is empty.
4. If the tier is High, also run the matching hand-checks in
   [`references/risk-playbooks.md`](references/risk-playbooks.md) in the parent
   session. Builds, tests, patches, and findings-log writes belong to the parent,
   never the read-only reviewer.
5. Sort every finding into high/critical or medium/low. For each **high or
   critical** finding:
   a. Patch it on the PR branch yourself.
   b. Commit and push, so CI re-validates.
   c. Repeat the independent `$security-review` against the updated HEAD and
      confirm the fix holds. Repeat until none remain.
6. If you cannot safely patch one — it is ambiguous or too large — then:
   interactive → surface it. Autonomous → emit
   `<<<MERGE_BLOCKED #N security:<finding>>>` and stop.
7. For each **medium or low** finding: append it to the owning context's
   `SECURITY-findings.md` — the append-only log beside its `SECURITY.md`,
   never `SECURITY.md` itself — as a deferred finding. Format and file resolution
   are in [`references/risk-playbooks.md`](references/risk-playbooks.md). These
   do not block the merge. The security skill reports only HIGH and MEDIUM;
   do not ask it to add excluded LOW findings. Retain this deferral rule for
   findings from the other review layers.
8. If later fixes or a base merge change the reviewed code, repeat this gate on
   the new revisions before merging.

**Do not continue until:** the separate review has completed successfully, zero
unresolved high or critical findings remain, and every medium or low finding is
recorded in the owning `SECURITY-findings.md`.

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

1. Keep a draft PR in draft until all review, security, local-check and runtime
   gates pass and their fixes are committed and pushed. If the branch is behind
   base, **merge base into the branch**, then repeat the affected review and
   local gates before proceeding. Never rebase a pushed branch.
2. Mark it ready only now: `gh pr ready <#>`. If it is already ready, preserve
   that state. The repository's `ready_for_review` event starts the full CI jobs
   that were deferred while the PR was a draft.
3. Wait for the full CI run on the current PR head:
   `gh pr checks <#> --watch --interval 30`. Confirm that the post-ready run has
   started; a previous green draft run with skipped test jobs is not full CI.
   Require every applicable test/E2E job to run and pass. Jobs excluded because
   their workspace is unaffected may remain skipped.
   Record the PR head and base commits associated with that run before waiting.
   Inspect a failed job before retrying. If the failure is transient and both
   commits are unchanged, use `gh run rerun <run-id> --failed` once; diagnose a
   repeat instead of retrying until green. This reruns whole failed jobs and
   their dependants, not individual failed tests. If a fix or base merge changes
   the code, push it and require fresh applicable checks on the new snapshot.
   An old run always retries its original snapshot, even when `main` has moved.
   If the original snapshot cannot be established, do not reuse its successes
   as evidence for newer code. Follow a repository guard's explicit recovery
   rule: AgCore's draft-skip guard needs a full rerun to refresh draft outputs.
4. A shell-call timeout is not a CI result. Repeat the watch within this turn;
   allow about 40 minutes before autonomous mode emits
   `<<<MERGE_BLOCKED #N ci-timeout>>>`. Never merge on pending checks. If new
   fixes or another base merge change HEAD, repeat affected gates and wait for
   CI on the new head before merging.
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
