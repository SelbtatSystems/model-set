---
name: docs-loop
description: Change-aware documentation maintenance loop for AgCore. Each autonomous run scans origin/main for user-visible changes, then completes exactly one coverage, shipped-feature, stale-page, screenshot, or prose-review unit against the running Docker app. Use when the ralph loop invokes it, or the user asks to run the docs loop, document the app, reconcile user-docu, refresh screenshots, or critique the docs.
---

# Docs Loop

Turn the whole AgCore employer app into current user documentation, one unit per run. Persistent
coverage state lives in `memory/AgCore/planning/docs-coverage/QUEUE.md`; change, prose, screenshot,
and feature-reconciliation state lives in `MAINTENANCE.md` beside it. The vault is read/write files
only, never git or scripts. End every run with exactly one sentinel on its own line:

- `<<<DOCS_PUBLISHED <unit-id>>>>` — unit shipped, PR open against main.
- `<<<DOCS_BLOCKED <unit-id> <reason>>>>` — row marked blocked in the queue, working tree left clean.
- `<<<DOCS_CRITIQUE_FILED <count>>>>` — critique pass filed `<count>` new issues.
- `<<<DOCS_ARCHIVED <slug>>>>` — a `user-docu/` folder was verified as documented and archived.
- `<<<DOCS_SATURATED>>>` — a critique pass found nothing worth filing. The runner stops after two
  in a row; never manufacture a finding to avoid it.
- `<<<DOCS_COMPLETE>>>` — queue and backlog are both empty **and** nothing remains to critique.

**A published unit means:** every claim on the page was observed in the running Docker app; every
screenshot is annotated and referenced from the page; the local gate (typecheck · lint · test ·
build) is green for each touched app; the page renders clean in the browser; the queue row and
`memory/log.md` are updated; a PR is open. The companion runner (`scripts/docs-loop.sh` in this
skill) merges that PR next cycle via `/do-pr auto`, so leave the PR open — never merge it yourself.

**Never end the run while work is in flight.** A backgrounded test run, a rebuilding container, a
CI job — none of these is a place to stop and report status. Wait for it, read its result, and carry
on to the sentinel. Ending with "I'll check back once it finishes" leaves the work uncommitted and
the tree dirty, which stops the loop's next sync outright, and the whole unit is redone from scratch
at full cost. A job that genuinely cannot be waited on is a `DOCS_BLOCKED` reason, not an early exit.

**Autonomy policy** — no human is present. Make in-scope changes and run validation without asking.
Retry a transient failure (network, container start, flaky test) at most twice, then mark the row
`blocked` with the reason and emit the sentinel. Permanently out of scope: committing to `main`,
touching `memory/AgCore/planning/issues/` (the feature trackers other loops own — your own backlog
at `docs-coverage/issues/` and archiving into `planning/archive/issues/` are both fine), renaming or
deleting an already-published docs slug or heading id, and force-pushing.

## Read first, every run

- `memory/AgCore/apps/AgCore-web/docs/adr/0012-two-app-hybrid-documentation-hub.md` — where a page
  lives: public pages in `agcore-landing` (Getting Started + Concepts lean public), gated pages in
  `agcore-web` (How-To + Reference lean gated). The visibility line is which app the page lives in.
- `memory/AgCore/planning/user-docu/documentation-hub/PRD.md` — the hub contract (pillars, registry,
  TSX authoring, anchor rules).
- The owning context's `CONTEXT.md` for the surface you document — every `_Avoid_:` line is a banned
  word list.
- `references/maintenance.md` in this skill — startup scan, lane selection, recursive feature
  evidence, page review, screenshot freshness, and the archive gate.
- `references/voice.md` (how to write) and `references/screenshots.md` (capture + ffmpeg annotation)
  in this skill.

## The queue

`memory/AgCore/planning/docs-coverage/QUEUE.md`. One row = one run's unit (one to three closely
related pages on a single surface). Status flows `todo → in-progress → published | blocked | skip`.

```markdown
| ID | Surface | Pages (slug @ app) | Status | Notes |
|----|---------|--------------------|--------|-------|
| gs-welcome | First login, org basics | getting-started/welcome @ landing | todo | |
```

`app` is `web` (Documentation hub) or `landing` (public docs).

## The backlog — `docs-coverage/issues/`

