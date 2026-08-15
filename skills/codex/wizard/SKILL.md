---
name: wizard
description: Generate an interactive Bash wizard for manual procedures such as provisioning infrastructure, configuring credentials or CI secrets, navigating an unfamiliar third-party dashboard, or running a one-off migration or cutover. Do not use for steps the agent can perform directly.
---

# Wizard

You are generating a Bash wizard that guides a human through actions only they can perform.

## Constraints

1. Start from [assets/template.sh](assets/template.sh).
2. Keep the library above the `STAGES` marker unchanged.
3. Use `ask_secret` for credentials and other sensitive values.
4. Use `confirm` before every irreversible action.
5. Do not invent third-party UI paths or commands. Check current documentation or ask the user when a step is unknown.
6. Make the wizard idempotent. Preserve existing values when the human presses Enter.
7. Treat generated wizards as temporary unless the user requests a repeatable repository script.

## Procedure

1. Inspect the repository before asking questions.
   - For setup work, read `.env*`, relevant README files, Docker configuration, framework configuration, and `.github/workflows/*` references to `secrets.*` and `vars.*`.
   - For migrations or cutovers, identify the current state, target state, rollback boundary, and irreversible actions.

2. Present the proposed stages for confirmation.
   - Name each stage in order.
   - List every captured value.
   - State where each value comes from, where it will be written, and whether it is secret.
   - Stop and wait for confirmation before authoring the wizard.

3. Copy `assets/template.sh` to the requested output path.
   - Replace the example stage with one focused `stage` block per manual task.
   - Set `TOTAL_STAGES` and `TOTAL_MINUTES` to realistic values.
   - Open the relevant URL before asking the human to copy a value.
   - Use `write_env` for local values, `set_secret` only for CI secrets, and `set_var` only for public CI configuration.

4. Validate the generated script.
   - Run `bash -n <script>`.
   - Run `shellcheck <script>` when ShellCheck is installed.
   - Trace every captured value to its intended destination.
   - Verify every GitHub secret and variable name against the workflow that consumes it.
   - Do not run the wizard end to end; it opens browsers and waits for human input.

5. Make the generated script executable and hand it off.
   - Run `chmod +x <script>`.
   - State the exact command the user should run.
   - If the user requested a repeatable repository script, commit it and link it from the relevant setup documentation.

## Output

Before creating the script, provide:

```text
Stages:
1. <stage> — captures <values> → writes <destinations>

Estimated time: <minutes>
Output path: <path>
```
