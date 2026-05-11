---
name: xray-test-suite
description: Full-cycle Xray test case workflow — generate test cases from requirements (Jira issue, Confluence page, file, or pasted text), produce import-ready CSV and/or create Jira issues directly via Atlassian API, and optionally upload the CSV via Playwright browser automation. Use this when you need to bulk-author Xray tests from a spec.
disable-model-invocation: true
argument-hint: "[source: jira-key | confluence-url | file-path | --dry-run]"
---

# Xray Test Suite

End-to-end workflow for authoring and importing Xray test cases:

1. **Input** — Jira Epic/Story, Confluence page, local file (.md/.pdf/.pptx/.docx/.png/.drawio/.txt), or pasted text
2. **Analyze** — extract requirements, categorize (positive/negative/edge/safety), optimize via merging
3. **Approve** — present test matrix; wait for user APPROVE
4. **Mode pick** — user chooses: CSV / API / Both
5. **Output** — CSV file in `output/`, Jira issues via API, optional Playwright upload

---

## Configuration

Three files. Read them at the start of every run.

| File | Purpose | Committed? |
|------|---------|-----------|
| `${CLAUDE_SKILL_DIR}/references/config.json` | Routing (cloudId, project key, custom field IDs, Xray import URL) | NO — gitignored |
| `~/.claude/.xray-credentials.json` | Real secrets (API token, Xray client ID/secret) | NO — lives outside skill |
| `${CLAUDE_SKILL_DIR}/references/importConfiguration.json` | CSV column → Jira field mapping (authoritative for CSV schema) | YES |

Templates: `config.sample.json` and `credentials.sample.json` are committed. See `references/README.md` for first-time setup.

---

## Critical Rules

- **NEVER create Jira issues until the user explicitly writes "APPROVE" / "APPROVE ALL" / "APPROVE: <TC-IDs>"**
- **NEVER leak credentials, tokens, or secrets in outputs**
- **ALWAYS present the draft test matrix with coverage before any creation**
- **ALWAYS ask the user to pick output mode (CSV / API / Both) — do not assume**
- **ALWAYS derive CSV column order from `importConfiguration.json` — never hardcode**
- **ALWAYS add Xray native test steps to the "Test Details" tab in API mode** (via API if credentials exist, else Playwright)
- **PAUSE for clarification when requirements are ambiguous — do not guess at safety-critical or business-critical behavior**

---

## Prerequisites

- **Atlassian MCP** — `mcp__atlassian__*` tools for Jira/Confluence access
- **Playwright MCP** — `mcp__playwright__*` tools (required for Step 7 upload and Xray UI step-entry fallback)
- A populated `~/.claude/.xray-credentials.json` (see setup README)

---

## Workflow

### Step 1 — Load Configuration

1. Read `${CLAUDE_SKILL_DIR}/references/config.json`. If missing, instruct user to `cp config.sample.json config.json` and abort.
2. Read the credentials file at `config.credentialsPath` (default `~/.claude/.xray-credentials.json`). If missing or contains placeholder `<...>` values, abort with setup instructions.
3. Determine `xrayMethod`:
   - `credentials.xrayCloud.clientId` and `clientSecret` both non-empty → `xrayMethod = "API"`
   - Otherwise → `xrayMethod = "Playwright"`

If `$ARGUMENTS == "--dry-run"`: read both configs, print resolved values (REDACT secrets), and exit.

---

### Step 2 — Detect Input

**Supported input types:**

| Input | Example | How to detect |
|-------|---------|---------------|
| Jira Issue Key | `FIFAGEN-2872` | `/^[A-Z]+-\d+$/` |
| Confluence URL | `https://...atlassian.net/wiki/...` | contains `/wiki/` |
| Confluence Page ID | `123456789` | `/^\d{6,}$/` |
| Local file | `./reqs.md`, `C:/docs/spec.pdf` | file extension recognized |
| Plain text | multi-line spec | nothing else matches |

