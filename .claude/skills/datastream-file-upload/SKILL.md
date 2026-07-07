---
name: datastream-file-upload
description: "Upload CSV files to Data Cloud Data Stream File Upload connectors using Playwright browser automation with an Aura-layer payload interceptor (Path A) that strips Salesforce-restricted advancedAttributes keys (isDataStreamConfigValid, delimiter) from /aura POSTs in flight. Handles Customer Affinities, Website Customer, POS Customer, and Customer Engagement Feed data streams. The interceptor is required because Salesforce rejects those keys for File-Upload data streams; without it, every Deploy click fails server-side. Uses MCP Playwright tools only. All files this skill creates are deleted on both success and failure paths. Use when user wants to upload files to Data Streams, update Data Stream files, or refresh Data Stream data."
---

# datastream-file-upload

## Purpose

Automate file uploads to Data Cloud Data Stream File Upload connectors using Playwright browser automation.

**✅ WORKING SOLUTION (Validated 2026-05-25)**

This skill successfully automates CSV file uploads to Data Cloud Data Streams using browser automation. The key breakthrough: clicking the visible "Upload Files" text (not the hidden input element) to trigger the file chooser.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT generate Playwright scripts (.js, .mjs, .ts files)
- ✅ Use MCP Playwright browser automation tools ONLY via direct tool calls
- ✅ All automation through `mcp__plugin_playwright_playwright__*` tools
- ✅ **MUST click `text=Upload Files`** to trigger file chooser (not hidden input element)
- 📸 **Screenshot Policy**: ONLY take screenshots when errors occur. Save to `.playwright-mcp/error-[timestamp].png`. Do NOT take screenshots for successful steps

**Temporary File Policy (MANDATORY):**
- ✅ Create temp SOQL files (e.g. `query_datastreams.soql`) ONLY when needed
- ✅ DELETE the file IMMEDIATELY after the step completes (`rm <filename>`)
- ❌ NEVER leave temporary SOQL/Apex/query files in the repo working tree

This skill uploads CSV files to Data Cloud Data Streams with File Upload connection type.

---

## 🚨 PER-FILE 3-TIER ESCALATION STRATEGY (when uploads stall at 0% on AWS S3)

**Symptom:** Salesforce's UI shows the file uploading but it sits at "Progress: 0%" until timeout. This is almost always a corporate proxy / TLS-inspection / cert-chain issue between the browser and AWS S3 (where Salesforce stores the CSV before processing).

**Rule:** All 4 files MUST upload successfully. No file is allowed to be skipped. If a file fails at one tier, retry **just that file** at the next tier. Tiers escalate per-file independently — don't reset successful files.

| Tier | Approach | When to use | What changes |
|---|---|---|---|
| **1** | **Plain Playwright UI** — no Aura interceptor, just click Update File → Full Refresh → Deploy | Default first attempt for every file. Salesforce's vanilla UI flow with no in-flight payload modification. | Nothing — just navigate the wizard normally. |
| **2** | **Aura payload interceptor (Path A)** — strip `isDataStreamConfigValid` + `delimiter` from `advancedAttributes` in `/aura` POSTs in flight | Tier 1's Deploy click fails server-side with a Salesforce validation error mentioning `advancedAttributes` (Salesforce rejects those keys on File-Upload streams). | Inject the interceptor before clicking Update File. See section below. |
| **3** | **Browser-state reset + cache-bypass retry (fully automatic)** | Tier 2 still stalls at "Progress: 0%" for >60s. Real causes the skill *can* fix: stale browser session, expired cookies mid-upload, corrupted page cache, mid-flight CDN cache poisoning. Real causes the skill *cannot* fix: corporate proxy TLS interception (system Chrome would be needed but cannot be invoked without config edit or relaunch). | See "Tier 3 automatic recovery" block below. Skill closes browser → clears all storage/cookies via `browser_evaluate` → reopens → re-injects Aura interceptor with an extra `Cache-Control: no-cache, no-store` header on every `/aura` + `/services` POST → retries the upload with extended timeout (5 min instead of 60s). |

**Escalation rules:**
- ✅ **Tier 1 → 2:** if the Deploy click returns a server error mentioning `isDataStreamConfigValid`, `delimiter`, or `advancedAttributes`. Usually a fast failure, not a 0% stall.
- ✅ **Tier 2 → 3:** if Tier 2's Deploy click succeeds (server accepts the request) but the upload sits at "Progress: 0%" for >60s — that's the AWS S3 PUT failing, which means proxy / cert-chain. Restart the file at Tier 1 logic but with the system-Chrome config now active.
- ❌ **Never skip a file.** If Tier 3 also stalls at 0%, STOP and surface to the user — at that point it's a network-team problem (allowlist `*.s3.<region>.amazonaws.com` in their proxy or disable TLS inspection for `*.amazonaws.com`).
- ✅ **Per-file independence:** if Customer_Affinities uploads cleanly at Tier 1 but POS Customer fails, only escalate POS Customer. Don't redo Customer_Affinities.
- ✅ **Tier 3 doesn't require restarting the install:** the config change is loaded automatically by Playwright MCP on the next browser_navigate call. No process restart needed.

**Detection pseudocode (apply per-file inside the per-stream loop):**

```
attempt_tier_1(file)
if click_deploy_returned_error_mentioning(['advancedAttributes','isDataStreamConfigValid','delimiter']):
    attempt_tier_2(file)  # inject Aura interceptor, retry
elif progress_stuck_at_0_for_60s:
    surface_tier_3_manual_instructions_to_user()  # see block below
    wait_for_user_confirmation("Playwright MCP relaunched with system Chrome")
    attempt_tier_1(file)  # re-run vanilla flow — now driving system Chrome
    if still_stuck_at_0_for_60s:
        STOP and surface network-team requirement
elif success: continue

# Final guard
if any_file_still_failing_after_tier_3:
    STOP and surface "AWS S3 PUT blocked by network. Network team must allowlist *.s3.<region>.amazonaws.com or disable TLS inspection for *.amazonaws.com"
```

### Tier 3 automatic recovery (fully in-skill, no manual user step, no config edit)

When Tier 2 stalls at "Progress: 0%" for >60s, run these steps in order. **All four phases run automatically inside the skill — the user is not asked to relaunch anything.**

**Phase 1 — Capture diagnostic before the reset:**

```
mcp__plugin_playwright_playwright__browser_console_messages(level: "error")
mcp__plugin_playwright_playwright__browser_network_requests()
```

Save the output for the final-failure surface. If errors mention `net::ERR_CERT_AUTHORITY_INVALID`, `net::ERR_PROXY_CONNECTION_FAILED`, or `net::ERR_TUNNEL_CONNECTION_FAILED`, the cause is corporate proxy / TLS interception — Tier 3 cannot fix this; skip to "Final failure surface" below.

**Phase 2 — Hard reset browser state (clears stale session / cookie / cache issues):**

```
mcp__plugin_playwright_playwright__browser_evaluate
  function: "() => { try { localStorage.clear(); sessionStorage.clear(); } catch(e){} ; document.cookie.split(';').forEach(c => { const eq = c.indexOf('='); const name = eq > -1 ? c.substr(0, eq).trim() : c.trim(); document.cookie = name + '=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/'; }); return 'state-cleared'; }"

mcp__plugin_playwright_playwright__browser_close
```

**Phase 3 — Reopen, re-authenticate via frontdoor, and re-inject the Aura interceptor with cache-bypass headers:**

Re-fetch a fresh access token (the cleared session means the old one is gone), then navigate via `frontdoor.jsp?sid=<fresh-token>` to the same Data Stream record page.

After the page loads, install an enhanced Aura interceptor that does what the existing Path A does PLUS adds `Cache-Control: no-cache, no-store, must-revalidate` to every outbound `/aura` and `/services` POST:

```
mcp__plugin_playwright_playwright__browser_evaluate
  function: "() => { const orig = window.XMLHttpRequest.prototype.send; window.XMLHttpRequest.prototype.send = function(body) { try { if (this.__url && (this.__url.includes('/aura') || this.__url.includes('/services'))) { this.setRequestHeader('Cache-Control', 'no-cache, no-store, must-revalidate'); this.setRequestHeader('Pragma', 'no-cache'); if (typeof body === 'string' && body.includes('isDataStreamConfigValid')) { try { const params = new URLSearchParams(body); const msg = params.get('message'); if (msg) { const parsed = JSON.parse(msg); if (parsed.actions) { parsed.actions.forEach(a => { if (a.params && a.params.advancedAttributes) { delete a.params.advancedAttributes.isDataStreamConfigValid; delete a.params.advancedAttributes.delimiter; } }); params.set('message', JSON.stringify(parsed)); body = params.toString(); } } } catch(e){} } } catch(e){} return orig.apply(this, [body]); }; const origOpen = window.XMLHttpRequest.prototype.open; window.XMLHttpRequest.prototype.open = function(method, url) { this.__url = url; return origOpen.apply(this, arguments); }; return 'tier3-interceptor-installed'; }"
```

**Phase 4 — Retry the upload with extended timeout:**

Run the same Update File → Full Refresh → Deploy flow as Tier 1. After clicking Deploy, instead of the normal 60-second wait, poll for completion every 10 seconds for up to **5 minutes** (300 seconds). Stale-session and cache-corruption uploads typically resume around minute 1–2 once the request hits S3 with fresh cookies + no-cache.

**Final failure surface (when Phase 1 detected proxy/cert errors, OR Phase 4 stalls past 5 minutes):**

The skill stops the chain and surfaces verbatim:

```
❌ Data Stream <filename> failed all 3 tiers.

Tier 1 (plain UI):     stalled at 0% / failed
Tier 2 (Aura strip):   stalled at 0%
Tier 3 (state reset):  stalled at 0% / proxy error detected

Diagnostic captured:
  - Console errors: <list from Phase 1>
  - Failed network requests to: <list of S3 hosts>

Root cause: Corporate proxy is blocking or TLS-intercepting AWS S3
(*.s3.<region>.amazonaws.com). The bundled Chromium browser cannot trust
the proxy's re-signed certificate. The skill has exhausted every
in-process workaround.

ONLY remaining fixes (require network-team / IT action):
  1. Allowlist *.s3.<region>.amazonaws.com + *.amazonaws.com in the
     corporate proxy
  2. Disable TLS inspection for *.amazonaws.com
  3. Run the install from a non-corporate network (home WiFi, mobile
     hotspot, AWS Cloud Workstation, etc.)

After IT fix is in place, re-run the install — the skill will pick up
from this Data Stream automatically.
```

