# model-set

Portable configuration for Claude Code, Codex CLI and OpenCode — clone it onto a
machine, run one script, get a working setup with per-agent skill sets.

Design rationale, including why the previous layout couldn't do this, is in
[PLAN.md](PLAN.md).

## Setup

```bash
git clone https://github.com/SelbtatSystems/model-set.git ~/model-set
cd ~/model-set

cp .env.example .env && $EDITOR .env      # three API keys

./scripts/setup.sh
```

Then log in — setup can't do this for you, all three agents use OAuth:

```bash
claude                 # then /login
codex login
opencode auth login
```

Verify:

```bash
./scripts/doctor.sh
```

### Flags

| Flag | Effect |
|---|---|
| `--with-ollama` | Install Ollama (off by default — multi-GB local model runtime) |
| `--with-obsidian` | Install the Obsidian CLI (off by default — needs a vault) |
| `--no-sogni` | Skip the Sogni image/video/music skill |
| `--force` | Replace existing config files instead of skipping them |

### Migrating from the old layout

If this repo previously symlinked your whole config directories
(`~/.claude -> global/claude`), run the one-time migration **with all agents
closed**:

```bash
./scripts/migrate-from-symlink.sh --dry-run   # inspect first
./scripts/migrate-from-symlink.sh
./scripts/setup.sh
```

A fresh clone never needs this.

## How it works

**File ownership.** The repo owns individual files, listed in
`scripts/lib/manifest.sh`, and symlinks each into whatever location its tool
expects. Config directories stay owned by the tools, so sqlite databases,
session logs and credentials never enter the repo.

Anything not on the manifest does not travel to a new machine.

**No generated config.** All three tools expand environment variables natively
(`${VAR}` for Claude, `env_vars` for Codex, `{env:VAR}` for OpenCode), so configs
are plain tracked files. No templates, no substitution, no secrets baked into
generated output, nothing that can go stale on re-run.

## Skills

Three sets, three different rules — see [skills/CONTRACT.md](skills/CONTRACT.md).

| Set | Consumers | Dialect |
|---|---|---|
| `skills/claude/` | Claude Code | Claude-native |
| `skills/codex/` | Codex **and** OpenCode | GPT |
| `skills/external/` | all three | upstream's — never edit |

The Claude and Codex sets are independent and hand-authored. The same skill is
written differently in each, because Claude handles latitude and prose framing
well while GPT-class models follow explicit numbered procedure more reliably.

`skills/manifest.json` declares routing policy; membership comes from globbing
the directories, so it can't drift from what's on disk. Each host's skills
directory is a farm of per-skill symlinks back into the repo — so editing
`~/.claude/skills/tdd/SKILL.md` *is* editing the tracked file. Edit in place,
`git diff` shows it.

A skill can be marked Codex-only in the manifest; it then gets the full Codex
stack (`codex review`, `~/.codex/agents/`, `~/.codex/prompts/`) and is never
linked into OpenCode. `do-pr` is the current example.

```bash
./scripts/lint-skills.sh              # enforce the contract
./scripts/lint-skills.sh --worklist   # machine-readable violations
```

**External skills** come from elsewhere and are exempt from the lint. Two kinds:
npm-delivered (Sogni — symlinked straight from the global install, so
`npm update -g` takes effect) and repo-synced (`agent-browser`,
`react-best-practices`, `react-native-skills`, `composition-patterns`,
`frontend-design`, `nodejs-backend-patterns`, `skill-creator` — vendored in
`skills/external/`, tracked by `skills-lock.json`).

## MCP servers

| Scope | Servers | Delivery |
|---|---|---|
| Global | `context7`, `aiguide` | Claude: registered by setup at user scope · Codex: `config.toml` · OpenCode: `opencode.json` |
| Project | `postgres` | `apply-local.sh` writes the project's `.mcp.json` |

Claude's global MCP is the one imperative step — `~/.claude.json` holds runtime
state and can't be a symlink, so setup runs `claude mcp add -s user`.

`DATABASE_URI` for postgres belongs to the project's own `.env`, never to
model-set's.

## Per-project setup

```bash
./scripts/apply-local.sh /path/to/project
```

Writes `CLAUDE.md`, `AGENTS.md` and a postgres `.mcp.json`. Never overwrites
existing files.

## Environment

`.env` holds secrets only — `CONTEXT7_API_KEY`, `FIRECRAWL_API_KEY`,
`SOGNI_API_KEY`. It's gitignored; fill it by hand on each machine from
`.env.example`.

Behaviour flags live in `setup.sh` so they're tracked in git. Setup appends a
block to your shell rc that sources `.env` and exports
`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` / `OPENCODE_DISABLE_EXTERNAL_SKILLS` —
without those, OpenCode would also read the Claude skill set.

## Scripts

| Script | Purpose |
|---|---|
| `setup.sh` | Install CLIs, link config and skills, register MCP |
| `doctor.sh` | Verify an install; non-zero exit on failure |
| `lint-skills.sh` | Enforce `skills/CONTRACT.md` |
| `apply-local.sh` | Apply project-level config to a repo |
| `migrate-from-symlink.sh` | One-time migration off the old layout |
| `uninstall.sh` | Remove links and shell block (`--purge-tools` for CLIs) |
| `claude-update.sh` | Update Claude Code with resume + checksum, no download deadline |

## Troubleshooting

**OpenCode sees Claude's skills** — the env flags aren't exported in that shell.
Open a new shell, or `source ~/.zshrc`.

**agent-browser won't launch** — containers and hardened kernels have no usable
sandbox. Setup detects this and writes `--no-sandbox` to
`~/.agent-browser/config.json`. Check with `agent-browser doctor`.

**MCP servers missing in a project** — global servers are registered at user
scope; run `claude mcp list`. Project servers need `apply-local.sh`.

**A skill isn't showing up** — `./scripts/doctor.sh` reports dangling links.
Codex-only skills are deliberately absent from OpenCode.
