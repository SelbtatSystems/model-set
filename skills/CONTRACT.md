# Skill capability contract

What a skill may assume, per set. `scripts/lint-skills.sh` enforces this.

This document exists because it didn't. `do-pr` was copied verbatim into the
Codex set while invoking `/code-review`, `/security-review`, `/review`,
`/simplify`, `/verify` and `/workflows` — all Claude Code **built-in slash
commands**. Codex has none of them, so the skill could not work at any wording.
Nobody had written down what a Codex skill is allowed to reach for.

---

## The three sets

| Set | Consumers | Dialect | May assume |
|---|---|---|---|
| `skills/claude/` | Claude Code | Claude-native | Everything Claude Code offers |
| `skills/codex/` | Codex **and** OpenCode | GPT | Codex ∩ OpenCode, unless marked Codex-only |
| `skills/external/` | all three | not ours | n/a — never edit; upstream owns the prose |

---

## Capability floor for `skills/codex/`

A shared Codex skill may assume **only**:

- Reading and writing files
- Running shell commands
- MCP tools configured for that host
- Other skills **in its own set**

It may **not** assume named sub-agents, host slash-commands, parallel fan-out,
plan mode, or todo tracking. OpenCode shares this set and has none of them.

### Banned constructs and their replacements

| Claude-only | Why it fails | Write instead |
|---|---|---|
| `/code-review`, `/review` | Claude built-in command | An inline review procedure, or `codex review` **only in a Codex-only skill** |
| `/security-review` | Claude built-in command | An explicit checklist the model walks itself |
| `/simplify`, `/verify`, `/workflows` | Claude built-in commands | Inline steps |
| `Task` / `Agent` tool, `subagent_type` | No sub-agent API | Sequential steps in one context |
| `Skill` tool | Different invocation model | "Read `skills/<name>/SKILL.md` and follow it" |
| `TodoWrite` | No todo tool | A numbered plan in the reply |
| `Workflow` tool | Claude Code only | Sequential steps |
| `allowed-tools:` frontmatter | Claude-only frontmatter key | Omit — permissions live in each host's config |
| `mcp__server__tool` | Claude's MCP tool naming | Name the server and tool in prose |
| `ExitPlanMode`, plan mode | Claude-only | Ask the user directly |

---

## Codex-only skills

A skill may opt out of the floor by declaring itself Codex-only in
`skills/manifest.json`:

```json
"overrides": {
  "codex/do-pr": { "hosts": ["codex"], "degraded": true }
}
```

It is then **never linked into OpenCode** — physically absent, not merely
discouraged — and may use the full Codex stack:

| Capability | Codex form |
|---|---|
| Code review | `codex review` |
| Sub-agents | `~/.codex/agents/<name>.md` (needs `[features] multi_agent = true`) |
| Slash commands | `~/.codex/prompts/<name>.md` |
| Command policy | `~/.codex/rules/*.rules` |
| MCP | `[mcp_servers.*]` in `~/.codex/config.toml` |

The lint permits these constructs **only** in skills marked Codex-only.

---

## The `## Degraded vs Claude` block

Any skill marked `"degraded": true` must carry a section named exactly
`## Degraded vs Claude`, stating:

1. What the Claude version does that this one cannot
2. Why the host can't do it
3. What to do manually to compensate

Required because a silently weaker skill is worse than a missing one — it gives
false confidence that a real check happened. The lint fails if the block is
absent.

```markdown
## Degraded vs Claude

Claude's `do-pr` fans out parallel review sub-agents and runs `/security-review`
as a dedicated pass. This version reviews sequentially in one context.

**Compensate:** before merging anything touching auth, payments or user data,
walk the security checklist in `references/risk-playbooks.md` yourself and paste
your findings into the PR. Do not treat a clean run here as a security review.
```

---

## GPT-dialect writing rules

Every skill in `skills/codex/` follows these, including Codex-only ones.

**Do**

- Number every procedure. `1.` `2.` `3.` — not prose paragraphs describing a flow.
- State the role in one line at the top: *"You are reviewing a pull request for merge safety."*
- Give explicit stop conditions. *"If no tests exist, stop and report that — do not write them."*
- Put constraints before the task, not after.
- Give the output format literally, with a template.
- Prefer one instruction per sentence.

**Don't**

- "Use your judgement", "as appropriate", "if it seems relevant" — decide, or give a rule.
- Long rationale before the instruction. Instruction first, reason after, if at all.
- Nested conditionals in prose. Flatten into a numbered decision list.
- Rely on the model inferring an unstated step.

The Claude set deliberately does **not** follow these. Claude handles latitude and
prose framing well; GPT-class models follow explicit procedure more reliably. That
difference is the entire reason the two sets exist.

---

## Adding a skill

1. Decide the set. Ours → `claude/` or `codex/`. Someone else's → `external/`.
2. Write it in that set's dialect.
3. If it's in `codex/` and needs Codex-native features, add an `overrides` entry.
4. If it's degraded, add the `## Degraded vs Claude` block.
5. Run `scripts/lint-skills.sh`.

Never edit anything in `skills/external/` — changes are lost on the next upstream
sync. Fork it into `claude/` or `codex/` under a new name instead.
