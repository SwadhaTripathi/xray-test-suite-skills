# Initial Setup — xray-test-suite

End-to-end walkthrough: from cloning this repo to running your first test-case generation. Plan ~10–15 minutes for a clean setup.

If you already understand the skill and just need a config reference, skip to [`references/README.md`](references/README.md).

---

## What this skill does

Given a requirements source (Jira issue, Confluence page, local file, or pasted text), the skill:

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
| [Claude Code](https://docs.claude.com/claude-code) installed | Required to run the skill |
| **Atlassian MCP server** connected | Reads Jira issues / Confluence pages, creates Jira test issues |
| **Playwright MCP server** connected | Optional — only needed if you use the auto-upload feature or fall back to UI-driven X-Ray step entry |
| Atlassian account with Jira & Xray access | You'll create an API token here |
| Xray Cloud admin access (or someone who can give you API keys) | Optional — needed only if you want X-Ray native steps added via API instead of Playwright |

Verify Claude Code is working before starting: `claude --version`.

---

## Step 1 — Clone the repository

The skill must live in `~/.claude/skills/xray-test-suite/` so Claude Code can discover it.

**Bash / Git Bash:**
```bash
git clone https://github.com/SwadhaTripathi/xray-test-suite-skills.git ~/.claude/skills/xray-test-suite
```

**PowerShell:**
```powershell
git clone https://github.com/SwadhaTripathi/xray-test-suite-skills.git $HOME\.claude\skills\xray-test-suite
```

Verify the clone:
```bash
ls ~/.claude/skills/xray-test-suite/
# expected: SKILL.md, references/, output/, examples/, initial_setup.md, .gitignore
```

---

## Step 2 — Create your routing config

This file holds tenant-level routing info — your cloud ID, project key, custom field IDs, and Xray import URL. **No secrets here.**

```bash
cd ~/.claude/skills/xray-test-suite/references
cp config.sample.json config.json
```

Open `config.json` in your editor and fill in:

| Field | How to find the value |
|-------|----------------------|
| `atlassian.cloudId` | Either your Jira hostname (e.g. `your-site.atlassian.net`) **or** the UUID-style cloudId. To get the UUID: invoke the Atlassian MCP `getAccessibleAtlassianResources` tool in Claude Code, or visit `https://your-site.atlassian.net/_edge/tenant_info`. |
| `atlassian.username` | Your work email registered on Atlassian |
| `project.key` | Jira project key (e.g. `FIFAGEN`). Visible in the URL when viewing any issue: `…/browse/FIFAGEN-123` → key is `FIFAGEN`. |
| `project.name` | Display name (e.g. `FIFA Genesis`). Cosmetic. |
| `xrayImport.url` | Navigate in your browser: Jira → Apps menu → **Xray** → **Test Case Importer**. Copy the full URL (it embeds `project.key` and `project.id`). |
| `customFields.epicLink` | Usually `customfield_10014` on Jira Cloud. To verify on your tenant: `GET https://<your-site>/rest/api/3/field` and search for `"Epic Link"`. |
| `customFields.manualTestSteps` | Tenant-specific — find the field named `Manual Test Steps` in the same `/rest/api/3/field` response. |
| Other `customFields.*` | Optional — leave at defaults unless you actively use these fields |

`config.json` is **gitignored** — your tenant-specific values stay on your machine and are never pushed.

---

## Step 3 — Create your credentials file (OUTSIDE the skill folder)

Real secrets live in your user home, not inside the skill folder. This ensures `git push` can never leak them.

```bash
cp ~/.claude/skills/xray-test-suite/references/credentials.sample.json \
   ~/.claude/.xray-credentials.json
```

Open `~/.claude/.xray-credentials.json` and fill in:

### 3a. Atlassian API token
1. Go to **https://id.atlassian.com/manage-profile/security/api-tokens**
2. Click **Create API token** → give it a label like `xray-test-suite`
3. Copy the token and paste it into `atlassian.apiToken` in your credentials file

> Treat this token like a password. Anyone with it can act as you in Jira/Confluence.

### 3b. Xray Cloud API keys (optional but recommended)

If you skip this, the skill falls back to Playwright browser automation for adding X-Ray native test steps. Slower (~5–10× slower for a 20-test suite) but works without API access.

1. In Jira, go to **Settings (gear icon) → Apps → Manage your apps**
2. In the left sidebar, find the **Xray** section → **API Keys**
3. Click **Create API Key** → give it a name
4. Copy the **Client ID** and **Client Secret** into `xrayCloud.clientId` and `xrayCloud.clientSecret`

> If you don't have admin access to Xray, ask your team's Xray administrator. The Client ID is not sensitive; the Client Secret is — it's shown only once at creation.

### 3c. Verify file is correctly placed
```bash
ls -la ~/.claude/.xray-credentials.json
# expected: file exists, permissions readable only by you
```

The skill loads this file at `~/.claude/.xray-credentials.json` by default. To change the location, set `credentialsPath` in `references/config.json`.

---

## Step 4 — Verify your setup (dry run)

Confirm both config files are wired up correctly **before** any real test generation:

```
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

## Step 5 — (Optional) Confirm the slash command is registered

The repo doesn't include the slash command file (it lives in your `~/.claude/commands/` folder, not in the skill). If `/xray-tests` doesn't autocomplete in Claude Code, create it:

**Bash:**
```bash
cat > ~/.claude/commands/xray-tests.md <<'EOF'
# Xray Tests — Generate & Import

Generate Xray test cases via the xray-test-suite skill.

## Usage
/xray-tests [source]
/xray-tests --dry-run

## How
Invoke the `xray-test-suite` skill via the Skill tool. Pass $ARGUMENTS as the source.
EOF
```

**PowerShell:** create `$HOME\.claude\commands\xray-tests.md` with the same content.

Restart your Claude Code session for the new command to register.

You can also invoke the skill directly via the Skill tool without the slash command — say something like *"use the xray-test-suite skill on FIFAGEN-1234"*.

---

## Step 6 — First run with the included example

The repo ships with a tiny example (`examples/sample-requirements.md`) so you can verify the full workflow end-to-end on something safe.

```
/xray-tests ./examples/sample-requirements.md
```

What you'll see:

1. The skill reads the `.md` file
2. It asks **which Epic** to link the generated tests to — give it any Epic key from your project (or one you create just for testing, e.g. `FIFAGEN-TEST-EPIC`)
3. It presents a **test matrix** (~4 tests covering UC1/UC2/UC3 from the example)
4. You approve by typing `APPROVE` or `APPROVE ALL`
5. It asks **output mode** — pick `1` for CSV only on your first run (safest, no Jira writes)
6. CSV is written to `~/.claude/skills/xray-test-suite/output/TestCases_<EPIC>_<timestamp>.csv`
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
| `--dry-run` says "config.json not found" | You didn't run Step 2 | `cp references/config.sample.json references/config.json` and edit |
| Dry-run says "credentials file contains placeholders" | You copied the sample but didn't fill in values | Open `~/.claude/.xray-credentials.json` and replace `<…>` placeholders |
| `getJiraIssue` returns 401 / 403 | API token wrong, expired, or lacks project access | Regenerate token at id.atlassian.com → API tokens |
| `getJiraIssue` returns 404 | Wrong `cloudId` or you don't have access to the issue | Verify cloudId via `getAccessibleAtlassianResources` MCP tool |
| Xray API auth fails (`401`) | Wrong clientId/clientSecret OR token expired (15-min TTL) | Re-create API key in Jira → Apps → Xray → API Keys |
| Playwright upload: file picker selector not found | Xray UI changed | Run `/xray-tests --dry-run` to verify, then fall back to manual import via the Xray UI |
| Custom field IDs don't work | Field IDs differ per tenant | `GET https://<your-site>/rest/api/3/field` to discover correct IDs |
| Push to your fork fails: "email privacy" | Your GitHub account hides your email | Use `git -c user.email="<id>+<login>@users.noreply.github.com" commit ...` or enable email in github.com/settings/emails |
| `/xray-tests` autocomplete not appearing | Slash command file missing | Step 5 above |
| CSV import fails on Xray side | Column order doesn't match `importConfiguration.json` | Verify the mapping config — column INDEX is the source of truth, not header text |

For deeper issues, run `/xray-tests --dry-run` first — it surfaces most config problems before any external call.

---

## Updating the skill

```bash
cd ~/.claude/skills/xray-test-suite
git pull
```

Your `config.json` and `~/.claude/.xray-credentials.json` are not affected by pulls (one is gitignored, one is outside the repo). If `config.sample.json` adds new fields in an update, copy them manually into your `config.json`.

---

## Uninstalling

```bash
rm -rf ~/.claude/skills/xray-test-suite
rm ~/.claude/commands/xray-tests.md          # if you added it
rm ~/.claude/.xray-credentials.json          # only if you don't use these credentials elsewhere
```

Nothing in Jira is rolled back — any issues created via the skill remain. To bulk-delete them, use a JQL filter like `project = <KEY> AND issuetype = Test AND created >= -7d` in Jira's bulk operations.

---

## Where to learn more

- **Workflow details:** `SKILL.md` in this folder — the full 9-step workflow with prompts, schemas, and tool calls
- **Config reference:** `references/README.md` — table of every config field
- **Xray field-mapping:** `references/importConfiguration.json` — column → Jira field map (authoritative)
- **Example:** `examples/sample-requirements.md` — minimal requirements doc for end-to-end testing
