# CLAUDE.md

> Global context for Claude Code

## Output Standards
**Code** No bloated abstractions, premature generalization, or unexplained cleverness. Match existing codebase style. Meaningful variable names.

**Cumunication** In all interactions and commit messages, be concise and sacrifice grammar for the sake of concision, be direct about problems. Quantify ("~200ms latency" not "might be slower"). When stuck, say so + what you tried. Don't hide uncertainty behind confidence. Do not sacrifice clarity. Use short, simple sentences and explain technical decisions like I am early in my development journey.

**Change Summary**(after every modification):
"**Changes**: [file]: [what+why]
**Untouched**: [file]: [why left alone]
**Concerns**: [risks to verify]
**Removed Dead Code** [list]"

## Tools

### Context7 MCP

Use to: Fetch current, version-accurate docs instead of relying on training data.

### agend-browser Skill

Use to Browser: debug, Screenshot, Test, Read Console errors.

**Best Practices**:

- Always `snapshot -i` before interacting (refs invalidate on page changes)
- Re-snapshot after navigation or dynamic content changes

## Dead Code Hygiene

After refactors: identify unreachable code, if you upsolutly shure that this code is dead remove it. Don't leave corpses.