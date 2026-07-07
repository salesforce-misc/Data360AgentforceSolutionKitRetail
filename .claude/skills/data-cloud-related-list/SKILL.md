---
name: data-cloud-related-list
description: "Automate creation of Data Cloud Related Lists on Contact object using Playwright browser automation. Creates Customer Affinities related list with proper configuration, then triggers a Full Refresh on Account_Home and Contact_Home Data Streams in the same browser session (fire-and-forget — no SOQL polling). Uses MCP Playwright tools only. Use when user wants to create Data Cloud related list, add related list to Contact, or configure Data Cloud relationships."
---

# data-cloud-related-list

## Purpose

Automate the creation of Data Cloud Related Lists on the Contact object using Playwright browser automation.

**✅ BROWSER AUTOMATION SOLUTION**

This skill automates the process of creating a Data Cloud Related List for Customer Affinities on the Contact object. It navigates through Setup → Object Manager → Contact → Data Cloud Related List and creates the related list with the specified configuration.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT generate Playwright scripts (.js, .mjs, .ts files)
- ✅ Use MCP Playwright browser automation tools ONLY via direct tool calls
- ✅ All automation through `mcp__plugin_playwright_playwright__*` tools
- ✅ **Execute steps sequentially** - complete one action before moving to next
- 📸 **Screenshot Policy**: ONLY take screenshots when errors occur. Save to `.playwright-mcp/error-[timestamp].png`. Do NOT take screenshots for successful steps

This skill creates the following Data Cloud Related List:
- **Data Cloud Object**: Customer Affinities
- **Related List Label**: Customer Affinities
- **Layouts**: Person Account Layout (checked), SDO - Person Account Layout (checked), Contact Layout (checked)
- **User Customizations**: Add to existing page customizations (checked)

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

Before running:

- Salesforce CLI authenticated with target org
- User has System Administrator profile or equivalent permissions
- Data Cloud must be enabled and provisioned
- Contact object must exist (standard object)
- Customer Affinities Data Cloud Object must exist
- MCP Playwright tools must be available (check deferred tools list)
- **IMPORTANT:** For fast, uninterrupted execution, configure auto-approval in `.claude/settings.json`:
  ```json
  {
    "permissions": {
      "allow": [
        "mcp__plugin_playwright_playwright__*",
        "bash:sf *"
      ]
    }
  }
  ```
  Without this, each Playwright action will prompt for user approval, slowing down the process.

---

## Workflow

**CRITICAL EXECUTION RULES:**

1. ✅ **Execute steps sequentially** - complete one action before moving to next
2. ✅ **Wait for page loads** - ensure elements are visible before clicking
3. ✅ **Use direct URL navigation** when possible for faster execution
4. ✅ **Take screenshots at key steps** for verification
5. ✅ **Close browser when done**

**Step Execution Order:**
```
Step 0: Load Playwright tools
   ↓
Step 1: Get org credentials
   ↓
Step 2: Launch browser and authenticate
   ↓
Step 3: Navigate directly to Contact Data Cloud Related List page
   ↓
Step 4: Click New button to create related list
   ↓
Step 5: Select Customer Affinities Data Cloud Object
   ↓
Step 6: Click Next (first time)
   ↓
Step 7: Keep default values and click Next (second time)
   ↓
Step 8: Configure related list settings
   ↓
Step 9: Click Next/Save to complete
   ↓
Step 9.5: Refresh Account_Home and Contact_Home Data Streams (in same browser session)
   ↓
Step 10: Close browser & generate report
```

---

### Step 0 — Load Playwright tools

**CRITICAL: Load Playwright tool schemas before using them**

Use ToolSearch to load MCP Playwright tools:

```
ToolSearch(
  query: "select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_click,mcp__plugin_playwright_playwright__browser_snapshot,mcp__plugin_playwright_playwright__browser_take_screenshot,mcp__plugin_playwright_playwright__browser_type,mcp__plugin_playwright_playwright__browser_wait_for",
  max_results: 10
)
```

This loads all necessary Playwright tools for browser automation.

---

### Step 1 — Get org credentials

