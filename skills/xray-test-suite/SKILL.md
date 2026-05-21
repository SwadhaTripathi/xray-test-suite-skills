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
| `${CLAUDE_SKILL_DIR}/references/config.json` | Routing (cloudId, project key, custom field IDs, Xray import URL, **step template Jira key, reviewer settings**) | NO — gitignored |
| `~/.claude/.xray-credentials.json` | Real secrets (API token, Xray client ID/secret) | NO — lives outside skill |
| `${CLAUDE_SKILL_DIR}/references/importConfiguration.json` | CSV column → Jira field mapping (authoritative for CSV schema) | YES |

**New in this version**: `config.templates.testStepTemplateKey` (Jira key for canonical Xray test) and `config.reviewer.*` (`enabled`, `maxIterations`, `severityThreshold`) drive the **Step 4.5 automated reviewer loop**. Defaults if unset: `enabled = true`, `maxIterations = 3`, `severityThreshold = "High"`. If `testStepTemplateKey` is unset/placeholder, the reviewer skips only the Template review category.

Templates: `config.sample.json` and `credentials.sample.json` are committed. See `references/README.md` for first-time setup.

---

## Critical Rules

- **NEVER create Jira issues until the user explicitly writes "APPROVE" / "APPROVE ALL" / "APPROVE: <TC-IDs>"** (after the Step 4.5 reviewer loop converges OR the user accepts gaps from the escalation menu)
- **WHEN `config.reviewer.enabled = true`, NEVER skip Step 4.5 — automated review is the primary gate**; manual APPROVE is only the fallback when reviewer is disabled OR when the user opts out via the escalation menu after iteration `maxIterations`
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

If `config.reviewer.enabled = true` (default), pass the draft matrix to **Step 4.5 — Review & Refine Loop** for automated coverage / mapping / template / state-machine / merge / diagram validation. Otherwise (or after the loop escalates and the user opts out), present the matrix to the user and wait for explicit `APPROVE` / `APPROVE ALL` / `APPROVE: <TC-IDs>` before proceeding to Step 5.

---

### Step 4.5 — Review & Refine Loop

**Runs when:** `config.reviewer.enabled = true` (default `true` if the field is missing). When `false`, skip directly to Step 5 after manual `APPROVE`.

**Purpose:** An automated test-case-reviewer subagent — running in a fresh context with no prior commitment to the draft — validates the matrix against the source SRS / images / state diagrams / step template, and loops with the generator (this skill) until either the reviewer is satisfied or the user accepts the remaining gaps.

**Algorithm:**

```
iter = 1
prev_feedback = null
loop:
    result = dispatch_reviewer_agent(
        source_type, source_content, image_paths,
        template_issue_key = config.templates.testStepTemplateKey,
        draft_matrix = current_matrix,
        iteration = iter,
        previous_feedback = prev_feedback
    )
    print "Reviewer iter <iter>: verdict=<result.verdict>, <#crit>/<#high>/<#med>/<#low> issues, <#gaps> gaps, <#merges> merges"
    if result.verdict == "PASS":
        break  # → proceed to Step 5
    if iter >= (config.reviewer.maxIterations ?? 3):
        escalate_to_user(result)  # see "Escalation menu" below — user decides
        break
    current_matrix = refine_matrix(current_matrix, result)  # see "Refinement strategy" below
    prev_feedback = result.issues
    iter += 1
```

