---
name: refresh-data-streams
description: "Automate Data Cloud Data Stream refresh using Playwright browser automation. Refreshes all specified Data Streams (Account_Home, Contact_Home, Product2_Home, etc.) sequentially and verifies success. Uses MCP Playwright tools only. Use when user wants to refresh data streams, update data streams, or sync data streams."
---

# refresh-data-streams

## Purpose

Automate the refresh of Data Cloud Data Streams using Playwright browser automation.

**✅ BROWSER AUTOMATION SOLUTION**

This skill automates the process of refreshing multiple Data Streams in Data Cloud. It navigates through App Launcher → Data Cloud → Data Streams and refreshes each specified Data Stream sequentially, waiting for success status.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT generate Playwright scripts (.js, .mjs, .ts files)
- ✅ Use MCP Playwright browser automation tools ONLY via direct tool calls
- ✅ All automation through `mcp__plugin_playwright_playwright__*` tools
- ✅ **Execute refreshes sequentially** - complete one before moving to next
- ✅ **Wait for Success status** before moving to next Data Stream
- 📸 **Screenshot Policy**: ONLY take screenshots when errors occur. Save to `.playwright-mcp/error-[timestamp].png`. Do NOT take screenshots for successful steps

**Temporary File Policy (MANDATORY):**
- ✅ Create temp SOQL files (e.g. `query_datastreams.soql`, `query_datastream_status.soql`) ONLY when needed
- ✅ DELETE the file IMMEDIATELY after the step completes (`rm <filename>`)
- ❌ NEVER leave temporary SOQL/Apex/query files in the repo working tree

**🚨 CRITICAL: Which Data Streams to Refresh**

**✅ REFRESH THESE (CRM Connector Data Streams):**
1. Account_Home
2. Contact_Home
3. Product2_Home
4. Pricebook2_Home
5. PricebookEntry_Home
6. Asset_Home
7. AssetWarranty_Home
8. Order_Home
9. OrderItem_Home
10. Promotion_Home
11. PromotionProduct_Home
12. ServiceAppointment_Home

**❌ NEVER REFRESH THESE (File-Based Data Streams):**
- Customer Engagement Feed
- POS Customer
- Website Customer
- Customer Affinities

**Why the difference?**
- **CRM Connector Data Streams** sync data from Salesforce objects and require automated refresh via "Refresh Now" button
- **File-Based Data Streams** are updated when files are uploaded and should NOT be refreshed via browser automation

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

Before running:

- Salesforce CLI authenticated with target org
- User has System Administrator profile or equivalent permissions
- Data Cloud must be enabled and provisioned
- All specified Data Streams must exist and be active
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

1. ✅ **ALWAYS execute Data Stream refreshes in SERIES (sequential order) - NEVER in parallel**
2. ✅ **Use SOQL to get Data Stream IDs first**
3. ✅ **Navigate directly to each Data Stream using /lightning/r/DataStream/{RecordId}/view**
4. ✅ **Click Refresh Now → Select Full Refresh → Click Refresh Now → Wait for refresh to start (3 seconds)**
5. ✅ **ALWAYS select "Full Refresh" (not Incremental)**
6. ✅ **Close browser immediately after all refreshes are triggered**
7. ✅ **After browser closed, verify status with SOQL query (no browser needed)**
8. ✅ **Wait for all Data Streams to show "Success" in ImportRunStatus via SOQL**
9. ✅ **Loop SOQL query every 30 seconds until all succeed or max wait time (15 minutes)**
10. ✅ **If any show "Failed", automatically retry by re-opening browser and refreshing only failed Data Streams**
11. ✅ **Maximum 2 retries per Data Stream (3 total attempts including initial refresh)**
12. ✅ **NEVER refresh file-based Data Streams** (Customer Engagement Feed, POS Customer, Website Customer, Customer Affinities)
13. ✅ **ONLY refresh CRM Connector Data Streams** (Account_Home, Contact_Home, Product2_Home, etc.)
14. ✅ **ONLY proceed to next skill when all Data Streams show Success status**

