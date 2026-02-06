# CLAUDE.md

> **Update when major changes made** to maintain accurate refference, be extremly concise.

- In all interactions and commit messages, be concise and sacrifice grammar for the sake of concision

## GitHub
Your primary method for interacting with GitHub should be the GitHub CLI.

## Git
When creating branches, prefix them with sven/ to indicate they came from me.

## Plans
At the end of each plan,give me a list of unresolved questions to answer, if any. Make the questions extremly concise. Sacrifice grammar for the sake of concision.

## Visual Testing (agent-browser)

**REQUIRED after every frontend change or feature implementation.**

### Quick Verification Workflow
```bash
# 1. Open changed page
agent-browser open http://localhost:3101/path

# 2. Get page structure & verify elements
agent-browser snapshot -i

# 3. Screenshot at desktop width
agent-browser screenshot ./test.png

# 4. Test key interactions
agent-browser click @e1
agent-browser snapshot -i

# 5. Close
agent-browser close
```

### Key Commands
```bash
agent-browser open <url>           # Navigate
agent-browser snapshot -i          # Get interactive elements w/ refs
agent-browser click @e1            # Click by ref
agent-browser fill @e2 "text"      # Fill input
agent-browser screenshot ./path    # Capture
agent-browser wait --network       # Wait for API calls
agent-browser console              # Check console logs
agent-browser errors               # Check errors only
agent-browser close                # Done
```

### Best Practices
- Always `snapshot -i` before interacting (refs invalidate on page changes)
- Re-snapshot after navigation or dynamic content changes
- Use `--headed` flag to see browser for debugging
- Verify vs `/context/design-principles.md`