**Reviewer dispatch:** Spawn one `general-purpose` agent (same agent-type as Step 8.2's parallel creators), foreground (Step 5 blocks on its result). Pass the inputs documented in the **Reviewer Agent Contract** section below. The agent's response is parsed as JSON conforming to that contract — if the response is not parseable JSON, retry the dispatch once with a stricter "return JSON only — no prose" instruction; on second failure, escalate to the user as if `iter == maxIterations`.

**Template gracefully optional:** If `config.templates.testStepTemplateKey` is unset, empty, or still a `<...>` placeholder, dispatch the reviewer with `template_issue_key = null` and instruct it to skip the **Template** review category (enforce only the other five: Coverage, Mapping, StateMachine, MergeOpportunity, DiagramCoverage). Note this in the iteration summary so the user knows step-shape was not checked.

**Refinement strategy** (`refine_matrix` is implemented inline by this skill — NOT a subagent — since the matrix lives in the current conversation):

| Reviewer issue category | Skill response (only if severity ≥ `config.reviewer.severityThreshold`) |
|------------------------|--------------------------------------------------------------------------|
| `Coverage` | Generate a new TC covering each missing requirement ID from `coverage_gaps[]` |
| `StateMachine` | Generate a new TC for each missing transition |
| `Mapping` | Fix the named TC's `requirement_ids` array to match what its steps actually exercise |
| `MergeOpportunity` | Merge tests per `merge_suggestions[]`: keep `merge_into`'s TC ID; absorb steps + `requirement_ids` from the named TCs in `absorb[]`; remove the absorbed TCs |
| `Template` | Rewrite the offending step's `action` / `data` / `expected_result` per the reviewer's `suggested_fix` |
| `DiagramCoverage` | Extend or add a TC referencing the missed visual element |
| Issues below `severityThreshold` | Note in the iteration summary; do NOT trigger refinement |

After each refinement, re-number TC IDs to remain dense (TC-001, TC-002…) and preserve `requirement_ids` traceability.

**Escalation menu (at `iter ≥ maxIterations` OR if reviewer JSON is unparseable twice):**

```
Reviewer did not converge after <N> iterations.

Remaining issues (severity ≥ <threshold>):
  [grouped by category, each with TC ID + description]

Coverage gaps still open: <R-IDs>
Merge suggestions not applied: <list>

Options:
  1. Accept all gaps  — proceed to Step 5 with the current matrix
  2. Accept specific  — e.g. "accept: TC-003, R7"  (only those issues skipped; others still loop)
  3. Force iterate    — re-run reviewer + refinement once more
  4. Abort            — exit workflow without creating any tests

Reply: 1, 2 (with list), 3, or 4
```

Options 1 and 2 proceed to Step 5. Option 3 sets `iter = iter` (no increment) and re-enters the loop body once. Option 4 cleanly exits with no Jira changes.

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
| 7 | `__xray_step_number` | `Step Number` | Every step row (1-indexed within test) |
| 8 | `customfield_10014` | `Epic Link` | First row of each test (Jira Epic key, e.g. `FIFAGEN-10400`) |

> ⚠️ **Tenant-portability note**: `customfield_10014` is the Epic Link field ID on the default reference tenant. If your Jira tenant uses a different ID (check `config.json` → `customFields.epicLink`), update column.index 8's `jira.field.id` in `importConfiguration.json` accordingly.

**Format rules** (from `importConfiguration.json`):
- Delimiter `,`  •  Encoding UTF-8  •  Quote `"`  •  Escape `"` as `""`
- Quote any field containing `,`, `"`, `\n`, or `;`
- Multi-value list delimiter inside a field: `;` (used for `requirement_ids`, `tags`)

**Row layout — row-per-step, grouped by Test ID:**

A test with N steps emits N rows sharing the same Test ID. The first row carries case-level fields (Summary / Description / Test Type); subsequent rows leave those blank. This matches how the Xray importer groups rows by `__xray_testId`.

Example (1 test, 2 steps):

```csv
Test ID,Summary,Description,Test Type,Step Data,Step Action,Step Result,Step Number,Epic Link
TC-001,"Basic Unload from Chuck","Objective: Verify wafer unload...

Preconditions:
- Chuck loaded
- Carrier slot empty

Requirements: R1;R3
Priority: High
Tags: Positive",Manual,"slot=1; wafer_id=W001","Click Unload button","Wafer moves to carrier slot 1",1,FIFAGEN-10400
TC-001,,,,"slot=1","Verify carrier light is green","Light is green and no alarms",2,
```

**Field construction:**

| Column | Source |
|--------|--------|
| `Test ID` | `test_case.id` |
| `Summary` | `test_case.summary` |
| `Description` | `Objective: <objective>\n\nPreconditions:\n- <p>\n\nRequirements: <ids joined ";">\nPriority: <p>\nTags: <tags joined ";">` |
| `Test Type` | `config.defaults.testType` |
| `Step Data` | `step.data` (use literal "no data" if step has no meaningful data; never use Unicode em-dash — cp1252 mojibake) |
| `Step Action` | `step.action` |
| `Step Result` | `step.expected_result` |
| `Step Number` | `step_index + 1` (1-indexed within test; Xray uses this for ordering and step-level display in Jira test issues) |
| `Epic Link` | `EPIC_KEY` on first row of each test, empty on subsequent step rows. Maps to `customfield_10014` so Xray auto-links the created Test under the Epic — no manual Jira UI click needed post-import. |

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

## Reviewer Agent Contract

Detailed I/O specification for the Step 4.5 reviewer subagent.

### Inputs (assembled by this skill before dispatch)

| Section | Content | Notes |
|---------|---------|-------|
| Role | "You are a test-case reviewer running in a fresh context with no prior commitment to the draft. Re-extract requirements independently from the source materials below — do NOT trust the draft matrix's interpretation." | Pinning fresh-context discipline is critical |
| `source_type` | `jira` / `confluence` / `file` / `text` | |
| `source_content` | Inline verbatim if < 8 KB; otherwise pass the path/key and instruct the agent to re-fetch via Read / `mcp__atlassian__getJiraIssue` / `mcp__atlassian__getConfluencePage` | Token budget |
| `image_paths` | Absolute paths to `.png` / `.jpg` / `.drawio` referenced in source; agent uses Read with vision | Raw — no preprocessing |
| `template_issue_key` | `config.templates.testStepTemplateKey` or `null` | If null, agent skips the Template category |
| `draft_matrix` | Full internal test-case schema array as JSON | |
| `iteration` | `1`, `2`, or `3` | |
| `previous_feedback` | (iter > 1) prior `issues[]` array | Agent verifies prior issues were addressed |
| Six review jobs | Bulleted checklist (see below) | |
| Severity rubric | Critical / High / Medium / Low with examples (see below) | |
| Output instruction | "Return JSON only — no prose preamble or postamble. Conform to the schema below." + the schema | |

### Six Review Jobs

The reviewer must check each:

1. **Coverage** — Re-extract requirement IDs (R1, R2…) from source. Every R-ID must map to ≥1 TC's `requirement_ids` array. Report missing R-IDs in `coverage_gaps[]` and emit a `Coverage` issue.
2. **Mapping** — For each TC, the steps must actually exercise the requirements listed in `requirement_ids`. Flag: requirements claimed but not tested, or steps testing un-listed requirements.
3. **StateMachine** — If source contains a state machine (text or diagram), every transition must have ≥1 covering TC. Report missing transitions as `category: "StateMachine"` issues.
4. **MergeOpportunity** — Two TCs with ≥80% step overlap, or where one's data set is a subset of the other's, are merge candidates. Emit `merge_suggestions[]` entries.
5. **Template** (skip if `template_issue_key == null`) — Fetch the template Xray test via `mcp__atlassian__getJiraIssue` + Xray Cloud `GET /api/v2/test/<KEY>/steps`. Derive shape rules (verb-first actions; measurable expected results — no "works correctly"; data field semantics). Flag steps that violate them.
6. **DiagramCoverage** — For each visual element / state / transition / box in attached diagrams, verify some TC references it. Flag uncited elements.

### Severity Rubric

| Severity | Examples |
|----------|----------|
| Critical | Missing requirement coverage; safety/compliance miss; broken state transition with no covering test |
| High | Vague expected results ("works correctly", "is correct"); mapping error; missing edge case explicitly listed in source |
| Medium | Merge opportunity; minor template-shape deviation; redundant test |
| Low | Stylistic phrasing; non-essential ordering |

### Output JSON Schema

```json
{
  "verdict": "PASS" | "REVISE",
  "iteration": 1,
  "summary": "<one-line human summary>",
  "issues": [
    {
      "category": "Coverage" | "Mapping" | "StateMachine" | "MergeOpportunity" | "Template" | "DiagramCoverage",
      "severity": "Critical" | "High" | "Medium" | "Low",
      "test_id": "TC-001" | null,
      "requirement_ids": ["R1", "R5"],
      "description": "<what's wrong>",
      "suggested_fix": "<concrete edit>"
    }
  ],
  "coverage_gaps": ["R7", "R9"],
  "merge_suggestions": [
    {"merge_into": "TC-002", "absorb": ["TC-005"], "reason": "<why>"}
  ]
}
```

**Verdict logic for the reviewer:** Return `PASS` only if NO issue has severity ≥ `config.reviewer.severityThreshold` (default `High`) AND `coverage_gaps[]` is empty. Otherwise `REVISE`.

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

### Example 5 — Reviewer loop converges (Step 4.5)
```
/xray-tests FIFAGEN-2872
→ matrix drafted at Step 4 (8 tests)
→ Step 4.5 iter 1: reviewer fetches template (FIFAGEN-99999), finds 2 coverage gaps
  (R5, R7), 1 mapping issue on TC-003, 1 merge opportunity (TC-006↔TC-008)
  verdict=REVISE
→ generator refines: adds TC-009 for R5+R7, fixes TC-003 requirement_ids,
  merges TC-008 into TC-006
→ Step 4.5 iter 2: reviewer PASS — no issues at severity ≥ High, no coverage gaps
→ Step 5: user picks mode "1" (CSV only)
→ CSV written; 8 tests (1 added, 1 merged in)
```

### Example 6 — Reviewer escalates after 3 iterations
```
/xray-tests ./reqs.md
→ matrix drafted (5 tests)
→ Step 4.5 iter 1: REVISE — StateMachine issue: "error→idle transition missing"
→ generator adds TC-006 for error→idle
→ Step 4.5 iter 2: REVISE — same StateMachine issue persists; reviewer says
  TC-006's expected_result doesn't actually verify the transition fires
→ generator rewrites TC-006 step 3 expected_result
→ Step 4.5 iter 3: REVISE — same issue; reviewer claims source diagram shows
  a SECOND error→idle transition under a different precondition
→ Escalation menu shown. User replies "accept: state-machine-transition-2"
  (acknowledges the gap is intentional — second transition is documented
   elsewhere as out-of-scope for this epic)
→ Step 5: user picks mode "3" (Both)
```