**Step Execution Order:**
```
Step 0: Load Playwright tools
   ↓
Step 1: Query Data Stream IDs using SOQL
   ↓
Step 2: Get org credentials
   ↓
Step 3: Launch browser and authenticate
   ↓
Steps 4-15: Refresh each Data Stream sequentially
   - Navigate directly to /lightning/r/DataStream/{Id}/view
   - Click Refresh Now
   - Select Full Refresh
   - Click Refresh Now button
   - Wait for refresh to start (3 seconds)
   ↓
Step 16: Close browser
   ↓
Step 17: Verify Data Stream status with SOQL (no browser needed)
   - Query ImportRunStatus for all Data Streams
   - Wait for all to show "Success" status
   - Loop every 30 seconds (max 15 minutes)
   ↓
   If any show "Failed":
      → Re-open browser (Step 17.5.1)
      → Refresh only failed Data Streams (Step 17.5.2)
      → Close browser (Step 17.5.3)
      → Restart verification loop (Step 17.5.4)
      → Maximum 2 retries per Data Stream (3 total attempts)
   ↓
   If all show "Success":
      → Proceed to Step 18
   ↓
   If still failed after 3 attempts OR timeout:
      → Report error and STOP
   ↓
Step 18: Generate final report & proceed to next skill
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

### Step 1 — Query Data Stream IDs using SOQL

**CRITICAL: Query all CRM Connector Data Stream IDs before starting browser automation**

**1.1 Create SOQL query file:**

```bash
cat > query_datastreams.soql << 'EOF'
SELECT Id, Name FROM DataStream 
WHERE Name IN (
  'Account_Home', 
  'Contact_Home', 
  'Product2_Home', 
  'Pricebook2_Home', 
  'PricebookEntry_Home', 
  'Asset_Home', 
  'AssetWarranty_Home', 
  'Order_Home', 
  'OrderItem_Home', 
  'Promotion_Home', 
  'PromotionProduct_Home', 
  'ServiceAppointment_Home'
)
EOF
```

**1.2 Execute SOQL query:**

```bash
sf data query --target-org <org_alias> --file query_datastreams.soql --json
```

**1.3 Parse JSON response and extract IDs:**

Example response:
```json
{
  "status": 0,
  "result": {
    "records": [
      {"Id": "1dsHu000000HmluIAC", "Name": "Account_Home"},
      {"Id": "1dsHu000000HmlxIAC", "Name": "Contact_Home"},
      ...
    ],
    "totalSize": 12
  }
}
```

**Store Data Stream IDs in variables:**
- `ACCOUNT_HOME_ID`
- `CONTACT_HOME_ID`
- `PRODUCT2_HOME_ID`
- `PRICEBOOK2_HOME_ID`
- `PRICEBOOKENTRY_HOME_ID`
- `ASSET_HOME_ID`
- `ASSETWARRANTY_HOME_ID`
- `ORDER_HOME_ID`
- `ORDERITEM_HOME_ID`
- `PROMOTION_HOME_ID`
- `PROMOTIONPRODUCT_HOME_ID`
- `SERVICEAPPOINTMENT_HOME_ID`

**If query returns fewer than 12 records:**
- Report which Data Streams are missing
- Continue with available Data Streams only
- Report missing Data Streams in final summary

**Important:** 
- **ONLY query CRM Connector Data Streams** (the 12 listed above)
- **NEVER include file-based Data Streams** like Customer Engagement Feed, POS Customer, Website Customer, Customer Affinities
- File-based Data Streams should NOT be refreshed via browser - they are updated when files are uploaded

**1.4 Delete temporary SOQL file:**

```bash
rm query_datastreams.soql
```

---

### Step 2 — Get org credentials

**Get instance URL and access token from Salesforce CLI**

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

### Step 3 — Launch browser and authenticate

**Use Playwright to open browser and navigate to org with the CLI access token**

Navigate via the frontdoor URL (auto-logs in using the existing CLI web session — no password prompt):

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}"
)
```

