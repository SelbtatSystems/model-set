# Incidents behind do-pr's rules

The rules in `SKILL.md` keep one line of *why*. These are the runs that produced them. Read this file when a rule looks arbitrary and you are tempted to bend it.

## A sub-skill's report ended the run — 2026-08-03 (admin loop)

`/review`, `/code-review`, `/security-review` and `/verify` are each built to *finish* with a report. Invoked inline, that terminal framing ended the whole do-pr run; prose reminders twice failed to prevent it. One merge log is 54 lines of code review of PR #826, the next is 9 lines of security review of PR #834 — both immaculate, both ending mid-pipeline with no sentinel and no merge, each discarding a full review. Delegating each report-producing layer to a subagent moved the "report and stop" onto the subagent.

## A subagent reviewing from the wrong directory — 2026-08-18, PR #1146

A subagent inherits the *session's* working directory, not the parent's. The session had started in a folder holding several worktrees — not a git repo — so `/security-review` and `/code-review` refused to launch, and `EnterWorktree` refused too. The subagent fell back to reviewing commits by hand, which looked like a hang rather than an error: ~3.5 h and ~101k tokens on a review a second agent had already completed.

## Ending the turn on a background watcher — 2026-08-04, PRs #849 and #850

The runner spawns do-pr with `claude --print`: single-shot. Twice a merge agent hit the Bash timeout on `gh run watch`, armed a Monitor, wrote "the monitor will wake me when it reaches a terminal state" and ended the turn. The process ended and the Monitor died with it. PR #849 cost $14.18 and PR #850 $11.36, each burning a full cycle before a retry merged the already-green PR in seconds.

## A dirty tree stopped the loop — PR #834

A one-line comment edit was left uncommitted while reviewing PR #834. The autonomous loop re-syncs its worktree at the *start* of the next cycle and refused to touch it ("working tree has uncommitted changes — refusing to touch it"), which took the admin loop down. Salvage only runs at cycle *end*, so it cannot rescue a tree that is already dirty at startup.

## Default watch intervals exhausted the API quota — 2026-08-16

`gh run watch` refreshes every 3 s by default and `gh pr checks --watch` every 10 s; each refresh is a REST call against the 5000/hour core quota shared by every loop on the machine. One default-interval watch spends ~390 calls; at `--interval 30` it spends ~40. Four loops watching CI on the default exhausted the hourly quota and stalled every pipeline.
