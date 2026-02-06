# Authentication Patterns

## Basic Login

```bash
agent-browser open https://app.com/login
agent-browser snapshot -i
agent-browser fill @e1 "$APP_USERNAME"
agent-browser fill @e2 "$APP_PASSWORD"
agent-browser click @e3
agent-browser wait --url "/dashboard"
```

## Session Persistence

```bash
# Save after login
agent-browser state save ./auth-state.json

# Restore later
agent-browser state load ./auth-state.json
agent-browser open https://app.com/dashboard
```

## OAuth/SSO

```bash
agent-browser open https://app.com/login
agent-browser click @oauth-button
agent-browser wait --url "accounts.google.com"
# Complete OAuth flow
agent-browser wait --url "app.com/callback"
```

## 2FA (Manual)

```bash
agent-browser open --headed https://app.com/login
# Fill credentials
agent-browser fill @e1 "$APP_USERNAME"
agent-browser fill @e2 "$APP_PASSWORD"
agent-browser click @e3
# User completes 2FA manually
agent-browser wait 30000
agent-browser state save ./auth-2fa.json
```

## Security

- Never commit state files (contain session tokens)
- Use environment variables for credentials
- Clear cookies after automation: `agent-browser cookies clear`
- Don't persist state in CI/CD