**Per-file independence still applies** — successful files at Tier 1 or 2 stay successful; only the failing file goes through Tier 3 and (if needed) the surface above. The skill never asks the user to relaunch anything.

---

### Inline error router (handles everything else automatically — no manual fallback)

Beyond the 3 tiers above, several other errors can surface during DataStream upload. The skill detects each one, applies the matching auto-fix in-flight, retries the failing operation **once** with the fix applied, and escalates to Tier 3 only if the auto-fix doesn't recover. **No error in this table requires user intervention.**

Run these checks at every Playwright step (after every `browser_click`, `browser_navigate`, `browser_file_upload`, `browser_wait_for`):

| Detected condition | Auto-fix | Retry strategy |
|---|---|---|
| **Auth / 401 / "Session expired" / page redirect to `/login`** | Re-fetch fresh access token via `sf org display --target-org <alias> --json`. Re-navigate via `<instanceUrl>/secur/frontdoor.jsp?sid=<freshToken>&retURL=<encoded data-stream URL>`. | Resume from the step that was failing — do NOT restart from file 1. |
| **`net::ERR_CERT_*` / `net::ERR_PROXY_*` / `net::ERR_TUNNEL_*`** in console messages | This is corporate proxy / TLS interception. **No skill workaround possible** — surface the final-failure block from Tier 3 immediately and STOP. Don't waste time on Tier 3 reset. | Skip directly to "Final failure surface". |
| **"File chooser already open" / orphan dialog blocking clicks** | Call `browser_handle_dialog(action: "dismiss")`. If still blocked, take a snapshot, find any visible `[role=dialog]` Cancel/Close button, click it. | Retry the original click once. |
| **Selector mismatch — `text=Update File` (or any documented selector) returns "no element"** | Re-take `browser_snapshot`. Search for the button by role + accessible name regex (e.g. `role=button name=/update.*file/i`). If still nothing, scroll the page (`browser_evaluate: window.scrollTo(0, 200)`), re-snapshot, retry. | Retry click with the fresh selector. If still missing after scroll, escalate to Tier 3 reset. |
| **Lightning page-load race — click fired before LWC mounted (button click is silent no-op, no `/aura` POST in network log)** | Insert `browser_wait_for(text: "<known stable text on the loaded page>", time: 10)` before re-clicking. For Data Stream record pages, wait for the stream Status badge ("Active", "UnderConstruction", etc.) to be visible. | Retry click once after the wait completes. |
| **Network blip / single 5xx from `/aura`** detected via `browser_network_requests` | Capture the failed request URL + response code for diagnostics. Wait 15 seconds (server-side 5xx usually clears on retry). | Retry the same `browser_click` that triggered the failed POST exactly once. Two consecutive 5xx → escalate to Tier 3. |
| **Aura interceptor never installed — `browser_evaluate` to check `typeof window.XMLHttpRequest.prototype.send.__intercepted` returns `"undefined"`** | The page navigated after the inject ran (SPA route change, or interceptor lost). Re-run the Tier 2 `browser_evaluate` injection block before the next Deploy click. | Retry Deploy click after re-injection. |
| **Deploy click timed out — 30s passed and `browser_network_requests` shows zero `/aura` POSTs since the click** | Click fired but didn't register. Re-snapshot DOM. The Deploy button may have moved (SPA re-render). Find it by accessible name regex `role=button name=/deploy/i`, click again. | Retry once with fresh selector. |
| **`browser_file_upload` fails with "no file chooser available"** | The file chooser dialog closed before upload registered (race condition with `browser_click` on the Upload Files label). Re-click the label, then *immediately* call `browser_file_upload` in the next tool call (no `browser_wait_for` between them). | Retry once. |
| **`Progress: 0%` for >60s but no console/network errors** (the canonical Tier 3 trigger) | Run Tier 3 automatic recovery (already documented above). | Standard Tier 3 flow. |
| **`Progress: 0%` >60s WITH `net::ERR_*` in console** | Skip Tier 3 (state reset won't help cert issues) and go straight to the final-failure block. | Surface and STOP. |
| **Any other unexpected exception from a Playwright tool** | Capture via `browser_console_messages(level: "error")` and `browser_network_requests`, save both into the diagnostic. Close the browser, re-open via frontdoor (handles auth recovery from #1 above too), retry the failing step once. | One retry. If the same exception fires twice, escalate to Tier 3. |

**Routing logic (per file, per step):**

```
on every Playwright tool call:
    if call_failed OR detected_condition_matches_table_above:
        log diagnostic
        apply_auto_fix_for(condition)
        retry_call_once
        if still_failing:
            if condition was 5xx, selector mismatch, race, dialog, file-chooser-race:
                escalate to Tier 3 (full state reset)
            elif condition was net::ERR_CERT/PROXY/TUNNEL:
                skip Tier 3, surface final-failure-block, STOP
            else:
                surface final-failure-block with full diagnostic, STOP

after every successful step: continue to next step in the same file
after every successful file: move to next file (per-file independence)
after all 4 files complete: skill done
```

**Final-failure surface diagnostic must always include** (so the user has everything for IT or self-debug):
- Which file failed
- Which step inside that file (auth / nav / click / upload / deploy)
- Console errors captured (last 20 entries)
- Network requests captured (last 30 entries, especially any 4xx/5xx)
- Screenshot saved to `.playwright-mcp/error-<file>-<timestamp>.png`
- The auto-fix attempts the skill made (so support knows what was already tried)

**Hard rule:** the skill never asks the user to do anything except in the final-failure surface (where the only ask is "tell IT to allowlist S3 / disable TLS inspection"). Every condition in the table is detected and auto-handled in-flight.

**Key Workflow Rules:**
1. 🔄 **Execute ALL uploads sequentially (series)** - Never run steps in parallel
2. 📁 **Verify file exists locally** before attempting upload
3. ✅ **Wait for processing confirmation** after each upload
4. 🔑 **Auto-fill credentials** - Get from `sf org display`, ask user if not available
5. 🚀 **Fast execution** - Minimize browser automation time

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username
- `files_directory` (optional): Directory containing CSV files. Defaults to "DIY Documents/DIY Documents"

---

## Preconditions

Before running:

- Salesforce CLI authenticated with target org
- User has System Administrator profile or equivalent permissions
- Data Cloud must be enabled and provisioned
- CSV files must exist in the specified directory:
  - Customer_Affinities 2.csv
  - Website Customer.csv
  - POS Customer.csv
  - Customer Engagement Feed.csv
- Data Streams with File Upload connection type must already exist:
  - Customer Affinities
  - Website Customer
  - POS Customer
  - Customer Engagement Feed
- MCP Playwright tools must be available (check deferred tools list)
- **IMPORTANT:** For fast, uninterrupted execution, configure auto-approval in `.claude/settings.json`:
  ```json
  {
    "permissions": {
      "allow": [
        "mcp__plugin_playwright_playwright__*",
        "bash:sf *",
        "bash:test *",
        "bash:ls *"
      ]
    }
  }
  ```
  Without this, each Playwright action will prompt for user approval, slowing down the process.

---

## Workflow

**CRITICAL EXECUTION RULES:**

1. ✅ **ALWAYS execute ALL uploads in SERIES (sequential order) - NEVER in parallel**
2. ✅ **Complete one Data Stream upload entirely before moving to the next**
3. ✅ **Wait for "Deploy" to complete before moving to next upload**
4. ✅ **Verify file exists before attempting upload**
5. ✅ **If Data Stream not found → Skip and continue with next**
6. ✅ **NEVER fail entire workflow if one upload fails → Report and continue**
7. 🚨 **BLANK-PAGE CHECK (CRITICAL): Immediately after navigating to a Data Stream record, snapshot the page. If the "Update File" button is NOT visible → Refresh the page IMMEDIATELY (do not wait, do not retry chain). Salesforce sometimes renders a blank/incomplete record page on first navigation.**
8. 🔄 **RETRY LOGIC: If any element not found (Upload Files button, Deploy button) → Refresh page/modal and retry once before skipping**

**Step Execution Order:**
```
Step 0: Load Playwright tools
   ↓
Step 1: Verify CSV files exist locally
   ↓
Step 2: Query Data Stream Record IDs using SOQL
   ↓
Step 3: Get credentials from sf org display
   ↓
Step 4: Launch browser and authenticate
   ↓
Step 4.5: 🛠️ Install Aura-layer payload interceptor (REQUIRED — strips
          isDataStreamConfigValid + delimiter from /aura POSTs in flight)
          Without this, EVERY Deploy click in Steps 5-8 fails server-side.
   ↓
Step 5: Customer_Affinities → Update File → Upload CSV → Deploy (interceptor active, Full Refresh kept as default — DO NOT touch the mode toggle)
   ↓
Step 6: Website Customer → Update File → Upload CSV → Deploy (interceptor active, Full Refresh kept as default — DO NOT touch the mode toggle)
   ↓
Step 7: POS Customer → Update File → Upload CSV → Deploy (interceptor active, Full Refresh kept as default — DO NOT touch the mode toggle)
   ↓
Step 8: Customer Engagement Feed → Update File → Upload CSV → Deploy (interceptor active, Full Refresh kept as default — DO NOT touch the mode toggle)
   ↓
Step 9: Close browser → Run mandatory cleanup of EVERY file/folder this run created → Generate report
```

**Per-Data-Stream sub-steps (current):**
- ✅ **Refresh Mode — DO NOT click anything.** Salesforce ships this modal with **Full Refresh preselected** (`aria-checked="true"`); we keep that default for all 4 streams. **Skip mode selection entirely.** Right after `Update File` opens the modal, go directly to clicking `Upload Files`. (Earlier skill versions instructed clicking Upsert before upload — that path is retired. Operator preference is Full Refresh; less ceremony, fewer clicks, no race condition between the mode toggle and the file chooser.)
- ✅ **Update File button not found → REFRESH the page → re-check.** Lightning sometimes renders the record page with the highlights-panel actions missing on first navigation. If `Update File` is not in the snapshot after `wait_for(time:5)`, re-`browser_navigate` to the same URL and snapshot again. Do not retry-click into a missing element.
- ⚠️ **Select Existing Model** — Only applicable if the modal explicitly offers a "New Model vs Existing Model" choice after upload. In current orgs the existing model is auto-selected because the Data Stream is already mapped to its DLO; skip unless the modal renders the choice.

---

## Data Stream Direct Navigation

**✅ BEST PRACTICE: Use SOQL query + direct URL navigation**

Instead of searching for Data Streams in the UI (slow and error-prone), use SOQL to get Record IDs and navigate directly:

**Step A: Query Data Stream IDs:**
```bash
sf data query --target-org <org_alias> --query "SELECT Id, Name FROM DataStream WHERE (Name LIKE 'Customer_Affinities%' OR Name LIKE 'Customer_Engagement_Feed%' OR Name LIKE 'POS_Customer%' OR Name LIKE 'Website_Customer%') OR Name IN ('Customer Affinities', 'Website Customer', 'POS Customer', 'Customer Engagement Feed')" --json
```

**Why both LIKE and IN clauses?** Salesforce sometimes ships the data kit's Data Stream `Name` field with the underscore-separated developer-name form (e.g. `Customer_Affinities`, `Customer_Engagement_Feed_v2`) and sometimes with the spaced label form (e.g. `Customer Affinities`). The `LIKE 'Customer_Affinities%'` patterns cover the underscore variants (including any version suffix like `_v2`); the `IN (...)` clause covers the literal-spaced variants. The combined query matches both shapes in a single round-trip — no need to retry with a different query if the kit's naming convention changed between versions.

**Important: still expect exactly 4 result rows.** If the query returns more (e.g. duplicate streams from a re-deploy) or fewer (e.g. Data Kit metadata didn't finish creating one of the streams), STOP and surface the row list to the user before proceeding — the per-stream navigation in Steps 5-8 hardcodes one ID per stream type.

**Step B: Navigate directly to Data Stream record page:**
```
{instanceUrl}/lightning/r/DataStream/{DataStreamRecordId}/view
```

**Benefits:**
- ✅ No UI search required - instant navigation
- ✅ Reliable - direct URL always works
- ✅ Fast - skip list view loading
- ✅ No search timing issues

---

## Error Handling & Retry Strategy

**🚨 Blank-Page Handling (Update File button not visible on record page)**

Salesforce frequently renders a blank/incomplete Data Stream record page on first navigation. The "Update File" button does not appear because the page never finished loading.

**Required behavior — Refresh Immediately:**
1. After every `browser_navigate` to a Data Stream record, take a snapshot
2. Check if "Update File" button is present in the snapshot
3. **If NOT present → Refresh the page IMMEDIATELY (no waiting, no element retry chain)**
4. Wait 5 seconds for refreshed page to load fully
5. Take new snapshot and recheck
6. Maximum 2 refresh attempts per Data Stream
7. If button still missing after 2 refreshes → Skip this Data Stream and continue

**🔄 General Retry Logic for Other Missing Elements**

For elements other than "Update File" button (e.g., Upload Files button, Deploy button):

**For Page-Level Elements:**
1. Take snapshot to verify page state
2. Refresh the current page using `browser_navigate` with current URL
3. Wait 5 seconds for page to fully reload
4. Take another snapshot to confirm page loaded correctly
5. Retry finding and clicking the element
6. If still not found → Skip this Data Stream and continue with next

**For Modal Elements (Upload Files button, Deploy button):**
1. Take snapshot to verify modal state
2. If button not found in modal:
   - Option A: Close modal and reopen by clicking Update File again
   - Option B: Wait 3-5 seconds and retry (element may still be loading)
3. Retry finding and clicking the element
4. If still not found → Skip this Data Stream and continue with next

**Maximum Retries:**
- Each element: 1 retry (total 2 attempts)
- Each Data Stream upload: Continue even if one step fails
- Overall workflow: Never fail completely - report all successes/failures at end

**When to Skip vs. Retry:**
- **Retry:** Element timing issues, page loading delays, modal animation delays
- **Skip:** Element truly doesn't exist, Data Stream not configured correctly, permissions issue

---

### Step 0 — Load Playwright tools

**CRITICAL: Load Playwright tool schemas before using them**

Use ToolSearch to load MCP Playwright tools:

```
ToolSearch(
  query: "select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_click,mcp__plugin_playwright_playwright__browser_snapshot,mcp__plugin_playwright_playwright__browser_take_screenshot,mcp__plugin_playwright_playwright__browser_type,mcp__plugin_playwright_playwright__browser_wait_for,mcp__plugin_playwright_playwright__browser_file_upload",
  max_results: 10
)
```

This loads all necessary Playwright tools for browser automation.

---

### Step 0.5 — Capability gate: verify `browser_file_upload` is exposed (Mac auto-install fallback)

**Why this step exists:** the file upload to Salesforce's hidden `<input type="file">` element requires the Playwright MCP `browser_file_upload` tool. Anthropic's standard `@playwright/mcp` exposes it. Some Salesforce-internal Playwright MCP mirrors (Falcon-distributed AISuite browser MCP, etc.) do not. Without it, every Step 5–8 upload will fail.

This gate fires automatically and behaves differently per platform:

| Platform | `browser_file_upload` exposed? | Behavior |
|---|---|---|
| **Windows** | ✅ Yes (standard case) | Skip silently, run Step 1 |
| **Windows** | ❌ No (rare — non-standard MCP) | Print one-line note, continue. Skill may fail later at Step 5 — user installs manually if so. **Do NOT auto-install on Windows.** |
| **macOS** | ✅ Yes (standard case) | Skip silently, run Step 1 |
| **macOS** | ❌ No (Falcon-distributed MCP) | Auto-install `@playwright/mcp` via `npx`, auto-merge config into Claude Code MCP config (preserves existing MCPs), STOP with restart instructions |
| **Linux** | ✅ Yes / ❌ No | Same as Windows — note only, no auto-install |

The Mac-only auto-install matches the agent-level check in [AGENT.md](../../agents/data360-retail-installer/AGENT.md) (Playwright MCP capability check block). When the agent runs the install end-to-end, the agent's check fires first; this skill-level check is a defense-in-depth fallback for cases where the skill is invoked directly without going through the agent.

**Detection (cross-platform, runs unconditionally):**

```
ToolSearch(query: "select:mcp__plugin_playwright_playwright__browser_file_upload", max_results: 1)
```

If the result includes the tool definition → continue to Step 1.
If the result is empty / "No matching deferred tools found" → run the platform-aware fallback below.

**Platform-aware fallback (only fires when the tool is missing):**

```bash
# Detect OS — uname -s returns Darwin on macOS, MINGW*/MSYS_NT*/CYGWIN* on Windows Git Bash, Linux on Linux.
OS_KIND="$(uname -s 2>/dev/null || echo unknown)"

case "$OS_KIND" in
  Darwin)
    # macOS — auto-install + auto-config + restart prompt
    echo "🍎 macOS detected, and your active Playwright MCP doesn't expose browser_file_upload."
    echo "   Auto-installing @playwright/mcp@latest — no manual command needed."
    echo ""

    # Verify Node.js is present
    if ! command -v node >/dev/null 2>&1; then
      echo "❌ Node.js is not installed. Install via:  brew install node"
      echo "   (or download from https://nodejs.org/ — LTS version)"
      echo "   Then re-run this skill."
      exit 1
    fi

    # Pre-cache via npx (no global install, no sudo)
    echo "📦 Pre-caching @playwright/mcp@latest..."
    npx -y @playwright/mcp@latest --version >/tmp/playwright_mcp_install.log 2>&1
    PRECACHE_RC=$?
    if [ "$PRECACHE_RC" -ne 0 ]; then
      echo "❌ npx pre-cache failed (exit $PRECACHE_RC). Log:"
      tail -20 /tmp/playwright_mcp_install.log
      echo ""
      echo "   Try manually: npm cache clean --force && npx -y @playwright/mcp@latest --version"
      exit 1
    fi
    echo "✅ Pre-cache complete."

    # Merge into Claude Code MCP config — preserves any existing MCPs (Falcon, AISuite, etc.)
    CLAUDE_CFG_DESKTOP="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    CLAUDE_CFG_CLI="$HOME/.claude/claude_desktop_config.json"

    merge_mcp_config() {
      local CFG_PATH="$1"
      mkdir -p "$(dirname "$CFG_PATH")"
      $PYTHON_CMD - "$CFG_PATH" <<'PYEOF'
import json, os, sys
cfg_path = sys.argv[1]
existing = {}
if os.path.isfile(cfg_path):
    try:
        with open(cfg_path, 'r') as f:
            existing = json.load(f)
    except Exception:
        os.rename(cfg_path, cfg_path + '.bak')
        existing = {}
existing.setdefault('mcpServers', {})
if 'playwright' in existing['mcpServers']:
    print(f"  ℹ️  playwright MCP already in {cfg_path}")
else:
    existing['mcpServers']['playwright'] = {
        'command': 'npx',
        'args': ['-y', '@playwright/mcp@latest']
    }
    with open(cfg_path, 'w') as f:
        json.dump(existing, f, indent=2)
    print(f"  ✅ Added playwright MCP to {cfg_path}")
PYEOF
    }

    merge_mcp_config "$CLAUDE_CFG_DESKTOP"
    merge_mcp_config "$CLAUDE_CFG_CLI"

    # Surface the one-time restart instruction (cannot be automated — MCP loads at Claude startup)
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    echo "  🎉  All set! Just one quick restart and you're back on track."
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    echo "  I installed and configured the Playwright MCP for you. Claude"
    echo "  Code only loads MCP servers at startup, so it needs to reload"
    echo "  once to pick up the new tool. After that, you'll never see this"
    echo "  message again."
    echo ""
    echo "  ▸ EASIEST WAY (VS Code):"
    echo ""
    echo "      1.  Press  Cmd + Shift + P"
    echo "      2.  Type:  Developer: Reload Window"
    echo "      3.  Press  Enter"
    echo ""
    echo "  Other ways, in case VS Code isn't how you launch Claude:"
    echo ""
    echo "    • Claude CLI in Terminal:  type 'exit' (or Ctrl+D), then re-run 'claude'"
    echo "    • Claude Desktop app:      Cmd+Q to fully quit, then re-launch from Applications"
    echo ""
    echo "  Once Claude is back up, just re-run:"
    echo "      /datastream-file-upload <org_alias>"
    echo ""
    echo "  This skill will detect the new tool, skip this gate silently,"
    echo "  and pick up the upload exactly where it left off — nothing lost."
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    exit 0
    ;;

  MINGW*|MSYS_NT*|CYGWIN*)
    # Windows: NO auto-install. Note only.
    echo "ℹ️  Windows: browser_file_upload not exposed by active Playwright MCP."
    echo "   Skill will try to proceed — if Step 5 fails with 'tool not available',"
    echo "   install manually:  npx -y @playwright/mcp@latest --version"
    echo "   Add to %APPDATA%\\Claude\\claude_desktop_config.json and restart Claude."
    ;;

  Linux)
    echo "ℹ️  Linux: browser_file_upload not exposed. Same guidance as Windows above."
    ;;

  *)
    echo "ℹ️  Unknown OS ($OS_KIND). Skipping auto-install."
    ;;
esac
```

**Net effect:**
- Windows users with the standard Playwright MCP: zero output, zero behavior change.
- Mac users with Falcon MCP: auto-installs in background, asks for one Claude Code restart, resumes cleanly.
- Mac users with the standard Playwright MCP: zero output, zero behavior change.
- All other failure modes: non-blocking warning, skill continues.

**No existing functionality is changed.** Steps 1–9 below run byte-identical to before. This step only adds a pre-flight detection that prevents the most common Mac-side failure.

---

### Step 1 — Verify CSV files exist locally

Check if all required CSV files exist in the files directory:

Default directory: `DIY Documents/DIY Documents`

Required files:
1. `Customer_Affinities 2.csv`
2. `Website Customer.csv`
3. `POS Customer.csv`
4. `Customer Engagement Feed.csv`

Run bash commands to verify:

```bash
test -f "DIY Documents/DIY Documents/Customer_Affinities 2.csv"
test -f "DIY Documents/DIY Documents/Website Customer.csv"
test -f "DIY Documents/DIY Documents/POS Customer.csv"
test -f "DIY Documents/DIY Documents/Customer Engagement Feed.csv"
```

List files to confirm:

```bash
ls -lh "DIY Documents/DIY Documents/"*.csv
```

**If any file is missing:**
- Report which files are missing
- Ask user to download missing files from GitHub: https://github.com/salesforce-misc/Data360AgentforceSolutionKitRetail/tree/master/DIY%20Documents
- Cannot proceed without all files

---

### Step 2 — Query Data Stream Record IDs using SOQL

**✅ NEW APPROACH: Query Data Stream IDs directly instead of searching in UI**

**Step 2.1: Create temporary SOQL query file**

```bash
cat > query_datastreams.soql << 'EOF'
SELECT Id, Name FROM DataStream WHERE (Name LIKE 'Customer_Affinities%' OR Name LIKE 'Customer_Engagement_Feed%' OR Name LIKE 'POS_Customer%' OR Name LIKE 'Website_Customer%') OR Name IN ('Customer Affinities', 'Website Customer', 'POS Customer', 'Customer Engagement Feed')
EOF
```

**Why both LIKE and IN clauses?** Salesforce sometimes ships the data kit's Data Stream `Name` field with the underscore-separated developer-name form (e.g. `Customer_Affinities`, `Customer_Engagement_Feed_v2`) and sometimes with the spaced label form (e.g. `Customer Affinities`). The `LIKE` patterns cover any underscore-prefixed variant including version suffixes; the `IN` clause covers the spaced literal variant. Single round-trip handles both shapes — no retry needed if the kit's naming convention drifts between versions.

**Step 2.2: Run SOQL query using the file**

```bash
sf data query --target-org <org_alias> --file query_datastreams.soql --json
```

**Why use --file instead of --query?**
- ✅ Avoids Windows command-line escaping issues with quotes
- ✅ More reliable across different shell environments
- ✅ Cleaner syntax for complex queries

**Parse JSON response to extract:**

| Data Stream Name | Field to Extract | Store As |
|---|---|---|
| Customer Affinities | `result.records[].Id` | `CUSTOMER_AFFINITIES_ID` |
| Website Customer | `result.records[].Id` | `WEBSITE_CUSTOMER_ID` |
| POS Customer | `result.records[].Id` | `POS_CUSTOMER_ID` |
| Customer Engagement Feed | `result.records[].Id` | `CUSTOMER_ENGAGEMENT_ID` |

**Example response:**
```json
{
  "status": 0,
  "result": {
    "records": [
      {"Id": "1dsHu000000HmluIAC", "Name": "Customer Affinities"},
      {"Id": "1dsHu000000HmlxIAC", "Name": "Website Customer"},
      {"Id": "1dsHu000000HmlvIAC", "Name": "POS Customer"},
      {"Id": "1dsHu000000HmlwIAC", "Name": "Customer Engagement Feed"}
    ]
  }
}
```

**If query fails or returns no records:**
- Report error: "Data Streams not found in org"
- Check if Data Kit metadata deployment completed (Step 3)
- Check if Data Kit API deployment completed (Step 4)
- Cannot proceed without Data Stream IDs

**Store these IDs for Step 5-8 navigation.**

---

### Step 3 — Get org credentials

**CRITICAL: Get instance URL and access token from Salesforce CLI**

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

### Step 4 — Launch browser and authenticate

**Use Playwright to open browser and navigate to org with the CLI access token**

Navigate via the frontdoor URL (auto-logs in using the existing CLI web session — no password prompt):

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}"
)
```

If the page redirects to a login form, the CLI session has expired. Stop and ask the user to run `sf org login web -a <org_alias>` again.

(No explicit wait — Step 4.5's `evaluate()` call auto-waits for the page to be in a state where `window.$A` is defined. That's the real gate; an arbitrary 3-5s sleep is just a guess.)

**✅ No need to navigate to Data Streams list - we'll use direct URLs with Record IDs from Step 2**

---

### Step 4.5 — Install Aura-layer payload interceptor (REQUIRED — fixes Salesforce restriction)

**🛠️ This step is what makes the Deploy click actually work.**

#### Why this step exists

When the user clicks **Deploy** inside the "Update Data Stream from a File" modal, the Lightning Web Component POSTs to `/aura?...aura.CdpDataStreams.patchUpdateDatastream=1`. The body is form-urlencoded — `message=<URL-encoded JSON>` — and the JSON contains an `advancedAttributes` block with two keys Salesforce now rejects for File-Upload data streams:

- `isDataStreamConfigValid`
- `delimiter`

The server returns:
```
Unable to update the data-stream - Advanced Attribute key
isDataStreamConfigValid cannot be patched for data streams
created using Uploaded Files connection
```

Salesforce's official workaround is "open DevTools and `delete e.input.advancedAttributes.isDataStreamConfigValid` before clicking Deploy." This step does that **programmatically** — wraps `XMLHttpRequest.send` and `window.fetch` so any outgoing request body that contains those keys gets sanitized in flight, regardless of how the LWC sends it.

#### Why other approaches DON'T work (validated against this org)

| Approach tried | Status flag | Data ingested? | Verdict |
|---|---|---|---|
| **Path A — Aura-layer interceptor (this step)** | ✅ Active | ✅ Yes | **Use this.** Lets the real Aura controller run end-to-end. |
| Path B — capture failed Aura POST + replay sanitized | ✅ Active | ❌ No | The replay flips the cosmetic status flag but skips the ingestion-job-submission code path inside the Aura controller |
| Path D — Playwright file upload + Connect REST PATCH `/services/data/v66.0/ssot/data-streams/{id}` | ✅ Active | ❌ No | Same problem as Path B — the public REST PATCH endpoint flips the flag but doesn't trigger the lakehouse ingestion job |

The pattern is unambiguous: **only Path A actually ingests the data**. Paths B and D pass the "status shows Active" smoke test but leave the DLO empty.

#### Install the interceptor — ONE evaluate() call before any modal interaction

Run this **once after Step 4 (home page)** AND **once after EVERY `browser_navigate` to a Data Stream record page in Steps 5–8**. The interceptor is idempotent — re-installing it is a no-op.

**🚨 OBSERVED FAILURE (2026-06-11, OrgRetailTest35) — interceptor MUST be reinstalled per record page.** The previous claim that "the interceptor lives in the page's window object and survives navigations within the same tab" is **wrong** for Lightning Experience. Each `browser_navigate` to `/lightning/r/DataStream/{id}/view` swaps the active iframe / page-window context, and `window.__dsAuraInterceptorInstalled` is `false` again on the new page. The XHR wrapper installed on the previous page does NOT cover the LWC that issues the `/aura?...patchUpdateDatastream=1` request from the new record page.

**Real-world consequence:** The first Customer Affinities Deploy click fired with the interceptor installed only on the Q Branch home page (the post-frontdoor landing). The DataStream record page had a fresh, unwrapped `XMLHttpRequest`. Salesforce rejected the request with `"Unable to update the data-stream - Advanced Attribute key delimiter cannot be patched for data streams created using Uploaded Files connection"`. After reinstalling the interceptor on the DataStream record page itself, the retry Deploy succeeded with `capturedCount: 1, kind: "xhr.aura-message", stripped: true`.

**Required pattern:**

1. After Step 4 (frontdoor → home page) → run the interceptor `evaluate()` once. Treat this as a sanity install only; do NOT rely on it covering downstream Deploy clicks.
2. **At the START of every per-stream block (Steps 5.1, 6.1, 7.1, 8.1) — immediately after `browser_navigate` to the record page and `wait_for(time:5)`** — re-run the interceptor `evaluate()`. Use this short reinstall snippet (the long version with all 3 hooks is overkill; only the `XMLHttpRequest.send` hook is load-bearing because the LWC's POST goes through XHR):

   ```javascript
   () => {
     // Force-reinstall — Lightning SPA navigation swaps page context, so the
     // previous record's interceptor doesn't cover this one.
     delete window.__dsAuraInterceptorInstalled;
     window.__dsAuraCaptured = [];
     function sanitizeObj(node) {
       if (!node || typeof node !== 'object') return false;
       let changed = false;
       if (Array.isArray(node)) { for (let i=0;i<node.length;i++) if (sanitizeObj(node[i])) changed=true; return changed; }
       if (node.advancedAttributes && typeof node.advancedAttributes === 'object') {
         if ('isDataStreamConfigValid' in node.advancedAttributes) { delete node.advancedAttributes.isDataStreamConfigValid; changed=true; }
         if ('delimiter' in node.advancedAttributes) { delete node.advancedAttributes.delimiter; changed=true; }
       }
       for (const k of Object.keys(node)) if (sanitizeObj(node[k])) changed=true;
       return changed;
     }
     const _origSend = XMLHttpRequest.prototype.send;
     const _origOpen = XMLHttpRequest.prototype.open;
     XMLHttpRequest.prototype.open = function(method,url){ this.__dsMethod=method; this.__dsUrl=url; return _origOpen.apply(this, arguments); };
     XMLHttpRequest.prototype.send = function(body) {
       try {
         if (typeof body === 'string' && (body.includes('isDataStreamConfigValid') || body.includes('delimiter'))) {
           if (body.startsWith('message=')) {
             const m = body.match(/^message=([^&]*)/);
             if (m) {
               const decoded = decodeURIComponent(m[1]);
               const obj = JSON.parse(decoded);
               if (sanitizeObj(obj)) {
                 body = 'message=' + encodeURIComponent(JSON.stringify(obj)) + body.slice(m[0].length);
                 window.__dsAuraCaptured.push({ kind: 'xhr.aura-message', stripped: true });
               }
             }
           }
         }
       } catch (e) {}
       return _origSend.call(this, body);
     };
     window.__dsAuraInterceptorInstalled = true;
     return { reinstalled: true };
   }
   ```

3. **After EVERY Deploy click**, verify with the read-only check (`capturedCount > 0`, `kind: "xhr.aura-message"`, `stripped: true`). If `capturedCount === 0`, the interceptor was missing — STOP, do NOT navigate to the next stream, and surface the failure: data did not strip and the server-side rejection will appear shortly after with the "delimiter cannot be patched" error.

**Do NOT close the browser between Data Streams** — that part is still correct. The reinstall is fast (<50 ms) and runs entirely client-side; reusing the same browser session keeps your CLI auth + frontdoor login intact.

```
mcp__plugin_playwright_playwright__browser_evaluate
  function: "() => { /* Aura interceptor — see code below */ }"
  element: "install Aura-layer interceptor that strips isDataStreamConfigValid + delimiter from advancedAttributes"
```

**Interceptor code (paste verbatim into the `function` argument):**

```javascript
() => {
  if (window.__dsAuraInterceptorInstalled) {
    return { alreadyInstalled: true, captured: window.__dsAuraCaptured || [] };
  }
  window.__dsAuraCaptured = [];

  function sanitizeObj(node) {
    if (!node || typeof node !== 'object') return false;
    let changed = false;
    if (Array.isArray(node)) {
      for (let i = 0; i < node.length; i++) {
        if (sanitizeObj(node[i])) changed = true;
      }
      return changed;
    }
    if (node.advancedAttributes && typeof node.advancedAttributes === 'object') {
      if ('isDataStreamConfigValid' in node.advancedAttributes) {
        delete node.advancedAttributes.isDataStreamConfigValid;
        changed = true;
      }
      if ('delimiter' in node.advancedAttributes) {
        delete node.advancedAttributes.delimiter;
        changed = true;
      }
    }
    for (const k of Object.keys(node)) {
      if (sanitizeObj(node[k])) changed = true;
    }
    return changed;
  }

  // ---- Hook 1: $A.enqueueAction (top-level Aura action queue) ----
  if (window.$A && typeof window.$A.enqueueAction === 'function') {
    const _origEnqueue = window.$A.enqueueAction.bind(window.$A);
    window.$A.enqueueAction = function(action) {
      try {
        if (action && typeof action.getParams === 'function') {
          const params = action.getParams();
          if (params && sanitizeObj(params)) {
            window.__dsAuraCaptured.push({ kind: 'aura.enqueueAction', stripped: true });
          }
        }
      } catch (e) {}
      return _origEnqueue(action);
    };
  }

  // ---- Hook 2: window.fetch ----
  const _origFetch = window.fetch.bind(window);
  window.fetch = async function(input, init) {
    try {
      if (init && typeof init.body === 'string') {
        const url = (typeof input === 'string' ? input : (input && input.url) || '');
        if (init.body.includes('isDataStreamConfigValid') || init.body.includes('delimiter')) {
          // Plain JSON body
          try {
            const obj = JSON.parse(init.body);
            if (sanitizeObj(obj)) {
              init = { ...init, body: JSON.stringify(obj) };
              window.__dsAuraCaptured.push({ kind: 'fetch', url: url.split('?')[0], stripped: true });
            }
          } catch (e) {}
          // Aura form-urlencoded `message=<encoded JSON>`
          if (init.body.startsWith('message=')) {
            try {
              const m = init.body.match(/^message=([^&]*)/);
              if (m) {
                const decoded = decodeURIComponent(m[1]);
                if (decoded.includes('isDataStreamConfigValid') || decoded.includes('delimiter')) {
                  const msgObj = JSON.parse(decoded);
                  if (sanitizeObj(msgObj)) {
                    const newBody = 'message=' + encodeURIComponent(JSON.stringify(msgObj)) + init.body.slice(m[0].length);
                    init = { ...init, body: newBody };
                    window.__dsAuraCaptured.push({ kind: 'fetch.aura-message', url: url.split('?')[0], stripped: true });
                  }
                }
              }
            } catch (e) {}
          }
        }
      }
    } catch (e) {}
    return _origFetch(input, init);
  };

  // ---- Hook 3: XMLHttpRequest.send (the actual transport the LWC uses) ----
  const _origSend = XMLHttpRequest.prototype.send;
  const _origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.__dsMethod = method;
    this.__dsUrl = url;
    return _origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function(body) {
    try {
      if (typeof body === 'string') {
        if (body.includes('isDataStreamConfigValid') || body.includes('delimiter')) {
          if (body.startsWith('message=')) {
            try {
              const m = body.match(/^message=([^&]*)/);
              if (m) {
                const decoded = decodeURIComponent(m[1]);
                const msgObj = JSON.parse(decoded);
                if (sanitizeObj(msgObj)) {
                  body = 'message=' + encodeURIComponent(JSON.stringify(msgObj)) + body.slice(m[0].length);
                  window.__dsAuraCaptured.push({
                    kind: 'xhr.aura-message',
                    url: (this.__dsUrl || '').split('?')[0],
                    stripped: true,
                  });
                }
              }
            } catch (e) {}
          } else {
            try {
              const obj = JSON.parse(body);
              if (sanitizeObj(obj)) {
                body = JSON.stringify(obj);
                window.__dsAuraCaptured.push({ kind: 'xhr', url: (this.__dsUrl || '').split('?')[0], stripped: true });
              }
            } catch (e) {}
          }
        }
      }
    } catch (e) {}
    return _origSend.call(this, body);
  };

  window.__dsAuraInterceptorInstalled = true;
  return { installed: true };
}
```

#### Verify the interceptor installed correctly

After the `evaluate()` call returns, the result must be `{ "installed": true }` (first run) or `{ "alreadyInstalled": true, ... }` (re-runs). If it's anything else, ABORT and surface the error to the user — proceeding without a working interceptor will cause every Deploy click to fail.

#### Verify the interceptor actually fired (after each Deploy click)

After each Data Stream's Deploy click in Steps 5–8, optionally run this read-only `evaluate()` to confirm a request was stripped:

```javascript
() => ({
  capturedCount: (window.__dsAuraCaptured || []).length,
  lastEntry: (window.__dsAuraCaptured || []).slice(-1)[0],
})
```

For a successful Deploy you should see `kind: "xhr.aura-message"` and `url: "/aura"` in the most recent entry. If `capturedCount` is 0 after a Deploy click, the interceptor missed the request — surface the error and STOP (the upload won't actually ingest data).

---

### Step 5 — Upload Customer_Affinities 2.csv

**5.1 Navigate directly to Customer Affinities Data Stream using Record ID**

**✅ NEW APPROACH: Direct URL navigation using SOQL query result from Step 2**

Navigate directly to the Data Stream record page:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{CUSTOMER_AFFINITIES_ID}/view"
)
```

Example:
```
https://storm-bf19b84cbeeb48.lightning.force.com/lightning/r/DataStream/1dsHu000000HmluIAC/view
```

Wait for Data Stream detail page to load (3 seconds):

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 3
)
```

**Benefits of direct navigation:**
- ✅ No UI search required
- ✅ Instant page load
- ✅ No timing issues with search results
- ✅ Reliable and fast

**5.1.1 — IMMEDIATE BLANK-PAGE CHECK: Verify Update File button is visible (auto-refresh if missing)**

🚨 **CRITICAL:** Salesforce occasionally renders a blank/incomplete page on first navigation. Verify the "Update File" button is present BEFORE proceeding. If it is not, IMMEDIATELY refresh the page once (no waiting, no retry chain — refresh first, then check again).

Take snapshot to check if "Update File" button is rendered:

```
mcp__plugin_playwright_playwright__browser_snapshot()
```

**If "Update File" button NOT visible in snapshot (blank page detected):**

```
🔄 Blank page detected - Update File button not found. Refreshing page immediately...
```

Refresh the page IMMEDIATELY:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{CUSTOMER_AFFINITIES_ID}/view"
)
```