If the page still redirects to a login form, the CLI session has expired. Stop and ask the user to run `sf org login web -a <org_alias>` again.

Take screenshot to confirm login success:

```
mcp__plugin_playwright_playwright__browser_take_screenshot(
  type: "png",
  filename: "login-success.png"
)
```

---

### Step 4 — Refresh Account_Home Data Stream

**✅ USE DIRECT URL NAVIGATION with Record ID from Step 1**

**4.1 Navigate directly to Account_Home Data Stream detail page**

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{ACCOUNT_HOME_ID}/view"
)
```

Example: `https://storm-3398078bda765e.my.salesforce.com/lightning/r/DataStream/1dsHu000000HmluIAC/view`

Wait for page to load:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

**4.2 Click "Refresh Now" button**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Refresh Now'), [role='button']:has-text('Refresh Now')",
  element: "Refresh Now button on Data Stream record page"
)
```

> **Why the OR-selector:** Salesforce renders the record-page "Refresh Now" action as `[role="button"]` (a clickable link), not a literal `<button>`. A plain `button:has-text('Refresh Now')` selector or `text=Refresh Now` will fail with "does not match any elements". The combined selector matches both shapes so this works regardless of which Lightning version the org is on.

Wait for dialog to appear:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 2
)
```

**4.3 Select "Full Refresh" option**

A dialog will appear with two options: "Incremental Refresh" and "Full Refresh". Always select "Full Refresh".

🚨 **SLDS hidden-input pattern.** The "Full Refresh" radio is rendered as `<input type="radio" id="Full-NNNN Refresh-NNNN">` hidden behind an SLDS `<label>` overlay. Clicking the input directly times out after 5 s with `<label for="..."> intercepts pointer events`. Click the label by its `for=*Full*` attribute instead:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "label[for*='Full']",
  element: "Full Refresh radio label (clicks the SLDS-overlay label, NOT the hidden input)"
)
```

> Do NOT use `text=Full Refresh` — that's a substring match that may resolve to the heading text or the descriptive paragraph rather than the label, and even when it resolves to the label it can hit the same pointer-events interception. The `label[for*='Full']` selector targets the visible label element directly.

Wait for selection:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 1
)
```

**4.4 Click "Refresh Now" button in dialog**

The dialog renders as either `section[role='dialog']` or `div[role='dialog']` depending on the Lightning version. Use the OR-selector so we match either, and scope to the dialog so the click never lands on the page-level "Refresh Now" again:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "[role='dialog'] button:has-text('Refresh Now'), section[role='dialog'] button:has-text('Refresh Now')",
  element: "Refresh Now submit button inside the Full Refresh confirmation dialog"
)
```

> A bare `div[role='dialog'] button:has-text('Refresh Now')` selector misses on this org because the dialog is a `<section>`, not a `<div>`.

Wait for refresh to start:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

**4.5 Wait for Success status**

Wait a reasonable time (30-60 seconds) for refresh to complete:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 30
)
```

Take snapshot to verify status:

```
mcp__plugin_playwright_playwright__browser_snapshot()
```

**4.6 Verify Last Processed Records**

Check that "Last Processed Records" shows a count > 0.

Report:
```text
✅ Account_Home refreshed successfully
   Status: Success
   Last Processed Records: [count]
```

---

### Steps 5-15 — Refresh remaining Data Streams

**Repeat the same process for each Data Stream using direct URL navigation:**