Coverage is one job; **quality is the other, and it never finishes**. `QUEUE.md` answers "is every
surface documented at all"; the backlog answers "is what we published any good". One file per issue
in `memory/AgCore/planning/docs-coverage/issues/`, numbered, same format and `**Triage:**` roles as
every other AgCore tracker (`ready-for-agent` · `ready-for-human` · `needs-info` · `wontfix` ·
`done`). Critique passes write it; build runs consume it.

An issue here is a documentation defect or gap — a screenshot that misleads, a page that skips an
edge case its feature actually has, a section nothing links to, a broken anchor. It is **not** a
product bug: an app defect found while reading the docs goes to the owning feature tracker's
attention via a note in the issue, never fixed here.

## The maintenance ledger

`memory/AgCore/planning/docs-coverage/MAINTENANCE.md` is the exhaustive ledger. It contains every
live public and gated page, every screenshot-bearing page, and every folder physically present in
`planning/user-docu/`. The directory is authoritative; the user-docu README is a maintained summary,
not the intake index. A page remains `unreviewed` or `needs-review` until its prose, source mapping,
live behaviour, and screenshots have been checked at the recorded `origin/main` commit.

Run the change-impact scan in `references/maintenance.md` **before selecting work on every run**.
The scan is intake, not the run's unit: it updates the ledger, then the run completes one selected
unit. Never advance the scan commit while a changed user-facing path is unaccounted for.

### 0. Bootstrap — only if QUEUE.md does not exist

Building the queue is that run's entire unit. Derive the surface list from code, so coverage is
complete by construction, then confirm the nav in the browser:

- `apps/agcore-web/src/main.tsx` (explicit routes) and `src/contexts/NavigationContext.tsx`
  (`pathToPage` — a page only has a URL if it appears here)
- `src/components/Sidebar.tsx` (`navSections`) and `src/app/settings/sectionRegistry.ts`
- `src/app/docs/docsRegistry.ts` — its `planned: true` entries become the first queue rows
- `memory/AgCore/planning/user-docu/README.md` — the feature manifest and its priority flags

Exclude: `/prototype/*`, `/map-side-card-prototype`, `/workforce/employees-preview`, placeholder
admin pages (`/admin/users`, `/admin/audit-log`), Coming-Soon items with no URL (Weather, AI
Assistant), and duplicate paths (`/workforce/workers-portal`, `/agtime`, `/organizations/:id/setup`).

Order rows by the employer lifecycle — set up → staff → hire → record time → correct → pay →
understand → look up — not the app menu. Row 1 is `landing-docs-scaffold` (build the public `/docs`
shell in agcore-landing per ADR 0012: `src/app/docs/` App-Router pages + a typed
`src/data/docs/pages.ts` module rendered through `RichText`, following the `legal`/`blog` pattern;
add the navbar link and `public/sitemap.xml` entries). The last row is `coverage-audit`: re-derive
the surface list from the same sources, diff against everything published, append rows for anything
missed — the loop only completes after an audit that finds nothing.

Write the queue, add one `memory/log.md` line, emit `<<<DOCS_PUBLISHED queue-bootstrap>>>` (no PR —
the vault is not in git).

### 1. Select the unit

Run the startup scan, then work down this precedence and stop at the first hit:

1. an `in-progress` queue, maintenance, or docs-coverage issue unit — finish or redo it
2. the first `todo` `QUEUE.md` row — a wholly undocumented surface still outranks maintenance
3. alternate the two maintenance lanes, using `MAINTENANCE.md`'s `last_completed_lane`:
   - **feature lane:** the oldest unresolved folder physically present in `planning/user-docu/`
   - **page lane:** the oldest `needs-review` or `unreviewed` live page; a ready docs-coverage issue
     on that page goes first
4. when the chosen lane is empty, take the other lane
5. when both are empty, run one full reader journey as the saturation check

`blocked` rows are a note for a human, not a retry queue. A folder whose implementation is absent
from `origin/main` is pending, not documented from an unmerged branch; leave it in user-docu and take
the next feature.

For a unit that will modify code-backed documentation, branch before building. Every such run starts
from the freshly fetched remote main, never from a local branch or whatever HEAD happens to be:
`git fetch origin main && git switch --no-track -c
documentation/<unit-id> origin/main` (a backlog issue uses `documentation/fix-<issue-slug>`). Prove
freshness: `git merge-base --is-ancestor $(git ls-remote origin -h refs/heads/main | cut -f1) HEAD`.
Keep the `documentation/` prefix whatever the work is — the runner counts open PRs by that prefix
and enforces "at most one open at a time".

