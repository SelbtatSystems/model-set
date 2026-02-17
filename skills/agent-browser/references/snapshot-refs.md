# Snapshot + Refs Workflow

Compact element references that reduce context usage for AI agents.

## How It Works

```bash
# Basic snapshot
agent-browser snapshot

# Interactive snapshot (-i flag) - RECOMMENDED
agent-browser snapshot -i
```

## Output Format

```
Page: Example Site
URL: https://example.com

@e1 [header]
  @e2 [nav]
    @e3 [a] "Home"
    @e4 [a] "Products"
  @e6 [button] "Sign In"

@e7 [main]
  @e8 [form]
    @e9 [input type="email"] placeholder="Email"
    @e10 [input type="password"] placeholder="Password"
    @e11 [button type="submit"] "Log In"
```

## Using Refs

```bash
agent-browser click @e6           # Click Sign In
agent-browser fill @e9 "user@test.com"
agent-browser fill @e10 "password"
agent-browser click @e11          # Submit
```

## Ref Lifecycle

**Refs invalidate on page changes!**

```bash
agent-browser snapshot -i         # @e1 [button] "Next"
agent-browser click @e1           # Page changes
agent-browser snapshot -i         # @e1 is now different element!
```

## Best Practices

1. Always snapshot before interacting
2. Re-snapshot after navigation
3. Re-snapshot after dynamic changes (dropdowns, modals)
4. Snapshot specific regions: `agent-browser snapshot @e9`

## Ref Notation

```
@e1 [tag type="value"] "text" placeholder="hint"
│    │   │             │      │
│    │   │             │      └─ Attributes
│    │   │             └─ Visible text
│    │   └─ Key attributes
│    └─ HTML tag
└─ Unique ref ID
```

## Common Patterns

```
@e1 [button] "Submit"
@e2 [input type="email"]
@e3 [input type="password"]
@e4 [a href="/page"] "Link"
@e5 [select]
@e6 [textarea] placeholder="Message"
@e7 [checkbox] checked
@e8 [radio] selected
```
