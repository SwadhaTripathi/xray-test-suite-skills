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
4. **Traceability gate** — generate traceability matrix (.xlsx), get user sign-off (Step 4.7)
5. **Mode pick** — user chooses: a) xray-mcp (default) / b) CSV import / c) playwright-mcp
6. **Output** — tests via xray-mcp, or CSV in `output/`, or Xray UI via Playwright

## Per-Test Wiring Checklist (every test created must satisfy ALL of these)

Regardless of which output mode was chosen, every test issue created during a run must end up with the following state. The skill MUST verify (or perform) each of these for every test before reporting success in Step 9:

1. **Test issue with steps in CSV** — test case generated with Action / Data / Expected Result rows, saved to `output/TestCases_<EPIC_KEY>_<TIMESTAMP>.csv` (Step 6).
2. **Imported via bulk importer + Playwright** — CSV uploaded through the Xray Test Case Importer UI driven by Playwright MCP (Step 7), OR equivalent API creation flow (Step 8) for the API_ONLY mode.
3. **Xray native test steps verified present** — after creation, the Test Details tab on each created Jira test must have populated steps (Step 8.3 verification — applies to both CSV-import path and API path).
4. **Test linked to its Epic (Epic Link / `customfield_10014`)** — set during CSV import via column 8, or via `editJiraIssue` post-creation in API mode (Step 8.1).
5. **Epic shows "is tested by" link to the test** — separate from Epic Link; created via `createIssueLink` with `inwardIssue=<TEST>, outwardIssue=<EPIC>` (Step 8.1.a — applies to both paths). Read the link back and confirm the test's `issuelinks` entry shows `outwardIssue=<EPIC>` (verified-correct direction; matches the 8.1.a body).
6. **"Reported by AI" = Yes** — `customfield_14374` set on every AI-generated test, in bulk after creation (Step 8.4 — applies to both paths). Makes AI-generated tests filterable via JQL `"Reported by AI" = Yes`.

These six items are NOT optional steps — they're the **completion contract**. Any test that ends a run with any of these missing should be reported in Step 9 as incomplete and offered for retry.

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
- **ALWAYS ask the user to pick output mode — `a) xray-mcp (default)`, `b) CSV import`, `c) playwright-mcp` — do not assume; default to xray-mcp**
- **ALWAYS derive CSV column order from `importConfiguration.json` — never hardcode**
- **EACH STEP CONTAINS EXACTLY ONE VERIFICATION POINT** — one observable assertion per step. Split compound checks (gRPC-state vs PLC-tag → two steps; a multi-signal snapshot → one step per signal; "consumed" AND "no error logged" → two steps). Enforced at generation (Step 4), by the reviewer (Job 10), and in every output mode.
- **ALWAYS produce the traceability matrix (.xlsx) and get explicit user review/sign-off BEFORE any step creation or import (Step 4.7)** — no `createTestWithSteps` / `addTestStep` / CSV import / Playwright upload runs until the traceability xlsx is approved
- **ALWAYS add Xray native test steps to the "Test Details" tab** (xray-mcp `createTestWithSteps`/`addTestStep`, or Playwright UI; never leave a created test step-less)
- **PAUSE for clarification when requirements are ambiguous — do not guess at safety-critical or business-critical behavior**
- **NEVER fabricate expected results when the SRS is silent on the recovery / failure / edge-case behavior**. Instead, write the expected result as the literal token `[OPEN FOR SPEC OWNER INPUT]` followed by the open question. This convention makes it greppable later and avoids the trap of inventing behavior that doesn't match what gets shipped. (Validated 2026-05-28 on 22 Map-family gap-fill tests where 12 of 22 SRS clauses required this treatment.)

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
3. Determine `xrayMethod` (how tests + native steps get written):
   - **`xray-mcp` MCP server available (`mcp__xray-mcp__*` tools) → `xrayMethod = "xray-mcp"` (DEFAULT, preferred).** Confirm with `mcp__xray-mcp__test_simple`.
   - Else `credentials.xrayCloud.clientId` and `clientSecret` both non-empty → `xrayMethod = "API"`
   - Else → `xrayMethod = "Playwright"`

   Note: on tenants where the Xray Cloud GraphQL key is read-blind (`getTests → total:0`), the PAT-based `xray-mcp` gateway is the only working step read/write path — prefer it.

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

**One verification per step (atomic steps) — REQUIRED:** author every step with exactly ONE observable verification in `expected_result`. Never bundle assertions in one step:
- a gRPC/state read AND a PLC-tag read → two steps
- a multi-signal snapshot ("Red BLINK, Green OFF, White ON") → one step per signal
- "event consumed" AND "no error logged" → two steps

When the target tool only appends (xray-mcp `addTestStep`), prefix each action with a stable `[NN]` index so intended order survives.