**CRITICAL: Get instance URL and access token from Salesforce CLI first**

Run command:

```bash
sf org display --target-org <org_alias> --json
```

Extract from JSON response:

| Field | Description | Usage |
|---|---|---|
| `result.instanceUrl` | Org URL | Base URL for navigation |
| `result.accessToken` | Session access token | Used for `frontdoor.jsp?sid=` auto-login |

**Authentication is web-based via Salesforce CLI — no username/password is ever collected by this skill.**

**If sf org display fails:**
- Report error: "Org not authenticated"
- Guide user: `sf org login web -a <org_alias>`
- Stop execution

---

### Step 2 — Launch browser and authenticate

**Use Playwright to open browser and navigate to org with the CLI access token**

Navigate via the frontdoor URL (auto-logs in using the existing CLI web session — no password prompt):

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}"
)
```

If the page redirects to a login form, the CLI session has expired. Stop and ask the user to run `sf org login web -a <org_alias>` again.

Take screenshot to confirm login success:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "login-success.png"
)
```

---

### Step 3 — Navigate directly to Contact Data Cloud Related List page

**✅ USE DIRECT URL for faster navigation**

Navigate directly to Contact object's Data Cloud Related List page:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/setup/ObjectManager/Contact/Enrichment-RelatedLists/view"
)
```

Wait for page to load:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

Take screenshot to confirm page loaded:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "related-lists-page.png"
)
```

**Important:** This direct URL eliminates the need to:
- Search in Object Manager
- Click on Contact object
- Navigate to Data Cloud Related List section

---

### Step 4 — Click New button to create related list

Look for the "New" button on the Data Cloud Related List page:

```
mcp__plugin_playwright_playwright__browser_snapshot(
  boxes: true
)
```

Click the "New" button:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('New')",
  element: "New button"
)
```

Wait for the wizard to open:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

Take screenshot:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "new-related-list-wizard.png"
)
```

---

### Step 5 — Select Customer Affinities Data Cloud Object

**5.1 Find Data Cloud Object dropdown**

Look for "Data Cloud Object" field or dropdown:

```
mcp__plugin_playwright_playwright__browser_snapshot(
  boxes: true
)
```

**5.2 Click on the Data Cloud Object dropdown**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "combobox[placeholder*='Search']",
  element: "Data Cloud Object search box"
)
```

Wait for dropdown to open:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 2
)
```

**5.3 Type "Customer Affinities" in search box**

```
mcp__plugin_playwright_playwright__browser_type(
  target: "combobox[placeholder*='Search']",
  text: "Customer Affinities",
  element: "Data Cloud Object search"
)
```

Wait for search results:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 2
)
```

**5.4 Click on "Customer Affinities" option**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Customer Affinities",
  element: "Customer Affinities option"
)
```

Wait for selection to register:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 2
)
```

Take screenshot:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "customer-affinities-selected.png"
)
```

---

### Step 6 — Click Next (first time)

Click the "Next" button to proceed to the next step:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Next')",
  element: "Next button"
)
```

Wait for next page to load:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

Take screenshot:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "wizard-step-2.png"
)
```

---

### Step 7 — Keep default values and click Next (second time)

**Important:** This step shows default configuration values. Keep them as-is.

Take snapshot to verify default values:

```
mcp__plugin_playwright_playwright__browser_snapshot(
  boxes: true
)
```

Click "Next" to proceed:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Next')",
  element: "Next button"
)
```

Wait for next page:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

Take screenshot:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "wizard-step-3.png"
)
```

---

### Step 8 — Configure related list settings

**8.1 Change the related list label to "Customer Affinities"**

Find the "Related List Label" field:

```
mcp__plugin_playwright_playwright__browser_snapshot(
  boxes: true
)
```

Clear existing value and type "Customer Affinities":

```
mcp__plugin_playwright_playwright__browser_type(
  target: "input[name*='label']",
  text: "Customer Affinities",
  element: "Related List Label field"
)
```

