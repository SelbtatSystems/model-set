---
name: admin-loop
description: Autonomous ralph-loop for the AgCore Admin Command Center. Each run works exactly ONE unit — build the next ready-for-agent issue from the admin-command-center backlog end-to-end (branch → build → Docker-verify → PR), or, when the queue is empty, run a critique pass over the running dashboard (screenshot, hunt gaps against the PRD + DESIGN.md, file new issues) — then end with one sentinel. Use when the admin-loop runner invokes it, or the user says "run the admin loop" / "work the admin backlog" / "critique the admin dashboard".
---

# Admin Loop

Build and then keep improving the Admin Command Center, one unit per run. The backlog is
`memory/AgCore/planning/issues/admin-command-center/issues/` (the vault — read and write
**files only**, never git or scripts there). End every run with exactly one sentinel on its
own line (the runner `scripts/admin-loop.sh` parses these — change them in skill AND script
together, never one side alone):

- `<<<ADMIN_BUILT <issue-file>>>>` — slice built, PR open against main. Leave the PR open;
  the runner merges it next cycle via `/do-pr auto`. Never merge it yourself.
- `<<<ADMIN_BLOCKED <issue-file> <reason>>>>` — this issue needs a human; issue annotated,
  working tree left clean.
- `<<<ADMIN_CRITIQUE_FILED <count>>>>` — critique pass filed <count> new issues.
- `<<<ADMIN_SATURATED>>>` — critique pass found nothing worth filing.