Wait 5 seconds for the refreshed page to fully load:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 5
)
```

Take another snapshot to confirm "Update File" button is now visible:

```
mcp__plugin_playwright_playwright__browser_snapshot()
```

**If still not visible after immediate refresh:**
- Refresh ONE more time (max 2 refresh attempts)
- Wait 5 seconds
- If still not visible → Report error and skip this Data Stream

**If "Update File" button IS visible:**
- ✅ Page rendered correctly, proceed to Step 5.2

**5.2 Click Update File button**

Click the now-visible Update File button:

```
mcp__plugin_playwright_playwright__browser_click(
  selector: "button:has-text('Update File')"
)
```

**If click fails (rare — button was visible but click intercepted):**
- Refresh page immediately
- Wait 5 seconds
- Retry click once
- If still fails → Skip this Data Stream and continue with next upload

Wait for file selection dialog to appear:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  selector: "input[type='file']",
  timeout: 5000
)
```

**5.3 Refresh Mode — DO NOT click anything; proceed straight to Upload Files**

✅ Salesforce ships this modal with **Full Refresh preselected** (FULL_REFRESH card carries `aria-checked="true"`; the UPSERT card carries `aria-checked="false"`). For the data360 retail install we keep that default — **skip mode selection entirely** and go directly to step 5.4 (Upload Files).

