#!/bin/bash
# Ralph Agent - OpenCode Edition
# Usage: ./opencode_ralph.sh [max_iterations]

set -e

MAX_ITERATIONS=${1:-10}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
PLAN_FILE="$SCRIPT_DIR/plan.md"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
PROMPT_FILE="$SCRIPT_DIR/prompt.md"

# Ensure we're in project root
cd "$PROJECT_ROOT"
echo "Working directory: $(pwd)"
echo "Model: OpenCode"

# Extract value from YAML frontmatter
get_frontmatter() {
  local key=$1
  sed -n "/^---$/,/^---$/{ /^${key}:/{s/^${key}: *[\"']*\([^\"']*\)[\"']*/\1/p; }}" "$PLAN_FILE" 2>/dev/null | head -1
}

# Count incomplete tasks (- [ ] pattern)
count_incomplete() {
  local count=$(grep -c '^\s*- \[ \]' "$PLAN_FILE" 2>/dev/null || echo "0")
  echo "$count" | tr -d '\r\n' | tr -d ' '
}

# Count complete tasks (- [x] pattern)
count_complete() {
  local count=$(grep -c '^\s*- \[x\]' "$PLAN_FILE" 2>/dev/null || echo "0")
  echo "$count" | tr -d '\r\n' | tr -d ' '
}

# Archive previous run if branch changed
if [ -f "$PLAN_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(get_frontmatter "branchName")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PLAN_FILE" ] && cp "$PLAN_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PLAN_FILE" ]; then
  CURRENT_BRANCH=$(get_frontmatter "branchName")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Show initial status
TOTAL_TASKS=$(($(count_complete) + $(count_incomplete)))
COMPLETE_TASKS=$(count_complete)
echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  Ralph Agent - OpenCode                               ║"
echo "╠═══════════════════════════════════════════════════════╣"
echo "║  Project: $PROJECT_ROOT"
echo "║  Plan: plan.md"
echo "║  Progress: $COMPLETE_TASKS / $TOTAL_TASKS tasks complete"
echo "║  Max iterations: $MAX_ITERATIONS"
echo "╚═══════════════════════════════════════════════════════╝"

for i in $(seq 1 $MAX_ITERATIONS); do
  COMPLETE_TASKS=$(count_complete)
  INCOMPLETE_TASKS=$(count_incomplete)
  TOTAL_TASKS=$((COMPLETE_TASKS + INCOMPLETE_TASKS))

  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Iteration $i of $MAX_ITERATIONS | Progress: $COMPLETE_TASKS / $TOTAL_TASKS tasks"
  echo "═══════════════════════════════════════════════════════"

  # Check if all tasks complete before running
  if [ "$INCOMPLETE_TASKS" -eq 0 ] && [ "$TOTAL_TASKS" -gt 0 ]; then
    echo ""
    echo "All tasks already complete!"
    exit 0
  fi

  # Run OpenCode with yolo mode (skips all permissions)
  TEMP_OUTPUT="$SCRIPT_DIR/.ralph-output.tmp"
  opencode --yolo -p "$(cat "$PROMPT_FILE")" 2>&1 | tee "$TEMP_OUTPUT" || true
  OUTPUT=$(cat "$TEMP_OUTPUT" 2>/dev/null || echo "")

  # Check for completion signal
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  ✓ Ralph completed all tasks!                        ║"
    echo "║  Finished at iteration $i of $MAX_ITERATIONS         ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  ⚠ Ralph reached max iterations ($MAX_ITERATIONS)     ║"
echo "║  Check progress.txt for status                        ║"
echo "╚═══════════════════════════════════════════════════════╝"
exit 1
