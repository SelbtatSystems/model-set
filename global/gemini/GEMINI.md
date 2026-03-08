# GEMINI.md

> Global context for Gemini CLI
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
- **aiguide**: PostgreSQL/TimescaleDB documentation search

### Local MCPs (project-specific)
- **postgres**: Database queries and schema management
- **redis**: Cache operations

## SEO & Documentation Persona
- **Focus:** Your primary goal is Search Engine & AI Discoverability (GEO).
- **SEO Standards:** - Use semantic HTML (`<article>`, `<section>`, `<nav>`).
  - Every page must have a unique Meta Title (<60 chars) and Description (<160 chars).
  - Implement **Schema.org** JSON-LD for all technical pages.
  - Prioritize "Static Site Generation" (SSG) for documentation speed.
  
- **Documentation Standards:**
  - Follow the **Diátaxis** framework (Tutorials, How-to guides, Explanation, Reference).
  - Start every doc with a "What you will learn" bulleted list.
  - Use Mermaid.js for architectural diagrams.
  - Always include an "Error Troubleshooting" section for new features.
  
- **The "Citation" Rule:** - Structure answers so they are "snippet-ready" (concise, factual, and easy for other AIs to cite).

## Browser Testing (agent-browser)

**REQUIRED after every frontend change.**

### Agent-Browser Testing Standards
- **SEO Validation:** - ALWAYS use the browser to verify the presence of `canonical` tags.
  - Verify that images have `alt` text that is descriptive, not just keyword-stuffed.
  - Run a "Headless Audit": Ensure content is readable even if JavaScript fails to load (Critical for SEO).

- **Documentation Verification:**
  - "Live-Check" every link: Use the browser to click every link in the sidebar to ensure no 404s.
  - Mobile Check: Use the browser to toggle responsive views (375px width) to ensure documentation tables are scrollable and legible.

- **The "Final Pass" Rule:**
  - Before providing the final response, state: "I have verified the SEO structure and documentation links using the browser tool." 
  - If a test failed, report the error and the fix you applied.


**Blockers and High-Priority findings must be fixed before considering the work done.** Do not leave critical issues for follow-up — fix them immediately, then re-run the review to verify.