(Earlier skill versions instructed clicking the Upsert card with mandatory `aria-checked` post-click verification. That guidance has been retired. Operator preference is **Full Refresh by default** because:
- Faster ingestion vs. Upsert,
- One fewer click (no race condition between the mode toggle and the file chooser),
- The modal's default state is already correct, so the click was always cosmetic.

If a future variant ever needs to read or change the mode, the deterministic anchors are still `[data-tid="UPSERT"]` and `[data-tid="FULL_REFRESH"]` on the `<runtime_cdp-data-stream-extended-data-source>` host elements — but no clicks are required during a normal run.)

**5.4 Upload Customer_Affinities 2.csv**

**✅ WORKING SOLUTION (Validated 2026-05-25):**

**CRITICAL: Click on the visible "Upload Files" text to trigger file chooser**

**🔄 RETRY LOGIC: Try multiple selectors, if all fail, refresh modal and retry**

Try multiple fallback selectors in order:

**Attempt 1 - Label selector (most reliable):**
```
mcp__plugin_playwright_playwright__browser_click(
  target: "label:has-text('Upload Files')",
  element: "Upload Files label"
)
```

**If that fails, try Attempt 2 - Text selector:**
```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Upload Files",
  element: "Upload Files button"
)
```

**If both fail:**
1. Take snapshot to debug the modal state
2. Close the modal by clicking Cancel/Close button
3. Wait 2 seconds
4. Re-click "Update File" button to reopen modal
5. Wait 2 seconds for modal to load
6. Retry clicking "Upload Files" using label selector

