# Session Management

Run isolated browser instances with separate state.

## Session Isolation

```bash
agent-browser --session agent1 open https://site-a.com
agent-browser --session agent2 open https://site-b.com
```

Each session has independent:
- Cookies
- LocalStorage / SessionStorage
- IndexedDB
- Cache
- Browsing history

## State Persistence

```bash
# Save authenticated state
agent-browser state save ./auth.json

# Restore in new session
agent-browser state load ./auth.json
```

## Concurrent Operations

```bash
# Parallel scraping
agent-browser --session s1 open https://site.com/page1
agent-browser --session s2 open https://site.com/page2
agent-browser --session s1 screenshot ./page1.png
agent-browser --session s2 screenshot ./page2.png
```

## Best Practices

- Use semantic session names
- Clean up sessions when done
- Don't commit state files (contain tokens)
- Use timeouts for long operations
