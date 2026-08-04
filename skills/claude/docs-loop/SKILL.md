---
name: docs-loop
description: Autonomous ralph-loop documentation sweep for AgCore. Each run works exactly ONE unit — the next docs-coverage queue row, else the next ready-for-agent issue in docs-coverage/issues, else a critique pass (read the published docs as a user and file gaps, or reconcile a planning/user-docu feature folder and archive it once documented) — verifying every claim in the running Docker app, then opening a PR and ending with one sentinel. Use when the ralph loop invokes it, or the user says "run the docs loop", "document the whole app", "docs sweep", or "critique the docs".
---

# Docs Loop

Turn the whole AgCore employer app into published user documentation, one unit per run. Persistent
state lives in `memory/AgCore/planning/docs-coverage/QUEUE.md` (the vault — read and write files
only, never git or scripts there). End every run with exactly one sentinel on its own line:

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

Work down this precedence and stop at the first hit:

1. an `in-progress` `QUEUE.md` row — a crashed earlier run; finish or redo it
2. the first `todo` `QUEUE.md` row — a surface with no documentation yet
3. the lowest-numbered `ready-for-agent` issue in `docs-coverage/issues/` whose `**Blocked by:**`
   entries are all `done` — a quality gap on something already published
4. nothing in 1–3 → **critique pass** (below). This is the normal steady state once coverage is
   complete, not an error.

Coverage outranks quality deliberately: an undocumented surface fails a reader worse than an
imperfect page. `blocked` rows are a note for a human, not a retry queue — never take one.

For 1–3, branch before building. Every run starts from the freshly fetched remote main, never from a
local branch or whatever HEAD happens to be: `git fetch origin main && git switch --no-track -c
documentation/<unit-id> origin/main` (a backlog issue uses `documentation/fix-<issue-slug>`). Prove
freshness: `git merge-base --is-ancestor $(git ls-remote origin -h refs/heads/main | cut -f1) HEAD`.
Keep the `documentation/` prefix whatever the work is — the runner counts open PRs by that prefix
and enforces "at most one open at a time".

✓ **Done when:** you know which of the four you are doing, and — for 1–3 — exactly one row or issue
is marked in progress and you are on a fresh `documentation/…` branch off origin/main.

### 2. Establish what is true today

Docs describe what runs, not what was planned. First check
`memory/AgCore/planning/user-docu/` — its README manifest maps shipped features to target pages;
if a folder there covers this unit's surface, read its `PRD.md` and everything under `issues/`
before writing: the user stories say what the feature is *for*, and the build issues say how it
actually works, including the edge cases worth documenting.

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

Crop and annotate with ffmpeg per `references/screenshots.md`, then place finals in
`apps/<app>/public/docs/<page-slug>/NN-<what>.png`. One idea per image. Never let a TFN, bank
detail, or real-looking personal value into a shot.

**Shoot the account state the reader is in.** A page about creating an organisation, first login, or
any other first-run step is read by someone whose app is *empty* — so capture it on a freshly
created account with nothing behind it, not on the loaded fixture org. Unrelated data in the
background of a "you have nothing yet" screen is the single most confusing thing a getting-started
shot can carry. For a page about working with existing records the opposite holds: populate enough
that the screen shows what it is for. This is policy for pages you create or change from now on;
already-published shots are re-taken only when an issue names them.

✓ **Done when:** every final image is cropped, annotated where an action needs pointing out, and
sitting in the right `public/docs/` folder.

### 4. Write the pages

Voice and structure: `references/voice.md`. One Diátaxis purpose per page — a page that mixes two is
two pages.

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

1. Queue row → `published`, with the shipped slugs in Notes. One line in `memory/log.md`.
2. If the unit drew on a `planning/user-docu/` feature folder, append a `## Documentation` section
   to that folder's `PRD.md`: the date, the slugs published, and anything from the PRD deliberately
   not documented (with the reason). When every page the README manifest expects for that feature
   is now live — public and gated — retire the folder: move it to
   `memory/AgCore/planning/archive/issues/<slug>/`, delete its row from the `user-docu/README.md`
   manifest, and add a *Documented* row to the archive README's manifest. Partially covered →
   the folder stays and the PRD section records what remains.
3. A backlog issue instead of a queue row → flip its `**Triage:**` to `done` with a `## Comments`
   line naming the PR.
