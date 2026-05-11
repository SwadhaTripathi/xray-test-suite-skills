# Xray Tests — Generate & Import

Generate Xray test cases (from Jira / Confluence / file / pasted text), produce an import-ready CSV and/or create Jira issues via API, and optionally upload the CSV via Playwright UI automation.

## Usage
```
/xray-tests [source]
/xray-tests --dry-run
```

## Arguments
- `$ARGUMENTS` — Optional. Any of:
  - Jira Issue key (Epic, Story, Task) — e.g. `FIFAGEN-2872`
  - Confluence URL or page ID
  - Local file path (`.md`, `.pdf`, `.pptx`, `.docx`, `.png`, `.drawio`, `.txt`)
  - Pasted requirements text
  - `--dry-run` to validate config without creating anything

## How

This command drives the full workflow **inline** — Claude does NOT call the Skill tool. The workflow definition lives in the bundled `SKILL.md` file so we keep one source of truth.

**Execute the workflow as follows:**

0. **Pre-flight: auto-setup if config is missing.** Before reading `SKILL.md`, verify these two files exist:
   - `<PLUGIN_DIR>/skills/xray-test-suite/references/config.json`
   - `~/.claude/.xray-credentials.json`

   If **either** is missing, invoke the bundled setup script automatically:
   - **Windows (native PowerShell)**: run `<PLUGIN_DIR>/scripts/xray-setup.ps1` via the PowerShell tool.
   - **macOS / Linux / Git Bash on Windows**: run `<PLUGIN_DIR>/scripts/xray-setup.sh` via the Bash tool.

   Handle the script's exit code:
   - `0` — fully configured. Continue to Step 1.
   - `2` — files staged but placeholders remain. Conduct an interactive chat with the user to gather each missing value (cloudId, username, projectKey, projectName, xrayImportUrl, apiToken, optional xrayClientId/xrayClientSecret). For the API token and Xray Cloud secret, **warn the user that these will pass through this conversation's transcript** and offer them the option to run the script themselves in their own terminal instead. Then re-invoke the script with the values via `-CloudId`/`--cloud-id`-style flags (PowerShell uses `-CamelCase`, bash uses `--kebab-case`). On `0`, continue to Step 1.
   - `1` — hard error (sample files missing). Abort and tell the user to verify the plugin install via `/plugin info xray-test-suite`.

   If `$ARGUMENTS == "--dry-run"`, you can skip Step 0 only when both files already exist — otherwise the dry-run cannot validate anything meaningful, so still run setup first.

1. **Load the workflow document.** Use the **Read** tool to load `SKILL.md` from the plugin. Try these paths in order:
   - `~/.claude/plugins/cache/xray-test-suite-skills/xray-test-suite/<version>/skills/xray-test-suite/SKILL.md` (plugin cache — what the harness loaded)
   - `~/.claude/skills/xray-test-suite/skills/xray-test-suite/SKILL.md` (local clone, if user installed via `git clone`)
   - If neither resolves, ask the user to run `/plugin info xray-test-suite` to find the install path and abort.
2. **Follow the 9-step workflow** defined in that document, treating `$ARGUMENTS` as the input source for Step 2 (input detection). If `$ARGUMENTS` is empty, follow the document's instruction to prompt the user with the supported-input table.
3. **Do NOT invoke the Skill tool.** The skill has `disable-model-invocation: true` set deliberately — autonomous invocation is blocked so the destructive Jira-creation workflow only runs when the user explicitly types `/xray-tests`. This command is the sole entry point.
4. **Respect every Critical Rule** in `SKILL.md`, especially:
   - Never create Jira issues without explicit user `APPROVE` / `APPROVE ALL` / `APPROVE: <TC-IDs>`
   - Always present the draft test matrix before any creation
   - Always ask the user to pick output mode (CSV / API / Both)
   - Never leak credentials in outputs

The `SKILL.md` document covers:
- Configuration loading (`skills/xray-test-suite/references/config.json` + `~/.claude/.xray-credentials.json`)
- Input detection and requirements fetching (Jira / Confluence / files / text)
- Test case analysis, categorization, optimization, and matrix approval
- Output mode prompt (CSV / API / Both)
- CSV generation, API creation, Playwright upload
- Mode-aware summary reporting

### Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Cannot find `SKILL.md` at either path | Plugin not installed or installed at non-standard path | Run `/plugin list` to confirm install; `/plugin info xray-test-suite` reveals path |
| Workflow refuses to start | Config or credentials missing | Run `/xray-tests --dry-run` to surface the missing piece |
| Plugin updated but old behavior persists | Cache stale | Run `/reload-plugins` or restart Claude Code |