**If still fails after modal refresh:**
- Report error: "Unable to click Upload Files button"
- Skip this Data Stream and continue with next upload
- Mark as failed in final summary

**Important:** Do NOT try to click the hidden `input[type="file"]` element directly - it will timeout due to label overlay intercepting pointer events. Always click on the visible "Upload Files" text or label element.

The file chooser will now open and be ready for file upload.

Upload the CSV file using relative path:

```
mcp__plugin_playwright_playwright__browser_file_upload(
  paths: ["DIY Documents/DIY Documents/Customer_Affinities 2.csv"]
)
```

**Note:** Use relative paths from the project root. Absolute paths outside the project directory will be rejected by MCP security policies.

**🚨 CRITICAL: Handle File Access Denied Errors**

If the file upload fails with "access denied" or permission errors:

1. **Close the browser immediately:**
   ```
   mcp__plugin_playwright_playwright__browser_close()
   ```

2. **Wait 5 seconds for cleanup:**
   ```
   bash: sleep 5
   ```

3. **Restart from Step 3 (Launch browser):**
   - Re-launch browser
   - Re-authenticate
   - Navigate back to Data Streams
   - Retry the upload from the beginning

This resolves file permission locks that can occur during browser automation.

(No explicit wait — the next click on the existing-model dropdown auto-waits for the model UI to appear. That UI only renders once upload is fully complete, so it's a meaningful gate. No success-path screenshot — only screenshot on failure.)

**Technical Notes:**

**Why Data Streams don't have REST API (Investigation Results):**
- ❌ Standard REST API: `/services/data/v66.0/sobjects/ssot__DataStream__c` - NOT SUPPORTED
- ❌ Connect API: `/services/data/v66.0/connect/data-cloud` - NOT FOUND
- ❌ Einstein API: `/services/data/v66.0/einstein/data-streams` - NOT FOUND

**Key Difference from Agentforce Data Library:**
- **Data Libraries**: Have REST API endpoint → Can use curl with presigned S3 URLs
- **Data Streams**: NO REST API → Must use browser automation via Playwright MCP

**How Browser Automation Works:**
- Lightning Web Components hide `<input type="file">` elements behind label overlays
- **Solution:** Click the visible "Upload Files" text (not the hidden input)
- Playwright can then interact with the opened file chooser
- File upload completes successfully via `browser_file_upload` tool

**5.5 Select Existing Model**

🆕 **NEW STEP:** After the file upload completes (and BEFORE clicking Deploy), select the existing model that matches the Data Stream.

For **Customer Affinities** Data Stream → select existing model whose name matches the Data Stream name pattern (e.g., `Customer_Affinities`).

Take a snapshot to locate the model selection UI:

```
mcp__plugin_playwright_playwright__browser_snapshot()
```

Click the "Select Existing Model" radio/option (if a choice between New/Existing model is shown):

```
mcp__plugin_playwright_playwright__browser_click(
  target: "label:has-text('Select Existing Model'), input[type='radio'][value='existing'], lightning-radio-group label:has-text('Existing')",
  element: "Select Existing Model option"
)
```

Wait for the existing-model dropdown to populate:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 2
)
```

Open the existing-model combobox:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "combobox[aria-label*='Existing Model' i], combobox[aria-label*='Model' i], lightning-combobox button",
  element: "Existing Model dropdown"
)
```

