---
name: copy-field-sync
description: "Automate Data Cloud Copy Field sync for Contact object using Playwright browser automation. Syncs Average Order Value Lifetime, Average Purchase Value, Customer Lifespan, Customer Lifetime Value, and Unified Contact Profile Information. Uses MCP Playwright tools only. Use when user wants to sync copy fields, start field sync, or configure Data Cloud copy fields."
---

# copy-field-sync

## Purpose

Automate Data Cloud Copy Field synchronization for the Contact object using Playwright browser automation.

The skill **only initiates** sync for each of the 5 Contact Copy Fields. It does NOT check Sync History, does NOT poll status, and does NOT wait for completion. The actual data sync runs in the background on Salesforce after the dialog "Start Sync" button is clicked — that is fire-and-forget from this skill's perspective.

**Target wall-clock: under 2 minutes for all 5 fields.** If the skill takes longer than ~5 min, something is wrong (selector mismatch, slow page load, etc.) — fix the root cause, don't add waits.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT generate Playwright scripts (.js, .mjs, .ts files)
- ❌ Do NOT check Sync History after starting a sync
- ❌ Do NOT poll for "Complete" / "Success" status
- ❌ Do NOT click on the field row twice or take snapshots between fields
- ✅ Use MCP Playwright tools ONLY via direct tool calls
- ✅ Execute syncs sequentially - one field at a time
- ✅ Pattern per field: click field name in list → click Start Sync → click Start Sync in dialog → return to list. Done.

This skill syncs the following Data Cloud Copy Fields on Contact object:
1. Average Order Value Lifetime (default)
2. Average Purchase Value (default)
3. Customer Lifespan (default)
4. Customer Lifetime Value (default)
5. Unified Contact Profile Information

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

- Salesforce CLI authenticated with target org (run via `sf org login web -a <org_alias>` if not already)
- User has System Administrator profile or equivalent permissions
- Data Cloud must be enabled and provisioned
- The 5 Contact Copy Fields above exist (created by the data kit deploy)
- MCP Playwright tools available (load via ToolSearch in Step 0)
- For uninterrupted execution, `.claude/settings.json` should pre-approve `mcp__plugin_playwright_playwright__*` and `bash:sf *`.

---

## Workflow

```
Step 0: Load Playwright tool schemas
   ↓
Step 1: Get org credentials (instanceUrl + accessToken)
   ↓
Step 2: Launch browser via frontdoor (auto-login)
   ↓
Step 3: Navigate to Copy Fields list page
   ↓
Step 4: For each of 5 fields — click row → click Start Sync → click Start Sync in dialog → back to list
   ↓
Step 5: Close browser & generate report
```

**Total tool calls per field: 4** (1 click on field row, 1 click on Start Sync, 1 click on dialog Start Sync, 1 navigate back to list). Five fields × 4 calls = 20 Playwright calls + setup. Should complete in <2 min.

---

### Step 0 — Load Playwright tools

```
ToolSearch(
  query: "select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_click,mcp__plugin_playwright_playwright__browser_snapshot,mcp__plugin_playwright_playwright__browser_close",
  max_results: 4
)
```

Snapshot is loaded for one-time selector verification only (not for status polling).

---

### Step 1 — Get org credentials

```bash
sf org display --target-org <org_alias> --json
```

Extract:
- `result.instanceUrl` — base URL for navigation
- `result.accessToken` — used for `frontdoor.jsp?sid=` auto-login

If the command fails ("No org with alias"), STOP and report. Tell the user to run `sf org login web -a <org_alias>`.

---

### Step 2 — Launch browser and auto-login

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}"
)
```

This drops the user into Lightning, already logged in. No password, no MFA, no screenshot needed.

If the page redirects to a login form, the CLI session expired — STOP and ask the user to run `sf org login web -a <org_alias>`.

---

### Step 3 — Navigate to Copy Fields list

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/setup/ObjectManager/Contact/Enrichment-CopyFields/view"
)
```

The list page shows all 5 Copy Fields. Their row text is the field label (e.g. `Average Order Value Lifetime`).

**One-time selector verification (only on first field — Step 4.1):** if the very first `click(target: "text=Average Order Value Lifetime")` fails, take ONE snapshot, find the actual link selector, and use that pattern for all 5 fields. Do NOT re-snapshot between fields.

---

### Step 4 — Sync all 5 fields (sequential, fire-and-forget)

Repeat the same 4-call pattern for each field. **No waits between actions** — Playwright's auto-wait handles element appearance.

#### 4.1 — Average Order Value Lifetime (default)

```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Average Order Value Lifetime",
  element: "Field row: Average Order Value Lifetime"
)
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Start Sync')",
  element: "Start Sync button on field detail"
)
mcp__plugin_playwright_playwright__browser_click(
  target: "div[role='dialog'] button:has-text('Start Sync')",
  element: "Confirm Start Sync in dialog"
)
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/setup/ObjectManager/Contact/Enrichment-CopyFields/view"
)
```