- Step 5: Contact_Home (use `CONTACT_HOME_ID` from Step 1)
- Step 6: Product2_Home (use `PRODUCT2_HOME_ID` from Step 1)
- Step 7: Pricebook2_Home (use `PRICEBOOK2_HOME_ID` from Step 1)
- Step 8: PricebookEntry_Home (use `PRICEBOOKENTRY_HOME_ID` from Step 1)
- Step 9: Asset_Home (use `ASSET_HOME_ID` from Step 1)
- Step 10: AssetWarranty_Home (use `ASSETWARRANTY_HOME_ID` from Step 1)
- Step 11: Order_Home (use `ORDER_HOME_ID` from Step 1)
- Step 12: OrderItem_Home (use `ORDERITEM_HOME_ID` from Step 1)
- Step 13: Promotion_Home (use `PROMOTION_HOME_ID` from Step 1)
- Step 14: PromotionProduct_Home (use `PROMOTIONPRODUCT_HOME_ID` from Step 1)
- Step 15: ServiceAppointment_Home (use `SERVICEAPPOINTMENT_HOME_ID` from Step 1)

**For each Data Stream:**
1. Navigate directly to: `{instanceUrl}/lightning/r/DataStream/{DataStreamId}/view`
2. Wait for page to load (3 seconds)
3. Click "Refresh Now" button
4. Wait for dialog (2 seconds)
5. Select "Full Refresh" option
6. Click "Refresh Now" button in dialog
7. Wait for refresh to complete (30 seconds)
8. Take snapshot to verify status
9. Verify Last Processed Records
10. Report success

**Important:** 
- Do NOT move to the next Data Stream until the current one shows "Success" status
- **NEVER refresh file-based Data Streams** (Customer Engagement Feed, POS Customer, Website Customer, Customer Affinities)
- Only refresh CRM Connector Data Streams listed above

---

### Step 16 — Close browser

**Close browser immediately after all 12 Data Streams have been refreshed**

Close the browser:

```
mcp__plugin_playwright_playwright__browser_close()
```

**Important:**
- Browser is no longer needed after all refreshes are triggered
- Status verification will be done via SOQL (no browser required)
- This allows Data Streams to process in the background

---

### Step 17 — Verify Data Stream Status with SOQL

**CRITICAL: After browser is closed, verify Data Stream status using SOQL queries**

This step verifies that all Data Streams have successfully completed processing. Data Streams continue to run in the background after the refresh is triggered, so we need to wait and verify their final status.

**17.1 Create SOQL query file for status check:**

```bash
cat > query_datastream_status.soql << 'EOF'
SELECT Id, Name, DataStreamStatus, ImportRunStatus 
FROM DataStream 
WHERE Name IN (
  'Account_Home', 
  'Contact_Home', 
  'Product2_Home', 
  'Pricebook2_Home', 
  'PricebookEntry_Home', 
  'Asset_Home', 
  'AssetWarranty_Home', 
  'Order_Home', 
  'OrderItem_Home', 
  'Promotion_Home', 
  'PromotionProduct_Home', 
  'ServiceAppointment_Home'
)
EOF
```

**17.2 Execute SOQL query in a loop until all succeed or timeout:**

```bash
sf data query --target-org <org_alias> --file query_datastream_status.soql --json
```

**17.3 Parse JSON response and check status:**

Example response:
```json
{
  "status": 0,
  "result": {
    "records": [
      {
        "Id": "1dsHp000000kf9GIAQ",
        "Name": "Account_Home",
        "DataStreamStatus": "Active",
        "ImportRunStatus": "Success"
      },
      ...
    ]
  }
}
```

**17.4 Status verification logic:**

**Check each Data Stream's ImportRunStatus:**
- ✅ **"Success"** → Data Stream processed successfully
- ⚠️ **"Running"** → Data Stream is still processing, wait and check again
- ❌ **"Failed"** → Data Stream failed, needs retry

**Loop until all Data Streams show Success:**
1. Query status every 30 seconds
2. If any Data Stream shows "Running", wait and query again
3. If any Data Stream shows "Failed", add to retry list
4. Maximum wait time: 15 minutes (30 iterations × 30 seconds)
5. If timeout reached, report which Data Streams are still processing

**If any Data Streams show "Failed" status:**
- Stop the polling loop
- Proceed to retry logic in Step 17.7
- Re-open browser and refresh only the failed Data Streams
- Close browser again and restart verification from Step 17.2

**17.5 Retry failed Data Streams:**

**If SOQL query shows any Data Streams with "Failed" status, retry them:**

