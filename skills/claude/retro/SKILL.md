---
name: retro
description: "Conduct a retrospective on a coding session or a loop run: suggest changes to the agent's environment, most severe first."
disable-model-invocation: true
metadata:
  upstream: mattpocock/skills@a7d038f skills/engineering/retro
---

The user has asked for a **retrospective**. You are suggesting improvements to the coding agent's **environment** to improve future runs. You suggest; you change nothing until the user picks a candidate.

## Steps

1. Call the Skill tool with "writing-for-agents" for the writing style guide.

2. Read the primary sources for the session the user specifies. If they name none, default to the current one.
   - A past Claude session is a transcript in `~/.claude/projects/<project>/*.jsonl`; its subagents are the `agent-*.jsonl` files beside it.
   - A loop run is a stream-json log in `<worktree>/issue-loop-logs/` (`build-*`, `merge-*`, `triage-*`). Its final `result` event holds the closing message and the cost.

3. Read the steering the session ran under: the root and nested `CLAUDE.md`/`AGENTS.md`, `CODING_STANDARDS.md`, the skills it loaded, and the auto-memory (`MEMORY.md`, its hubs, and the notes they link).

4. Look for candidates for improvement in these categories.

- **Navigation**: how easy was it for the agent to find the right files? Are there hidden dependencies between files? Would a **navigation pointer** make it easier? _Use when_ the session took a long time to find a piece of information.
- **Automated checks**: are there automated checks that could catch errors the agent made? Linting, typing, tests, filesystem linters? Read the repo's own check command first (its `package.json`/build-tool `lint`/`check` scripts, its CI workflow), so a check that already exists but sits unwired or silently broken is the finding, not a reinvention. A repo with no **guardrail** (no pre-commit hook and no CI job running its lint/typecheck/test command) is itself a finding: an un-linted repo is a standing missed opportunity, not a neutral default. _Use when_ the agent made a mistake an automated check could have caught, or the repo has no guardrail at all.
- **Coding standards**: should the **reviewer agent** be given a new rule to enforce? Should an existing rule be removed or clarified? Classify the violation first: a **mechanical** one (a fixed syntactic pattern, a banned API, an import shape, a file-location rule) gets a deterministic check, full stop: a custom rule in the repo's own linter, a new pre-commit hook, or a new CI job, whichever the repo's language and existing guardrail make cheapest. Default to building the check over writing the rule. Reserve `CODING_STANDARDS.md` for genuine **judgement calls** (cross-file consistency, "matches the surrounding style," anything no guardrail could ever substitute for). _Use when_ the reviewer agent failed to catch a mistake.
- **Global AGENTS.md**: are there any steering instructions that should be moved to coding standards (or automated checks) instead? _Use when_ the AGENTS.md file is particularly large - in the repo OR the user's global scope.
- **Auto-memory**: a memory note that records a **mechanical** mistake is a check waiting to be built: propose the check, then retiring the note. A note every session needs belongs in a steering file or a skill. A note the code has made untrue gets deleted. _Use when_ the session hit a gotcha a note already described, or the memory index has grown past what a session reads.
- **Tool economy**: did the agent make expensive tool calls that could be streamlined? Is there any custom tooling (CLI's, MCP's) that is particularly token-inefficient? _Use when_ the agent made an expensive tool call.
- **No-ops**: look for instructions in steering files that don't modify the agent's behavior. _Use when_ the steering files are large and unwieldy.
- **Information access**: look for opportunities to increase the agent's access to information. Teeing dev server logs, readonly access to third-party services. _Use when_ a crucial piece of information was not available to the agent.

5. Present these candidates to the user, in order of severity. For each: the evidence (transcript line, log, file), the change, and where it lands.

## Reference

### Implementation vs Review

Remember that all work goes through two stages: implementation and review. The implementation agent has the most **context pressure**. They are responsible for exploration, writing code, and debugging failures.

The review agent has the least context pressure - it receives a diff, so no exploration needed. It often does not need to write code or debug.

This means that the review agent should be responsible for imposing coding standards, not the implementation agent. In this setup the review agent is `two-axis-review`'s Standards axis, run by `do-pr` on every PR.

### Files

- `CLAUDE.md`/`AGENTS.md`: pushed to the context window of any agent working in this repo. They should be used incredibly sparingly, usually only for **navigation pointers** to other files. In AgCore they are a pair (Claude reads one, Codex the other): a change to one goes into both. Nested ones are `CLAUDE.md` with an `AGENTS.md` symlink beside it.
- `CODING_STANDARDS.md` (repo root): read during review, not implementation. Add **navigation pointers** to docs folders if it gets more than 1,000 lines long.
- Docs: use docs as reference files, pointed to by other files. Look for existing docs before writing new ones. AgCore's live in the vault (`memory/AgCore/`), which takes file edits only.
- Skills: use skills for docs (since their description goes into the agent's context window), or for user-invoked commands. Follow the advice in the `writing-for-agents` skill. They live in `~/model-set/skills/` (rules: `skills/CONTRACT.md`); a fix that stops a failure goes into both the `claude/` and `codex/` copies.
- Auto-memory: `~/.claude/projects/<project>/memory/`, per machine. `MEMORY.md` is the index; group lines into hubs rather than letting it grow.
- Evidence across many runs: `~/model-set/scripts/skill-usage.py` (how often each skill loaded or was refused, per agent) and `~/model-set/scripts/loop-outcomes.py` (how loop runs ended, and their cost).