**Internal test case schema** (drives all output modes):

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
| `MergeOpportunity` | Merge tests per `merge_suggestions[]`: keep `merge_into`'s TC ID; absorb steps + `requirement_ids` from the named TCs in `absorb[]`; remove the absorbed TCs. **Compare INTENT (objective + `requirement_ids`), not only step text — TCs covering the same SRS Open Issue or scenario are merge candidates even with non-overlapping steps.** |
| `Template` | Rewrite the offending step's `action` / `data` / `expected_result` per the reviewer's `suggested_fix` |
| `DiagramCoverage` | Extend or add a TC referencing the missed visual element |
| `PriorityLadder` | Generate per-rule isolated-collision TCs for each missing rule; add one full-ladder top→down release TC per affected signal. For safety-critical signals (alarm-bearing, buzzer, emergency-stop equivalents) lift severity to Critical regardless of `severityThreshold` |
| `APIContract` | Generate a direct-call TC for each named method; if `oneof` / Result / Either pattern is referenced, add explicit success AND error wire-shape assertions; for documented parameter ranges, add boundary-value tests for `-1`, `max+1`, and one oversized value |
| `SpecCompletenessGap` | Generate a new characterization TC for each sub-check (a-j) that has no covering TC. When the SRS is silent on recovery / failure / decision (sub-checks a, c, d, g, j most commonly), set the expected_result to the literal token `[OPEN FOR SPEC OWNER INPUT]` followed by the specific open question — never invent behavior. For (a) cross-spec contradictions, the new TC must explicitly call out which existing test(s) it contradicts, so spec owner can reconcile. For (g) `Comment:` / `Need to add` annotations, the new TC's Description must quote the SRS annotation verbatim. |
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

### Step 4.7 — Traceability Matrix (.xlsx) + Review Gate (REQUIRED before any Jira write)

After the matrix is approved (Step 4.5 / manual APPROVE) and BEFORE any output mode runs, generate a **traceability matrix as an .xlsx** and get explicit user sign-off. No `createTestWithSteps` / `addTestStep` / CSV import / Playwright upload may run until the user approves this file.

1. Build `output/traceability_matrix_<EPIC_KEY>_<YYYYMMDD>.xlsx` (openpyxl) with:
   - **Summary** tab: total tests, distinct requirements, total atomic step rows.
   - **Test-to-Requirement** tab: TC ID | Jira Key (if known) | Pos/Neg | Priority | # Steps | Requirements Covered | Summary.
   - **Requirement-to-Test** tab: Requirement / spec-query | # Tests | Tests covering it.
2. Present the file path + a one-screen coverage summary; ask: `Review the traceability matrix — approve to proceed to creation/import? (yes / changes)`.
3. **WAIT.** On "changes", revise (loop back to Step 4 / 4.5) and regenerate. Only on explicit approval proceed to Step 5.

Rationale: step creation/import is effectively irreversible on append-only / import paths — catch coverage gaps in the xlsx, not in Jira.

---

### Step 5 — Output Mode Selection (REQUIRED)

After the traceability matrix is approved (Step 4.7), ask:

```
## How would you like to generate these test cases?

a) xray-mcp       — create tests + native steps directly via the xray-mcp gateway  [DEFAULT]
b) CSV import     — import-ready CSV in output/, then the Xray Test Case Importer
c) playwright-mcp — create / enter tests via Xray UI browser automation

Reply: a, b, or c   (default a)
```

Map the answer to `OUTPUT_MODE` ∈ `{XRAY_MCP, CSV_IMPORT, PLAYWRIGHT}`. Default to `XRAY_MCP` when the user says "go" / "default". Do not guess between b and c — re-ask if ambiguous.

**Routing:**

| Mode | Steps that run |
|------|----------------|
| XRAY_MCP (default) | 8 (xray-mcp pilot + serial creation) → 8.4 → 9 |
| CSV_IMPORT | 6 (generate CSV) → 7 (Playwright importer upload + 7.9 wiring) → 9 |
| PLAYWRIGHT | 8 (Method B: Xray UI step entry) → 8.4 → 9 |

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

#### 7.9 Post-import Wiring (REQUIRED, both CSV_ONLY and BOTH modes)

After the importer reports success and the new Jira keys are harvested, run these finalization steps so the CSV-import path produces tests in the same fully-wired state as the API path:

1. **Create "is tested by" links** — for each created test, perform the idempotent pre-check + POST from Step 8.1.a (the CSV importer does NOT create issue links — only the Epic Link customfield).
2. **Verify Xray native test steps** — for each created test, GET the Test Details tab (Playwright `browser_navigate` + `browser_snapshot`, or Xray Cloud API `GET /api/v2/test/<KEY>/steps`) and assert ≥1 step is present. If any test has zero steps, the CSV's `__xray_step_*` columns were either empty or mismapped — flag for retry.
3. **Bulk-tag "Reported by AI" = Yes** — run Step 8.4 against the full list of created Jira keys.

These steps are NOT optional: skipping any of them produces a half-wired test that violates the Per-Test Wiring Checklist at the top of this skill.