**Step 17.5.1 - Re-open browser and authenticate:**

Re-fetch a fresh access token (the prior one may have expired):

```bash
sf org display --target-org <org_alias> --json
```

Then re-open the browser via the frontdoor URL using the refreshed token (same web-based pattern as Step 3 — no password prompt):

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}"
)
```

If this redirects to a login form, the CLI session has expired — ask the user to run `sf org login web -a <org_alias>` and retry.

**Step 17.5.2 - Refresh only the failed Data Streams:**

For each Data Stream with "Failed" status:
1. Navigate to: `{instanceUrl}/lightning/r/DataStream/{FailedDataStreamId}/view`
2. Wait for page to load (3 seconds)
3. Click "Refresh Now" button
4. Wait for dialog (2 seconds)
5. Select "Full Refresh" option
6. Click "Refresh Now" button in dialog
7. Wait 3 seconds for refresh to start

**Step 17.5.3 - Close browser after retry:**

```
mcp__plugin_playwright_playwright__browser_close()
```

**Step 17.5.4 - Restart status verification:**

After retrying failed Data Streams:
- Go back to Step 17.2 (execute SOQL query in loop)
- Continue polling until all show Success
- Maximum retry attempts per Data Stream: 2
- Track retry count for each Data Stream to prevent infinite loops

**Retry tracking:**
- First attempt: Initial refresh (Steps 4-15)
- Second attempt: First retry (Step 17.5)
- Third attempt: Second retry (Step 17.5 again if still failed)
- If still failed after 3 total attempts → report error and STOP

**17.6 Delete temporary SOQL file:**

```bash
rm query_datastream_status.soql
```

**17.7 Status report after verification:**

```text
🔍 Data Stream Status Verification:

✅ All Data Streams processed successfully!

Final Status:
- Account_Home: Success
- Contact_Home: Success
- Product2_Home: Success
- Pricebook2_Home: Success
- PricebookEntry_Home: Success
- Asset_Home: Success
- AssetWarranty_Home: Success
- Order_Home: Success
- OrderItem_Home: Success
- Promotion_Home: Success
- PromotionProduct_Home: Success
- ServiceAppointment_Home: Success
```

**If any Data Streams failed after maximum retries:**

```text
⚠️ Some Data Streams did not complete successfully after retries:

❌ Failed Data Streams:
- [DataStream Name]: Failed (attempted 3 times total)

✅ Successful Data Streams:
- [List of successful Data Streams]

Retry Summary:
- [DataStream Name]: Attempt 1 (Initial) → Failed
- [DataStream Name]: Attempt 2 (Retry 1) → Failed
- [DataStream Name]: Attempt 3 (Retry 2) → Failed

Error context for diagnostics:
1. Source object data verification (auto-checked via SOQL)
2. Data Stream field mappings (auto-validated)
3. Data Cloud logs reviewed automatically
4. System errors/governor limits checked

🛑 STOPPING: Cannot proceed to next skill until all Data Streams show Success status.
```

**If timeout reached (15 minutes) with Data Streams still "Running":**

```text
⏱️ Timeout reached - Some Data Streams still processing:

⚠️ Still Running:
- [DataStream Name]: Running (after 15 minutes)

✅ Successful Data Streams:
- [List of successful Data Streams]

Auto-recovery: Continue polling for an additional 15 minutes via SOQL.
If still running after extended wait, report final status and STOP.
```

**Important:**
- **ALWAYS wait for all Data Streams to reach Success status** before proceeding to next skill
- **Do NOT proceed if any Data Streams are still "Running"** - wait until complete
- **If Data Streams show "Failed", automatically retry** (up to 2 additional attempts = 3 total)
- **Maximum wait time per attempt: 15 minutes** (30 iterations × 30 seconds)
- **Only proceed to next skill when ALL 12 Data Streams show Success status**

---

### Step 18 — Generate final report and proceed to next skill

**ONLY generate final report after ALL Data Streams show Success status from Step 17**

Generate final report:

```text
✅ Data Streams Refreshed Successfully!

