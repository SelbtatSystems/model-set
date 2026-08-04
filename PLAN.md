# model-set — portable setup rebuild

Goal: `git clone` this repo onto a second server and have a working, correct
install — with Claude and Codex running genuinely different skill sets.

Decisions below came out of a design review of the existing setup. Each one
records *why*, because the reasons are the part that rots first.

---

## Why the current design can't meet the goal

Three structural problems, all confirmed against the repo:

1. **The repo owns whole config directories.** `~/.claude` is a symlink to
   `global/claude/`, so Claude's sqlite files, session logs, `daemon.log`,
   `agent-memory/`, `plugins/` and `.credentials.json` all live inside the git
   repo. `.gitignore` is ~60 lines of damage control chasing files the CLIs
   invent. It also cannot work for OpenCode at all, whose config and data live
   in *different* XDG directories.

2. **Skill divergence is impossible.** `setup.sh:seed_skills_dir()` copies
   `skills/` into each tool's directory only if the target doesn't exist, and
   those targets are gitignored. Result: all 41 shared `SKILL.md` files are
   currently **byte-identical** between `global/claude/skills/` and
   `global/codex/skills/`, and none of the local drift is in git. A fresh clone
   gives both tools the same 34 skills.

3. **Config generation is stale-by-design.** Setup `sed`-substitutes secrets
   into `~/.mcp.json` and skips the file if it already exists, so `git pull &&
   setup.sh` never picks up template changes. `~/.mcp.json` is also the wrong
   path — `.mcp.json` is Claude's *project* scope, so global MCP only applies
   when the working directory happens to be `$HOME`.

Concrete symptom the user hit: **`do-pr` is broken under Codex** because it
invokes `/code-review`, `/security-review`, `/review`, `/simplify`, `/verify`
and `/workflows` — Claude Code *built-in slash commands* that Codex does not
have. A copy-paste of that file into a Codex set cannot work at any wording.

---

## Architecture

### 1. File ownership, not directory ownership

The repo owns a **manifest** of specific files, each symlinked individually into
whatever location its tool expects. Config directories stay real directories
owned by the tools.

```
global/claude/settings.json        → ~/.claude/settings.json
global/claude/CLAUDE.md            → ~/.claude/CLAUDE.md
global/claude/agents/*.md          → ~/.claude/agents/
global/claude/scripts/*.py         → ~/.claude/scripts/
global/codex/AGENTS.md             → ~/.codex/AGENTS.md
global/codex/config.toml           → ~/.codex/config.toml
global/codex/rules/*.rules         → ~/.codex/rules/
global/opencode/opencode.json      → ~/.config/opencode/opencode.json
```

Runtime state never enters the repo. `.gitignore` collapses to a few lines.
Each tool's idiosyncratic path is one manifest entry — which is what fixes
OpenCode.

**Cost, stated plainly:** anything not on the manifest does not travel. The
current tree already demonstrates the failure mode — `claude-update.sh`,
`global/codex/rules/agents.rules`, `global/claude/agents/frontend-review.md`
and ten skill directories are untracked today and would be lost on a new
machine.

### 2. Tools in scope

| Tool | Status |
|---|---|
| Claude Code | core |
| Codex CLI | core |
| OpenCode | core |
| agent-browser | core (default-on) |
| firecrawl CLI | core (default-on) |
| Sogni | default-on, `--no-sogni` to skip |
| Warp plugin | default-on (Claude Code + OpenCode) |
| Ollama | `--with-ollama`, default off |
| obsidian CLI | `--with-obsidian`, default off |
| Gemini CLI | **removed** |
| Stitch | **removed** |
| Ralph | **removed** |
| PowerShell scripts | **removed** |
| higgsfield | never installed; superseded by Sogni |

Flags rather than named profiles: profiles are a second thing to maintain and
they rot — six months on, "server" means whatever it meant the day it was
written. Flags are self-documenting at the call site.

Gemini goes because Stitch was its reason for being here, and it costs a whole
tool's worth of branching in a script that has to be trustworthy on a fresh box.
PowerShell goes because it is ~1,400 lines that must mirror every change below,
and the target is Linux servers. Both remain in git history.

### 3. Skills

Three categories, three different rules.

| Category | Source of truth | Dialect | Lint |
|---|---|---|---|
| Own — Claude | `skills/claude/` in git | Claude-native | Claude rules |
| Own — Codex | `skills/codex/` in git | **GPT-dialect** | common-denominator |
| External | npm / upstream | not ours to rewrite | exempt |

The seed model is deleted. There is no shared `skills/` source tree; each set is
its own starting point.

**`skills/codex/` is GPT-dialect throughout** — explicit numbered procedures,
tight role framing, low ambiguity, less "use your judgement."

**Capability floor.** By default a Codex skill may assume only: file I/O, shell,
MCP, and other skills in its own set. Not `codex review`, not `~/.codex/agents/`,
not `~/.codex/prompts/` — because OpenCode shares this set and has none of them.