Wait:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 1
)
```

**Mandatory page-layout selections.** ALWAYS check **all three** of these checkboxes before clicking Save — never just one or two:

1. **Person Account Layout**
2. **Contact Layout**
3. **SDO - Person Account Layout**

**🚨 Why exact-text match is mandatory (verified from inspect-element on 2026-06-10):**

The page-layouts checkbox group renders six rows in this DOM order. They share `name="entity-page-layouts"` and a stable `<label>` structure:

```html
<span class="slds-checkbox">
  <input type="checkbox" name="entity-page-layouts" id="checkbox-N-701" value="...">
  <label class="slds-checkbox__label" for="checkbox-N-701">
    <span class="slds-checkbox_faux"></span>
    <span class="slds-form-element__label">Person Account Layout</span>
  </label>
</span>
```

Six rows shipped by the wizard:

| Index | Label text                      | Want to click? |
|-------|---------------------------------|----------------|
| 0     | Person Account Layout           | ✅ Yes         |
| 1     | Contact Layout                  | ✅ Yes         |
| 2     | SDO - Partner Contact           | ❌ No          |
| 3     | SDO - Person Account Layout     | ✅ Yes         |
| 4     | B2B Contact Layout              | ❌ No          |
| 5     | SDO - Contact                   | ❌ No          |

**The trap with substring-text selectors:** `label:has-text('Contact Layout')` is a substring match in Playwright's selector engine. It would match BOTH `Contact Layout` (row 1, correct) AND `B2B Contact Layout` (row 4, wrong) — and depending on DOM order Playwright might click whichever is found first. Same issue would happen with `label:has-text('Person Account Layout')` matching both `Person Account Layout` and `SDO - Person Account Layout`.

**The fix:** scope to `span.slds-form-element__label` (the inner span that holds the exact label text) and use Playwright's `:text-is(...)` exact-match pseudo. Click events bubble from the inner span up to the parent label, which toggles the checkbox just like clicking the label directly.

**🚨 SLDS-checkbox click rule:** never click the hidden `<input type="checkbox">` directly — the SLDS faux-span overlay intercepts pointer events. Always click the visible label-text span.

**8.2 Check the "Person Account Layout" checkbox**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "span.slds-form-element__label:text-is('Person Account Layout')",
  element: "Person Account Layout checkbox label (exact match — must NOT match SDO - Person Account Layout)"
)
```

(No explicit wait — Playwright auto-waits before the next click.)

**8.3 Check the "Contact Layout" checkbox** 🆕

```
mcp__plugin_playwright_playwright__browser_click(
  target: "span.slds-form-element__label:text-is('Contact Layout')",
  element: "Contact Layout checkbox label (exact match — must NOT match B2B Contact Layout)"
)
```

**8.4 Check the "SDO - Person Account Layout" checkbox**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "span.slds-form-element__label:text-is('SDO - Person Account Layout')",
  element: "SDO - Person Account Layout checkbox label (exact match)"
)
```

**Optional verification after clicking all three.** Run a single `evaluate()` to confirm exactly the right three inputs are checked and none of the wrong three (`SDO - Partner Contact`, `B2B Contact Layout`, `SDO - Contact`) got toggled by accident:

```
mcp__plugin_playwright_playwright__browser_evaluate
  function: "() => { const want = new Set(['Person Account Layout','Contact Layout','SDO - Person Account Layout']); const dontWant = new Set(['SDO - Partner Contact','B2B Contact Layout','SDO - Contact']); const result = {wanted: {}, unwanted: {}}; document.querySelectorAll('input[name=\"entity-page-layouts\"]').forEach(i => { const lbl = i.closest('span.slds-checkbox')?.querySelector('span.slds-form-element__label')?.textContent?.trim(); if (!lbl) return; if (want.has(lbl)) result.wanted[lbl] = i.checked; if (dontWant.has(lbl)) result.unwanted[lbl] = i.checked; }); const allWantedChecked = Object.values(result.wanted).every(v => v === true) && Object.keys(result.wanted).length === 3; const noneUnwantedChecked = Object.values(result.unwanted).every(v => v === false); return { ok: allWantedChecked && noneUnwantedChecked, ...result }; }"
  element: "Verify exactly the 3 wanted layouts are checked, none of the 3 unwanted"