Org: <org_alias>
Instance: {instanceUrl}

═══════════════════════════════════════════════════

📊 Data Streams Refreshed:

1. ✅ Account_Home
   Status: Success
   Last Processed Records: [count]
   
2. ✅ Contact_Home
   Status: Success
   Last Processed Records: [count]
   
3. ✅ Product2_Home
   Status: Success
   Last Processed Records: [count]
   
4. ✅ Pricebook2_Home
   Status: Success
   Last Processed Records: [count]
   
5. ✅ PricebookEntry_Home
   Status: Success
   Last Processed Records: [count]
   
6. ✅ Asset_Home
   Status: Success
   Last Processed Records: [count]
   
7. ✅ AssetWarranty_Home
   Status: Success
   Last Processed Records: [count]
   
8. ✅ Order_Home
   Status: Success
   Last Processed Records: [count]
   
9. ✅ OrderItem_Home
   Status: Success
   Last Processed Records: [count]
   
10. ✅ Promotion_Home
    Status: Success
    Last Processed Records: [count]
    
11. ✅ PromotionProduct_Home
    Status: Success
    Last Processed Records: [count]
    
12. ✅ ServiceAppointment_Home
    Status: Success
    Last Processed Records: [count]

═══════════════════════════════════════════════════

✅ All 12 Data Streams refreshed successfully!

📋 Status Verification Complete:
- All Data Streams processed to completion
- Final ImportRunStatus: Success for all 12 Data Streams
- Ready to proceed to next skill

🔗 Next Step: Proceed to next skill in installation workflow
```

**Important:**
- This final report is generated ONLY after Step 17 confirms all Data Streams show Success status
- Browser was closed in Step 16, status verification was done via SOQL in Step 17
- Skill will NOT proceed to next step unless all 12 Data Streams show Success

---

## Important Rules

**CRITICAL - Execution Sequence:**
- 🚨 **ALWAYS refresh Data Streams in SERIES (sequential order) - NEVER in parallel**
- 🚨 **Trigger all 12 refreshes sequentially in browser**
- 🚨 **Do NOT click multiple Refresh Now at once**
- 🚨 **Close browser after all refreshes triggered**
- 🚨 **Verify status with SOQL after browser closed**

**CRITICAL - Status Verification:**
- ✅ **Use SOQL query to check ImportRunStatus** - not browser UI
- ✅ **Wait for "Success" status for ALL Data Streams** - loop every 30 seconds
- ✅ **Do NOT proceed to next skill until all show Success**
- ✅ **Maximum wait time per attempt: 15 minutes** (30 iterations × 30 seconds)
- ✅ **If any show "Failed", automatically retry those specific Data Streams**
- ✅ **Maximum 2 retries per Data Stream** (3 total attempts)
- ✅ **If still failed after 3 attempts or timeout, report error and STOP**

**CRITICAL - Browser Automation:**
- ✅ **ONLY use MCP Playwright tools** - Never generate JavaScript
- ✅ **Wait for elements to appear** before clicking
- ✅ **Use time-based waits** (2-3 seconds) for menu opens
- ✅ **Close browser immediately after all refreshes triggered**

**CRITICAL - Error Handling:**
- ✅ **If any Data Stream shows "Failed" in SOQL query, automatically retry it**
- ✅ **Re-open browser, refresh only failed Data Streams, close browser**
- ✅ **Restart SOQL verification after retry**
- ✅ **Maximum 2 retries (3 total attempts) per Data Stream**
- ✅ **If still failed after 3 attempts, report error and STOP**
- ✅ **Provide actionable error messages with retry history**
- ✅ **Only proceed to next skill when all 12 show Success**

**General Rules:**
- NEVER hardcode org names — always use provided org_alias parameter
- ALWAYS verify user is authenticated before starting
- ALWAYS close browser after all refreshes triggered
- ALWAYS verify status with SOQL before proceeding
- ALWAYS provide comprehensive summary report
- Estimated time per refresh trigger: 3 seconds
- Estimated time for status verification: 5-15 minutes (waiting for completion)
- Total estimated time: 5-15 minutes for complete workflow

---

## Data Streams to Refresh

| # | Data Stream Name | Description |
|---|-----------------|-------------|
| 1 | Account_Home | Account data from Salesforce |
| 2 | Contact_Home | Contact data from Salesforce |
| 3 | Product2_Home | Product data from Salesforce |
| 4 | Pricebook2_Home | Price Book data from Salesforce |
| 5 | PricebookEntry_Home | Price Book Entry data from Salesforce |
| 6 | Asset_Home | Asset data from Salesforce |
| 7 | AssetWarranty_Home | Asset Warranty data from Salesforce |
| 8 | Order_Home | Order data from Salesforce |
| 9 | OrderItem_Home | Order Item data from Salesforce |
| 10 | Promotion_Home | Promotion data from Salesforce |
| 11 | PromotionProduct_Home | Promotion Product data from Salesforce |
| 12 | ServiceAppointment_Home | Service Appointment data from Salesforce |

---

## Example Usage

### Example 1: User provides org name

**User:** "Refresh Data Streams in MyRetailOrg"

**Skill:**
1. Gets org credentials: `sf org display`
2. Launches browser and authenticates
3. Navigates directly to Data Streams page
4. Refreshes Account_Home → Selects Full Refresh → Waits for Success
5. Refreshes Contact_Home → Selects Full Refresh → Waits for Success
6. Refreshes Product2_Home → Selects Full Refresh → Waits for Success
7. Continues for all 12 Data Streams (always selecting Full Refresh)
8. Closes browser
9. Reports summary with all refresh statuses

---

### Example 2: Error handling - Data Stream not found

**User:** "Refresh Data Streams in TestOrg"

**Skill:** [Opens Data Streams page]

**Error:** `Data Stream "Account_Home" not found`

**Skill:**
```text
⚠️ Data Stream Not Found

