# Maintenance: keep every page tied to the current app

Read this on every docs-loop run. `QUEUE.md` records whether a surface has documentation at all.
`MAINTENANCE.md` records whether the published explanation and its pictures still match the app.

## Ledger contract

The ledger lives at `memory/AgCore/planning/docs-coverage/MAINTENANCE.md` and carries:

- `last_scanned_commit`: the `origin/main` commit through which user-visible changes were classified
- `last_completed_lane`: `feature` or `page`, used to alternate work without starving either lane
- one row for every live page in the gated and public registries
- one row for every folder physically present under `planning/user-docu/`

Page status is `unreviewed`, `needs-review`, `in-progress`, `current`, or `blocked`. Feature status is
`unreviewed`, `in-progress`, `partly-covered`, `pending-merge`, or `blocked`. Moving a feature to the
archive removes its row. A page is `current` only at a named `origin/main` commit and only after its
prose, source mapping, live behaviour, and every referenced screenshot have been checked.

The registries and filesystem are authoritative. At startup, add missing live pages and user-docu
folders to the ledger as `unreviewed`; remove a page row only when the page was intentionally retired
under the existing stable-slug rules. A missing README manifest row never hides a folder.

## Startup change-impact scan

Run this before selecting the unit. It is intake, not the run's unit.

1. Resolve the current remote commit with `git fetch origin main` and `git rev-parse origin/main`.
2. Compare `last_scanned_commit..origin/main`. Inspect user-visible changes under the web apps,
   shared UI, route/navigation registries, and any backend or shared-type change that alters a
   documented result, permission, limit, state, or error.
3. Also check `planning/active/`, live feature tickets under `planning/issues/`, and newly arrived or
   changed folders under `planning/user-docu/`. Plans and tickets identify redesigns; they do not
   override what is merged and running.
4. Map each changed surface to published pages by its route, exact screen labels, in-app docs links,
   screenshot content, registry keywords, and the page's existing source mapping. Mark every affected
   row `needs-review` with the changed paths and commit range.
5. Classify internal refactors, tests, comments, and invisible fixes as checked without making a page
   stale. A changed shared style makes an image stale only when the captured pixels visibly change.
6. Advance `last_scanned_commit` only when every user-visible changed path is either attached to a
   maintenance row or recorded as having no documentation effect.

Do not document an unmerged branch. When a related feature PR is still open, mark its feature row
`pending-merge`; leave any currently published page at its last verified commit and revisit after the
merge reaches `origin/main`.

## Feature lane: read the whole implementation record

Choose the oldest unresolved directory, using the earliest merged implementation date recorded in
its tickets and falling back to lexical folder order. For the selected folder, recursively list and
read every Markdown file. That includes:

- `PRD.md`, `PLAN.md`, `MAP.md`, `NEEDS-HUMAN.md`, and `User-Guide.md`
- conventional `issues/**/*.md`
- numbered tickets stored at the feature root
- implementation reports, provenance sections, and every `## Comments` section

Build an evidence checklist with one row per user-facing capability, edge case, limit, permission,
empty state, error state, external-data constraint, and deliberate non-capability. Record which
ticket and implementation comment support each row. Extract linked PRs and confirm with `gh pr view`
or commit ancestry that the relevant implementation is in `origin/main`. A checked acceptance box,
`done` triage value, or plan status is not merge evidence.

Check the evidence list against current code and the running Docker app, then map each row to a live
page and section. Later changes win over the PRD. If the app contradicts an accepted ADR or security
rule, stop and surface it rather than documenting the contradiction as intended behaviour.

Outcomes:

- Fully covered and archive gate green: retire the folder and emit `DOCS_ARCHIVED`.
- A page needs work: update or create the closely related pages as this run's unit, then archive only
  if the gate becomes green.
- More than one unit remains: record the page mapping and exact gaps, leave the folder
  `partly-covered`, and file at most three deduplicated docs-coverage issues.
- Implementation absent from main or a redesign is active: mark `pending-merge` or `blocked` with the
  evidence and take the next eligible feature.

## Page lane: exhaustive prose and screenshot review

Take the oldest `needs-review` row, then the oldest `unreviewed` row. Review one page, or up to three
pages that explain one tightly coupled surface.

1. Read the page, its registry entry, mapped feature evidence, owning glossary, and relevant ADRs.
2. Drive every described path in Docker with the roles the page names. Populate enough data to see
   the real workflow, boundaries, and error states.
3. Check the explanation for the reader's actual question. Improve missing concepts, reasons,
   boundaries, examples, and recovery steps. Keep one Diátaxis purpose per page.
4. Compare every embedded picture with the same live state using the screenshot test below.
5. Draft factual prose, run `$humanizer:humanizer` in file mode, then audit the result against the
   evidence again. Exact UI copy, legal wording, facts, numbers, links, metadata, and heading ids must
   survive unchanged unless the live app proves they changed.
6. Verify navigation, search, TOC anchors, links, images, light/dark themes, 1440 px and 375 px, and a
   clean browser console. Run the touched workspaces' full local gate.
7. Record the source paths, screenshot paths and capture state, verified commit, and outcome. Mark
   `current` only after every check passes.

## Screenshot freshness test

A picture is current only when a reader can find the same screen and recognise every instruction it
supports. For each image, record in the page row or its notes:

- image path and the page section that uses it
- exact app route, including stable query state when required
- fixture or account state, role, viewport, density, and theme used for capture
- what the annotation is teaching
- verified `origin/main` commit

Open that state in the running app and compare it with the published image. Replace the image when a
label, control, position, layout, empty/data state, density, or visible style makes the old picture
look unlike the current task. Keep it when intervening code changes are invisible in the captured
region. Retain the filename when the instructional idea is unchanged so links do not churn; use a
new numbered filename when the idea changed.

The existing July/August images start `unreviewed`. A page edit does not make its screenshots current
automatically.

## Archive gate

Archiving claims the feature's readers are properly served. All conditions must be true:

- every Markdown file in the feature folder was read, including implementation comments
- every user-facing behaviour is mapped to a live page/section or excluded with a specific reason
- the relevant implementation exists in `origin/main` and was observed in Docker
- no active plan or live ticket is redesigning the documented surface
- all affected prose passed the humanizer and fact-preservation checks
- every referenced screenshot matches the current app and has capture evidence
- browser checks and local gates are green
- the PRD `## Documentation` section names the date, verified commit, live slugs, screenshot status,
  deliberate omissions, and anything still blocked
- the user-docu README, archive README, maintenance ledger, and folder location agree

If one condition fails, leave the folder in user-docu. Never archive it merely because an existing
page mentions the feature.

## Saturation

Do not sample or emit `DOCS_SATURATED` while any live page is `unreviewed` or `needs-review`, any
eligible feature folder remains, or `last_scanned_commit` differs from the commit the current rows
were checked against. Once the ledger is current, walk one real reader journey. Dedupe any findings
against open documentation issues before filing at most three.