**Selector strategy (in order of preference):** text → role → data-testid → CSS → XPath. Take fresh snapshot after each major action. Iframes: Xray Test Case Importer runs in an iframe — use iframe refs from snapshots.

---

### Step 8 — Test Creation (when OUTPUT_MODE ∈ {XRAY_MCP, PLAYWRIGHT})

**Primary path = `xray-mcp` gateway** (mode `XRAY_MCP`, default). Mode `PLAYWRIGHT` runs the same flow but enters tests/steps via the Xray UI (Method B in 8.3).

**xray-mcp mechanics (learned constraints — obey them):**
- **New tests:** `mcp__xray-mcp__createTestWithSteps(projectKey, summary, steps[])` creates the test WITH all steps ordered in one call (no reordering needed). It does NOT set description/priority/fields — set those afterwards via Atlassian MCP. Multiple new-test `createTestWithSteps` calls MAY run in parallel.
- **Adding steps to an EXISTING test:** `mcp__xray-mcp__addTestStep` only — it **APPENDS to the end, one step per call**, and the gateway **rejects concurrency with HTTP 503**. Call it **strictly serially** (await each before the next); order is then preserved. Prefix each action with `[NN]` so order is self-evident/recoverable.
- **No delete/update/insert step tool exists.** To rewrite an existing test's steps, append a clearly-labelled delete-marker step + the new `[NN]` atomic steps; the user deletes the old block in the UI.
- The Xray Cloud GraphQL **API key may be read-blind on the tenant** (`getTests → total:0`); the PAT-based `xray-mcp` gateway is the working path. Verify with `mcp__xray-mcp__test_simple`.

#### 8.1 Pilot Test
Create ONE test via `mcp__xray-mcp__createTestWithSteps` (atomic steps from the approved matrix) to validate formatting before bulk creation. Then:
- Set fields via `mcp__atlassian__editJiraIssue`: `description` (Objective/Preconditions/Requirements/Priority/Tags), `priority {name}`, Epic Link `customfield_10014 = <EPIC_KEY>` (and `customfield_14374 = {value:"Yes"}` here or in bulk at Step 8.4).
- **Create "is tested by" issue link (Step 8.1.a) and READ IT BACK** — the test's `issuelinks` entry must show `outwardIssue = <EPIC_KEY>` (verified-correct direction).
- **Verify Issue Links table on Epic (Step 8.1.b).**

**Present pilot URL to user and WAIT for explicit approval before proceeding to 8.2.** In 8.2, create remaining NEW tests with `createTestWithSteps` (may batch in parallel); use serial `addTestStep` only when appending to pre-existing tests.

##### 8.1.a — Create "is tested by" Issue Link (post-Epic-Link, IDEMPOTENT)

The Epic Link custom field (`customfield_10014`) establishes hierarchy but does NOT populate the Epic's **Issue Links** panel. To make the Epic's Issue Links section display `is tested by <TEST_KEY>`, create a standard Jira issue link AFTER the Epic Link is set.

**⚠ Idempotency requirement (critical):** Jira's `POST /rest/api/3/issueLink` is NOT idempotent — calling it twice for the same (type, inwardIssue, outwardIssue) tuple creates TWO duplicate rows in the Issue Links panel. ALWAYS pre-check existing links before posting. The skip condition: a link with `type.name == linkTypeName` AND `inwardIssue.key == <TEST_KEY>` already exists on the Epic.

**Pre-check (once per Epic, cache the result for that run):**
```
existing = mcp__atlassian__getJiraIssue(cloudId, issueIdOrKey=<EPIC_KEY>, fields=["issuelinks"])
existingTestKeys = set of l.inwardIssue.key for l in existing.fields.issuelinks where l.type.name == config.linkTypes.testLinkName AND l.inwardIssue
```

**Then per test, only POST if not already present:**
```
if <TEST_KEY> not in existingTestKeys:
  mcp__atlassian__createIssueLink(
    cloudId,
    type: config.linkTypes.testLinkName  // default "Test" — see Issue Link Types Reference
    inwardIssue: <TEST_KEY>,              // active subject (named by outward label "tests")
    outwardIssue: <EPIC_KEY>              // passive object (named by inward label "is tested by")
  )
  status: "created"
else:
  status: "skipped-already-linked"
```

Report both counts in Step 9 summary: `created: N, skipped (already linked): M, failed: K`.

**Directionality** (Jira convention): `inwardIssue` is the issue whose role matches the link type's **outward** label; `outwardIssue` matches the **inward** label. For `Test` link type (`outward="tests"`, `inward="is tested by"`):
- The Test "tests" the Epic → Test = `inwardIssue`
- The Epic "is tested by" the Test → Epic = `outwardIssue`

Result on Epic page: "is tested by `<TEST_KEY>`" appears in the Issue Links panel.
Result on Test page: "tests `<EPIC_KEY>`" appears.