Org: TestOrg

Data Stream: Account_Home

This Data Stream must exist before refreshing.

Suggested Fix:
1. Navigate to Setup → Data Cloud → Data Streams
2. Verify "Account_Home" Data Stream exists
3. Check that Data Stream is active
4. Ensure Data Stream has been deployed

Skipping Account_Home and continuing with remaining Data Streams...
```

---

## Success Criteria

Refresh is successful when:

✅ Org authentication validated via `sf org display`
✅ Browser launched successfully
✅ Data Streams page loaded via direct URL
✅ All 12 Data Streams found
✅ Refresh Now clicked for each Data Stream
✅ Success status verified for each Data Stream
✅ Last Processed Records verified for each Data Stream
✅ Browser closed cleanly
✅ Comprehensive summary report provided

---

## Notes

- Each refresh can take 30-60 seconds depending on data volume
- Do NOT refresh all Data Streams in parallel - system may throttle
- Success status indicates data was successfully ingested
- Last Processed Records should match or exceed previous run
- Some Data Streams may process 0 records if no new data available
- Refreshes are incremental by default (only new/changed data)

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If a step fails (or any Data Stream stays Failed after retries), **do NOT clean up** — leave artifacts for debugging.
- Fix the underlying issue, retry the failed step, then run cleanup once all 12 Data Streams show Success.

**Files this skill creates and must delete (in repo root):**

```bash
rm -f query_datastreams.soql
rm -f query_datastream_status.soql
```

**Folders this skill creates and must delete:**

```bash
# Playwright session cache produced by browser automation in Steps 4-15
cmd.exe //c "rmdir /S /Q .playwright-mcp" 2>/dev/null || rm -rf .playwright-mcp
```

**Verification (must show no leftovers):**

```bash
ls *.soql 2>&1 | grep -v "cannot access"
ls -d .playwright-mcp 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete the items listed above. Do NOT touch any other repo files.
- ❌ Skipping this step is not allowed once all 12 Data Streams reach SUCCESS.