**Codex-only opt-in.** A skill may declare `hosts = ["codex"]` and then use the
full Codex stack. `do-pr` is one: it gets `codex review`, `~/.codex/agents/`
sub-agents and `~/.codex/prompts/`, and OpenCode never sees it.

**Degraded skills** carry a required `## Degraded vs Claude` block naming what
Claude does, why this host can't, and what to do manually instead. Silent
degradation is worse than absence — it gives false confidence that a real
review happened.

#### Linking

Every tool's skills directory is a **generated farm of per-skill symlinks**,
driven by `manifest.toml`. Uniform across all three tools:

```
~/.claude/skills/<name>           → skills/claude/<name>   or skills/external/<name>
~/.codex/skills/<name>            → skills/codex/<name>    or skills/external/<name>
~/.config/opencode/skills/<name>  → skills/codex/<name>    or skills/external/<name>
```

Per-skill rather than a single directory symlink, because a tool's set is a
*union* of its own skills and the shared external ones — a single link can only
point at one source. It also gives host targeting for free: OpenCode is only
linked to skills marked `hosts = ["codex", "opencode"]`, so Codex-only skills
are physically invisible to it. Setup prunes stale links when the manifest
changes.

Symlinks — not copies — so editing `~/.claude/skills/tdd/SKILL.md` *is* editing
the repo file. Editable in place **and** tracked, with no build step and no
copy-back.

OpenCode also scans `~/.claude/skills/` and `~/.agents/skills/` for
compatibility, which would leak the Claude set into it. Blocked by exporting:

```sh
OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1
OPENCODE_DISABLE_EXTERNAL_SKILLS=1
```

(Both verified present in the OpenCode 1.18.7 binary.)

#### External skills

Skills we don't author. Two flavours, distinguished by how they update — both
exempt from the GPT-dialect rewrite and from the lint, because the prose isn't
ours to change.

**npm-installed** — the package *is* the skill. Symlinked straight from the
install location into all three agents, never vendored:

```
~/.npm-global/lib/node_modules/@sogni-ai/sogni-creative-agent-skill
   → ~/.claude/skills/sogni   → ~/.codex/skills/sogni   → ~/.config/opencode/skills/sogni
```

npm stays the version manager, so `npm update -g` actually takes effect.
Currently just Sogni.

**repo-synced** — materialised into `skills/external/` by `npx skills add`, and
tracked in git because there is no install step that would recreate them:
`agent-browser`, `react-best-practices`, `react-native-skills`,
`composition-patterns` (all `vercel-labs/agent-skills`), and `skill-creator`
(Anthropic). One `skills-lock.json` records repo + path + version; setup refreshes
from it.

`skills/external/` is shared — linked into the Claude *and* Codex sets rather
than duplicated in each.

> Earlier draft said to delete `skills-lock.json`. That was wrong: it is the
> lockfile for the repo-synced flavour, not a bad reimplementation of npm. The
> *duplicate* copy (repo root and `skills/`) is the actual problem — keep one.

#### Supporting files

- `skills/manifest.toml` — per-skill set membership, host targeting, external flag
- `skills/CONTRACT.md` — Claude-only constructs and their Codex equivalents; the
  document whose absence caused the `do-pr` bug
- `scripts/lint-skills.sh` — fails on Claude-only constructs in shared Codex
  skills, and on a missing `## Degraded vs Claude` block where required

### 4. MCP

No template/sed generation. All three tools expand env vars natively, so secrets
are never baked into a generated file and nothing goes stale on re-run.

| Scope | Servers | Delivery |
|---|---|---|
| Global | context7, aiguide | Claude: `claude mcp add -s user` · Codex: `[mcp_servers.*]` with `env_vars` · OpenCode: `mcp` block with `{env:VAR}` |
| Project | postgres | `apply-local.sh` writes the project's own `.mcp.json`; `DATABASE_URL` from the project's `.env` |
| Removed | stitch, redis | — |

Claude's global MCP is the one imperative step: `~/.claude.json` also holds
runtime state and cannot be symlinked. Setup shells out, guarded by an
already-registered check. The setup script is the source of truth, and it is in
git.

Deleted: `global/mcp/mcp.json.template`, `global/codex/config.toml.template`.
`global/codex/config.toml` stops being a tracked *generated* file — it becomes a
plain tracked config, which also ends the merge conflict on every pull.

### 5. OpenCode

Two separate bugs. The path was wrong — OpenCode reads
`~/.config/opencode/opencode.json`, not `~/.opencode/settings.json`. The
*content* was also wrong: the ~50-entry allowlist under `permissions.autoApprove`
is not OpenCode's schema and has been silently ignored since it was written. The
filename gives away the origin — `settings.json` is Claude's convention.