Pick the model whose name matches the Data Stream name pattern (`Customer_Affinities` for the Customer Affinities Data Stream). Try matching by closest name:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "lightning-base-combobox-item:has-text('Customer_Affinities'), [role='option']:has-text('Customer_Affinities'), [role='option']:has-text('Customer Affinities')",
  element: "Customer_Affinities existing model option"
)
```

**Naming pattern reference per Data Stream:**

| Data Stream | Existing Model Name Pattern |
|---|---|
| Customer Affinities | `Customer_Affinities` |
| Website Customer | `Website_Customer` |
| POS Customer | `POS_Customer` |
| Customer Engagement Feed | `Customer_Engagement_Feed` |

Wait 1 second for the selection to register:

```
mcp__plugin_playwright_playwright__browser_wait_for(
  time: 1
)
```

**Retry logic:**
- If matching model not found in dropdown → snapshot, log available options, pick the closest fuzzy match (case-insensitive, ignore spaces/underscores)
- If no existing model option exists at all → log warning and proceed with default
- Max 1 retry per element

**5.6 Click Deploy button**

**🛠️ INTERCEPTOR PRECONDITION:** The Aura-layer interceptor from **Step 4.5** MUST be **(re)installed on THIS Data Stream's record page** before this click. The home-page install does NOT survive `browser_navigate` to `/lightning/r/DataStream/{id}/view` — Lightning swaps the page-window context. If `window.__dsAuraInterceptorInstalled === false` at this point, the Deploy click will fail server-side with `"Advanced Attribute key delimiter cannot be patched for data streams created using Uploaded Files connection"`. Per Step 4.5's required pattern, run the short reinstall `evaluate()` immediately after navigating to this record page (Step 5.1) — well before reaching this click. After clicking Deploy, verify with `window.__dsAuraCaptured.length > 0` and `lastEntry.kind === 'xhr.aura-message'`. If `capturedCount === 0`, the interceptor was missing — STOP and re-run the reinstall + Deploy retry. (See Step 4.5 for the full rationale and code.)

**🔄 RETRY LOGIC: If Deploy button not found or disabled, wait and retry**

Click the Deploy button to start file processing:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Deploy')",
  element: "Deploy button"
)
```

**If button click fails (timeout or not found):**
1. Take snapshot to check button state
2. Check if button is disabled (file upload may not have completed)
3. Wait 5 seconds for file upload to complete
4. Try clicking Deploy button again
5. If still fails, report error and skip this Data Stream

(No explicit wait — Playwright auto-waits before the next `browser_navigate` to Step 6. Salesforce processes the data ingestion server-side after Deploy returns; the skill does not need to babysit it.)

**5.7 Verify deployment**

The modal will close and you'll return to the Data Stream page. The file will be processed asynchronously.

**Important:** Do NOT wait for processing to complete in the browser - it can take several minutes. The deployment has started successfully once the Deploy button is clicked and the modal closes.

Report:
```text
✅ Customer_Affinities 2.csv uploaded successfully
   Data Stream: Customer Affinities
   File: Customer_Affinities 2.csv
   Status: Deployed
```

**No need to navigate back to list - proceed directly to next Data Stream using its Record ID**

---

### Step 6 — Upload Website Customer.csv

**6.1 Navigate directly to Website Customer Data Stream using Record ID**

Navigate directly using SOQL query result from Step 2:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{WEBSITE_CUSTOMER_ID}/view"
)
```

(Playwright auto-waits for the page to load — no explicit `wait_for(time: N)` needed. If the next click times out, that's the signal the page is genuinely slow; don't pre-emptively burn 3 s on every navigate.)

**6.1.1 — IMMEDIATE BLANK-PAGE CHECK**

Take snapshot and check if "Update File" button is visible:

```
mcp__plugin_playwright_playwright__browser_snapshot()
```

**If "Update File" button NOT visible (blank page):**

```
🔄 Blank page detected on Website Customer record. Refreshing immediately...
```

Refresh page IMMEDIATELY:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{WEBSITE_CUSTOMER_ID}/view"
)
```

Wait 5 seconds and re-snapshot. Max 2 refresh attempts. If still missing, skip this Data Stream.

**6.2 Click Update File button**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Update File')",
  element: "Update File button"
)
```

(No explicit wait — the next click on `Upload Files` auto-waits for the modal to render.)

**6.3 Refresh Mode** — keep the default (Full Refresh). **No click required.** See Step 5.3. Proceed straight to 6.4.

**6.4 Upload Website Customer.csv**

Click "Upload Files":

```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Upload Files",
  element: "Upload Files button"
)
```

Upload file:

```
mcp__plugin_playwright_playwright__browser_file_upload(
  paths: ["DIY Documents/DIY Documents/Website Customer.csv"]
)
```

(No explicit wait — the next action — clicking the existing-model option — auto-waits for the model UI to appear, which is the real signal that upload finished.)

**6.5 Select Existing Model = `Website_Customer`** 🆕

After upload completes, select the existing model matching the Data Stream:

```
mcp__plugin_playwright_playwright__browser_click(
  target: "label:has-text('Select Existing Model'), input[type='radio'][value='existing']",
  element: "Select Existing Model option"
)

mcp__plugin_playwright_playwright__browser_click(
  target: "combobox[aria-label*='Model' i], lightning-combobox button",
  element: "Existing Model dropdown"
)

mcp__plugin_playwright_playwright__browser_click(
  target: "[role='option']:has-text('Website_Customer'), [role='option']:has-text('Website Customer')",
  element: "Website_Customer existing model option"
)

```

(See Step 5.5 for full retry logic and naming pattern reference.)

**6.6 Click Deploy button**

**🛠️ INTERCEPTOR PRECONDITION:** The Aura-layer interceptor MUST be **reinstalled on this Website Customer record page** (per Step 4.5's required pattern). Lightning's `browser_navigate` between record pages drops the previous page's wrapped XHR; trusting the prior install will produce the "Advanced Attribute key delimiter cannot be patched" error. Run the short reinstall `evaluate()` from Step 6.1 BEFORE this click. After Deploy, verify `__dsAuraCaptured.length > 0` and `lastEntry.kind === 'xhr.aura-message'` — `capturedCount === 0` means missing interceptor; STOP and reinstall + retry.

```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Deploy",
  element: "Deploy button"
)
```

(No explicit wait — the next action is `browser_navigate` to the next Data Stream's record page, which auto-waits. Don't pre-emptively wait 3 s.)

Report:
```text
✅ Website Customer.csv uploaded successfully
   Data Stream: Website Customer
   File: Website Customer.csv
   Status: Deployed
```

---

### Step 7 — Upload POS Customer.csv

**7.1 Navigate directly to POS Customer Data Stream using Record ID**

Navigate directly using SOQL query result from Step 2:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{POS_CUSTOMER_ID}/view"
)
```

(Playwright auto-waits for the page to load — no explicit `wait_for(time: N)` needed. If the next click times out, that's the signal the page is genuinely slow; don't pre-emptively burn 3 s on every navigate.)

