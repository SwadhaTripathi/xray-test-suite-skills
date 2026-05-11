# xray-test-suite — Setup (config reference)

Tight reference for users already familiar with the workflow. For a full first-time walkthrough, see [`initial_setup.md`](../../../initial_setup.md) at the plugin root.

Two files to create, both from the included `.sample.json` templates.

---

## 1. Routing config (inside the plugin folder)

Locate the installed plugin folder with `/plugin info xray-test-suite`, then:

```bash
cd <PLUGIN_DIR>/skills/xray-test-suite/references
cp config.sample.json config.json
```

Edit `config.json` and fill in:

| Field | Where to find it |
|-------|------------------|
| `atlassian.cloudId` | Your Atlassian site hostname (e.g. `your-site.atlassian.net`) or the UUID-style cloudId from the Atlassian MCP `getAccessibleAtlassianResources` tool |
| `atlassian.username` | Your work email on Atlassian |
| `project.key` / `project.name` | Jira project (e.g. `FIFAGEN` / `FIFA Genesis`) |
| `xrayImport.url` | Open Jira → Xray → Importer page → copy the URL (it embeds `project.key` and `project.id`) |
| `customFields.*` | Run `GET /rest/api/3/field` on your Jira to find the right custom-field IDs |

`config.json` is **gitignored** — your tenant-specific values stay local.

---

## 2. Secrets (outside the skill folder)

```bash
cp credentials.sample.json ~/.claude/.xray-credentials.json
```

Edit `~/.claude/.xray-credentials.json` and fill in:

| Field | Where to find it |
|-------|------------------|
| `atlassian.apiToken` | https://id.atlassian.com/manage-profile/security/api-tokens → Create token |
| `xrayCloud.clientId` & `clientSecret` | Jira → Settings → Apps → Xray → API Keys → Create new key |

> If you leave both `xrayCloud.*` empty, the skill falls back to **Playwright browser automation** for adding X-Ray native test steps. Slower but works without API credentials.

This file lives in `~/.claude/` (your user home) — never inside the skill folder, never committed.

---

## 3. Xray Import Configuration (already provided)

`importConfiguration.json` in this folder defines the **CSV column → Jira field** mapping for the Xray Test Case Importer.

- Column INDEX is the source of truth (not header text).
- The default config maps a 7-column CSV: `Test ID, Summary, Description, Test Type, Step Data, Step Action, Step Result`.
- If your team uses different columns, edit this file — the skill reads it at runtime.

---

## 4. Verify

Run a dry-run to confirm everything is wired up:

```
/xray-tests --dry-run
```

The skill will read both configs and report any missing fields or broken paths.

---

## File map (within the plugin)

```
xray-test-suite-skills/                          # plugin root
├── .claude-plugin/
│   ├── plugin.json                              # plugin manifest
│   └── marketplace.json                         # marketplace manifest
├── skills/
│   └── xray-test-suite/
│       ├── SKILL.md                             # workflow Claude follows
│       ├── references/
│       │   ├── README.md                        # this file
│       │   ├── config.sample.json               # COMMIT — routing template
│       │   ├── config.json                      # GITIGNORED — your actual routing config
│       │   ├── credentials.sample.json          # COMMIT — secrets template
│       │   └── importConfiguration.json         # COMMIT — Xray CSV column mapping
│       └── output/
│           └── *.csv                            # GITIGNORED — generated test case CSVs
├── commands/
│   └── xray-tests.md                            # /xray-tests slash command
└── examples/
    └── sample-requirements.md                   # COMMIT — small example to test end-to-end
```

Real secrets live at `~/.claude/.xray-credentials.json` (outside the plugin folder, never committed).
