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

This command delegates the full workflow to the `xray-test-suite` skill (bundled with this plugin at `skills/xray-test-suite/SKILL.md`).

**You MUST invoke the skill via the Skill tool — do not re-implement the workflow inline.**

```
Skill: xray-test-suite
args: $ARGUMENTS
```

The skill owns:
- Configuration loading (`skills/xray-test-suite/references/config.json` + `~/.claude/.xray-credentials.json`)
- Input detection and requirements fetching
- Test case analysis, categorization, optimization
- Output mode prompt (CSV / API / Both)
- CSV generation, API creation, Playwright upload
- Mode-aware summary reporting

If the skill is not loaded (you see a "skill not found" error), the user has installed the plugin without proper activation. Direct them to verify via `/plugin list` and `/plugin install xray-test-suite` if needed.
