#!/usr/bin/env bash
# Enforce skills/CONTRACT.md.
#
# Skills in skills/codex/ are consumed by BOTH Codex and OpenCode, so by default
# they may only assume file I/O, shell, MCP, and other skills in their own set.
# A skill listed as Codex-only in skills/manifest.json opts out of that floor and
# may use the Codex-native stack — it is never linked into OpenCode.
#
# Usage: scripts/lint-skills.sh [--worklist]
#   --worklist   machine-readable "<file>:<line>: <construct>" for phase-2 triage
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_DIR/skills/manifest.json"
WORKLIST=false
[ "${1:-}" = "--worklist" ] && WORKLIST=true

command -v jq >/dev/null || { echo "lint-skills: jq is required" >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "lint-skills: no $MANIFEST" >&2; exit 2; }

violations=0
skills_with_issues=0

# Claude-only constructs. A shared Codex skill using any of these is broken:
# neither Codex nor OpenCode provides them. This is the do-pr bug class.
#
# Slash commands are matched with boundaries so /code-review does not also fire
# the bare /review rule, and so /research is not mistaken for /review.
#
# Rules are "<extended-regex>:::<label>". The separator is ':::' and not '|'
# because the patterns themselves use '|' for alternation.
CLAUDE_ONLY=(
  '(^|[^A-Za-z0-9/_-])/(code-review|security-review|review|simplify|verify|workflows)([^A-Za-z0-9_-]|$):::Claude built-in slash command'
  '\b(Task|Agent) tool\b:::Claude sub-agent API'
  '\bsubagent_type\b:::Claude sub-agent API'
  '\bSkill tool\b:::Claude skill-invocation API'
  '\bTodoWrite\b:::Claude-only tool'
  '\bWorkflow tool\b:::Claude-only tool'
  '^allowed-tools::::Claude-only frontmatter key'
  '\bmcp__[a-z0-9_]+:::Claude MCP tool naming'
  '\b(ExitPlanMode|EnterPlanMode)\b:::Claude-only plan mode'
)

# Codex-native constructs. Fine in a Codex-only skill, fatal in a shared one
# because OpenCode has no equivalent.
CODEX_NATIVE=(
  '\bcodex review\b:::Codex-only subcommand'
  '~/\.codex/agents:::Codex-only sub-agent dir'
  '~/\.codex/prompts:::Codex-only prompt dir'
)

is_codex_only() {
  local key="codex/$1"
  [ "$(jq -r --arg k "$key" '.overrides[$k].hosts // [] | index("opencode") // "none"' "$MANIFEST")" = "none" ] \
    && [ "$(jq -r --arg k "$key" '.overrides[$k] // "absent"' "$MANIFEST")" != "absent" ]
}

is_degraded() {
  [ "$(jq -r --arg k "codex/$1" '.overrides[$k].degraded // false' "$MANIFEST")" = "true" ]
}

report() {
  local file="$1" line="$2" label="$3" text="$4"
  violations=$((violations + 1))
  if $WORKLIST; then
    printf '%s:%s: %s\n' "${file#"$REPO_DIR"/}" "$line" "$label"
  else
    printf '    %s:%s\n      %s — %s\n' "${file#"$REPO_DIR"/}" "$line" "$label" "$text"
  fi
}

scan_rules() {
  local file="$1"; shift
  local found_here=0 rule pattern label
  for rule in "$@"; do
    pattern="${rule%%:::*}"
    label="${rule##*:::}"
    while IFS=: read -r lineno text; do
      [ -n "$lineno" ] || continue
      report "$file" "$lineno" "$label" "$(echo "$text" | sed 's/^[[:space:]]*//' | cut -c1-90)"
      found_here=1
    done < <(grep -nE "$pattern" "$file" 2>/dev/null)
  done
  return $found_here
}

$WORKLIST || {
  echo "lint-skills — enforcing skills/CONTRACT.md"
  echo "==========================================="
  echo ""
}

for dir in "$REPO_DIR"/skills/codex/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  skill_md="${dir%/}/SKILL.md"
  [ -f "$skill_md" ] || {
    $WORKLIST || echo "  $name: no SKILL.md"
    violations=$((violations + 1))
    continue
  }

  before=$violations

  # Claude-only constructs are fatal in every Codex skill, without exception.
  scan_rules "$skill_md" "${CLAUDE_ONLY[@]}"

  # Codex-native constructs are fatal only in skills shared with OpenCode.
  if ! is_codex_only "$name"; then
    scan_rules "$skill_md" "${CODEX_NATIVE[@]}"
  fi

  # A degraded skill must say what it gives up.
  if is_degraded "$name" && ! grep -q '^## Degraded vs Claude' "$skill_md"; then
    report "$skill_md" 1 "missing '## Degraded vs Claude' block" \
      "marked degraded in manifest.json but does not document the gap"
  fi

  if [ $violations -gt $before ]; then
    skills_with_issues=$((skills_with_issues + 1))
    $WORKLIST || echo "  $name  ($((violations - before)) issue(s))$(is_codex_only "$name" && echo '  [codex-only]')"
  fi
done

$WORKLIST && exit 0

total_skills=$(find "$REPO_DIR/skills/codex" -maxdepth 1 -mindepth 1 -type d | wc -l)
echo ""
if [ $violations -eq 0 ]; then
  echo "PASS — $total_skills skills, no contract violations."
  exit 0
fi

echo "FAIL — $violations violation(s) across $skills_with_issues of $total_skills skills."
echo ""
echo "These are phase-2 work: each skill needs rewriting into GPT-dialect at the"
echo "capability floor in skills/CONTRACT.md. Machine-readable list:"
echo "    scripts/lint-skills.sh --worklist"
exit 1