✓ **Done when:** exactly one unit is marked in progress and, for a code-backed unit, you are on a
fresh `documentation/…` branch off origin/main.

### 2. Establish what is true today

Docs describe what is merged and running, not what was planned. For a related user-docu folder,
follow the recursive evidence read in `references/maintenance.md`. This includes conventional
`issues/**/*.md`, numbered tickets stored at the folder root, implementation reports, plans, maps,
guides, `NEEDS-HUMAN.md`, provenance, and ticket comments. Extract every linked implementation PR
and confirm its relevant behaviour is in `origin/main`; a `done` label or completed plan is not
proof that it merged.

**Edge cases and limits are content, not trivia.** A reader trusts a page that tells them where the
feature stops. From the feature's issues and its code, carry across: what happens at the boundaries
(no data yet, one item, the maximum, an expired or superseded record), what the feature deliberately
does *not* do, and — wherever a surface is backed by an **external data source** — where that data
comes from, how current it is, how precise it is, and what it cannot answer. A capability with a
known weak spot documented plainly beats one that reads as flawless and then surprises someone.

Then read the surface's code and drive it live:
`cd infrastructure/docker && docker compose --env-file ../../.env build <service> && docker compose
--env-file ../../.env up -d` — never the Vite/Next dev server. Log in with the `agcore-web` owner
account from `memory/AgCore/TEST-LOGIN.md`; use the five `agcore-role-users` fixtures to verify any claim about
who can see what. If a screen is empty because the worktree DB has no data, create minimal data
through the UI first — an empty state documents nothing. Walk every path the page will describe and
capture raw screenshots as you go (workflow and gotchas: `references/screenshots.md`).

✓ **Done when:** each claim the pages will make is something you watched happen, and every needed
raw screenshot exists.

### 3. Annotate the screenshots

Compare every screenshot already used by the selected page with the same live Docker surface before
deciding it can stay. The comparison is visual and functional: labels, controls, layout, state,
density, and visible styling must still match. Record the route, account state, purpose, paths, and
verified commit in `MAINTENANCE.md`. Crop and annotate replacements per `references/screenshots.md`, then place finals in
`apps/<app>/public/docs/<page-slug>/NN-<what>.png`. One idea per image. Never let a TFN, bank
detail, or real-looking personal value into a shot.

**Shoot the account state the reader is in.** A page about creating an organisation, first login, or
any other first-run step is read by someone whose app is *empty* — so capture it on a freshly
created account with nothing behind it, not on the loaded fixture org. Unrelated data in the
background of a "you have nothing yet" screen is the single most confusing thing a getting-started
shot can carry. For a page about working with existing records the opposite holds: populate enough
that the screen shows what it is for. This is policy for pages you create or change from now on;
already-published shots are re-taken when an issue or maintenance row requires their review.

✓ **Done when:** every final image is cropped, annotated where an action needs pointing out, and
sitting in the right `public/docs/` folder.

### 4. Write the pages

Voice and structure: `references/voice.md`. One Diátaxis purpose per page — a page that mixes two is
two pages. After the factual draft is complete, invoke `$humanizer:humanizer` in **file mode** on
every new or materially edited page. Then compare the result with the evidence again: preserve every
claim, exact interface label, legal wording, number, link target, heading id, and metadata value.

Preserve the file's established formatting. Inspect the workspace formatter configuration before
running it, and do not accept a formatter pass that rewrites unrelated lines in an existing docs
page. Restore that churn with targeted edits, keep only the documentation change, and review the
final diff before the gate.

**agcore-web (Documentation hub):**
- Page component in `apps/agcore-web/src/app/docs/<Name>Page.tsx`, shaped like
  `SmallBusinessEmployerPage.tsx`. Every `h2`/`h3` gets a stable `id` that never changes once
  shipped. Callouts: `ds-docs-callout--warning` / `--note`.
- Register it in `docsRegistry.ts`: prefer flipping an existing `planned: true` entry; fill
  `description`, `keywords`, `headings`, `order` (contiguous within its pillar+group bucket),
  `audience`, `updated`, `minutes`. New slug must be `<pillar>/...`.
- `docsRegistry.test.ts` hard-codes the expected `liveDocs` slugs — add yours there too.
- Figures: `.ds-docs-figure` in `packages/shared-ui/src/styles/sage-patterns.css`. If the class does
  not exist yet, this unit creates it beside the other `.ds-docs-*` rules (image with border,
  max-width 100%, caption) — the one sanctioned new-class exception.