`opencode.json` is rewritten from scratch against the real schema (`permission`
singular, with `edit` / `bash` / `webfetch`), carrying over the *intent* —
auto-approve git/npx/docker/agent-browser/firecrawl, ask otherwise. The
`@warp-dot-dev/opencode-warp` plugin, currently only in the live machine config
and not in the repo, comes into the tracked file.

> Verify against `https://opencode.ai/config.json` before finalising.

### 6. Secrets and environment

`.env` — secrets only, gitignored:

```
CONTEXT7_API_KEY
FIRECRAWL_API_KEY
SOGNI_API_KEY
```

`.env.example` — **committed**. The README currently instructs `cp .env.example
.env` and the file does not exist, so step one of a new-machine setup fails
today.

Behaviour flags (`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS`, etc.) live in the setup
script, tracked in git — they are design decisions, not secrets. Setup currently
sources the whole `.env` into the shell rc, making every var global in every
shell; that is fine for three API keys and wrong for configuration.

Postgres stays out of the global `.env` entirely — `DATABASE_URL` belongs to the
project.

Prerequisites gain **ffmpeg** (Sogni's `requires.anyBins`) alongside python3,
jq, node. Setup probes for non-interactive sudo up front and fails fast rather
than hanging on a password prompt midway through `agent-browser install
--with-deps`.

**Auth cannot be scripted.** Claude, Codex and OpenCode all use OAuth here. The
README needs an explicit post-setup checklist — otherwise setup "succeeds" into
three unusable CLIs.

---

## Phasing

### Phase 1 — portable and honest

Everything above. `skills/codex/` starts as the current content and the lint runs
immediately, emitting the phase-2 worklist. End state: the repo clones onto
server #2 and installs correctly. The Codex set is still Claude-dialect and
`do-pr` is still broken — but the lint says so out loud, in named files at named
lines. Visibly broken beats silently broken, and it converts a blocking cliff
into a measurable backlog.

Also in phase 1: **`scripts/doctor.sh`** — verifies every manifest symlink
resolves, every CLI is installed and on PATH, MCP servers respond, required env
vars are set, and skill sets are linked where expected. Without it, "did it
install correctly?" is answered by trial and error.

### Phase 2 — GPT-dialect rewrite

Skill by skill, worst offenders first, `do-pr` leading. One commit each. The lint
goes green incrementally and then gates CI.

~40 skills, several thousand lines of prose, each a genuine rewrite rather than a
find-and-replace. This is why it is not phase 1: blocking portability on it costs
weeks.

---

## Deviations taken during implementation

- **`manifest.json`, not `manifest.toml`.** `jq` is already a hard prerequisite;
  a bash TOML parser would have been a liability for no gain.
- **The manifest declares policy, not membership.** Setup globs the set
  directories, so the manifest cannot drift from what is on disk.
- **`skills-lock.json` is kept, not deleted.** It is the lockfile for the
  repo-synced external flavour. Reading it also showed the external
  classification was incomplete — `frontend-design` and `nodejs-backend-patterns`
  were tracked in it but had been left in the own-skills sets.
- **Config-file manifest is a bash array** (`scripts/lib/manifest.sh`), not JSON.
  Only `setup.sh`, `doctor.sh` and `uninstall.sh` consume it, and they are all
  bash; JSON would have added parsing for no consumer.
- **`migrate-from-symlink.sh` added.** Not foreseen: an existing machine has
  `~/.claude` symlinked into the repo with live sqlite handles open. Switching
  layouts underneath a running agent would corrupt its session, so the migration
  is a separate script to run with everything closed. A fresh clone skips it.
- **`migrate-from-symlink.sh` also removes legacy seeded skill copies.** That
  step began as an ad-hoc loop in the migration notes and got its host→set
  mapping wrong, reporting a `skills/claude` skill stranded in the OpenCode
  directory as an unrecoverable orphan. Membership is a filesystem check across
  every set, so it now lives in the script where it cannot be re-derived wrongly.
  The same pass fixed a `--dry-run` that probed for collisions through the very
  symlink it had only *pretended* to remove, and so reported moving nothing.

## Open items

- **`skills/claude/` dialect audit** — the Claude set was never reviewed for
  Claude-only constructs that are simply *wrong* rather than host-incompatible.
  Out of scope for both phases as agreed, but worth a pass eventually.

### Closed

- **Phase 2 worklist** — done 2026-08-04. `./scripts/lint-skills.sh` is green
  across all 38 Codex skills. The last 8 violations were `context7-mcp` (3),
  `improve-codebase-architecture` (2), and a Claude-only `allowed-tools:` key in
  `design-md`, `enhance-prompt` and `firecrawl-cli`. One commit each. `do-pr`'s
  12 were cleared earlier.
- **Legacy `.gitignore` section** — deleted 2026-08-04, after
  `migrate-from-symlink.sh` ran on this machine. Removing it exposed no
  newly-untracked runtime files, which is the proof the migration was complete.
