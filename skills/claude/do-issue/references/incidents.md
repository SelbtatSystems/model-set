# Incidents behind do-issue's rules

The rules in `SKILL.md` keep one line of *why*. These are the runs that produced them. Read this file when a rule looks arbitrary and you are tempted to bend it.

## Ending the run while work is in flight — 2026-08-02

Two build agents each ended their turn while a test run was still going ("I'll push once the suite reports"). Together they spent $18 and shipped nothing: no commit, no PR. In the autonomous loop the ticket was redone from scratch, and the dirty tree left behind stopped the loop's next sync.

## Delegating and ending the turn — 2026-08-05

A build agent finished map-evolution ticket 09 — 816 verified lines, backend e2e 14/14, backend units 1887/1887 — then wrote "the only outstanding item is the browser verification agent; I'll commit and PR as soon as it reports" and ended the turn. The runner had started it with `claude --print`, so the process ended and the browser agent died with it. $37.84 spent, nothing committed, no PR, and the loop's ledger held a branch that did not exist on the remote.

## The orphaned migration — 2026-08-05 (same run)

Ticket 09's migration was already applied to the worktree's database, but absent from the base branch once the abandoned unit branch was left behind — an *orphaned* migration, which `db:check` fails on. The loop could then not restart to merge the very PR that would have cleared it, and a human had to break the deadlock by hand. Committing as soon as the gate is green would have made the whole failure recoverable.

## A decision left as `ready-for-agent` — 2026-09-26

pay-adjustments ticket 18 needed a product decision. The agent ended the run without handing the ticket back, so it stayed `ready-for-agent`. The issue-loop picked the same lowest-numbered ticket three cycles running, stopped after `MAX_FAILS` identical failures, and ticket 22 — buildable — never got a turn.
