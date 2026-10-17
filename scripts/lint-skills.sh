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

# The '## Degraded vs Claude' block exists to name the Claude capabilities this
# host lacks, so it necessarily mentions them. Scanning it would flag the very
# documentation the contract requires. Truncate there; line numbers in the kept
# portion are unaffected because we only ever drop the tail.
body_before_degraded() {
  sed '/^## Degraded vs Claude/,$d' "$1"
}

scan_rules() {
  local file="$1"; shift
  local found_here=0 rule pattern label body
  body="$(mktemp)"
  body_before_degraded "$file" > "$body"
  for rule in "$@"; do
    pattern="${rule%%:::*}"
    label="${rule##*:::}"
    while IFS=: read -r lineno text; do
      [ -n "$lineno" ] || continue
      report "$file" "$lineno" "$label" "$(echo "$text" | sed 's/^[[:space:]]*//' | cut -c1-90)"
      found_here=1
    done < <(grep -nE "$pattern" "$body" 2>/dev/null)
  done
  rm -f "$body"
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
contract_violations=$violations

# ---------------------------------------------------------------------------
# Skill references: a skill that tells the agent to load another skill must
# name one the agent can load. A broken reference fails silently at run time:
# do-issue named `diagnose` (renamed in June) and a `tdd` that skillOverrides
# hid from the model, so for 60 days its build step loaded neither.
# ---------------------------------------------------------------------------

# Claude Code ships these. A personal skill with the same name replaces the
# built-in: a skill named code-review hid the bug-hunting /code-review.
# Add a name here when Claude Code bundles a new one (see its `/` list).
CLAUDE_BUILTINS=(code-review review verify simplify security-review init run loop schedule
  update-config keybindings-help fewer-permission-prompts claude-api workflow-authoring plugin-authoring)
# The ones the model may load through the Skill tool. /verify and /review it may not.
CLAUDE_BUILTINS_CALLABLE=(code-review security-review simplify init)

SETTINGS="$REPO_DIR/global/claude/settings.json"
mapfile -t HIDDEN < <(jq -r '.skillOverrides // {} | to_entries[]
  | select(.value == "user-invocable-only" or .value == "off") | "\(.key)=\(.value)"' "$SETTINGS")
mapfile -t NPM_CLAUDE < <(jq -r '.npmSkills // {} | to_entries[]
  | select(.value.hosts | index("claude")) | .key' "$MANIFEST")

in_list() { local needle="$1" x; shift; for x in "$@"; do [ "$x" = "$needle" ] && return 0; done; return 1; }

# Hosts that receive <set>/<skill>, per manifest.json (an override wins over the set).
set_hosts() {
  jq -r --arg k "$1/$2" --arg s "$1" '(.overrides[$k].hosts // .sets[$s].hosts)[]' "$MANIFEST"
}

# Directory of the skill linked for <host> under <name>; non-zero when there is none.
skill_dir_for() {
  local host="$1" name="$2" set
  for set in claude codex shared external; do
    [ -f "$REPO_DIR/skills/$set/$name/SKILL.md" ] || continue
    set_hosts "$set" "$name" | grep -qx "$host" && { echo "$REPO_DIR/skills/$set/$name"; return 0; }
  done
  return 1
}

frontmatter_has() {
  awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { exit } f' "$1" | grep -qE "$2"
}

check_claude_ref() {
  local file="$1" line="$2" name="$3" dir hidden
  hidden="$(printf '%s\n' "${HIDDEN[@]}" | grep -m1 "^$name=" | cut -d= -f2)"
  if dir="$(skill_dir_for claude "$name")"; then
    frontmatter_has "$dir/SKILL.md" '^disable-model-invocation:[[:space:]]*true' \
      && report "$file" "$line" "skill reference" "\"$name\" sets disable-model-invocation: only a person can start it"
  elif in_list "$name" "${NPM_CLAUDE[@]}" || in_list "$name" "${CLAUDE_BUILTINS_CALLABLE[@]}"; then
    :
  elif in_list "$name" "${CLAUDE_BUILTINS[@]}"; then
    report "$file" "$line" "skill reference" "\"$name\" is a Claude Code built-in the model cannot load"
    return
  else
    report "$file" "$line" "skill reference" "no skill named \"$name\" is linked for Claude"
    return
  fi
  [ -n "$hidden" ] && report "$file" "$line" "skill reference" \
    "\"$name\" is \"$hidden\" in settings.json skillOverrides: the model cannot see it (use \"name-only\")"
  return 0
}

$WORKLIST || { echo ""; echo "Skill references"; }

# Claude: `Call the Skill tool with "x"`, `... twice, for "x" and "y"`.
for skill_md in "$REPO_DIR"/skills/claude/*/SKILL.md; do
  while IFS=: read -r lineno text; do
    while read -r name; do
      [ -n "$name" ] && check_claude_ref "$skill_md" "$lineno" "$name"
    done < <(grep -oE 'Skill tool (with|[a-z]+, for) "[^"]+"((,| and|, and) "[^"]+")*' <<< "$text" \
               | grep -oE '"[^"]+"' | tr -d '"')
  done < <(grep -nE 'Skill tool (with|[a-z]+, for) "' "$skill_md")
done

# Codex: `read skills/x/SKILL.md`.
for skill_md in "$REPO_DIR"/skills/codex/*/SKILL.md; do
  while IFS=: read -r lineno name; do
    skill_dir_for codex "$name" > /dev/null \
      || report "$skill_md" "$lineno" "skill reference" "no skill named \"$name\" is linked for Codex"
  done < <(grep -noE 'skills/[a-z0-9:-]+/SKILL\.md' "$skill_md" | sed -E 's#^([0-9]+):skills/([^/]+)/SKILL\.md$#\1:\2#')
done

# A personal skill must not take a built-in's name.
for set in claude shared external; do
  for dir in "$REPO_DIR"/skills/"$set"/*/; do
    name="$(basename "$dir")"
    set_hosts "$set" "$name" | grep -qx claude || continue
    in_list "$name" "${CLAUDE_BUILTINS[@]}" && report "${dir%/}/SKILL.md" 1 "built-in name" \
      "a personal skill named \"$name\" replaces Claude Code's built-in /$name: rename it"
  done
done

ref_violations=$((violations - contract_violations))

$WORKLIST && exit 0

total_skills=$(find "$REPO_DIR/skills/codex" -maxdepth 1 -mindepth 1 -type d | wc -l)
echo ""
if [ $violations -eq 0 ]; then
  echo "PASS — $total_skills Codex skills, no contract violations; every skill reference resolves."
  exit 0
fi

if [ $contract_violations -gt 0 ]; then
  echo "FAIL — $contract_violations contract violation(s) across $skills_with_issues of $total_skills Codex skills."
  echo ""
  echo "These are phase-2 work: each skill needs rewriting into GPT-dialect at the"
  echo "capability floor in skills/CONTRACT.md. Machine-readable list:"
  echo "    scripts/lint-skills.sh --worklist"
fi
[ $ref_violations -gt 0 ] && echo "FAIL — $ref_violations broken skill reference(s) or built-in name clash(es), listed above."
exit 1