```

`{ok: true}` → proceed to 8.5. `{ok: false, ...}` surfaces which row went wrong; abort and report rather than saving the wizard with a wrong layout.

**8.5 Check "Add related list to users' existing record page customizations" checkbox**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "span.slds-form-element__label:text-is('Add related list to users’ existing record page customizations')",
  element: "Add-to-existing-customizations checkbox label (exact match — note the curly apostrophe ’)"
)
```

> The wizard uses a curly apostrophe (Unicode U+2019) in `"users' existing"`, not a straight ASCII `'`. The label text from inspect-element is verbatim: `Add related list to users’ existing record page customizations`. Use `’` in the selector or paste the literal curly character — a straight `'` will silently miss.

---

### Step 9 — Click Next/Save to complete

Click the "Next" or "Save" button to complete the wizard:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Next')",
  element: "Next/Save button"
)
```

Wait for completion:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

Take screenshot to confirm success:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "related-list-created.png"
)
```

Report:
```text
✅ Customer Affinities related list created successfully
```

---

### Step 9.5 — Refresh Account_Home and Contact_Home Data Streams

**Why this runs here:** the Customer Affinities related list draws from Contact-side Data Cloud data, which depends on the Account_Home + Contact_Home CRM Connector Data Streams being current. Refreshing them right after the related list is saved (in the same browser session) eliminates a stale-data window between this skill and downstream Data Cloud work.

**Pattern reused from `/refresh-data-streams`:** trigger Full Refresh on each stream sequentially via direct URL navigation. **Fire-and-forget — no SOQL polling/verification.** The selectors are identical to Steps 4.2–4.4 of `/refresh-data-streams` and are copied verbatim because Salesforce's SLDS markup for the Refresh Now dialog is the same on every record page. Status verification is intentionally omitted: the refreshes continue running on Salesforce after the browser closes, and downstream skills do not require synchronous confirmation.

**9.5.1 Query Account_Home and Contact_Home Data Stream IDs**

Create temp SOQL file:

```bash
cat > query_ds_acct_contact.soql << 'EOF'
SELECT Id, Name FROM DataStream WHERE Name IN ('Account_Home', 'Contact_Home')
EOF
```

Execute and parse:

```bash
sf data query --target-org <org_alias> --file query_ds_acct_contact.soql --json
```

Extract `ACCOUNT_HOME_ID` and `CONTACT_HOME_ID` from the response.

Delete the temp file immediately:

```bash
rm query_ds_acct_contact.soql
```

**If either ID is missing:** report which stream is missing and skip just that one — continue with whichever stream(s) were found. Do NOT fail the skill; the related list creation already succeeded above.

**9.5.2 Refresh Account_Home**

Navigate directly to the Data Stream record page:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{ACCOUNT_HOME_ID}/view"
)
```

Wait for the page to settle:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

Click the page-level "Refresh Now" action (OR-selector — Salesforce renders this as `[role='button']`, not `<button>`, on some Lightning versions):

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Refresh Now'), [role='button']:has-text('Refresh Now')",
  element: "Refresh Now button on Account_Home Data Stream record page"
)
```

Wait for the dialog:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 2
)
```

Select the "Full Refresh" radio. The radio input is hidden behind an SLDS label overlay — clicking the label is required:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "label[for*='Full']",
  element: "Full Refresh radio label (clicks the SLDS-overlay label, NOT the hidden input)"
)
```

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 1
)
```

Click the dialog's "Refresh Now" submit (scoped to the dialog so we don't click the page-level button again — OR-selector covers both `section` and `div` dialog wrappers):

```
mcp__plugin_playwright_playwright__browser_click(
  target: "[role='dialog'] button:has-text('Refresh Now'), section[role='dialog'] button:has-text('Refresh Now')",
  element: "Refresh Now submit button inside the Full Refresh confirmation dialog"
)
```

Wait for the refresh to start:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

Report:
```text
✅ Account_Home — Full Refresh triggered
```

**9.5.3 Refresh Contact_Home**

Repeat the same six tool calls as 9.5.2, but with `CONTACT_HOME_ID`:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{CONTACT_HOME_ID}/view"
)
```

