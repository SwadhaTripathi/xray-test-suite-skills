# xray-test-suite

A [Claude Code](https://claude.com/claude-code) **plugin** that bundles a skill + slash command for authoring Xray test cases end-to-end: parse requirements, generate a categorized test matrix, and deliver as **CSV import file**, **direct Jira API creation**, or both.

> **New here? Start with [`initial_setup.md`](initial_setup.md)** — a ~10-minute walkthrough from installing the plugin to running your first test generation.

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

## Install (Claude Code plugin)

```text
/plugin marketplace add SwadhaTripathi/xray-test-suite-skills
/plugin install xray-test-suite
```

After install, restart your Claude Code session. The `/xray-tests` slash command and the `xray-test-suite` skill become available.

Then follow [`initial_setup.md`](initial_setup.md) for first-time configuration (~10 min: copy two `.sample.json` files, fill in values, dry-run).

## Run

```
/xray-tests <jira-key | confluence-url | file-path>
/xray-tests --dry-run                                  # validate config without creating anything
```

---

## Plugin layout

```
xray-test-suite-skills/
├── .claude-plugin/
│   ├── plugin.json                          # plugin manifest
│   └── marketplace.json                     # single-plugin marketplace manifest
├── skills/
│   └── xray-test-suite/
│       ├── SKILL.md                         # workflow Claude follows (9 steps)
│       ├── references/
│       │   ├── README.md                    # config field reference
│       │   ├── config.sample.json           # routing template (placeholders)
│       │   ├── credentials.sample.json      # secrets template (placeholders)
│       │   └── importConfiguration.json     # Xray CSV column → field mapping
│       └── output/
│           └── .gitkeep                     # generated CSVs land here (gitignored)
├── commands/
│   └── xray-tests.md                        # /xray-tests slash command
├── examples/
│   └── sample-requirements.md               # tiny sample for end-to-end testing
├── README.md                                # this file
├── initial_setup.md                         # first-time setup guide
└── .gitignore
```

---

## Secrets safety

| Where | What | Committed? |
|-------|------|-----------|
| `skills/xray-test-suite/references/*.sample.json` | Templates with placeholder values | YES |
| `skills/xray-test-suite/references/config.json` | Your tenant routing (no secrets) | NO — gitignored |
| `~/.claude/.xray-credentials.json` | API tokens & Xray Cloud client secret | NO — lives outside the plugin |
| `skills/xray-test-suite/output/*.csv` | Generated test case CSVs | NO — gitignored |

The `.gitignore` and the "credentials outside the plugin" pattern together ensure a `git push` cannot leak real secrets.

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