**7.1.1 — IMMEDIATE BLANK-PAGE CHECK**

Take snapshot and check if "Update File" button is visible:

```
mcp__plugin_playwright_playwright__browser_snapshot()
```

**If "Update File" button NOT visible (blank page):**

```
🔄 Blank page detected on POS Customer record. Refreshing immediately...
```

Refresh page IMMEDIATELY:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{POS_CUSTOMER_ID}/view"
)
```

Wait 5 seconds and re-snapshot. Max 2 refresh attempts. If still missing, skip this Data Stream.

**7.2 Click Update File button**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Update File')",
  element: "Update File button"
)
```

(No explicit wait — the next click on `Upload Files` auto-waits for the modal to render.)

**7.3 Refresh Mode** — keep the default (Full Refresh). **No click required.** See Step 5.3. Proceed straight to 7.4.

**7.4 Upload POS Customer.csv**

Click "Upload Files":

```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Upload Files",
  element: "Upload Files button"
)
```

Upload file:

```
mcp__plugin_playwright_playwright__browser_file_upload(
  paths: ["DIY Documents/DIY Documents/POS Customer.csv"]
)
```

(No explicit wait — the next action — clicking the existing-model option — auto-waits for the model UI to appear, which is the real signal that upload finished.)

**7.5 Select Existing Model = `POS_Customer`** 🆕

```
mcp__plugin_playwright_playwright__browser_click(
  target: "label:has-text('Select Existing Model'), input[type='radio'][value='existing']",
  element: "Select Existing Model option"
)

mcp__plugin_playwright_playwright__browser_click(
  target: "combobox[aria-label*='Model' i], lightning-combobox button",
  element: "Existing Model dropdown"
)

mcp__plugin_playwright_playwright__browser_click(
  target: "[role='option']:has-text('POS_Customer'), [role='option']:has-text('POS Customer')",
  element: "POS_Customer existing model option"
)

```

(See Step 5.5 for full retry logic.)

**7.6 Click Deploy button**

**🛠️ INTERCEPTOR PRECONDITION:** The Aura-layer interceptor MUST be **reinstalled on this POS Customer record page** (per Step 4.5's required pattern). Each `browser_navigate` to a new DataStream record drops the previous page's wrapped XHR. Run the short reinstall `evaluate()` from Step 7.1 BEFORE this click. After Deploy, verify `__dsAuraCaptured.length > 0` and `lastEntry.kind === 'xhr.aura-message'`. If `capturedCount === 0`, STOP and reinstall + retry.

```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Deploy",
  element: "Deploy button"
)
```

(No explicit wait — the next action is `browser_navigate` to the next Data Stream's record page, which auto-waits. Don't pre-emptively wait 3 s.)

Report:
```text
✅ POS Customer.csv uploaded successfully
   Data Stream: POS Customer
   File: POS Customer.csv
   Status: Deployed
```

---

### Step 8 — Upload Customer Engagement Feed.csv

**8.1 Navigate directly to Customer Engagement Feed Data Stream using Record ID**

Navigate directly using SOQL query result from Step 2:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{CUSTOMER_ENGAGEMENT_ID}/view"
)
```

(Playwright auto-waits for the page to load — no explicit `wait_for(time: N)` needed. If the next click times out, that's the signal the page is genuinely slow; don't pre-emptively burn 3 s on every navigate.)

**8.1.1 — IMMEDIATE BLANK-PAGE CHECK**

Take snapshot and check if "Update File" button is visible:

```
mcp__plugin_playwright_playwright__browser_snapshot()
```

**If "Update File" button NOT visible (blank page):**

```
🔄 Blank page detected on Customer Engagement Feed record. Refreshing immediately...
```

Refresh page IMMEDIATELY:

```
mcp__plugin_playwright_playwright__browser_navigate(
  url: "{instanceUrl}/lightning/r/DataStream/{CUSTOMER_ENGAGEMENT_ID}/view"
)
```

Wait 5 seconds and re-snapshot. Max 2 refresh attempts. If still missing, skip this Data Stream.

**8.2 Click Update File button**

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Update File')",
  element: "Update File button"
)
```

(No explicit wait — the next click on `Upload Files` auto-waits for the modal to render.)

**8.3 Refresh Mode** — keep the default (Full Refresh). **No click required.** See Step 5.3. Proceed straight to 8.4.

**8.4 Upload Customer Engagement Feed.csv**

Click "Upload Files":

```
mcp__plugin_playwright_playwright__browser_click(
  target: "text=Upload Files",
  element: "Upload Files button"
)
```

Upload file:

```
mcp__plugin_playwright_playwright__browser_file_upload(
  paths: ["DIY Documents/DIY Documents/Customer Engagement Feed.csv"]
)
```

(No explicit wait — the next action — clicking the existing-model option — auto-waits for the model UI to appear, which is the real signal that upload finished.)

**8.5 Select Existing Model = `Customer_Engagement_Feed`** 🆕

```
mcp__plugin_playwright_playwright__browser_click(
  target: "label:has-text('Select Existing Model'), input[type='radio'][value='existing']",
  element: "Select Existing Model option"
)

mcp__plugin_playwright_playwright__browser_click(
  target: "combobox[aria-label*='Model' i], lightning-combobox button",
  element: "Existing Model dropdown"
)

mcp__plugin_playwright_playwright__browser_click(
  target: "[role='option']:has-text('Customer_Engagement_Feed'), [role='option']:has-text('Customer Engagement Feed')",
  element: "Customer_Engagement_Feed existing model option"
)

```

(See Step 5.5 for full retry logic.)

**8.6 Click Deploy button**

