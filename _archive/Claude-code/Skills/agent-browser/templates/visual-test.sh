#!/bin/bash
# Visual Testing Template for AgCore
# Usage: ./visual-test.sh <url> [screenshot-name]

set -euo pipefail

URL="${1:-http://localhost:3101}"
NAME="${2:-test}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "Testing: $URL"

# Open page
agent-browser open "$URL"

# Wait for page load
agent-browser wait --network

# Get page structure
echo "=== Page Structure ==="
agent-browser snapshot -i

# Desktop screenshot (1440px)
agent-browser screenshot "./screenshots/${NAME}_desktop_${TIMESTAMP}.png"

# Optional: Mobile viewport
# agent-browser resize 375 812
# agent-browser screenshot "./screenshots/${NAME}_mobile_${TIMESTAMP}.png"

# Get page title for verification
echo "=== Page Title ==="
agent-browser get title

# Close browser
agent-browser close

echo "Done: screenshots saved to ./screenshots/"