**Autonomy policy** — no human is present. Make in-scope changes and run validation without
asking. Retry a transient failure (network, container start, flaky test) at most twice, then
emit `ADMIN_BLOCKED` with the reason. Permanently out of scope: committing to `main`;
touching the wayfinder tickets (files `01-…` through `21-…`) or MAP.md history; flipping any
`needs-triage` issue (the deferred Kuma/PostHog set 44–46 is Sven's call); merging PRs;
force-pushing; running scripts inside `memory/`.

## Read first, every run

1. `memory/AgCore/planning/issues/admin-command-center/PRD.md` — the contract (stories,
   implementation decisions, test seams, the needs-triage carve-out).
2. `memory/AgCore/planning/issues/admin-command-center/MAP.md` — Destination + Decisions
   index; zoom a decision ticket only when the unit touches its area.
3. `memory/AgCore/apps/Admin-web/DESIGN.md` if it exists (it is built by issue 26); until
   then, the variant C + h2 references on branch `prototype/admin-sage-redesign` and
   `memory/AgCore/apps/AgCore-web/DESIGN.md` are the design authority.
4. `memory/AgCore/apps/Admin-web/SECURITY.md` — non-negotiables for the highest-privilege
   surface (server-side @Roles on every /admin/* route, audit, no tokens in URLs).

## Branch lane — `admin-panel/`

**Every branch this loop creates is named `admin-panel/<issue-number>-<slug>`** (e.g.
`admin-panel/22-sage-nav-home-shell`). This is load-bearing, not cosmetic: the runner only
counts and merges PRs whose head branch carries that prefix, so the admin loop and any other
loop (or human) can work the same repo concurrently without fighting over the
"one open PR" invariant. A slice pushed on any other prefix is invisible to the runner and
will sit unmerged — if you find yourself on a non-`admin-panel/` branch, rename it before
pushing (`git branch -m`).

## Select the unit

Scan `issues/` for files numbered **22 or higher** with `**Triage:** ready-for-agent`.
A candidate is takeable when every entry in its `**Blocked by:**` line is satisfied:

- an issue filename → that issue's `**Triage:**` is `done`;
- a wayfinder ticket filename (e.g. `21-provision-dingo-mail.md`) → that ticket's
  `**Status:**` is `closed` **with a Resolution section**;
- a prose external gate (e.g. "stripe-subscription-billing PRD must be shipped") → every
  issue in that feature's folder is `**Triage:** done`.

Take the lowest-numbered takeable issue → **Build pass**. If none is takeable but blocked
ready-for-agent issues remain, emit `ADMIN_BLOCKED` naming the tightest gate (usually a HITL
provisioning task). If no open ready-for-agent issues remain at all → **Critique pass**.

**Issue 47 (QA — full implementation review) is a build unit, not a critique pass**, and it
comes first: it is a queued issue blocked by 22–43, so the selector takes it as soon as its
blockers close. It verifies acceptance criteria against the running app; the critique pass
asks the different question of what the criteria never covered. Run 47 as an ordinary build
unit and let critique passes follow it.

## Build pass

Run the **do-issue** skill against the selected issue and see it through end-to-end: read the
issue as the contract, explore the current code fresh, build the vertical slice on a new
`admin-panel/<issue-number>-<slug>` branch (see Branch lane above), validate against the Docker containers (never the dev server — rebuild the touched
service and wait healthy), verify in the browser with agent-browser (admin login needs TOTP —
see the admin-web 2FA memory/notes; set `AGENT_BROWSER_SESSION=admin-loop`), run the local
gate (typecheck · lint · test · build) for every touched app, open ONE PR against main with
`gh pr create --fill`, flip the issue's `**Triage:**` to `done` with a `## Comments` line
referencing the PR, add one `memory/log.md` line, then emit `ADMIN_BUILT`.

House rules that bite here: migration + init.sql together + `check-init-schema.sh`; the
rls-role-permissions invariant; new backend routes 404 until the container restarts;
multipart org routes need `?orgId=`; never weaken or skip tests to pass.

## Critique pass — "the previous iteration is a 100; find what makes it 120"

1. Open the running admin dashboard in the Docker stack (agent-browser, TOTP login) and walk
   every nav group, watching the console on every route. Screenshot to record what you saw —
   but **sample rather than exhaust the matrix**: a full route × light/dark × desktop/390px
   sweep costs most of a pass's wall time and rarely earns it. The high-yield probes are the
   console walk, a contrast audit, keyboard-focus checks, and asserting state the UI claims
   (e.g. exactly one nav item marked current). Screenshot the pages you actually reason about.
2. Judge against the PRD's stories + acceptance shape, `Admin-web/DESIGN.md`, and the MAP
   Destination — hunting in this order: broken flows and console errors · missing/dishonest
   states (fake numbers, dead tiles, silent failures) · security-rule violations · design
   deviations from the C/tile-wall language · UX friction on the operator's daily paths
   (morning status read, support case, payment trouble) · genuinely missing capability
   toward the Destination.
3. **Dedupe before filing — this is the step that makes a pass useful.** Read the OPEN issues
   in the folder before filing anything; if a finding matches an open issue or the deferred
   44–46 set, it is not a finding. In a dense queue most of what you see is already ticketed,
   and a pass that files "the costs page is empty" when that is a queued issue has failed.
   - **Budget**: at ~20 issues read them all. Beyond that, grep titles + `## What to build`
     first and open only the plausible matches in full — never skip the step to save tokens.
   - **When a finding matches an issue's *spirit* but not its acceptance criteria** (the queued
     issue would plausibly absorb it), **reject it and name it in your report** rather than
     filing. The report is where near-misses live; the queue is for what the queue does not
     already say.
   - **Defects buried in a closed issue's `## Comments`** (a builder noted something but never
     filed it) are invisible to a queue grep — those ARE fileable, and worth checking for.
4. File at most **3** new issues per pass — quality over volume, continuing the folder's
   numbering, using the standard issue template with testable acceptance criteria:
   `ready-for-agent` when an agent can build it alone; `ready-for-human` when it needs a
   product/design decision that is Sven's. Never file into the deferred set's scope.
5. Update `memory/log.md` (one line), emit `ADMIN_CRITIQUE_FILED <count>` — or, if nothing
   survived the dedupe and the honesty bar, `ADMIN_SATURATED` (the runner stops after two
   consecutive saturations; do not manufacture findings to avoid it).