**🛠️ INTERCEPTOR PRECONDITION:** The Aura-layer interceptor MUST be **reinstalled on this Customer Engagement Feed record page** (per Step 4.5's required pattern). This is the 4th and final Data Stream — same browser session throughout, but Lightning's per-record page-context swap means the interceptor must be re-run after the navigation in Step 8.1, BEFORE this click. After Deploy, verify `__dsAuraCaptured.length > 0` and `lastEntry.kind === 'xhr.aura-message'`. If `capturedCount === 0`, STOP and reinstall + retry.

```
mcp__plugin_playwright_playwright__browser_click(
  target: "button:has-text('Deploy')",
  element: "Deploy button"
)
```

(No explicit wait — the next action is `browser_navigate` to the next Data Stream's record page, which auto-waits. Don't pre-emptively wait 3 s.)

Report:
```text
✅ Customer Engagement Feed.csv uploaded successfully
   Data Stream: Customer Engagement Feed
   File: Customer Engagement Feed.csv
   Status: Deployed
```

---

### Step 9 — Close browser and cleanup

**Step 9.1: Close the browser**

```
mcp__plugin_playwright_playwright__browser_close()
```

**Step 9.2: Delete temporary SOQL query file**

**IMPORTANT: Clean up the temporary file created in Step 2**

```bash
rm query_datastreams.soql
```

This removes the temporary SOQL query file to keep the workspace clean.

**Step 9.3: Generate final report**

```text
📤 Data Stream File Upload Complete!

Org: <org_alias>
Instance: {instanceUrl}

═══════════════════════════════════════════════════

📁 Files Uploaded:

1. ✅ Customer Affinities
   File: Customer_Affinities 2.csv
   Data Stream: Customer Affinities
   Status: Deployed
   
2. ✅ Website Customer
   File: Website Customer.csv
   Data Stream: Website Customer
   Status: Deployed
   
3. ✅ POS Customer
   File: POS Customer.csv
   Data Stream: POS Customer
   Status: Deployed
   
4. ✅ Customer Engagement Feed
   File: Customer Engagement Feed.csv
   Data Stream: Customer Engagement Feed
   Status: Deployed

═══════════════════════════════════════════════════

✅ All files uploaded successfully!

Next Step: Proceeding to Refresh Data Cloud Components...
```

**Step 9.4: Auto-invoke next skill**

After all files are uploaded successfully, automatically invoke the next skill in the installation workflow:

```
Skill(
  skill: "refresh-data-cloud-components",
  args: "org_alias: <org_alias>"
)
```

The downstream skill authenticates via the Salesforce CLI web session (`sf org login web`) — no credentials are passed between skills.

This ensures seamless continuation of the Data360 Retail installation workflow.

---

### Step 10 — Handle errors gracefully

If any upload fails, provide clear error message:

```text
❌ Data Stream File Upload Failed

Org: <org_alias>

Data Stream Failed: <data_stream_name>
File: <file_name>
Error: <error_message>

Possible Causes:
• Data Stream not found in org
• File format incorrect (not CSV)
• File path incorrect
• Data Cloud not enabled
• Missing permissions

Suggested Fixes:
✅ Verify Data Stream exists: Setup → Data Cloud → Data Streams
✅ Check file format: Must be CSV with headers
✅ Check file path: DIY Documents/DIY Documents/[filename]
✅ Verify Data Cloud enabled: Setup → Data Cloud → Settings
✅ Check permissions: Setup → Users → Permission Sets → Data Cloud Admin

Already Uploaded:
<list of successfully uploaded files>

Remaining:
<list of files not yet uploaded>

Would you like me to retry the failed upload?
```

Common errors:

| Error | Suggested Fix | Retry Strategy |
|---|---|---|
| Update File button not found (blank page) | Salesforce rendered blank record page | ✅ **Refresh page IMMEDIATELY** (no waiting), max 2 refreshes |
| "Upsert" mode button not found | Modal not fully loaded — Refresh Mode is a button group, not a picklist | ✅ Wait 2s, snapshot, try fallback selectors (label, role=radio, text=). If still missing, proceed (Upsert may be default) |
| Clicked Refresh Mode but state didn't change | Wrong selector matched a different element | ✅ Snapshot, verify aria-pressed/aria-checked on the Upsert button, try next fallback selector |
| Upload Files button not found | Modal not fully loaded or label overlay issue | ✅ Close/reopen modal, use label selector |
| Existing Model option not found | Model UI may not render until upload completes | ✅ Wait 3s after upload, retry once. If missing, proceed with default |
| Specific model name not in list | Model name pattern mismatch | ✅ Fuzzy-match (case-insensitive, ignore _/spaces). If still none, log and proceed |
| Deploy button not found/disabled | File upload or model selection incomplete | ✅ Wait 5s, retry once |
| Data Stream not found | Verify Data Stream exists and Connection Type is "File Upload" | ❌ Skip and continue with next |
| File not found | Check file path and ensure file exists locally | ❌ Stop workflow (cannot upload) |
| Browser timeout | Increase wait timeout and refresh page | ✅ Refresh and retry once |
| File access denied / Permission error | Close browser, wait 5 seconds, restart from Step 3 (Launch browser), retry upload | ✅ Full browser restart |

---

## Important Rules

**CRITICAL - Execution Sequence:**
- 🚨 **ALWAYS upload files in SERIES (sequential order) - NEVER in parallel**
- 🚨 **Complete one Data Stream upload entirely before starting next**
- 🚨 **Wait for Deploy to complete before moving to next upload**
- 🚨 **Do NOT close browser between uploads - reuse same session**

**CRITICAL - File Handling:**
- ✅ **Verify file exists before attempting upload**
- ✅ **Use exact file names as specified**
- ✅ **Check file size is reasonable (< 150MB)**
- ✅ **Ensure file is CSV format with headers**

**CRITICAL - Browser Automation:**
- ✅ **ONLY use MCP Playwright tools** - Never generate JavaScript
- ✅ **Click visible "Upload Files" text** - NOT the hidden input element
- ✅ **Take screenshots at key steps** for verification
- ✅ **Wait for elements to appear** before clicking
- ✅ **Use time-based waits** (2-3 seconds) for modal/page loads instead of element-based selectors

**CRITICAL - Error Handling:**
- ✅ **If one upload fails, continue with remaining uploads**
- ✅ **Report all successes and failures at the end**
- ✅ **Automatic retry logic enabled:** Refresh page/modal once when elements not found
- ✅ **Maximum 1 retry per element** (2 total attempts)
- ✅ **Provide actionable error messages with fix suggestions**
- 🔄 **Element not found → Refresh → Retry → Skip if still fails**

**General Rules:**
- NEVER hardcode org names — always use provided org_alias parameter
- NEVER suggest manual completion - automate everything
- ALWAYS verify files exist before starting browser automation
- ALWAYS take screenshots at critical steps
- ALWAYS close browser when done
- ALWAYS provide comprehensive summary report
- Estimated upload time: 2-5 minutes per Data Stream
- Total estimated time: 10-20 minutes for all 4 uploads
- **🚨 If file upload encounters "access denied" errors:** Close browser, wait 5 seconds, restart from Step 3 (Launch browser) and retry

---

## Example Usage

### Example 1: User provides org name

**User:** "Upload Data Stream files to MyRetailOrg"

**Skill:**
1. Verifies CSV files exist in "DIY Documents/DIY Documents/"
2. Gets org credentials: `sf org display`
3. Launches browser and navigates to Data Cloud
4. Uploads Customer_Affinities 2.csv → Deploys → Verifies
5. Uploads Website Customer.csv → Deploys → Verifies
6. Uploads POS Customer.csv → Deploys → Verifies
7. Uploads Customer Engagement Feed.csv → Deploys → Verifies
8. Closes browser
9. Reports summary with all upload statuses

---

### Example 2: Error handling - File not found

**User:** "Upload Data Stream files to TestOrg"

**Skill:** [Verifies files]

**Error:** `File not found: DIY Documents/DIY Documents/Customer_Affinities 2.csv`

**Skill:**
```text
❌ File Verification Failed

Org: TestOrg

Missing Files:
• Customer_Affinities 2.csv

Location Checked:
DIY Documents/DIY Documents/

Suggested Fix:
1. Download missing files from GitHub:
   https://github.com/salesforce-misc/Data360AgentforceSolutionKitRetail/tree/master/DIY%20Documents
2. Save files to: DIY Documents/DIY Documents/
3. Retry upload

Cannot proceed without required CSV files.
```

---

### Example 3: Error handling - Data Stream not found

**User:** "Upload Data Stream files to MyOrg"

**Skill:** [Opens Customer Affinities Data Stream]

**Error:** `Data Stream "Customer Affinities" not found`

**Skill:**
```text
⚠️ Data Stream Not Found

Org: MyOrg

Data Stream: Customer Affinities
Connection Type Expected: File Upload

This Data Stream must exist before uploading files.

Suggested Fix:
1. Navigate to Setup → Data Cloud → Data Streams
2. Verify "Customer Affinities" Data Stream exists
3. Check Connection Type is "File Upload"
4. If missing, create Data Stream or deploy Data Kit metadata first

Skipping Customer Affinities and continuing with remaining uploads...
```

---

## Success Criteria

Upload is successful when:

✅ All 4 CSV files exist locally
✅ Org authentication validated via `sf org display`
✅ Browser launched successfully
✅ Data Cloud Data Streams home page loaded (`/lightning/o/DataStream/home`)
✅ Search functionality works to find each Data Stream
✅ All 4 Data Streams found and opened (Customer Affinities, Website Customer, POS Customer, Customer Engagement Feed)
✅ "Update File" button clicked for each Data Stream
✅ Refresh Mode "Upsert" button clicked for each Data Stream 🆕
✅ "Upload Files" text clicked successfully (triggers file chooser)
✅ All 4 CSV files uploaded (100% progress shown)
✅ Existing model selected for each Data Stream (Customer_Affinities, Website_Customer, POS_Customer, Customer_Engagement_Feed) 🆕
✅ All 4 "Deploy" buttons clicked successfully
✅ Modal closes after each deployment (indicating deployment started)
✅ Screenshots captured at key steps for verification
✅ Browser closed cleanly
✅ Comprehensive summary report provided with all 4 uploads
✅ User can verify processing status in Refresh History tab of each Data Stream

---

## Files to Upload

| # | Data Stream Name | CSV File Name | File Location |
|---|-----------------|---------------|---------------|
| 1 | Customer Affinities | Customer_Affinities 2.csv | DIY Documents/DIY Documents/ |
| 2 | Website Customer | Website Customer.csv | DIY Documents/DIY Documents/ |
| 3 | POS Customer | POS Customer.csv | DIY Documents/DIY Documents/ |
| 4 | Customer Engagement Feed | Customer Engagement Feed.csv | DIY Documents/DIY Documents/ |

**File Requirements:**
- Format: CSV
- Headers: Must include (first row)
- Size: < 150MB per file
- Encoding: UTF-8
- Line endings: LF or CRLF

---

## Notes

After skill completes, the next skill in the workflow (refresh-data-cloud-components) automatically refreshes Identity Resolution, Calculated Insights, and Segment. Copy Field Sync (copy-field-sync) runs after that, and the optional Data Stream refresh step (refresh-data-streams) runs later in the chain if the user opted in. No verification action is required from the user.

---

## Cleanup temp artifacts (MANDATORY before skill returns)

**🚨 HARD RULE — read this in full before invoking any cleanup command:**

> Every file or folder THIS run created in the working tree MUST be deleted before the skill returns successfully. The only exceptions are token-bearing files, which are deleted on **both success and failure paths** (security: never leave a live OAuth token on disk).

This applies regardless of which step created the file — if any prior run, debug session, or interceptor `evaluate()` call wrote something to the working tree under the names listed below, it gets removed at the end of this skill.

### Files this skill is known to create

```bash
# Step 2 — SOQL query input + JSON response
rm -f query_datastreams.soql
rm -f datastream_ids.json

# Step 2 — derived ID map (DS_ID per Data Stream)
rm -f ds_ids.env

# Step 3 — credentials JSON (SECURITY: contains a live OAuth access token)
rm -f org_creds.json

# Step 4 — frontdoor URL holder (also contains the access token in the query string)
rm -f frontdoor_url.txt

# Step 4.5 — Aura interceptor capture log (if you used `filename:` arg on the
# `evaluate()` call to dump window.__dsAuraCaptured to disk for debugging,
# OR if a request-capture diagnostic was written here during investigation)
# This file may contain Aura JWTs and AWS S3 pre-signed URLs. ALWAYS delete.
rm -f capture_log.json

# Step 8/9 — sample CLI / curl debug artifacts that older skill versions
# sometimes leave behind. Forward-compatible cleanup.
rm -f tree_import_log.txt tree_import_result.json
```

### Folders this skill creates via Playwright (Steps 4-9) and must delete

```bash
# Cross-platform: Windows + WSL/Git Bash both work via Python rmtree.
# rm -rf can prompt for permission on Windows; this avoids that.
python3 -c "import shutil, pathlib; p=pathlib.Path('.playwright-mcp'); shutil.rmtree(p) if p.exists() else None"
```

### Verification (must show no leftovers)

```bash
ls query_datastreams.soql datastream_ids.json ds_ids.env \
   org_creds.json frontdoor_url.txt capture_log.json \
   tree_import_log.txt tree_import_result.json 2>&1 | grep -v "cannot access"
ls -d .playwright-mcp 2>&1 | grep -v "cannot access"
```

If any of those lines print a path (i.e. the file/folder still exists), the cleanup failed — STOP and surface it to the user. The skill MUST NOT return success until the verification grep prints nothing.

### What to keep (do NOT delete)

- ✅ The 4 CSV files in `DIY Documents/DIY Documents/` — repo source, never touched
- ✅ `.claude/` — the skill's own definition lives here
- ✅ Anything in `data/`, `diy-base/`, `diy-datacloud/`, `scripts/` — repo source

### Cleanup-on-failure policy (per-Workspace-Hygiene rule)

| Artifact | On clean success | On any-step failure |
|---|---|---|
| `org_creds.json` | ✅ Delete | ✅ **DELETE** (token leakage risk — never leave on disk) |
| `frontdoor_url.txt` | ✅ Delete | ✅ **DELETE** (URL contains the token in the query string) |
| `capture_log.json` | ✅ Delete | ✅ **DELETE** (may contain Aura JWT + S3 pre-signed URL) |
| `query_datastreams.soql` | ✅ Delete | ❌ Keep — surfaces which DS IDs the run was targeting |
| `datastream_ids.json` | ✅ Delete | ❌ Keep — same reason |
| `ds_ids.env` | ✅ Delete | ❌ Keep — same reason |
| `.playwright-mcp/` | ✅ Delete | ❌ Keep — snapshots are the failure evidence |

**SECURITY: token-bearing files are NEVER kept.** Even if the skill failed mid-Data-Stream, the cleanup MUST delete `org_creds.json`, `frontdoor_url.txt`, and `capture_log.json`. Print a short message confirming each deletion so the user has a paper trail.

### Per-Data-Stream "did the interceptor fire?" log (optional cleanup)

If during Step 4.5 you set up a verification call that dumps `window.__dsAuraCaptured` to disk (e.g. for skills-debugging in CI), include that file in the cleanup list above. The current skill text does NOT write that log to disk — the verification call only reads `window.__dsAuraCaptured` and returns the count inline — so no extra cleanup is needed by default.
