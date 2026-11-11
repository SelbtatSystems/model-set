# librarian-loop — one vault maintenance pass per day

A Codex librarian maintains the memory vault (`~/Nextcloud/memory`): it runs the vault gate, merges
sync-conflict copies, fixes frontmatter and links, moves finished plans, checks the indexes and
reviews one area. `SKILL.md` holds its rules. It works on vault files only: no git, no network, no
code repository, and it never deletes.

## Run it

```bash
~/model-set/skills/codex/librarian-loop/scripts/librarian-loop.sh --dry-run   # read-only survey
~/model-set/skills/codex/librarian-loop/scripts/librarian-loop.sh             # one real pass
```

In a Codex session inside the vault, `$librarian-loop` runs the same pass with you present.

## Schedule it (one machine only)

```bash
~/model-set/skills/codex/librarian-loop/scripts/install-timer.sh
```

This installs a systemd user timer for 03:00 each day. The vault syncs between machines, and two
librarians that edit the same note make a sync-conflict copy, so install the timer on one machine.

## What a pass leaves behind

Everything is in `~/.local/state/agcore/librarian-loop/`, never in the vault:

- `logs/<stamp>.report.md` — the librarian's report; `logs/<stamp>.log` — the full agent log (30 days).
- `snapshots/vault-notes-<stamp>.tar.gz` — every note before the pass (14 kept). The vault has no
  history, so this is the undo: `tar -xzf <snapshot> -C <dir>` and copy the note back.
- `quarantine/<stamp>/` — files the librarian moved out of the vault, under their vault path.

## Why it cannot do more

Codex runs with `--sandbox workspace-write` and the vault as its working root. It cannot write
outside the vault and the quarantine directory, and it has no network. The script has a lock (one
pass at a time) and a 90-minute limit (`RUN_MINUTES`). `CODEX_MODEL` overrides the model.