**API fallback when Atlassian MCP cannot see the issue** (some tenants/permissions block recent issues from the MCP — see `xray-cloud-api-access` memory pattern): use Playwright with in-browser `fetch()` (see `corporate-tls-workaround` memory for the validated pattern). The pre-check + create pattern is the SAME — just run both fetches inside `mcp__plugin_playwright_playwright__browser_evaluate`. The idempotency rule still applies: GET `issuelinks` first, build the existing-keys set, then POST only for missing pairs.

Validated 2026-05-22 on FIFAGEN tenant: pre-check via `GET /rest/api/3/issue/<EPIC>?fields=issuelinks` (session-cookie auth), filter on `type.name == "Test" && inwardIssue`, build a `Set<TEST_KEY>`, then `POST /rest/api/3/issueLink` only for tests not in the set. Catches both same-batch retries and cross-batch reruns.

##### 8.1.b — Verify Issue Links Table on Epic

After the link is created (whether via API or Playwright), confirm it appears in the Epic's **Issue Links** section. Two verification paths:

**Path A — API** (when MCP visibility allows):
```
mcp__atlassian__getJiraIssue(cloudId, issueIdOrKey=<EPIC_KEY>, fields=["issuelinks"])
```
Assert: at least one entry in `fields.issuelinks[]` where `type.inward == "is tested by"` AND `inwardIssue.key == <TEST_KEY>`.

