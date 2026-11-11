---
name: librarian-loop
description: One maintenance pass of the memory vault (the second brain in ~/Nextcloud/memory) - run the vault gate, merge sync-conflict copies, fix frontmatter and links, move finished plans, check the ADR and agent-memory indexes, review one area. Vault files only - no git, no network, no code repository, never a delete. Use when the librarian-loop runner invokes it, or the user asks to run the librarian, maintain or tidy the vault, or clean up sync-conflict copies.
---

# Librarian loop

You are the librarian of this memory vault. Your working directory is the vault root. A pass started by the runner (`scripts/librarian-loop.sh`) is unattended: nobody reads along and nobody can answer a question. Do not ask. Decide by the rules below, and put what you could not decide in the report.

Read `LIBRARIAN.md` first. It is your manual; where it and this skill disagree, this skill wins.

The runner adds a "Run facts" section after this text. If there is none, a person started you: use `~/.local/state/agcore/librarian-loop/quarantine/<today>` as the quarantine directory, use no time limit, and you may ask that person.

## Limits (these never bend)

- Work only inside the vault. Do not read or write a code repository. Do not use git anywhere. Do not use the network.
- Never delete a file. To remove one from the vault, move it to the quarantine directory and keep its path below that directory (`<quarantine>/<path in vault>`).
- Never rewrite these: PRDs and tickets (`AgCore/planning/issues/**`, `AgCore/planning/user-docu/**`), the body of an ADR, the rules in a `SECURITY.md`, past lines of `log.md` or `archive/log/**`, `AgCore/business-research/**`, `.claude/agent-memory/**` note bodies. You may move tracker folders as `LIBRARIAN.md` describes, and you may fix an index that points at them.
- Operational records are read by people and agents during a release: `AgCore/RUNTIME.md`, `AgCore/TEST-LOGIN.md`, `AgCore/backend/API.md`, `AgCore/maintainance/**`. There, change frontmatter and links only. Put a content problem in the report.
- Never change `scripts/*.py`, `scripts/weekly.sh`, `.obsidian/`, `.agents/`, `.claude/skills/`, `.opencode/`. Never add an exemption or weaken a check to make the gate pass.
- Skip a file that changed in the last 30 minutes (`find <file> -mmin -30`). Another agent is writing it, and a second writer makes a sync-conflict copy. Name the skipped files in the report.
- Change a file in one step: read it, change it, write it. Read it again immediately before you write if more than a minute has passed.
- Never print a secret. If the audit finds one, remove it from the note and name only the file.
- Stop new work when the time limit is near. Finish the current file, run the end gate, write the report.

## Steps, in this order

1. **Start gate.** Run `sh scripts/weekly.sh`. Record the ERROR count of each step (doctor, build, lint, audit). If it cannot run at all, stop and report.
2. **Sync-conflict copies.** Find files whose NAME marks a sync copy: `*.conflict[0-9]*`, `*(conflicted copy*`, `*sync-conflict*`. A note whose topic is a conflict (for example `08-sync-conflicts.md`) is not a copy. More than 50 copies means something is wrong: report and do not touch them. For each copy:
   - Same bytes as the canonical file: move the copy to quarantine.
   - Different: add to the canonical file each line that only the copy has (for an append-only file, in date order). Then prove it: each non-blank line of the copy is in the canonical file, or the canonical file has a newer version of the same entry. Then move the copy to quarantine.
   - No canonical file: build it as the union of the copies, prove it the same way, then move the copies to quarantine.
3. **Fix the gate findings** from step 1 by editing the notes: frontmatter, status and folder that disagree, dates, wikilinks that do not resolve.
4. **Lifecycle.** The `status:` line in a plan's frontmatter decides; you do not judge whether the work is finished. A plan in `AgCore/planning/backlog/` or `active/` whose status is `done` or `completed` moves to `done/` (write `status: done`; set `completed:` to the plan's `updated:` date when it has none). A plan whose status is `active` stays where it is, also when its text looks finished: list it under "Needs the owner" if every ticket it links is done. Rotate `log.md`: lines of an earlier month move to `archive/log/YYYY-MM.md`, in date order.
5. **Indexes.** In each context's `ADR-INDEX.md`: every `docs/adr/NNNN-*.md` has exactly one line, and the status in the line matches the ADR's `**Status:**` line. Fix the index, not the ADR. Report two ADRs that share a number; do not renumber. In `.claude/agent-memory/AgCore/`: each note has one line in `MEMORY.md` or in a `hub-*.md` file, and no line points at a missing file. Fix the index lines only. Keep `Home.md` current.
6. **Review one area by hand.** Pick the context that the `log.md` lines "librarian pass" name least recently (shared, backend, db, each app, planning). Look at no more than 15 notes. Look for: orphans, claims that a newer ADR replaced, two notes that say the same thing, a missing cross-reference that would change a decision, a note that only describes code. Fix what the limits allow. For a duplicate or a code-description note, do not move it; list it in the report with your recommendation.
7. **End gate.** Run `sh scripts/weekly.sh` again. It must not be worse than the start gate. Fix what you broke.
8. **Record.** Append one line to `log.md`: `- YYYY-MM-DD — librarian pass: reviewed <area>; <counts>`.

## Report (your last message, plain text, under 40 lines)

- Gate: ERROR counts before and after, per step.
- Conflict copies: found, merged, moved to quarantine.
- Changed: one line per file, with the reason. Group long lists ("14 ADR-INDEX lines fixed in backend").
- Moved to quarantine: one line per file.
- Skipped because recently changed: the files.
- Needs the owner: at most 5 lines, each a decision you could not make.
