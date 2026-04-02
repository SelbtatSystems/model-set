# AGENTS.md

> Global context for OpenAI Codex CLI
## Output Standards
**Code** No bloated abstractions, premature generalization, or unexplained cleverness. Match existing codebase style. Meaningful variable names.

**Cumunication** In all interactions and commit messages, be concise and sacrifice grammar for the sake of concision, be direct about problems. Quantify ("~200ms latency" not "might be slower"). When stuck, say so + what you tried. Don't hide uncertainty behind confidence.

**Change Summary**(after every modification):
"**Changes**: [file]: [what+why]
**Untouched**: [file]: [why left alone]
**Concerns**: [risks to verify]
**Removed Dead Code** [list]"

## Git & GitHub
- Use `gh` CLI for GitHub operations
- Prefix branches with `sven/`

## MCP Servers

### Global MCPs (always available)
- **stitch**: Generate UI designs from text prompts
- **context7**: Documentation lookup and code context

### Local MCPs (project-specific)
- **postgres**: Database queries and schema management
- **redis**: Cache operations

## Browser Testing (agent-browser)

Use `agent-browser` to debug and test in the browser 

### Best Practices
- Always `snapshot -i` before interacting (refs invalidate on page changes)
- Re-snapshot after navigation or dynamic content changes


**REQUIRED after every feature implementation and frontend change.**

Run the `design-review` skill after completing UI work. The agent reviews visual consistency, accessibility, responsiveness, and code health against project design systems and S-Tier SaaS standards.

**Blockers and High-Priority findings must be fixed before considering the work done.**
Do not leave critical issues for follow-up — fix them immediately, then re-run the `design-review` to verify.