**Path B — Playwright** (when API can't see the Epic):
- `mcp__plugin_playwright_playwright__browser_navigate` → `https://<site>/browse/<EPIC_KEY>`
- `mcp__plugin_playwright_playwright__browser_snapshot` (capture full page)
- Search snapshot text for the pattern: `is tested by` followed by `<TEST_KEY>`
- Take a `mcp__plugin_playwright_playwright__browser_take_screenshot` for evidence (filename pattern: `verify_link_<EPIC_KEY>_<TEST_KEY>.png`)

Record the verification outcome (`linked: true/false`) on the test's result record so Step 9's summary can display it as a new column.

#### 8.2 Parallel Creation (after pilot approved)
For each remaining test case, spawn a `general-purpose` agent with `run_in_background: true`. All agents in a single message → true parallel execution.

**Batching:** Default 10 agents per batch. Wait for each batch to complete before spawning the next.

**Per-agent prompt template** must include:
- Test case details (id, summary, objective, steps, priority, requirements)
- `OUTPUT_MODE`, `cloudId`, `EPIC_KEY`, `loginEmail`
- `xrayMethod` ("API" or "Playwright") so the agent knows how to add native steps
- Custom field IDs from config
- **`linkTypeName`** from `config.linkTypes.testLinkName` (default `"Test"`) for the "is tested by" link creation in Step 8.1.a (parallel agents perform 8.1.a per test, but defer 8.1.b verification to the orchestrator in Step 9)
- Instructions to return JSON result: `{status, testCaseId, jiraKey, url, xrayStepsAdded, isTestedByLinkCreated, error}`

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

#### 8.4 Bulk-tag "Reported by AI" = Yes (orchestrator step, both paths)

**Purpose:** Tag every created test with the AI-generation marker so they're filterable in Jira (`"Reported by AI" = Yes`) for audit and traceability. Required by the FIFAGEN tenant convention; configurable per tenant via `config.fields.reportedByAi`.

**When this runs:**
- After Step 7 (Playwright CSV import) — for CSV_ONLY and BOTH modes, run this once the importer success page shows the created Jira keys.
- After Step 8.2 (parallel API creation) — for API_ONLY and BOTH modes, run this once all parallel agents have returned and the orchestrator has the full key list.

**Field details (FIFAGEN tenant default):**

| Property | Value | Override |
|---|---|---|
| ID | `customfield_14374` | `config.fields.reportedByAi.id` |
| Name | `Reported by AI` | `config.fields.reportedByAi.name` |
| Schema | `option` | — |
| Payload | `{value: "Yes"}` | `config.fields.reportedByAi.value` |

**Implementation** — use Playwright `browser_evaluate` with one batched fetch loop (validated 2026-05-28 on 85 tests across 4 epics, 100% success):

```js
async () => {
  const keys = [/* every Jira test key created in this run */];
  const batchSize = 15;
  let ok = 0, failed = [];
  for (let i = 0; i < keys.length; i += batchSize) {
    const batch = keys.slice(i, i + batchSize);
    const results = await Promise.all(batch.map(async k => {
      const r = await fetch('/rest/api/3/issue/' + k, {
        method: 'PUT',
        headers: {'Content-Type':'application/json', 'X-Atlassian-Token':'no-check'},
        credentials: 'include',
        body: JSON.stringify({ fields: { customfield_14374: { value: 'Yes' } } })
      });
      return { k, ok: r.ok, status: r.status };
    }));
    ok += results.filter(r => r.ok).length;
    failed.push(...results.filter(r => !r.ok));
  }
  return { ok, failed_count: failed.length, failed_keys: failed.map(f => f.k) };
}
```

> ⚠ **Editmeta gotcha**: on the FIFAGEN tenant, `customfield_14374` is NOT exposed via `GET /rest/api/3/issue/<KEY>/editmeta` for the Test issue type (it's not on the Test edit screen scheme). The direct PUT works anyway because the field IS in the contextual scope. Don't use editmeta as a gatekeeper — try the PUT and check the response. A 204 response means it took.

**Verification (REQUIRED — double-check via two independent paths):**

1. **Per-issue sample GET** — pull `customfield_14374` from 3-5 keys spanning all epics; assert `value: "Yes"`.
2. **JQL sweep** — `issue in (<every key>) AND "Reported by AI" = Yes` — must return exactly `keys.length` issues. If lower, list which keys are missing and retry.

Both checks must pass before declaring the bulk-tag complete. Either alone has a blind spot (sample misses non-sampled failures; JQL sweep doesn't tell you WHICH key failed).

**On failure:** If any tests didn't take the tag, retry those keys once (network blips are the common cause); if still failing, list them in Step 9 with the HTTP status returned. Don't silently drop the failures.

See `feedback-reported-by-ai-field-tagging` memory for the validated pattern and reusable JQL filter.

#### 8.5 Error Isolation
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
"is tested by" link rate: <Y>/<N>  (counted after Step 8.1.b verification on Epic Issue Links table)
"Reported by AI" = Yes tag rate: <Z>/<N>  (counted after Step 8.4 JQL verification sweep)

| # | TC ID | Jira Key | Xray Steps | is tested by | Reported by AI | Status | Link |
| - | ----- | -------- | ---------- | ------------ | -------------- | ------ | ---- |
...

Failed cases (if any):
| TC ID | Error | Suggested action |

Failed link creations (if any):
| TC ID | Test Key | Reason | Suggested action |

Failed "Reported by AI" tag patches (if any):
| Test Key | HTTP status | Suggested action |
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

### Pre-pass: SRS Annotation Catalog

**Before running the 9 review jobs**, the reviewer must scan the source materials and build a catalog of:

- **Struck-through / obsolete text** — paragraphs, requirements, or sentences with strikethrough formatting (`~~...~~` in markdown, `<s>` in HTML, struck-through font in Word/PDF). Treat as obsolete; any TC that tests struck-through behavior is a candidate for retirement.
- **Spec-author annotations** — every occurrence of `Comment:`, `Note:`, `Need to add`, `Should we`, `Define`, `TBD`, `Open Question`, `🔴 Missing`, or similar self-flagged-gap markers. Each annotation is a SELF-IDENTIFIED gap by the spec author.
- **Cross-spec references** — text like "Part of XYZ spec", "See also ABC SRS", "tracked in <other doc>". Each cross-ref means the reviewer must check (a) whether the referenced spec actually covers what was deferred, and (b) whether the matrix tests the interaction at the boundary.
- **"Example shows but doesn't require" sentinel values** — values appearing in printed-log examples or sample tables that aren't called out as requirements (e.g., `unknown` slot tokens in a printed map example). These are usually valid runtime states that real tests miss.

This catalog feeds the new **SpecCompletenessGap** review job (#9) below.

### Twelve Review Jobs

The reviewer must check each. **Paraphrase/abbreviation tolerance applies to all jobs**: when checking whether a TC covers a documented identifier (PLC tag, enum value, requirement ID, API method, rule), accept abbreviated/full-form/synonymous variations as equivalent unless the verification is explicitly about verbatim string matching. Example: `WATCH_DOG_ALARM` and `BRV_TOWER_WATCH_DOG_ALARM` refer to the same tag — do NOT flag the abbreviated form as missing coverage.

1. **Coverage** — Re-extract identifiers from source independently. The reviewer must enumerate ALL of:
   - **Requirement IDs** (R1, R2…, UC-001…) — every R-ID must map to ≥1 TC's `requirement_ids` array
   - **Enum values** in category/parameter tables — including values that have NO matching rule (which should default to OFF/inactive); each enum value (including the no-rule ones) needs a reachability TC
   - **Shipped default configuration values** — when SRS documents a default (e.g., `watchdog.timeout default = 9999 = disabled`), the default-config behavior must have its OWN dedicated TC (testing only non-default configurations is a category-error; the default ships to every customer)
   - **PLC / device / hardware tag entries** with documented values or semantics (including default values and special command values like `OTHER = No change`) — each documented tag must have an assertion in at least one TC
   - **Open Issues / Known Issues / Unresolved sections** of the SRS — each Open Issue must have a TC pinning current behavior OR an explicit out-of-scope traceability note in the matrix
   - **Non-Functional Requirements** AND **explicit "missing tests" / "recommended test enhancements" / "🔴 Missing" sections of the SRS** — these are quite literally the SRS author telling you what's missing; every entry must have ≥1 TC
   
   Severity: Critical for shipped-default-config misses and items the SRS explicitly flags as missing; High for enum values, Open Issues, NFRs without coverage; Medium for tag-level documentation assertions.

2. **Mapping** — For each TC, the steps must actually exercise the requirements listed in `requirement_ids`. Flag: requirements claimed but not tested, or steps testing un-listed requirements. **Apply paraphrase tolerance**: a step that asserts `WATCH_DOG_ALARM=0` covers a requirement that references `BRV_TOWER_WATCH_DOG_ALARM`.

3. **StateMachine** — If source contains a state machine (text or diagram), every transition must have ≥1 covering TC. Report missing transitions as `category: "StateMachine"` issues.

4. **PriorityLadder** (NEW) — For each multi-rule priority ladder in the SRS (e.g., Red has 5 rules; Buzzer has 3; Yellow has 7; Green has 5):
   - Every individual rule must have ≥1 TC asserting it isolated **with a conflicting event present** (the rule fires while a different rule could also match)
   - At least one full-ladder TC must exercise the complete top→down release sequence (P1 wins → clear → P2 wins → clear → ... → Pn → OFF)
   - For ladders ≥3 rules, every adjacent-priority collision (Pn vs Pn+1) must have either a dedicated TC or be exercised in a multi-event TC
   
   Severity: High by default, Critical for safety-critical signals (alarm-bearing, buzzer, emergency-stop equivalents).

5. **APIContract** (NEW) — When the SRS lists explicit API methods (gRPC, REST, RPC, message bus, etc.):
   - Every method must have ≥1 **direct-call** TC. End-to-end coverage is necessary but not sufficient — a reviewer who only sees E2E will reject the suite as missing unit-level method coverage
   - If methods use `oneof` / `Result` / `Either` / discriminated-union error contracts, both success AND error wire shapes must be asserted
   - For documented parameter ranges (e.g., `signal_id 0-4`), boundary values (`-1`, `max+1`, `100`, oversized) must be in a TC
   
   Severity: Critical for any public method without direct-call coverage; High for missing error-path coverage and missing parameter-boundary tests.

6. **MergeOpportunity** (STRENGTHENED) — Two TCs are merge candidates when ANY of:
   - ≥80% step overlap
   - One's data set is a subset of the other's
   - **Both test the same SRS open-issue, requirement, or scenario described in their objectives — even with different step shape**. Compare INTENT and `requirement_ids`, not only step text. Example: TC-A "watchdog lifecycle including timeout<reset_interval validation" and TC-B "Open Issue #5: reset_interval > timeout misconfig" overlap at intent level despite different step phrasings.
   
   Emit `merge_suggestions[]` entries.

7. **Template** (skip if `template_issue_key == null`) — Fetch the template Xray test via `mcp__atlassian__getJiraIssue` + Xray Cloud `GET /api/v2/test/<KEY>/steps`. Derive shape rules (verb-first actions; measurable expected results — no "works correctly"; data field semantics). Flag steps that violate them.

8. **DiagramCoverage** — For each visual element / state / transition / box in attached diagrams, verify some TC references it. Flag uncited elements.

9. **SpecCompletenessGap** (NEW — validated 2026-05-28) — Validates the matrix against common production scenarios that SRSes routinely omit. The 8 prior jobs check completeness against what's WRITTEN; this job checks completeness against what production tools NEED but SRSes don't enumerate. For each of these 10 sub-checks, flag a missing TC if no existing TC addresses it AND the source does not explicitly mark it out of scope:

   a. **Cross-spec contradiction (Critical)** — If the SRS contains struck-through text (from the pre-pass catalog) and any TC tests that struck-through behavior, flag for spec-owner reconciliation. If multiple linked SRSes contradict each other, the matrix must contain at least one characterization TC that exposes the contradiction.

   b. **Multi-instance behavior (High)** — When SRS describes a singular resource ("the device", "the load port", "the pipe", "the lane") but the production system has N instances, the matrix must include at least one multi-instance isolation TC asserting an operation on instance A doesn't mutate instance B's state. (Example from this session: 9 Powerup tests all assumed single Load Port; real tools have 2-4.)

   c. **Hardware-failure path (High)** — For each spec step that calls hardware (sensor, motor, robot, mapper, valve, network), the matrix must contain ≥1 characterization TC for "hardware returns failure / non-response / sensor unknown". When SRS is silent on recovery, mark expected result `[OPEN FOR SPEC OWNER INPUT]`.

   d. **Intermediate / partial-state recovery (High)** — For multi-step sequences (e.g., load = Clamp → Dock → Open → Map → Create), the matrix must include ≥1 TC for the partial-state case (shutdown after Clamp but before Dock). Power loss can leave hardware in these intermediate states. When SRS is silent, mark `[OPEN FOR SPEC OWNER INPUT]`.

   e. **Default-config persistence (High)** — Job 1's "shipped default configuration values" rule already requires a default-value TC; this sub-check additionally requires verifying the default persists across clean install AND clean reset AND power cycle.

   f. **Cross-session / cross-feature interaction (Medium)** — When two features share state (e.g., Diagnostics ↔ Production, EU ↔ Power-up, Multiple commands targeting the same resource), the matrix must include ≥1 TC asserting one feature's operations don't mutate the other's persisted state when transitioning between sessions.

   g. **Spec-author "Comment:" annotations (Critical)** — From the pre-pass catalog: every `Comment:` / `Need to add` / `Should we` / `Define` / `TBD` / `Open Question` annotation is a SELF-IDENTIFIED gap by the spec author. Every such annotation must have either a TC pinning current behavior with `[OPEN FOR SPEC OWNER INPUT]` markers, OR an explicit out-of-scope traceability note. This is the highest-leverage check: the spec author already told you it's missing. (Example: MoU SRS `Comment: Need to add a case when Cassette is removed during power down... Part of MAP During power up SRS` — but Powerup SRS Rev 3 didn't address it. Now covered by FIFAGEN-16207 and FIFAGEN-16208.)

   h. **Non-binary sensor/data states (Medium)** — From the pre-pass catalog of "Example shows but doesn't require" sentinel values: if SRS examples or error messages mention values like `unknown`, `unspecified`, `not applicable`, `<null>`, the matrix must include a TC exercising those values (not just binary True/False / present/absent cases). (Example: R003.5a printed-map example showed `unknown` tokens — but no test exercised mismatch with unknown values.)

   i. **Same-instance vs new-instance ambiguity (Medium)** — When SRS says "load a NEW cassette" / "send another request" / "open another session", check whether the matrix also covers "re-load the SAME instance". Usually implicitly the same behavior, but SRS rarely states so — ambiguity worth flagging.

   j. **Operator-interrupt scenarios (Low)** — Power-down during power-up, cancel during a pending operation, second command while first in flight, browser-close during a multi-step UI flow. SRS rarely covers; mark `[OPEN FOR SPEC OWNER INPUT]` if recovery is undefined.

   **Output**: feed back into the regular `issues[]` array with `category: "SpecCompletenessGap"`. **Severity defaults**: Critical for (a) and (g); High for (b), (c), (d), (e); Medium for (f), (h), (i); Low for (j). Override per safety/business impact judgment.

10. **AtomicSteps** (NEW) — Every step must contain **exactly one verification point**. Flag any step whose `expected_result` bundles multiple independent assertions (e.g. a gRPC state read AND a PLC-tag value; a multi-signal snapshot like "Red BLINK, Green OFF, White ON"; "consumed AND no error logged"). `suggested_fix` = "split <TC-id> step <n> into one step per verification". Severity: High — a bundled step defeats one-verification-per-step traceability and per-step pass/fail.

11. **ConfigMatrix** (NEW) — When the SRS defines a configuration parameter that changes the *execution path* (not merely a numeric/threshold value), every behavioral TC that traverses that path must exist for **each** value of the parameter — **including the basic positive / happy-path cases**, not just edge cases.
   - Detect path-altering configs from SRS phrasing like *"For X device … / For Y device …"*, *"if Preference = A … else if = B …"*, *"in mode M1 the flow is … in mode M2 the flow is …"*. Real example: **Mapping Preference = `Mapping by Robot` | `Mapping by Load Port`** — Robot issues an explicit Map after door-open; Load-Port auto-maps *during* the door-open event (and must close-then-reopen if the door is already open). These are genuinely different step sequences, so one config tested ≠ both covered.
   - For each such parameter, build the value set and assert that every scenario (especially every Positive scenario) has a TC per value. A happy-path covered under only one configuration is a **High** gap, even if every requirement ID is otherwise "covered" — Coverage (Job 1) checks identifier reachability; ConfigMatrix checks *behavioral duplication across path-altering configs*.
   - Distinguish from a pure value enum (Job 1): ConfigMatrix fires only when the value **changes the steps/flow**, not when it merely changes an asserted value.
   
   Severity: High for a missing config-variant of any Positive/critical scenario; Medium for missing config-variant of a low-priority negative case. Emit one issue per (scenario, missing-config) pair; `suggested_fix` = "duplicate <TC-id> for <config value> with <device/mode>-specific step deltas".

12. **StateRealism** (NEW) — Reject TCs that exercise **physically unreachable states** or **impossible configurations**, and flag flows that don't return a resource to its required end-state. The reviewer must first reconstruct the entity lifecycle ordering from the SRS, then test every setup/precondition against it.
   - **Unreachable intermediate state** — derive the documented state order (e.g. carrier **load** order `Present → Placed → Clamped → Docked → Open`; **unload** is the strict reverse `Closed → UnDocked → UnClamped → Placed=false → Present=false`). A TC whose setup asserts a state that violates this order — e.g. *"Docked but NOT Clamped"* when Clamp precedes Dock — is **unreal** and must be flagged for **removal**, unless the SRS explicitly defines that partial/transitional state as reachable.
   - **Impossible / mutually-exclusive configuration** — options the SRS presents as alternatives (e.g. *"For Robot device … For Load Port device …"*) must not be combined in one TC (e.g. *both* mapping devices active simultaneously) unless the SRS states the combination is reachable. Flag such TCs for removal.
   - **Flow completeness / return-to-initial-state** — when the SRS says to restore a resource at end of flow (e.g. *"consider to close door after mapping"* for a cassette whose door started **closed**), the TC must include that restoring step and assert the final state. Missing-restore is a coverage defect, not a removal.
   - Cross-check against ConfigMatrix and StateMachine: an "unreal" mixed-config or impossible-transition TC should be reported here (remove), while a *legitimately missing* config-variant or transition belongs to ConfigMatrix / StateMachine (add).
   
   Severity: High for a TC asserting an unreachable state or impossible config (it misleads reviewers and wastes execution); Medium for a missing return-to-initial-state step. `suggested_fix` = "remove <TC-id>: state/config unreachable per SRS lifecycle <…>" OR "append restoring step to <TC-id>: <…>".

**Presentation conventions** (apply when emitting the matrix, not a blocking job): keep **Positive and Negative tests separable** (tag each TC `Positive`/`Negative` by intent — valid-condition behavior vs. error/exclusion/failure/anomaly/boundary-rejection — so the deliverable can be split into per-polarity tabs), and keep each **Test Summary concise** (short, scannable name; move full prose into the objective). Report only as `severity: "Low"` `category: "StateRealism"` notes if violated — do not block the loop.

### Severity Rubric

| Severity | Examples |
|----------|----------|
| Critical | Missing requirement coverage; safety/compliance miss; broken state transition with no covering test; **missing TC for any shipped default configuration value (the default ships to every customer)**; **missing direct-call coverage of any documented public API method**; **any item explicitly listed as "🔴 Missing" / "Missing Critical Tests" / "Required" / "Recommended Test Enhancements" in the SRS itself (the SRS author already told you it's missing — failing to enumerate this is the reviewer's most damning miss)**; **SpecCompletenessGap sub-checks (a) cross-spec contradiction / struck-through-text TC and (g) any `Comment:` / `Need to add` / `Should we` / `Define` / `TBD` annotation in the SRS without a covering TC — the spec author already self-identified the gap** |
| High | Vague expected results ("works correctly", "is correct"); mapping error; missing edge case explicitly listed in source; **missing rule in an N-rule priority ladder (every rule needs an isolated-collision TC)**; **missing enum value reachability test (including no-rule enum values that should default OFF)**; **missing direct-call test for an API method's error / oneof path**; **SRS Open Issue not addressed (no TC pinning current behavior AND no explicit out-of-scope flag)**; **NFR section without any covering TC**; **SpecCompletenessGap sub-checks (b) multi-instance behavior, (c) hardware-failure path, (d) intermediate / partial-state recovery, (e) default-config persistence — these are production-required even when SRS is silent** |
| Medium | Merge opportunity (especially intent-level overlap, not just step overlap); minor template-shape deviation; redundant test; **documented PLC / device / hardware tag default value without an assertion in any TC**; **minor enum-value verbatim / typo string-match deviation (when verbatim match was a stated requirement)**; **SpecCompletenessGap sub-checks (f) cross-session / cross-feature interaction, (h) non-binary sensor/data states, (i) same-instance vs new-instance ambiguity** |
| Low | Stylistic phrasing; non-essential ordering; **SpecCompletenessGap sub-check (j) operator-interrupt scenarios** |

### Output JSON Schema

```json
{
  "verdict": "PASS" | "REVISE",
  "iteration": 1,
  "summary": "<one-line human summary>",
  "issues": [
    {
      "category": "Coverage" | "Mapping" | "StateMachine" | "PriorityLadder" | "APIContract" | "MergeOpportunity" | "Template" | "DiagramCoverage" | "SpecCompletenessGap" | "AtomicSteps" | "ConfigMatrix" | "StateRealism",
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

## Issue Link Types Reference

Configurable via `config.linkTypes.testLinkName` (default: `"Test"`). Discover available types per tenant via `mcp__atlassian__getIssueLinkTypes`.

| Link Type Name | Inward Label | Outward Label | Use For |
|----------------|--------------|---------------|---------|
| `Test` (default) | `is tested by` | `tests` | Standard Jira test linking — Epic page shows "is tested by <TEST>" |
| `Epic-Test Link` | `Epic Tested By` | `Test for Epic` | Tenant-specific variant (some legacy projects) |

**API directionality reminder** (`mcp__atlassian__createIssueLink`):
- `inwardIssue` = the issue whose role is the **outward** label of the type (the active subject)
- `outwardIssue` = the issue whose role is the **inward** label of the type (the passive object)

So for `Test` type, to make Epic display "is tested by Test":
```
inwardIssue = <TEST_KEY>      # Test "tests" the Epic
outwardIssue = <EPIC_KEY>     # Epic "is tested by" the Test
```

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
