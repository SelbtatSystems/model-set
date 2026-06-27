---
name: do-issue
description: Execute one ready-for-agent ticket end-to-end to done. Use when the user wants to work the next ticket from the issue tracker, or build a specific ticket they name. The executor end of the to-prd → to-issues → triage pipeline.
---

# Do Issue

Build one `ready-for-agent` ticket to done — the executor end of `to-prd` → `to-issues` → `triage`. **One ticket per run**, the same lifecycle every time.

The tracker spec — where tickets live, the issue file format, the find-work command, and the triage roles — is defined in `docs/agents/issue-tracker.md` + `docs/agents/triage-labels.md` (reached via the repo's `## Agent skills` block). Read them; this skill does not restate them. Run `/setup-matt-pocock-skills` if that config is missing.

## Process

### 1. Select the ticket

If the user named a ticket, use it. Otherwise grep the `ready-for-agent` queue and take the **lowest-numbered `NN-*.md`** whose `**Blocked by:**` is `None` or a ticket already marked `done`. The PRD is not a ticket — skip it.

Stop and surface to the user — build nothing — if the ticket is not AFK (`**Triage:** ready-for-human`), a blocker is still open, or nothing qualifies.

✓ **Done when:** one AFK issue file is chosen and every blocker it names is `done`.

### 2. Read the contract

The ticket's **Agent Brief** (or its *What to build* + *Acceptance criteria*) is **the contract** — the spec you build against. Read it in full, plus the parent PRD for intent. Then load the owning context per `docs/agents/domain.md`: the `**App:**`'s `CONTEXT.md` glossary and the ADRs in that area. Work in glossary vocabulary. If the contract contradicts an ADR, stop and surface it instead of overriding.

✓ **Done when:** you can restate the acceptance criteria as a checklist and you know the owning context.

### 3. Branch

Cut a `<type>/<desc>` branch off the up-to-date base, per the repo's git rules — never on `main`/`master`.

✓ **Done when:** you are on a fresh branch off current base.

### 4. Build the tracer bullet

Implement the slice end-to-end through every layer it touches. Delegate to the fitting build skill — `tdd` for a feature, `diagnose` for a `bug`, the stack skills (`senior-backend`, `react-best-practices`, …) for domain work. Hold to the contract's *Out of scope*; do not gold-plate.

✓ **Done when:** every acceptance criterion is satisfied by something you built.

### 5. Go green — verify by running, not reading

Discover the repo's quality gate first (`cat package.json`, `ls .github/workflows`), then run it — typecheck · lint · test · build. Check **each acceptance criterion by executing the actual check** (`verify`, `agent-browser`, `design-review`, a query, a request) — never by inspecting code or diffs. A criterion you cannot execute stays unchecked: report it as such, do not claim it.

✓ **Done when:** the gate is green and every acceptance criterion was confirmed by a command you ran.

### 6. Open the PR

`gh pr create` against the base. The body restates the slice, lists each acceptance criterion with its verified result, and references the ticket.

✓ **Done when:** the PR exists and names the ticket.

### 7. Close the loop in the tracker

In the ticket file: flip `**Triage:**` to `done` and append a dated `## Comments` line linking the PR; commit the wiki. **Never modify the parent PRD.** Then name the tickets this unblocks and stop — the next run takes the next ticket.

✓ **Done when:** the ticket's `**Triage:**` reads `done` and a `## Comments` entry links the PR.