Then `wait_for(time:3)` → page-level Refresh Now click → `wait_for(time:2)` → Full Refresh label click → `wait_for(time:1)` → dialog Refresh Now click → `wait_for(time:3)`. Selectors are identical to 9.5.2.

Report:
```text
✅ Contact_Home — Full Refresh triggered
```

**9.5.4 Failure handling**

- If `Refresh Now` button is missing on either record page (e.g. user lacks permission, stream not yet active), skip that stream and continue. Do NOT fail this skill — the related list creation is the primary deliverable.
- If only Account_Home or only Contact_Home succeeded, the final report should list which triggered and which was skipped.
- **No SOQL polling/verification is performed.** Refreshes are fire-and-forget — the trigger click is treated as success once the dialog dismisses without error. Status confirmation, if needed, is the user's call after the skill exits.

---

### Step 10 — Close browser and generate report

Close the browser (refreshes triggered in Step 9.5 continue running on Salesforce after the browser closes):

```
mcp__plugin_playwright_playwright__browser_close()
```

**No SOQL polling/verification is performed** — refreshes are fire-and-forget. Proceed directly to the final report.

Generate final report:

```text
✅ Data Cloud Related List Created!

Org: <org_alias>
Instance: {instanceUrl}

═══════════════════════════════════════════════════

📋 Related List Details:

Object: Contact
Data Cloud Object: Customer Affinities
Related List Label: Customer Affinities

Configuration:
✅ Person Account Layout - Added
✅ SDO - Person Account Layout - Added
✅ Contact Layout - Added
✅ Existing Page Customizations - Added

═══════════════════════════════════════════════════

🔄 Data Stream Refresh (Account_Home + Contact_Home):

✅ Account_Home: Full Refresh triggered (fire-and-forget, runs async on Salesforce)
✅ Contact_Home: Full Refresh triggered (fire-and-forget, runs async on Salesforce)

(Or, if a stream was skipped because the Refresh Now button was missing:
 ⚠️ Account_Home: Skipped — Refresh Now button not available
 ✅ Contact_Home: Full Refresh triggered)

═══════════════════════════════════════════════════

🔗 Verify Related List:
{instanceUrl}/lightning/setup/ObjectManager/Contact/Enrichment-RelatedLists/view

Instructions:
1. Navigate to Setup → Object Manager → Contact
2. Click "Data Cloud Related List" tab
3. Verify "Customer Affinities" related list appears
4. Open a Contact record to see the related list

═══════════════════════════════════════════════════

✅ Related list created successfully!

Next: Open a Contact record to see Customer Affinities data.
```

---

## Important Rules

**CRITICAL - Execution Sequence:**
- 🚨 **Execute steps sequentially** - complete one before moving to next
- 🚨 **Wait for page loads** after each navigation
- 🚨 **Verify elements are visible** before clicking
- 🚨 **Use direct URLs** for faster navigation

**CRITICAL - Configuration:**
- ✅ **Related List Label must be "Customer Affinities"**
- ✅ **ALL THREE page-layout checkboxes must be checked (Person Account Layout, Contact Layout, SDO - Person Account Layout)** — never skip any
- ✅ **Add to existing customizations checkbox must be checked**
- ✅ **Use exact-text selectors** — `span.slds-form-element__label:text-is('<label>')`. NEVER use substring `:has-text(...)` here because `Person Account Layout` would also match `SDO - Person Account Layout`, and `Contact Layout` would also match `B2B Contact Layout` — wrong rows would get toggled.
- ✅ **Run the post-click `evaluate()` verification** in Step 8.4 to confirm only the three wanted inputs are checked before proceeding to Save.
- ✅ **Keep default values** for other settings

**CRITICAL - Browser Automation:**
- ✅ **ONLY use MCP Playwright tools** - Never generate JavaScript
- ✅ **Take screenshots at key steps** for verification
- ✅ **Wait for elements to appear** before clicking
- ✅ **Use time-based waits** (2-3 seconds) for page loads

**CRITICAL - Error Handling:**
- ✅ **If Customer Affinities not found, report error and stop**
- ✅ **If wizard fails, take screenshot and report issue**
- ✅ **Provide actionable error messages with fix suggestions**

