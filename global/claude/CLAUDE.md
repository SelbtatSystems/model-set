# Global agent context

> Identical copies: `~/.claude/CLAUDE.md` = `~/.codex/AGENTS.md` — when you change one, apply the same change to the other.

## Output Standards

**Code** — No bloated abstractions, premature generalization, or unexplained cleverness. Match existing codebase style. Meaningful variable names.

**Communication** — Talk in ASD-STE100 Simplified Technical English. Concise and direct about problems; clarity wins when the two conflict. Quantify ("~200ms latency", not "might be slower"). When stuck, say so + what you tried; don't hide uncertainty behind confidence. Explain technical decisions in short, simple sentences, as to someone early in their development journey.

**Change Summary** — after a nontrivial modification (new behavior, refactor, multi-file change — not typo/rename/formatting):
"**Changes**: [file]: [what+why]
**Untouched**: [file]: [why left alone]
**Concerns**: [risks to verify]
**Removed Dead Code**: [list]"

## Tools

- **Context7 MCP** — fetch current, version-accurate library/framework docs instead of relying on training data (details: `context7-mcp` skill).
- **agent-browser skill** — browser debugging, screenshots, testing, reading console errors. `snapshot -i` before interacting; re-snapshot after navigation (refs invalidate on page changes).
- **Subagent models (Claude Code)** — research, design-decision, and planning subagents inherit the session model (no override). All other subagent tasks (implementation, mechanical sweeps, routine work) run **Opus 5** (`model: "opus"`) at **high reasoning effort** wherever effort is settable (e.g. Workflow `agent()`); the Agent tool has no effort knob — model override only. **Exception** — all agent-browser browser testing and frontend testing (e.g. the `frontend-review` agent, agent-browser QA sweeps) run **Sonnet 5** (`model: "sonnet"`) at **high reasoning effort**.

## Credentials

Never write a production login into any file — not a repo, a vault note, a memory note, a skill, or a log. Production test credentials arrive only as environment variables set by the human in the shell that launches the agent (AgCore: `AGCORE_QA_EMAIL` / `AGCORE_QA_PASSWORD`); use them as `$VAR` in the command that fills the form, never echo or store the value. If you find a production credential written down, remove it and tell the user.

## Dead Code Hygiene

After refactors, remove code you are absolutely sure is unreachable — dead code misleads the next reader. If unsure, flag it instead of deleting. Don't leave corpses.