**agcore-landing (public docs):**
- **Audience: a prospect deciding whether to make an account** (ADR:
  `memory/AgCore/apps/AgCore-landing/docs/adr/0001-public-docs-shallow-seo-depth-gated.md`).
  Public pages orient — the job a capability does, why it matters, one orienting screenshot at
  most. Never step-by-step instructions, settings enumerations, or field-level detail: that depth
  belongs in the gated hub, and the public page links across to it. Write titles, descriptions
  and headings around real search phrases (SEO is the page's second job), and end every page
  pointing at the app (open the app / request access).
- Wherever the reader must act in the app, link the **exact app screen** via the `app-url.ts`
  convention (`https://app.agcore.com.au/<path>`), not a bare "open the app" — the app sends a
  logged-out visitor through login and then on to that screen. Prefer path-shaped URLs: the
  login round-trip currently keeps only the pathname, so `?query`/`#hash` deep links lose their
  detail for logged-out readers.
- Content goes in the typed `src/data/docs/pages.ts` module (HTML-string sections with
  `<h2 id="...">`, like `src/data/legal/pages.ts`), rendered by `src/app/docs/[...]` pages with
  `generateStaticParams` + `generateMetadata`. Figures are plain `<figure><img
  src="/docs/<slug>/NN-x.png" alt="..."><figcaption>` in the section HTML.
- Add each new page to `public/sitemap.xml` (it is a static file, not generated).

✓ **Done when:** pages render with working TOC entries, and each image on them earns its place.

### 5. Verify

Run the app-appropriate gate for every touched workspace: typecheck · lint · test · build. Then
rebuild the touched containers (`docker compose … build <service> && … up -d`) and check in the
browser: page loads from its nav, TOC anchors land, search finds it (web), images load at both
themes and at a 375 px viewport, zero console errors. Fix everything found; a failed gate means fix
and re-run, never skip or weaken a test.

✓ **Done when:** local gate green and the browser pass is clean.

### 6. Record and hand off

1. Queue row → `published`, with the shipped slugs in Notes. Update the page and feature rows in
   `MAINTENANCE.md`. Add one line to `memory/log.md`.
2. For a `planning/user-docu/` feature, apply the archive gate in `references/maintenance.md`.
   Append or replace its `## Documentation` section with the date, verified `origin/main` commit,
   live slugs, current screenshots, and every deliberate omission with its reason. Only then move
   the whole folder to `memory/AgCore/planning/archive/issues/<slug>/`, remove its user-docu README
   row if present, and add a *Documented* row to the archive README. Partially covered means the
   folder stays and its maintenance row states exactly what remains.
3. A backlog issue instead of a queue row → flip its `**Triage:**` to `done` with a `## Comments`
   line naming the PR.
4. When repo files changed, stage explicitly (never `git add .`), commit, push the branch, and run
   `gh pr create --fill`. A vault-only reconciliation opens no empty PR.
5. Emit `<<<DOCS_PUBLISHED <unit-id>>>>`.

✓ **Done when:** any required PR is open, all ledgers match reality, and the sentinel is the last
line.

## Maintenance and saturation passes

Coverage finishing is not completion. Work the exhaustive page and feature rows in
`MAINTENANCE.md` through the two lanes in `references/maintenance.md`; do not sample while any row is
`unreviewed` or `needs-review`. Only after both lanes are current at the same `origin/main` commit,
walk one real reader journey in Docker and dedupe findings against open docs-coverage issues.

File at most three evidence-backed issues, fix only a small certain defect in place, and emit the
existing critique or publish sentinel. Emit `<<<DOCS_SATURATED>>>` only when the ledger is exhaustive
and current, the user-docu directory has no unresolved folders, and the reader journey found
nothing. Emit `<<<DOCS_COMPLETE>>>` only when that is also true and no coverage or backlog unit is
available.

## When blocked

A surface mid-redesign (check `memory/AgCore/planning/issues/` for in-flight work), a broken
container, a gate that stays red after honest fixes: discard only this run's code-repository edits
with safe, targeted changes (never reset or revert the vault), set the row to
`blocked` with a one-line reason, and emit `<<<DOCS_BLOCKED <unit-id> <reason>>>>`. Next run takes
the next row — blocked is a note for the human, not a retry queue.