**Supported file formats:**

| Extension | How to read |
|-----------|-------------|
| `.md`, `.txt` | Read tool, direct text |
| `.pdf` | Read tool with `pages` parameter for >10 pages |
| `.pptx`, `.docx` | Read tool |
| `.png`, `.jpg`, `.jpeg` | Read tool (vision/OCR for diagrams) |
| `.drawio`, `.xml` | Read tool, parse `mxCell` elements |

If no argument provided, prompt the user with the above table.

---

### Step 3 — Fetch Requirements

Route based on detected input type:

| Type | Tool / method |
|------|---------------|
| Jira Issue | `mcp__atlassian__getJiraIssue` (+ fetch linked children if it's an Epic) |
| Confluence | `mcp__atlassian__getConfluencePage` (extract page ID from URL if needed) |
| Local file | `Read` tool |
| Plain text | use directly |

**Epic resolution:** Test cases must link to an Epic.
- If fetched issue IS an Epic → use it.
- If it's a Story/Task → use parent / `customfield_10014`. If unset, ASK USER.
- For file/text input → ASK USER which Epic to link tests to.

---

### Step 4 — Analyze, Categorize, Optimize

**Parse** the requirements: use cases (UC1, UC2…), requirements (R1, R2…), state transitions, error scenarios.

**Categorize** into: Positive Flow / Negative Flow / Edge Case / State Machine / Integration / Error Recovery.

**Assign priority** (P1 Critical → P4 Low) based on business impact and safety-criticality.

**Optimize** by merging related scenarios (since tests run serially, fewer well-designed tests beat many narrow ones):
- Negative → Recovery → Positive flow in one test
- State sequences combined
- Shared setup grouped
- Cleanup verification appended to positive tests

**Internal test case schema** (drives both CSV and API output):

```json
{
  "id": "TC-001",
  "requirement_ids": ["R1", "R3"],
  "summary": "Concise title (max 100 chars)",
  "description": {
    "objective": "What this validates and why",
    "preconditions": ["System state", "Data setup"]
  },
  "steps": [
    {"action": "Click Unload", "data": "slot=1", "expected_result": "Wafer moves to slot 1"}
  ],
  "priority": "Critical|High|Medium|Low",
  "tags": ["Positive|Negative|Boundary|ErrorHandling|Safety"]
}
```

Present the test matrix to the user and wait for explicit approval before proceeding.

---

### Step 5 — Output Mode Selection (REQUIRED)

After matrix approval, ask:

```
## How would you like to deliver these test cases?

1. CSV only — import-ready CSV in output/, no Jira issues created until you run import manually
2. API only — create Jira issues directly via API (pilot + parallel agents)
3. Both — generate CSV first as backup, then proceed with API creation

Reply: 1, 2, or 3
```

Map the answer to `OUTPUT_MODE` ∈ `{CSV_ONLY, API_ONLY, BOTH}`. Do not guess — re-ask if ambiguous.

**Routing:**

| Mode | Steps that run |
|------|----------------|
| CSV_ONLY | 6 → 7 (offer Playwright upload) → 9 |
| API_ONLY | 8 (pilot + parallel) → 9 |
| BOTH | 6 → 7 (offer Playwright upload) → 8 → 9 |

---

### Step 6 — Generate CSV File (when OUTPUT_MODE ∈ {CSV_ONLY, BOTH})

The CSV is consumed by Xray's Test Case Importer. The column schema is **driven by `importConfiguration.json`** — read it now and rebuild the order from `config.field.mappings[]`. Do NOT hardcode.

**Current schema (sorted by `column.index`):**

| Index | Field ID | Header | Row scope |
|-------|----------|--------|-----------|
| 0 | `__xray_testId` | `Test ID` | Every row (group key) |
| 1 | `summary` | `Summary` | First row of each test |
| 2 | `description` | `Description` | First row of each test |
| 3 | `xray_testtype` | `Test Type` | First row of each test |
| 4 | `__xray_step_data` | `Step Data` | Every step row |
| 5 | `__xray_step_action` | `Step Action` | Every step row |
| 6 | `__xray_step_result` | `Step Result` | Every step row |

**Format rules** (from `importConfiguration.json`):
- Delimiter `,`  •  Encoding UTF-8  •  Quote `"`  •  Escape `"` as `""`
- Quote any field containing `,`, `"`, `\n`, or `;`
- Multi-value list delimiter inside a field: `;` (used for `requirement_ids`, `tags`)

**Row layout — row-per-step, grouped by Test ID:**

A test with N steps emits N rows sharing the same Test ID. The first row carries case-level fields (Summary / Description / Test Type); subsequent rows leave those blank. This matches how the Xray importer groups rows by `__xray_testId`.

Example (1 test, 2 steps):

```csv
Test ID,Summary,Description,Test Type,Step Data,Step Action,Step Result
TC-001,"Basic Unload from Chuck","Objective: Verify wafer unload...

Preconditions:
- Chuck loaded
- Carrier slot empty

Requirements: R1;R3
Priority: High
Tags: Positive",Manual,"slot=1; wafer_id=W001","Click Unload button","Wafer moves to carrier slot 1"
TC-001,,,,"slot=1","Verify carrier light is green","Light is green and no alarms"
```

**Field construction:**

| Column | Source |
|--------|--------|
| `Test ID` | `test_case.id` |
| `Summary` | `test_case.summary` |
| `Description` | `Objective: <objective>\n\nPreconditions:\n- <p>\n\nRequirements: <ids joined ";">\nPriority: <p>\nTags: <tags joined ";">` |
| `Test Type` | `config.defaults.testType` |
| `Step Data` | `step.data` (empty string if null) |
| `Step Action` | `step.action` |
| `Step Result` | `step.expected_result` |

**Write to:** `${CLAUDE_SKILL_DIR}/output/TestCases_<EPIC_KEY>_<YYYYMMDD-HHMMSS>.csv` (or per `config.output.filenamePattern`).

After writing, present the file path, row count, and instructions to either continue to Step 7 (Playwright upload) or stop.

---

### Step 7 — Optional Playwright Upload (when OUTPUT_MODE includes CSV)

After CSV is written, ask:

```
Upload this CSV to Xray now via browser automation? (yes / no)
- yes: I'll navigate to the Xray Test Case Importer, handle SSO, upload the CSV + importConfiguration.json, and run the import wizard.
- no: skip — you can import manually later via Jira → Xray → Test Case Importer
```

If yes, run the upload sub-workflow:

#### 7.1 Navigate to Importer
- `mcp__playwright__browser_navigate` → `config.xrayImport.url`
- Wait up to 30s for page load
- If login page detected → Step 7.2; else → Step 7.3

#### 7.2 SSO Login
- Locate email input → fill with `config.atlassian.username`
- Click `Continue` → wait for SSO redirect
- **Password handling:** if a password field appears (no SSO), PAUSE and tell user to enter password manually
- Wait for Xray import interface to load

#### 7.3 Select CSV Format
- On the importer page, click the **CSV** option (button / card / radio)

#### 7.4 Upload Files
- Click "Choose File" / file input → upload generated CSV from `output/`
- Click "Choose Existing Configuration" → upload `references/importConfiguration.json`
- Verify both filenames appear in the UI

#### 7.5 Next — Setup Screen
- Click **Next**
- Take a screenshot (settings are auto-populated from importConfiguration.json)
- Click **Next** again

#### 7.6 Map Fields Screen
- Take a screenshot of the mapping table for user verification
- Click **Begin Import**

#### 7.7 Wait for Completion
- Poll the import status screen until success or error appears
- Take final screenshot

#### 7.8 Report
On success: list created Jira keys (read from the importer's results page — do NOT hardcode).
On failure: report error + screenshot, suggest checking CSV format or field mappings.

**Selector strategy (in order of preference):** text → role → data-testid → CSS → XPath. Take fresh snapshot after each major action. Iframes: Xray Test Case Importer runs in an iframe — use iframe refs from snapshots.

---

### Step 8 — API Creation (when OUTPUT_MODE ∈ {API_ONLY, BOTH})

#### 8.1 Pilot Test
Create ONE test case via `mcp__atlassian__createJiraIssue` to validate formatting before bulk creation.

```
issueTypeName: "Test"
summary: "[<EPIC_KEY>] <Category>: <Test Description>"
description: <ADF body — see ADF Reference below>
```

Then:
- Link to Epic: `mcp__atlassian__editJiraIssue` with `customfield_10014 = <EPIC_KEY>`
- Populate `customfield_11985` (manual test steps, ADF format)
- Add Xray native steps (Step 8.3)

**Present pilot URL to user and WAIT for explicit approval before proceeding to 8.2.**

#### 8.2 Parallel Creation (after pilot approved)
For each remaining test case, spawn a `general-purpose` agent with `run_in_background: true`. All agents in a single message → true parallel execution.

**Batching:** Default 10 agents per batch. Wait for each batch to complete before spawning the next.

**Per-agent prompt template** must include:
- Test case details (id, summary, objective, steps, priority, requirements)
- `OUTPUT_MODE`, `cloudId`, `EPIC_KEY`, `loginEmail`
- `xrayMethod` ("API" or "Playwright") so the agent knows how to add native steps
- Custom field IDs from config
- Instructions to return JSON result: `{status, testCaseId, jiraKey, url, xrayStepsAdded, error}`

#### 8.3 Add Xray Native Test Steps
**Method A — Xray Cloud API** (when `xrayMethod == "API"`):

```bash
TOKEN=$(curl -s -X POST -H "Content-Type: application/json" \
  -d '{"client_id":"<CLIENT_ID>","client_secret":"<CLIENT_SECRET>"}' \
  https://xray.cloud.getxray.app/api/v2/authenticate | tr -d '"')

curl -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '[{"action":"...","data":"...","result":"..."}]' \
  https://xray.cloud.getxray.app/api/v2/test/<TEST_KEY>/steps
```

Token TTL is ~15 minutes — each agent authenticates independently.

**Method B — Playwright** (when `xrayMethod == "Playwright"`): Navigate to test issue → Test Details tab → loop "Add Step / New Step" for each step, filling Action / Data / Expected Result fields. UI runs in an iframe — refresh snapshot between actions.

#### 8.4 Error Isolation
Agent failures are scoped to single tests. Other agents continue. Failed tests are reported in Step 9 and can be retried.

---

### Step 9 — Summary

Mode-aware report:

**CSV_ONLY:**
```
CSV Generation Complete

File: <path>
Tests: <N>, Step rows: <TOTAL_STEPS>
Schema: derived from references/importConfiguration.json
No Jira issues created.

To import: see Step 7 instructions (re-run /xray-tests and pick mode 1 → say yes to Playwright upload),
or manually upload via Jira → Xray → Test Case Importer.
```

**API_ONLY:**
```
Test Case Creation Summary

Total: <N>
Pilot: <PILOT_KEY>
Parallel agents: <M>
Success rate: <X>/<N>

| # | TC ID | Jira Key | Xray Steps | Status | Link |
| - | ----- | -------- | ---------- | ------ | ---- |
...

Failed cases (if any):
| TC ID | Error | Suggested action |
```

**BOTH:** combine — lead with CSV path, then the API table. Note that CSV is the rollback artifact if API had failures.

If any API failures, offer retry options:
1. Retry all failed (re-spawn agents)
2. Retry specific TC IDs
3. Skip (accept current results)
4. Manual fix (provide Jira links to complete by hand)

---

## ADF Reference

Atlassian Document Format examples for `description` and custom-field bodies.

**Paragraph:**
```json
{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[{"type":"text","text":"Your text"}]}
]}
```

**Ordered list:**
```json
{"type":"orderedList","content":[
  {"type":"listItem","content":[
    {"type":"paragraph","content":[{"type":"text","text":"Step 1"}]}
  ]}
]}
```

**Bold:** `{"type":"text","text":"bold","marks":[{"type":"strong"}]}`

---

## Custom Fields Reference

Default IDs (override in `config.json` per tenant):

| Field ID | Name | Purpose |
|----------|------|---------|
| `customfield_10014` | Epic Link | Parent epic |
| `customfield_11985` | Manual Test Steps | Legacy ADF steps field |
| `customfield_12591` | Rovo Manual Steps | Rovo agent field |

---

## Xray Cloud API Reference

| Action | Method + Endpoint |
|--------|------------------|
| Authenticate | `POST https://xray.cloud.getxray.app/api/v2/authenticate` body: `{"client_id":"...","client_secret":"..."}` |
| Get steps | `GET https://xray.cloud.getxray.app/api/v2/test/<KEY>/steps` |
| Set steps | `PUT https://xray.cloud.getxray.app/api/v2/test/<KEY>/steps` body: array of `{action, data, result}` |

Get API credentials: Jira → Settings → Apps → Xray → API Keys → Create new key.

---

## Error Handling

| Scenario | Action |
|----------|--------|
| Config or credentials file missing | Abort with setup instructions pointing to `references/README.md` |
| Credentials contain placeholder `<...>` values | Abort with "fill in credentials.json" message |
| File not found / unsupported extension | Report and re-prompt |
| PDF >20 pages without page range | Ask user for page range |
| Jira fetch fails | Report HTTP error, check API token & cloudId |
| Xray import URL 404 | Verify project.id in URL matches the project key |
| Playwright file upload selector not found | Try alternative selectors (`input[type="file"]`, `[data-testid*="file"]`), screenshot if still missing |
| "Begin Import" button disabled | Read validation errors on screen, report to user |
| Xray API auth 401 | Re-check clientId/clientSecret; tokens expire ~15min, re-authenticate |
| Agent batch failure | Continue remaining agents; offer retry in Step 9 |

---

## What This Skill Does NOT Do

- Does not store or type passwords (SSO/password entry is manual)
- Does not hardcode test case names, field mappings, or project keys
- Does not modify `importConfiguration.json` (it's the contract with the Xray importer)
- Does not commit real `config.json` or `~/.claude/.xray-credentials.json` to git
- Does not create Jira issues without explicit user APPROVE

---

## Examples

### Example 1 — Jira Epic (CSV only)
```
/xray-tests FIFAGEN-2872
→ skill fetches epic + linked stories
→ presents 8-test matrix, user APPROVES
→ user picks mode "1" (CSV only)
→ writes output/TestCases_FIFAGEN-2872_20260511-143022.csv
→ user picks "no" to Playwright upload
→ summary shows file path
```

### Example 2 — Local .md file (Both modes)
```
/xray-tests ./examples/sample-requirements.md
→ user provides Epic FIFAGEN-3001 when asked
→ matrix approved
→ user picks mode "3" (Both)
→ CSV written → user picks "no" to Playwright (will use API path instead)
→ pilot test created in Jira → user approves
→ 7 parallel agents create remaining tests
→ summary shows CSV path + Jira key table
```

### Example 3 — Confluence page → CSV + auto-upload
```
/xray-tests https://...atlassian.net/wiki/spaces/PROJ/pages/12345
→ matrix approved
→ mode "1" (CSV only)
→ CSV written
→ user picks "yes" to Playwright upload
→ skill navigates to Xray, handles SSO, uploads files, runs import wizard
→ summary lists Jira keys read from import results page
```

### Example 4 — Dry run
```
/xray-tests --dry-run
→ skill reads config + credentials, redacts secrets, prints resolved values
→ verifies importConfiguration.json is valid
→ exits without any creation
```
