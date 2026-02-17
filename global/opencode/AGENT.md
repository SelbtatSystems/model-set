# AGENT.md

> Global context for opencode

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

## Browser Testing (agent-browser)

**REQUIRED after every frontend change.**

### Installation
```bash
npm install -g agent-browser
agent-browser install  # Download Chromium
```

### Quick Workflow
```bash
agent-browser open http://localhost:3000/path
agent-browser snapshot -i          # Get interactive elements
agent-browser screenshot ~/model-set/skills/agent-browser/screenshots/test.png
agent-browser click @e1            # Interact by ref
agent-browser close
```

### Key Commands
```bash
agent-browser open <url>           # Navigate
agent-browser snapshot -i          # Interactive elements w/ refs
agent-browser click @e1            # Click by ref
agent-browser fill @e2 "text"      # Fill input
agent-browser screenshot ~/model-set/skills/agent-browser/screenshots/name.png  # Capture
agent-browser wait --network       # Wait for API calls
agent-browser close                # Done
```

### Snapshot Ref Format
```
@e1 [button] "Submit"           # Button with text
@e2 [input type="email"]        # Email input
@e3 [a href="/page"] "Link"     # Anchor link
```

### Best Practices
- Always `snapshot -i` before interacting (refs invalidate on page changes)
- Re-snapshot after navigation or dynamic content changes
- Use `--headed` flag to see browser for debugging
