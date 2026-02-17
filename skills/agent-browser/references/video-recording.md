# Video Recording

Record browser sessions for debugging and documentation.

## Commands

```bash
agent-browser record start ./output.webm
agent-browser record stop
agent-browser record restart ./newfile.webm
```

## Debugging Workflow

```bash
agent-browser record start ./debug-$(date +%s).webm
agent-browser open https://app.com
agent-browser snapshot -i
agent-browser click @e1 || agent-browser record stop
# Review recording to see what happened
```

## Documentation

```bash
agent-browser record start ./workflow.webm
agent-browser open https://app.com
agent-browser wait 500  # Pause for visibility
agent-browser click @e1
agent-browser wait 500
agent-browser record stop
```

## CI/CD Evidence

```bash
TEST_DIR="./recordings/$(date +%Y%m%d)"
mkdir -p $TEST_DIR
agent-browser record start "$TEST_DIR/test-run.webm"
# Run tests...
agent-browser record stop
```

## Best Practices

- Add pauses between actions for clarity
- Use descriptive filenames with timestamps
- Recording adds slight overhead
- Large recordings consume significant disk space
- Pair with screenshots for key moments