4. Stage explicitly (never `git add .`), commit, push the branch, `gh pr create --fill`.
5. Emit `<<<DOCS_PUBLISHED <unit-id>>>>`.

✓ **Done when:** the PR is open, the queue matches reality, and the sentinel is the last line.

## Critique pass — when there is no unit to build

Coverage finishing is not the loop finishing. Alternate the two passes below, newest first: run
**reader critique** if the last critique pass was a reconciliation, and vice versa. Read
`memory/log.md`'s recent docs lines to see which it was.

### A. Reader critique — "the docs are a 100; find what makes them 120"

Read the published documentation the way someone with a problem reads it, in the running Docker
stack — never the dev server.

1. **Walk it as a reader, not an author.** Pick a real question a user arrives with ("how do I fix a
   wrong clock-out", "what does this rate mean"), start where they would start, and see whether the
   docs answer it. Watch the console on every page. Sample rather than exhaust: the high-yield
   probes are scroll and anchor behaviour, TOC accuracy, images at both themes and 375 px, search
   hits (web), dead links, and pages whose claims the app no longer matches.
2. **Hunt in this order:** broken behaviour and console errors · claims that are no longer true ·
   missing edge cases and limits the feature actually has · screenshots that mislead (wrong account
   state, stale UI, unreadable crop) · a page nothing links to from where the reader needs it ·
   voice and structure drift from `references/voice.md`.
3. **Dedupe before filing — this is the step that makes a pass useful.** Read the open issues in
   `docs-coverage/issues/` and the `blocked` queue rows first. A finding that matches an open issue
   is not a finding. Name near-misses in your report rather than filing them.
4. **File at most 3** new issues, continuing the folder's numbering, each with testable acceptance
   criteria: `ready-for-agent` when an agent can do it alone, `ready-for-human` when it needs a
   product or design decision.
5. **Fix in place only what is small and certain.** If a finding is a self-evident defect you can
   correct in a few lines and prove in the browser (a broken anchor, an unscrollable container, a
   dead link, a wrong label), fix it on a `documentation/fix-<slug>` branch, run the local gate, and
   open the PR as an ordinary unit — then it needs no issue. Anything needing judgement about what
   the docs should *say*, anything touching more than one page's structure, or anything you would
   have to guess at: file it instead. When in doubt, file — a wrong fix ships, a wrong issue gets
   read first.
6. One `memory/log.md` line. Emit `<<<DOCS_CRITIQUE_FILED <count>>>>`, or `<<<DOCS_PUBLISHED
   fix-<slug>>>>` if the pass ended in a fix PR, or `<<<DOCS_SATURATED>>>` if nothing survived the
   dedupe and the honesty bar.

### B. user-docu reconciliation — close the loop on shipped features

`memory/AgCore/planning/user-docu/` holds the feature folders whose documentation is not yet
confirmed. Take **one** folder per pass, oldest first by its README manifest row.

1. Read its `PRD.md` and every file under `issues/`. Build the list of what a user would need to
   know: the capability, its edge cases, its limits, and any external data source's currency and
   precision.
2. Check that list against what is actually published — the hub pages and the public pages the
   manifest names. Verify in the browser, not from the registry alone.
3. **Fully covered** → append the `## Documentation` section to its `PRD.md` (date, slugs, anything
   deliberately not documented and why), move the folder to
   `memory/AgCore/planning/archive/issues/<slug>/`, delete its `user-docu/README.md` row, add a
   *Documented* row to the archive README manifest, and emit `<<<DOCS_ARCHIVED <slug>>>>`.
4. **Gaps found** → file them as backlog issues (at most 3, same bar as above), record what remains
   in the PRD's `## Documentation` section, leave the folder where it is, and emit
   `<<<DOCS_CRITIQUE_FILED <count>>>>`.

Archiving is a claim that a reader is properly served by what is published. Do not archive to make
the folder count go down.

## When blocked

A surface mid-redesign (check `memory/AgCore/planning/issues/` for in-flight work), a broken
container, a gate that stays red after honest fixes: revert uncommitted changes, set the row to
`blocked` with a one-line reason, and emit `<<<DOCS_BLOCKED <unit-id> <reason>>>>`. Next run takes
the next row — blocked is a note for the human, not a retry queue.
