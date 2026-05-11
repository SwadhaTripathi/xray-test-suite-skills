# Initial Setup — xray-test-suite (Claude Code plugin)

End-to-end walkthrough: from installing the plugin to running your first test-case generation. Plan ~10 minutes for a clean setup.

If you already understand the workflow and just need a config reference, skip to [`skills/xray-test-suite/references/README.md`](skills/xray-test-suite/references/README.md).

---

## What this plugin does

Given a requirements source (Jira issue, Confluence page, local file, or pasted text), the bundled skill:

1. **Parses** the requirements
2. **Generates** a categorized, prioritized, deduplicated test matrix
3. **Waits for your approval** of the matrix
4. **Asks** how you want the tests delivered: **CSV** (import file) / **API** (direct Jira creation) / **Both**
5. **Produces** the output and optionally uploads the CSV via Playwright UI automation

You stay in control — nothing is written to Jira until you explicitly approve.

---

## Prerequisites

| Requirement | Why |
|-------------|-----|
| [Claude Code](https://docs.claude.com/claude-code) installed | Required to run the plugin |
| **Atlassian MCP** server connected | Reads Jira issues / Confluence pages, creates Jira test issues |
| **Playwright MCP** server connected | Optional — only needed for CSV auto-upload or UI-driven Xray step entry |
| Atlassian account with Jira & Xray access | You'll create an API token here |
| Xray Cloud admin access (or someone who can give you API keys) | Optional — only needed if you want X-Ray native steps via API instead of Playwright |

Verify Claude Code is working: `claude --version`.

---

## Step 1 — Install the plugin

```text
/plugin marketplace add SwadhaTripathi/xray-test-suite-skills
/plugin install xray-test-suite
```

Restart your Claude Code session so the plugin loads.

Verify:
```text
/plugin list
```

You should see `xray-test-suite` in the installed list, and `/xray-tests` should now autocomplete when you start typing it.

> **Alternative: install from a local checkout** (useful for development or air-gapped environments):
> ```bash
> git clone https://github.com/SwadhaTripathi/xray-test-suite-skills.git ~/code/xray-test-suite-skills
> ```
> Then in Claude Code: `/plugin marketplace add ~/code/xray-test-suite-skills` followed by `/plugin install xray-test-suite`.

---

## Step 2 — Locate the installed plugin folder

Claude Code installs plugins into `~/.claude/plugins/marketplaces/<marketplace>/<plugin>/`. To find the exact path, run:

```text
/plugin info xray-test-suite
```

…or search:

```bash
find ~/.claude/plugins -name "plugin.json" -path "*xray-test-suite*"
```

For the rest of this guide we'll refer to that location as `<PLUGIN_DIR>`. You'll edit one file inside it (`skills/xray-test-suite/references/config.json`) and one outside (`~/.claude/.xray-credentials.json`).

---

## Step 3 — Create your routing config

This file holds tenant-level routing info — your cloud ID, project key, custom field IDs, and Xray import URL. **No secrets here.**

```bash
cd <PLUGIN_DIR>/skills/xray-test-suite/references
cp config.sample.json config.json
```

Open `config.json` in your editor and fill in:

| Field | How to find the value |
|-------|----------------------|
| `atlassian.cloudId` | Either your Jira hostname (e.g. `your-site.atlassian.net`) **or** the UUID-style cloudId. To get the UUID: invoke the Atlassian MCP `getAccessibleAtlassianResources` tool in Claude Code, or visit `https://your-site.atlassian.net/_edge/tenant_info`. |
| `atlassian.username` | Your work email registered on Atlassian |
| `project.key` | Jira project key (e.g. `FIFAGEN`). Visible in any issue URL: `…/browse/FIFAGEN-123` → key is `FIFAGEN`. |
| `project.name` | Display name (e.g. `FIFA Genesis`). Cosmetic. |
| `xrayImport.url` | Jira → Apps menu → **Xray** → **Test Case Importer**. Copy the full URL (it embeds `project.key` and `project.id`). |
| `customFields.epicLink` | Usually `customfield_10014` on Jira Cloud. To verify on your tenant: `GET https://<your-site>/rest/api/3/field` and search for `"Epic Link"`. |
| `customFields.manualTestSteps` | Tenant-specific — find the field named `Manual Test Steps` in the same `/rest/api/3/field` response. |
| Other `customFields.*` | Optional — leave at defaults unless you actively use these fields |

`config.json` is **gitignored** — your tenant values stay local and are never pushed back if you ever contribute to the plugin.

---

## Step 4 — Create your credentials file (OUTSIDE the plugin folder)

Real secrets live in your user home, never inside the plugin folder. This ensures any `git push` (whether of your fork or by accident) cannot leak them.

```bash
cp <PLUGIN_DIR>/skills/xray-test-suite/references/credentials.sample.json \
   ~/.claude/.xray-credentials.json
```

Open `~/.claude/.xray-credentials.json` and fill in:

### 4a. Atlassian API token
1. Go to **https://id.atlassian.com/manage-profile/security/api-tokens**
2. Click **Create API token** → label it `xray-test-suite`
3. Copy the token into `atlassian.apiToken` in your credentials file

> Treat this token like a password. Anyone with it can act as you in Jira/Confluence.

### 4b. Xray Cloud API keys (optional but recommended)

Skip this and the skill falls back to Playwright browser automation for adding X-Ray native test steps. Slower (~5–10× slower for a 20-test suite) but works without API access.

1. In Jira → **Settings (gear) → Apps → Manage your apps**
2. Left sidebar → **Xray** → **API Keys**
3. Click **Create API Key**
4. Copy **Client ID** → `xrayCloud.clientId`, **Client Secret** → `xrayCloud.clientSecret`

> If you don't have admin access to Xray, ask your Xray administrator. The Client Secret is shown only once at creation.

### 4c. Verify file is correctly placed
```bash
ls -la ~/.claude/.xray-credentials.json
```

The plugin loads this file from `~/.claude/.xray-credentials.json` by default. To change the location, set `credentialsPath` in the routing `config.json`.

---

## Step 5 — Verify your setup (dry run)

Confirm both config files are wired up correctly **before** any real test generation:

```text
/xray-tests --dry-run
```

The skill will:
- Read `config.json` and the credentials file
- Print resolved values with **secrets redacted**
- Validate `importConfiguration.json` is parseable
- Exit without creating anything

If the dry-run reports missing fields or unparseable JSON, fix them now. Common issues:
- Placeholder values like `<your-...>` still in place → you didn't edit the file
- Credentials file at wrong path → check `~/.claude/.xray-credentials.json` exists exactly
- Invalid JSON → unescaped quote in a value, missing comma, etc.

---

## Step 6 — First run with the included example

The plugin ships with a tiny example (`examples/sample-requirements.md` at the plugin root) so you can verify the full workflow on something safe.

```text
/xray-tests <PLUGIN_DIR>/examples/sample-requirements.md
```

What you'll see:

1. The skill reads the `.md` file
2. It asks **which Epic** to link the generated tests to — give it any Epic key from your project (or one you create just for testing, e.g. `FIFAGEN-TEST-EPIC`)
3. It presents a **test matrix** (~4 tests covering UC1/UC2/UC3 from the example)
4. You approve by typing `APPROVE` or `APPROVE ALL`
5. It asks **output mode** — pick `1` for CSV only on your first run (safest, no Jira writes)
6. CSV is written to `<PLUGIN_DIR>/skills/xray-test-suite/output/TestCases_<EPIC>_<timestamp>.csv`
7. It asks if you want to **upload via Playwright** — pick `no` for the first run
8. You get a summary with the file path

Open the CSV in Excel/Sheets to confirm the row-per-step layout looks right before you graduate to API or Both modes on a real Epic.

---

## Output Modes Cheatsheet

When the skill asks "How would you like to deliver these test cases?" — here's the picker:

| Reply | Mode | Best for |
|-------|------|---------|
| `1` | **CSV only** | Bulk loads (50+ tests), audit trail needed, or you want to review the import before commit |
| `2` | **API only** | Small batches (<20 tests), immediate Jira issues required, you have Xray Cloud API credentials |
| `3` | **Both** | Default recommendation — CSV as backup, API for immediate creation |

If you pick a mode that produces a CSV, you'll then be asked whether to **auto-upload via Playwright**. That triggers a browser session that:
- Navigates to the Xray Test Case Importer URL from your config
- Handles SSO login (pauses if a manual password step is needed)
- Uploads the CSV and `importConfiguration.json` (field mapping)
- Runs the import wizard end-to-end
- Reports the created Jira keys

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `/xray-tests` doesn't autocomplete | Plugin installed but session not restarted, or `/plugin list` doesn't show it | Restart Claude Code; if still missing, re-run `/plugin install xray-test-suite` |
| Dry-run says "config.json not found" | You didn't run Step 3 | `cp config.sample.json config.json` and edit |
| Dry-run says "credentials file contains placeholders" | You copied the sample but didn't fill in values | Open `~/.claude/.xray-credentials.json` and replace `<…>` placeholders |
| `getJiraIssue` returns 401 / 403 | API token wrong, expired, or lacks project access | Regenerate token at id.atlassian.com → API tokens |
| `getJiraIssue` returns 404 | Wrong `cloudId` or you don't have access to the issue | Verify cloudId via `getAccessibleAtlassianResources` MCP tool |
| Xray API auth fails (`401`) | Wrong clientId/clientSecret OR token expired (15-min TTL) | Re-create API key in Jira → Apps → Xray → API Keys |
| Playwright upload: file picker selector not found | Xray UI changed | Run `/xray-tests --dry-run` to verify, then fall back to manual import via the Xray UI |
| Custom field IDs don't work | Field IDs differ per tenant | `GET https://<your-site>/rest/api/3/field` to discover correct IDs |
| CSV import fails on Xray side | Column order doesn't match `importConfiguration.json` | Verify the mapping config — column INDEX is the source of truth, not header text |

For deeper issues, run `/xray-tests --dry-run` first — it surfaces most config problems before any external call.

---

## Updating the plugin

```text
/plugin update xray-test-suite
```

Your `config.json` and `~/.claude/.xray-credentials.json` are not affected by plugin updates (one is gitignored, one is outside the plugin folder). If `config.sample.json` adds new fields in an update, the update will surface them — copy any new fields into your `config.json` by hand.

---

## Uninstalling

```text
/plugin uninstall xray-test-suite
/plugin marketplace remove xray-test-suite-skills
```

Optionally remove your credentials file if you don't use it elsewhere:
```bash
rm ~/.claude/.xray-credentials.json
```

Nothing in Jira is rolled back — any issues created via the plugin remain. To bulk-delete them, use a JQL filter like `project = <KEY> AND issuetype = Test AND created >= -7d` in Jira's bulk operations.

---

## Where to learn more

- **Workflow details:** [`skills/xray-test-suite/SKILL.md`](skills/xray-test-suite/SKILL.md) — the full 9-step workflow with prompts, schemas, and tool calls
- **Config reference:** [`skills/xray-test-suite/references/README.md`](skills/xray-test-suite/references/README.md) — table of every config field
- **Xray field-mapping:** [`skills/xray-test-suite/references/importConfiguration.json`](skills/xray-test-suite/references/importConfiguration.json) — column → Jira field map (authoritative)
- **Example:** [`examples/sample-requirements.md`](examples/sample-requirements.md) — minimal requirements doc for end-to-end testing