Print: `✅ Average Order Value Lifetime — sync started`

#### 4.2 — Average Purchase Value (default)

Same 4 calls, swap `text=Average Purchase Value`. Print: `✅ Average Purchase Value — sync started`

#### 4.3 — Customer Lifespan (default)

Same 4 calls, swap `text=Customer Lifespan`. Print: `✅ Customer Lifespan — sync started`

#### 4.4 — Customer Lifetime Value (default)

Same 4 calls, swap `text=Customer Lifetime Value`. Print: `✅ Customer Lifetime Value — sync started`

#### 4.5 — Unified Contact Profile Information

Same 4 calls, swap `text=Unified Contact Profile Information`. Print: `✅ Unified Contact Profile Information — sync started`. After this last field, **skip the "navigate back to list" call** — proceed directly to Step 5 (close browser).

---

### Step 5 — Close browser and report

```
mcp__plugin_playwright_playwright__browser_close()
```

Report:

```text
✅ Copy Field Sync Initiated (5 of 5 fields)

Org: <org_alias>
Instance: {instanceUrl}

Sync started for:
1. ✅ Average Order Value Lifetime (default)
2. ✅ Average Purchase Value (default)
3. ✅ Customer Lifespan (default)
4. ✅ Customer Lifetime Value (default)
5. ✅ Unified Contact Profile Information

Note: This skill only INITIATES the syncs. Salesforce processes them in the
background; verification (if desired) can be done later in Setup → Object
Manager → Contact → Data Cloud Copy Field → Sync History. Downstream skills
do not depend on the sync completing.
```

This is the last mandatory installer step. Auto-proceed to the optional `/refresh-data-streams` only if the user explicitly opted in; otherwise generate the final installation report.

---

## Failure handling

If a click fails (selector not found, dialog button missing) on **any field**, that single field is skipped — the skill continues with the remaining fields. At the end, the report lists which fields started and which were skipped, plus the failing selector for the user to fix.

```text
⚠️ Copy Field Sync — partial completion (3 of 5 fields started)

Started:
  ✅ Average Order Value Lifetime
  ✅ Average Purchase Value
  ✅ Customer Lifespan

Skipped (selector failure):
  ❌ Customer Lifetime Value — selector "text=Customer Lifetime Value" not found
  ❌ Unified Contact Profile Information — dialog Start Sync button not present

Suggested fix: open Setup → Object Manager → Contact → Data Cloud Copy Field
manually, verify the field labels match exactly, and re-run /copy-field-sync.
```

Do NOT auto-retry within the skill — the failing selector won't fix itself, and retrying just doubles the wall-clock for no reason.

---

## What this skill INTENTIONALLY does NOT do

- ❌ **Does not check Sync History** — this was the original 30-minute time waster. Salesforce processes the sync in the background; the skill doesn't need to babysit it.
- ❌ **Does not poll for "Complete" / "Success" status** — same reason.
- ❌ **Does not screenshot** — screenshots add ~1s each and provide no information the agent uses.
- ❌ **Does not `wait_for(time: N)` between actions** — Playwright auto-waits for elements to be actionable. Explicit time-based waits are anti-patterns.
- ❌ **Does not navigate back to the list after the LAST field** — the next call is `browser_close`; the navigate would just be wasted.

Fire-and-forget is safe here because nothing downstream depends on the copy-field syncs being complete: the upstream `/refresh-data-cloud-components` already ran against IR/CIs/Segments (not the copy fields), and the Customer Affinities related list was created earlier in the chain at Step 8 (`/data-cloud-related-list`). Salesforce processes the syncs in the background after this skill exits.

---

## Important Rules

- 🚨 **ALWAYS run on all 5 fields** — even if one fails, continue
- 🚨 **NEVER check Sync History** — this is the rule that gets the wall-clock under 2 min
- 🚨 **NEVER add `wait_for(time: N)`** between Playwright actions — auto-wait handles it
- 🚨 **NEVER take screenshots on success paths** — only on failure for debugging
- ✅ Use direct URL navigation (no Object Manager search clicks)
- ✅ Sync fields in series (sequential), not parallel
- ✅ Auto-proceed to next installer skill on success — no user prompts

---

## Cleanup temp artifacts (MANDATORY before next skill)

```bash
cmd.exe //c "rmdir /S /Q .playwright-mcp" 2>/dev/null || rm -rf .playwright-mcp
```

Verify:

```bash
ls -d .playwright-mcp 2>&1 | grep -v "cannot access"
```

**Failure handling rule:** if some fields failed (selector mismatches, dialog stuck), do NOT clean up — leave `.playwright-mcp/` traces so the user can inspect them. Cleanup only fires on full success (5 of 5 syncs initiated).