**General Rules:**
- NEVER hardcode org names — always use provided org_alias parameter
- ALWAYS verify user is authenticated before starting
- ALWAYS take screenshots at critical steps
- ALWAYS close browser when done
- ALWAYS provide comprehensive summary report
- Estimated time: 2-3 minutes for complete process

---

## Example Usage

### Example 1: User provides org name

**User:** "Create Customer Affinities related list in MyRetailOrg"

**Skill:**
1. Gets org credentials: `sf org display`
2. Launches browser and authenticates
3. Navigates directly to Contact Related Lists page
4. Clicks "New" button
5. Selects "Customer Affinities" Data Cloud Object
6. Clicks Next
7. Keeps default values, clicks Next
8. Changes label to "Customer Affinities"
9. Checks Person Account Layout checkbox
10. Checks SDO - Person Account Layout checkbox
11. Checks Contact Layout checkbox
12. Checks Add to customizations checkbox
13. Clicks Next to save
12. Closes browser
13. Reports success

---

### Example 2: Error handling - Data Cloud Object not found

**User:** "Create Customer Affinities related list in TestOrg"

**Skill:** [Opens wizard and searches for Customer Affinities]

**Error:** `Data Cloud Object "Customer Affinities" not found`

**Skill:**
```text
❌ Data Cloud Object Not Found

Org: TestOrg

Data Cloud Object: Customer Affinities

This Data Cloud Object must exist before creating a related list.

Suggested Fix:
1. Verify Data Cloud is enabled: Setup → Data Cloud → Settings
2. Check Data Streams: Setup → Data Cloud → Data Streams
3. Verify "Customer Affinities" Data Stream exists and is active
4. Ensure data has been ingested into Data Cloud
5. Check Data Model: Setup → Data Cloud → Data Model Browser

Cannot proceed without Customer Affinities Data Cloud Object.
```

---

## Success Criteria

Related list creation is successful when:

✅ Org authentication validated via `sf org display`
✅ Browser launched successfully
✅ Contact Related Lists page loaded via direct URL
✅ "New" button clicked successfully
✅ Customer Affinities Data Cloud Object found and selected
✅ First "Next" button clicked
✅ Second "Next" button clicked (default values kept)
✅ Related List Label set to "Customer Affinities"
✅ Person Account Layout checkbox checked
✅ SDO - Person Account Layout checkbox checked
✅ Contact Layout checkbox checked
✅ Add to customizations checkbox checked
✅ Final "Next" button clicked to save
✅ Related list created successfully
✅ Browser closed cleanly
✅ Comprehensive summary report provided

---

## Notes

- The wizard has multiple steps - follow them in order
- Do NOT skip any steps or try to navigate directly to final step
- Screenshots help verify each step completed successfully
- If wizard changes between Salesforce versions, the selectors may need adjustment
- Related list will appear on Contact record pages after creation
- Users with existing page customizations will see the related list automatically

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If the wizard fails (object not found, deploy error, etc.), **do NOT clean up** — leave `.playwright-mcp/` traces so the failure can be inspected.
- Fix the underlying issue, retry from the failed step, then run cleanup once the related list is created and verified.

**Files this skill creates and must delete (in repo root):**

```bash
rm -f query_ds_acct_contact.soql
# Defensive cleanup — older skill versions created this file during SOQL polling.
# Polling has been removed, but leftover files from prior runs should still be cleaned up.
rm -f query_ds_status_acct_contact.soql
```

**Folders this skill creates via Playwright and must delete:**

```bash
cmd.exe //c "rmdir /S /Q .playwright-mcp" 2>/dev/null || rm -rf .playwright-mcp
```

**Verification (must show no leftovers):**

```bash
ls *.soql 2>&1 | grep -v "cannot access"
ls -d .playwright-mcp 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete the items listed above (`.playwright-mcp/` Playwright session cache + the two temp SOQL files this skill creates).
- ✅ Do NOT touch any repo source.
- ❌ Skipping this step is not allowed once the Customer Affinities related list is verified created.
