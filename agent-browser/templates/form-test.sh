#!/bin/bash
# Form Testing Template
# Usage: ./form-test.sh <form-url>

set -euo pipefail

URL="${1:-http://localhost:3101/form}"

echo "Testing form at: $URL"

# Open form page
agent-browser open "$URL"
agent-browser wait --network

# Get form structure
echo "=== Form Elements ==="
agent-browser snapshot -i

# Fill form fields (customize refs based on snapshot)
# agent-browser fill @e1 "test@example.com"
# agent-browser fill @e2 "password123"
# agent-browser select @e3 "option1"
# agent-browser check @e4

# Submit form
# agent-browser click @submit-button
# agent-browser wait --network

# Verify result
echo "=== Result Page ==="
agent-browser snapshot -i
agent-browser screenshot ./form-result.png

agent-browser close
