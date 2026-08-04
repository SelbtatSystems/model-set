---
name: to-user-docs
description: Pick one completed feature from planning/user-docu/, write its Documentation hub pages in agcore-web, verify them in the browser, then retire the folder to planning/archive/issues/. Use when the user wants to write user documentation, document a shipped feature, work the docs queue, or says "write the docs for X" / "pick up the next user-docu ticket". The documentation end of the to-plan → do-plan → to-prd → to-issues → do-issue → do-pr pipeline.
---

# To User Docs

Turn one shipped feature into published user documentation. **One feature per run.** A completed PRD
goes in, live Documentation hub pages come out, and the folder retires to the archive.

The vault is reached via the repo's `./memory` symlink. Read + write files only — never git or
scripts there.

## Read these first, every run

- `memory/AgCore/planning/user-docu/README.md` — the queue, the manifest (what each feature shipped
  and which pillar it feeds), and the audience/terminology caveats.
- `memory/AgCore/planning/issues/documentation-hub/PRD.md` — the hub's contract: four Diátaxis
  pillars, sidebar order, registry as single source of truth, TSX authoring (not MDX), planned-page
  rules, anchor/deep-link contract.
- The owning context's `CONTEXT.md` glossary. Every `_Avoid_:` line is a **banned word list** —
  several exist because the wrong word once caused a bug.

## Process

### 1. Select the feature

If the user named one, use it. Otherwise list `memory/AgCore/planning/user-docu/` and show each
folder's manifest row (target pillar + what shipped), then ask which to document. Prefer the row the
manifest marks highest-impact when the user has no preference.

✓ **Done when:** exactly one folder is chosen and you have read its `PRD.md` and every file under
its `issues/`.

### 2. Establish what is actually true today

A PRD is what was intended, not what runs. Before writing a word:

- **Read the shipped code** for the surfaces the feature describes. Later features amend earlier
  ones — the PRD may describe a screen that has since been redesigned.
- **Run the app in Docker and look at it** (`dc build <service> && dc up -d <service>`, then the
  `agent-browser` skill with `memory/AgCore/TEST-LOGIN.md`). Never the Vite dev server — see the repo CLAUDE.md.
  Screenshot each surface you intend to document.
- **Check `planning/issues/` for in-flight work** on the same surface. Documenting a screen that is
  mid-redesign wastes the page; say so and pick a different feature or a narrower scope.
- **Collect the exact glossary terms** the pages must use.

✓ **Done when:** every claim you plan to make is something you have seen in the running app, and you
can name the in-flight work (if any) that will invalidate part of it.

### 3. Plan the pages, then confirm

Propose the page set before writing: for each page, its `slug` (`<pillar>/<name>`), pillar, How-To
`group` if applicable, title, one-line description, keywords, and the headings it will carry.

Rules from the hub PRD:

- Pillars are **Diátaxis**: `getting-started` (get to a working setup) · `how-to` (recipe for one
  job) · `concepts` (the why) · `reference` (look up a fact). A page that mixes two is two pages.
- How-To groups are **Time & Attendance**, **Hiring & eForm**, **Payroll & Integrations**.
- Sidebar order follows the **employer lifecycle** — set up → staff → hire → record time → correct →
  pay → understand → look up — not the app's own menu.
- Prefer filling an existing `planned: true` registry entry over inventing a new slug. Adding a slug
  is fine; renaming or removing one breaks links and needs the user's approval.

Ask the user to confirm the page set. Do not write pages they did not agree to.

✓ **Done when:** the user has approved the page list.

### 4. Write the pages

- Content components live beside the registry in `apps/agcore-web/src/app/docs/`. Follow the shape of
  the existing page (`SmallBusinessEmployerPage.tsx`) — TSX, no MDX toolchain.
- Every `##`/`###` heading needs a **stable id**; the right-hand TOC and the registry's `headings`
  array read from them. Ids never change once shipped — old links point at them.
- Register each page in `apps/agcore-web/src/app/docs/docsRegistry.ts`: flip `planned` to `false`,
  attach the content component, fill `description`, `keywords`, `headings`, `order`, and `audience`
  where the content is not employer-facing.
- Style is the sage docs treatment already in `sage-patterns.css` (`.ds-docs-*`): article typography,
  serif headings, sharp-left callouts for warnings and notes. Do not invent new classes — check
  `apps/agcore-web/DESIGN.md` first.
- Write for a farmer or their office manager. Short sentences. The task, then the steps, then the
  edge case. Where a rule is legal (award floor, attestation text, record-keeping), say so plainly
  and link the Fair Work source rather than paraphrasing the law.
- If the repo has a `writing-guidelines` skill, run the pages past it.

✓ **Done when:** every approved page renders, has a working TOC, and the registry data test
(`docsRegistry.test.ts`) passes with the new entries.

### 5. Verify

- Quality gate: typecheck · lint · test · build for `agcore-web`.
- In the browser (Docker, `agent-browser`): each new page loads from the sidebar, the TOC tracks and
  highlights, prev/next skips planned entries, search finds the page (once Cmd+K ships), and no page
  appears in search that is still `planned`. Fix **all** console errors.
- Both themes and a 375px viewport.

✓ **Done when:** local gate green, browser clean, screenshots taken.

### 6. Retire the folder

Only when every page in the manifest row for that feature has shipped:

1. Append a `## Documentation` section to the feature's `PRD.md` — the date, the slugs published, and
   anything from the PRD you deliberately did **not** document (with the reason).
2. Move `memory/AgCore/planning/user-docu/<slug>/` → `memory/AgCore/planning/archive/issues/<slug>/`.
3. Delete that feature's row from the `user-docu/README.md` manifest and add a row to the
   `archive/issues/README.md` manifest (kind 2: *Documented*).
4. Append one line to `memory/log.md`.

If only part of the row shipped, the folder **stays** — record progress in the PRD's
`## Documentation` section and say what remains.

✓ **Done when:** the folder is in exactly one place and both manifests agree with reality.

### 7. Report

Name the pages published (slug + pillar), the surfaces you verified in the browser, anything in the
PRD you chose not to document and why, and whether the folder retired or stayed. State what is left
in the queue.

## Notes

- **Employer-gated.** Documentation hub Phase 1 sits behind `requireAgCoreAccess` and is written for
  the employer. Worker-facing behaviour has no home yet — tag it with `audience` and write from the
  employer's side rather than dropping it.
- **The queue is not the truth.** `planning/user-docu/` records what was built; the running app
  records what is. When they disagree, the app wins and the PRD gets a note.
- **Never edit `planning/issues/`** from this skill — that is the live work queue, owned by
  `to-issues` / `triage` / `do-issue`.
