# xray-test-suite

A distributable [Claude Code](https://claude.com/claude-code) skill for authoring Xray test cases end-to-end: parse requirements, generate a categorized test matrix, and deliver as **CSV import file**, **direct Jira API creation**, or both.

> **New here? Start with [`initial_setup.md`](initial_setup.md)** — a ~15-minute walkthrough from cloning this repo to your first test generation.

---

## What it does

Given a Jira issue, Confluence page, local file (`.md` / `.pdf` / `.pptx` / `.docx` / `.png` / `.drawio` / `.txt`), or pasted text, the skill:

1. **Extracts** requirements, use cases, state transitions, error scenarios
2. **Generates** a categorized (Positive / Negative / Edge / Safety) and prioritized test matrix
3. **Waits for your approval** of the matrix
4. **Asks** how to deliver: **CSV** / **API** / **Both**
5. **Produces** output and (optionally) uploads the CSV via Playwright UI automation

You stay in control — nothing is written to Jira until you explicitly approve.

---

## Install

```bash
git clone https://github.com/SwadhaTripathi/xray-test-suite-skills.git ~/.claude/skills/xray-test-suite
```

Then follow [`initial_setup.md`](initial_setup.md) for configuration (~10 min: copy two `.sample.json` files, fill in values, dry-run).

## Run

```
/xray-tests <jira-key | confluence-url | file-path>
/xray-tests --dry-run                                  # validate config without creating anything
```

---

## Repo layout

| Path | Purpose |
|------|---------|
| [`SKILL.md`](SKILL.md) | The workflow Claude follows (9 steps) |
| [`initial_setup.md`](initial_setup.md) | First-time setup walkthrough |
| [`references/README.md`](references/README.md) | Config-field reference for users already familiar with the flow |
| [`references/config.sample.json`](references/config.sample.json) | Routing template — placeholders only |
| [`references/credentials.sample.json`](references/credentials.sample.json) | Secrets template — placeholders only |
| [`references/importConfiguration.json`](references/importConfiguration.json) | Xray CSV column→field mapping (authoritative) |
| [`examples/sample-requirements.md`](examples/sample-requirements.md) | Tiny sample to verify end-to-end |
| `output/` | Generated CSVs land here (gitignored) |

---

## Secrets safety

| Where | What | Committed? |
|-------|------|-----------|
| `references/*.sample.json` | Templates with placeholder values | YES |
| `references/config.json` | Your tenant routing (no secrets) | NO — gitignored |
| `~/.claude/.xray-credentials.json` | API tokens & Xray Cloud client secret | NO — lives outside the repo |
| `output/*.csv` | Generated test case CSVs | NO — gitignored |

The `.gitignore` and the "credentials outside the skill" pattern together ensure a `git push` cannot leak real secrets.

---

## Prerequisites

- [Claude Code](https://docs.claude.com/claude-code)
- **Atlassian MCP** server connected (reads Jira/Confluence, creates Jira issues)
- **Playwright MCP** server connected (only required for CSV auto-upload or UI-driven Xray step entry)
- Atlassian account with Jira + Xray access
- (Optional) Xray Cloud Client ID/Secret for fastest native-step creation; without them, the skill falls back to Playwright

---

## Output Modes

| Reply | Mode | Best for |
|-------|------|---------|
| `1` | **CSV only** | Bulk loads (50+ tests), audit trail, or you want to review before commit |
| `2` | **API only** | Small batches (<20), immediate Jira creation |
| `3` | **Both** | Default recommendation — CSV as backup, API for immediate creation |

---

## License

No license specified yet — add one (e.g. MIT, Apache-2.0) before broad public distribution.
