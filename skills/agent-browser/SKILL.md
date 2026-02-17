---
name: agent-browser
description: Browser automation CLI for AI agents. Use when testing frontend changes visually, taking screenshots, clicking through UI flows, filling forms, or verifying page behavior after code changes. Triggers on tasks requiring visual verification, browser interaction, or automated UI testing.
allowed-tools: Bash
---

# agent-browser

Browser automation CLI for AI agents. Use for visual testing after frontend changes.

## Installation

```bash
npm install -g agent-browser
agent-browser install  # Download Chromium
```

## Core Workflow

1. **Navigate**: `agent-browser open <url>`
2. **Snapshot**: `agent-browser snapshot -i` (get interactive elements with refs)
3. **Interact**: `agent-browser click @e1`, `agent-browser fill @e2 "text"`
4. **Re-snapshot** after page changes (refs invalidate on navigation)

## Key Commands

```bash
# Navigation
agent-browser open <url>
agent-browser back / forward / reload
agent-browser close

# Snapshot & Refs
agent-browser snapshot -i          # Interactive elements only (recommended)
agent-browser snapshot             # Full page structure

# Interaction
agent-browser click @e1
agent-browser fill @e2 "text"
agent-browser type "text"          # Type without targeting element
agent-browser hover @e3
agent-browser check @e4            # Checkbox
agent-browser select @e5 "option"  # Dropdown

# Screenshots & Capture
agent-browser screenshot ~/model-set/skills/agent-browser/screenshots/name.png
agent-browser screenshot --full    # Full page
agent-browser pdf ./path.pdf

# Wait Conditions
agent-browser wait 1000            # Wait ms
agent-browser wait --network       # Wait for network idle
agent-browser wait --url "pattern" # Wait for URL match

# Information
agent-browser get text @e1
agent-browser get title
agent-browser get url

# Sessions (parallel browsers)
agent-browser --session test1 open https://site.com
agent-browser --session test2 open https://other.com

# State Persistence
agent-browser state save ./auth.json
agent-browser state load ./auth.json
```

## Snapshot Ref Format

```
@e1 [button] "Submit"           # Button with text
@e2 [input type="email"]        # Email input
@e3 [a href="/page"] "Link"     # Anchor link
@e4 [select]                    # Dropdown
```

## Visual Testing Workflow

After every frontend change:

```bash
# 1. Open the changed page
agent-browser open http://localhost:3101/path

# 2. Get page structure
agent-browser snapshot -i

# 3. Take screenshot at desktop width
agent-browser screenshot ~/model-set/skills/agent-browser/screenshots/test-desktop.png

# 4. Test interactions if needed
agent-browser click @e1
agent-browser snapshot -i

# 5. Close when done
agent-browser close
```

## Screenshot Storage

**ALWAYS save screenshots to `~/model-set/skills/agent-browser/screenshots/`** — never use relative paths like `./test.png` which pollute the working directory.

## Best Practices

- Always `snapshot -i` before interacting
- Re-snapshot after navigation or dynamic changes
- Use `--headed` flag to see browser visually for debugging
- Use `wait --network` after form submissions
- Session flag for parallel testing

## Troubleshooting

```bash
# Ref not found - re-snapshot
agent-browser snapshot -i

# Element not visible - scroll first
agent-browser scroll --bottom
agent-browser snapshot -i

# See browser window
agent-browser open --headed https://site.com
```
