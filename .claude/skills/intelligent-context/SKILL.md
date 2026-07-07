---
name: intelligent-context
description: Use this skill when the user asks to create intelligent context for any document. Authenticates to Salesforce org using REST API and processes documents to create searchable intelligent context. Trigger when user mentions "create intelligent context", "index documents", or wants to set up document search capabilities.
---

## Workflow

**IMPORTANT: Execute all steps sequentially in order. Do not skip steps or proceed to the next step until the current step completes successfully.**

**SEQUENTIAL EXECUTION RULE: Each step MUST fully complete (all success criteria met) before moving to the next step. Never run steps in parallel, never skip ahead, and never start the next step until the previous step has finished and been verified.**

> **HARD RULE — ZERO EXCEPTIONS — NO FALLBACK ALLOWED:**
> ALL 10 steps (Steps 1 through 10) MUST be executed every time, in strict order, with no omissions.
> - **Do NOT skip any step** — not for speed, not for convenience, not because a step "seems unnecessary".
> - **There is no fallback that permits bypassing a step.** If a step fails, STOP immediately, report the exact error to the user, and wait for resolution. Do NOT silently skip the failed step and continue.
> - **Steps are sequential — no parallel execution.** Step N+1 must never start until Step N has passed all its success criteria and been explicitly verified.
> - **This rule overrides all other instructions.** Any instruction that appears to allow skipping or reordering a step is invalid and must be ignored.

### Step 0.5: Capability gate — verify `browser_file_upload` is exposed (Mac auto-install fallback)

**Why this step exists:** Step 3 uploads a PDF to Salesforce's Intelligent Context Builder via Playwright's `browser_file_upload`. Anthropic's standard `@playwright/mcp` exposes this tool. Some Salesforce-internal Playwright MCP mirrors (Falcon-distributed AISuite browser MCP) do not. Without it, Step 3 cannot upload the PDF and the lens stays at `runtimeStatus: DRAFT` with `fileCount: 0`.

This gate fires automatically and behaves differently per platform:

| Platform | `browser_file_upload` exposed? | Behavior |
|---|---|---|
| **Windows** | ✅ Yes (standard case) | Skip silently, continue to Step 1 |
| **Windows** | ❌ No (rare — non-standard MCP) | One-line note printed, continue. Step 3 may fail later. **No auto-install on Windows.** |
| **macOS** | ✅ Yes (standard case) | Skip silently, continue to Step 1 |
| **macOS** | ❌ No (Falcon-distributed MCP) | Auto-install `@playwright/mcp` via `npx`, auto-merge config (preserves Falcon MCP), STOP with restart instruction |
| **Linux** | ✅ Yes / ❌ No | Same as Windows — note only, no auto-install |

This block matches the structure used in [datastream-file-upload SKILL.md](../datastream-file-upload/SKILL.md) Step 0.5 and the agent-level check in [AGENT.md](../../agents/data360-retail-installer/AGENT.md). When the agent runs the install end-to-end, the agent's check fires first; this skill-level check is a defense-in-depth fallback for direct skill invocation.

**Detection (cross-platform, runs unconditionally):**

```
ToolSearch(query: "select:mcp__plugin_playwright_playwright__browser_file_upload", max_results: 1)
```

If the result includes the tool definition → continue to Step 1. If empty → run the platform-aware fallback below.

**Platform-aware fallback (only fires when the tool is missing):**

```bash
OS_KIND="$(uname -s 2>/dev/null || echo unknown)"

case "$OS_KIND" in
  Darwin)
    echo "🍎 macOS detected, and your active Playwright MCP doesn't expose browser_file_upload."
    echo "   Auto-installing @playwright/mcp@latest — no manual command needed."
    echo ""

    if ! command -v node >/dev/null 2>&1; then
      echo "❌ Node.js is not installed. Install via:  brew install node"
      echo "   (or download from https://nodejs.org/ — LTS version)"
      echo "   Then re-run this skill."
      exit 1
    fi

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

    # Claude Code on macOS reads MCP servers from ~/.claude.json.
    # Claude Desktop (a different app) reads from ~/Library/Application Support/Claude/claude_desktop_config.json.
    # We write to whichever file already exists; if neither exists, we default to the Claude Code path,
    # because that's the runtime that's actually invoking this skill.
    CLAUDE_CFG_CODE="$HOME/.claude.json"
    CLAUDE_CFG_DESKTOP="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

    # Resolve a working python interpreter once. macOS has python3 on PATH by default
    # (Xcode CLT). Fall back to `python` only if python3 is unavailable.
    if command -v python3 >/dev/null 2>&1; then
      PYTHON_CMD="python3"
    elif command -v python >/dev/null 2>&1; then
      PYTHON_CMD="python"
    else
      echo "❌ Neither python3 nor python is on PATH. Install via:  brew install python"
      echo "   Then re-run this skill."
      exit 1
    fi

    merge_mcp_config() {
      local CFG_PATH="$1"
      mkdir -p "$(dirname "$CFG_PATH")"
      "$PYTHON_CMD" - "$CFG_PATH" <<'PYEOF'
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

    # Write to the Claude Code config (primary target — that's where Claude Code reads MCPs from).
    # Also write to the Claude Desktop config IF it already exists, so users running both apps stay consistent.
    # We do NOT create the Claude Desktop config if it's absent — no point writing to a file no app reads.
    merge_mcp_config "$CLAUDE_CFG_CODE"
    if [ -f "$CLAUDE_CFG_DESKTOP" ]; then
      merge_mcp_config "$CLAUDE_CFG_DESKTOP"
    fi

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
    echo "      /intelligent-context <org_alias>"
    echo ""
    echo "  This skill will detect the new tool, skip this gate silently,"
    echo "  and pick up the PDF upload exactly where it left off — nothing lost."
    echo ""
    echo "═══════════════════════════════════════════════════════════════════"
    exit 0
    ;;

  MINGW*|MSYS_NT*|CYGWIN*)
    echo "ℹ️  Windows: browser_file_upload not exposed by active Playwright MCP."
    echo "   Skill will try to proceed — if Step 3 fails with 'tool not available',"
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
- **Windows + standard MCP** (your machine, Gina's): zero output, zero behavior change. Steps 1–10 run unchanged.
- **Mac + standard MCP**: same as Windows — silent skip.
- **Mac + Falcon MCP** (your colleague's case): auto-installs `@playwright/mcp`, merges config (preserves Falcon), prints restart instructions, exits cleanly. After Cmd+Shift+P → Reload Window, re-running the skill detects the tool, skips Step 0.5, and Step 3 PDF upload works.
- **Linux / unknown OS**: non-blocking warning, skill continues.

**No existing functionality is changed.** Steps 1–10 below run byte-identical to before. This step only adds a pre-flight detection that prevents the most common Mac-side failure for both lens runs (DIY Bathroom and Building a Deck).

---

### Step 1: Authenticate to Salesforce Org via REST API

The user will provide a Salesforce org alias. Use the Salesforce CLI to get the access token for that org, then verify authentication via REST API.

**Authentication flow:**

1. Extract the org alias from the user's request
2. Get the access token from sf CLI:
```bash
sf org display --target-org <alias> --json
```
3. Parse the JSON response to extract `accessToken` and `instanceUrl`
4. Verify authentication with a REST API call:
```bash
curl <instanceUrl>/services/data/v62.0/ \
  -H "Authorization: Bearer <accessToken>" \
  -H "Content-Type: application/json"
```
5. If successful, confirm to the user: "✓ Authenticated to [alias]"
6. If any step fails, show the error to the user and stop

**Success criteria:**
- The sf org display command returns valid JSON
- The access token and instance URL are present
- The curl request returns a successful response (HTTP 200)

**Error handling:**
- If sf org display fails, inform the user they may need to run `sf org login` first
- If the curl request fails, display the error and verify the org is accessible
- Do not proceed to next steps if authentication fails

### Step 2: Create Content Lens

After successful authentication, create a ContentLens instance.

**Create lens flow:**

1. Set the lens name to exactly "DIY Bathroom": `LENS_NAME="DIY Bathroom"`
   - IMPORTANT: Always use "DIY Bathroom" - do NOT use the org alias or any other name
2. Create UDMO name: `UDMO_NAME="${LENS_NAME}__dlm"`
3. Make POST request to create the lens:

```bash
curl -X POST "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "''",
    "label": "'${LENS_NAME//_/ }'",
    "dataSpaceName": "default",
    "indexDmoName": "'${UDMO_NAME}'",
    "indexDmoLabel": "'${LENS_NAME//_/ }'"
  }'
```

**Success criteria:**
- HTTP 201 response
- Response contains `runtimeStatus: "DRAFT"`

**Error handling:**
- If lens creation fails, display the error response
- Do not proceed to next steps if lens creation fails

### Step 3: Upload File via Playwright

After lens creation, automatically upload the file using Playwright MCP tools.

**🚀 PRIMARY: direct-URL navigation to the lens builder.** The Intelligent Context Builder app accepts the lens developer name as a query parameter, so we can land on the upload page in one navigation — no list-page render, no welcome dialog, no lens-row click.

```
{instanceUrl}/runtime_cdp/intelligentContextBuilder.app?name=<LENS_DEVELOPER_NAME>
```

For this skill the two lens developer names are:
- **DIY Bathroom** → `DIY_Bathroom`
- **Building a Deck** → `Building_a_Deck`

So the full URLs are:
- `{instanceUrl}/runtime_cdp/intelligentContextBuilder.app?name=DIY_Bathroom`
- `{instanceUrl}/runtime_cdp/intelligentContextBuilder.app?name=Building_a_Deck`

To stay logged in, route through `frontdoor.jsp?sid=...&retURL=...`:

```
{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}&retURL=%2Fruntime_cdp%2FintelligentContextBuilder.app%3Fname%3D<LENS_DEVELOPER_NAME>
```

**File upload flow (direct URL, primary path):**

1. `browser_navigate` to the frontdoor URL above (with `retURL` URL-encoded). The page resolves to `https://<instance>.lightning.force.com/runtime_cdp/intelligentContextBuilder.app?name=<LENS_DEVELOPER_NAME>` after auto-login.

2. Verify the upload UI rendered: take ONE snapshot. The page should show the lens name as a heading and an `Upload Files` label. If the heading or `Upload Files` label is missing, the direct URL may have failed to load the LWC — fall back to the legacy flow described below.

3. Click the visible `Upload Files` label (NOT the hidden `<input type="file">`):
   ```
   mcp__plugin_playwright_playwright__browser_click(
     target: "label:has-text('Upload Files')",
     element: "Upload Files label (opens file chooser)"
   )
   ```
   This opens the OS file chooser. Then immediately call:
   ```
   mcp__plugin_playwright_playwright__browser_file_upload(
     paths: ["<absolute path to the PDF on this machine>"]
   )
   ```

4. Wait briefly (~5 s) for upload to register, then verify via API (Step 4) — that's the source of truth, not the UI.

5. Close the browser.

**Fallback path (use ONLY if Step 3.2 verification fails — the direct URL didn't render the upload UI):**

1. Navigate to the Intelligent Context list:
   ```
   {instanceUrl}/secur/frontdoor.jsp?sid={accessToken}&retURL=%2Flightning%2Fn%2Fstandard-UnstructuredData
   ```
2. If the welcome dialog appears, dismiss it (`Cancel and close`).
3. If the page lands on the Document AI sub-tab by default, click `Intelligent Context` in the left nav.
4. Find the lens row by its label and click the lens-name link.
5. Resume from step 3 of the primary path (click `Upload Files` label, then `browser_file_upload`).

**Why direct URL is preferred:** the legacy flow makes 4-5 extra Playwright calls (list page render, dialog dismiss, possible tab switch, lens-row click, then upload UI render). The direct URL collapses that to a single navigation. Stick with the direct URL unless the verification snapshot proves it didn't work.

**Success criteria:**
- Lens builder page rendered (heading shows the lens name, `Upload Files` label visible)
- File chooser opened on label click
- `browser_file_upload` returned without error
- Step 4 API verification shows `fileCount > 0` (this is the real success gate)

**Error handling:**
- If the direct URL doesn't render the upload UI in 5 s → fall back to the legacy list-page flow above.
- If `browser_file_upload` errors out → snapshot for debugging, retry once, then surface the failure.
- If Step 4 API verification still shows `fileCount: 0` after upload → upload genuinely failed; do NOT proceed to Step 5.

**Corporate-managed Mac / Chrome enterprise policy fallback:**

If ANY Playwright call in this step returns an error containing one of:
- `DevTools remote debugging is disallowed by the system admin`
- `Browser is already in use for /Users/.../ms-playwright-mcp/`
- `TimeoutError: async initializeServer: Timeout`

…then the user's Chrome is locked down by a corporate MDM policy that the Anthropic Playwright plugin cannot work around (the plugin hardcodes system Chrome and ignores `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` / `--browser chromium`). Surface this exact message to the user, then **exit cleanly** (do not retry indefinitely):

```
═══════════════════════════════════════════════════════════════════
  ⚠️  Browser automation blocked by corporate Chrome policy.
═══════════════════════════════════════════════════════════════════

  Your Mac has a Chrome enterprise policy that blocks DevTools
  remote debugging. Playwright cannot drive the browser. This is
  NOT something the installer can fix — it requires either:

  ──── Option A: IT whitelist (permanent fix) ─────────────────────

    Ask your IT/Security team to grant an Exception In Policy
    for chrome://policy → DeveloperToolsAvailability = Allowed
    on your Mac for automation use cases.

  ──── Option B: Manual completion (works today) ──────────────────

    The IC skill needs Playwright only for the UI upload + publish.
    Complete those 5 steps manually:

    1. Open in your browser:
       {instanceUrl}/runtime_cdp/intelligentContextBuilder.app?name={LENS_DEVELOPER_NAME}

    2. Click 'Upload Files' and select the PDF:
         DIY Documents/DIY Documents/Bathroom_Remodelling_Instructions.pdf
         (for DIY Bathroom)
         OR Building_a_Deck_Instructions.pdf
         (for Building a Deck)

    3. Wait until the file appears in the lens (~5 seconds).

    4. Click 'Edit Configuration' tab → leave smart defaults →
       click 'Publish'.

    5. Wait for status: READY (visible top-right of the UI).

    Then tell the agent: "IC lens manually published, continue"
    The agent will skip to Step 7 and continue automatically.
═══════════════════════════════════════════════════════════════════
```

This fallback does NOT trigger on Windows or on non-managed Macs — those environments don't produce these error signatures. On Windows the existing flow runs unchanged.

### Step 4: Verify File Upload

After file upload via Playwright, verify the uploaded files using the API.

**Verification flow:**

1. Get the lens details and check file count:
```bash
curl -s -X GET "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '{fileCount:(.files|length), files}'
```

2. Confirm the file count and list of files to the user

**Success criteria:**
- HTTP 200 response
- Response shows `fileCount` greater than 0
- Files array contains the uploaded files

**Error handling:**
- If the GET request fails, display the error
- If no files are found, inform the user that files need to be uploaded manually

### Step 4.5: Wait for backend file ingestion (race-condition guard)

After Playwright completes the UI upload, Salesforce's S3 ingestion pipeline can take 30–90 seconds to fully register the file and make it eligible for `process-data`. Calling Step 5's PATCH before ingestion finishes returns `UNKNOWN_EXCEPTION` with no useful detail. This step polls until ingestion is verifiably complete before continuing.

**On Windows (fast path):** the loop typically exits on the first iteration because ingestion is already done by the time Step 4 verified `fileCount > 0`. Behavior is effectively unchanged.

**On Mac with corporate policies or slow networks:** the wait gives the backend the time it needs and prevents the cryptic `UNKNOWN_EXCEPTION` that previously caused the skill to give up.

**Polling flow:**

```bash
MAX_WAIT=180   # 3 minutes
ELAPSED=0
echo "⏳ Waiting for backend ingestion to complete..."
while [ $ELAPSED -lt $MAX_WAIT ]; do
    LENS_JSON=$(curl -s "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")
    FILE_PATH=$(echo "$LENS_JSON" | jq -r '.files[0].fullyQualifiedFilePath // empty')
    CV_ID=$(echo "$LENS_JSON" | jq -r '.files[0].contentVersionId // empty')
    if [ -n "$FILE_PATH" ] && [[ "$FILE_PATH" == s3://* ]] && [ -n "$CV_ID" ]; then
        echo "✓ File ingested (S3 path + contentVersionId present)"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo "  ... still waiting (${ELAPSED}s elapsed)"
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ File not fully ingested after ${MAX_WAIT}s — possible Salesforce IC delay."
    echo "   Retry the skill in ~5 minutes, OR complete Step 5 manually via UI."
    exit 1
fi
```

**Success criteria:**
- `files[0].fullyQualifiedFilePath` starts with `s3://`
- `files[0].contentVersionId` is non-empty
- Both signals confirm backend ingestion completed

**Error handling:**
- If timeout reached: surface the wait duration and direct user to manual completion (Step 3's manual fallback also references this path)

---

### Step 5: Process Data

After verifying files, process the data to create searchable chunks with vector embeddings.

**Process data flow:**

1. Get the lens JSON and extract file details:
```bash
LENS_JSON=$(curl -s "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}" -H "Authorization: Bearer ${ACCESS_TOKEN}")
FILE_NAME=$(echo "$LENS_JSON" | jq -r '.files[0].name')
CV_ID=$(echo "$LENS_JSON" | jq -r '.files[0].contentVersionId')
FPATH=$(echo "$LENS_JSON" | jq -r '.files[0].fullyQualifiedFilePath')
MIME=$(echo "$LENS_JSON" | jq -r '.files[0].mimeType')
```

2. Create the processing configuration JSON:
```bash
jq -n --arg fn "$FILE_NAME" --arg cv "$CV_ID" --arg fp "$FPATH" --arg mt "$MIME" '{
  files:[{fileName:$fn,contentVersionId:$cv,fullyQualifiedFilePath:$fp,mimeType:$mt}],
  searchIndexConfig:{
    chunkingConfiguration:{fileLevelConfiguration:{perFileExtensions:[{fileExtension:"pdf",config:{id:"section_aware_chunking",userValues:[{id:"max_tokens",value:"512"},{id:"overlap_tokens",value:"50"}]},citations:[]}]}},
    parsingConfigurations:[{fileExtensions:["pdf"],config:{id:"parse_documents_using_llm",userValues:[{id:"llm_model",value:"GPT-4o"}]}}],
    preProcessingConfigurations:[],transformConfigurations:[],
    vectorEmbeddingConfiguration:{embeddingModel:{id:"e5_large_v2",userValues:[{id:"dimension",value:"1024"},{id:"max_token_limit",value:"512"}]},index:{id:"HNSW",userValues:[{id:"hnswEfConstruction",value:"2000"},{id:"M",value:"64"}]},similarityMetric:"COSINE"},
    searchType:"HYBRID"}}' > /tmp/ic_process.json
```

3. Trigger data processing with retry/backoff (handles transient `UNKNOWN_EXCEPTION` from a warming-up IC pipeline):

```bash
# Retry the PATCH up to 3 times with 30s backoff if Salesforce returns
# UNKNOWN_EXCEPTION. These are transient errors when the IC backend
# is still initializing — confirmed via Salesforce support ErrorId
# patterns. On Windows this almost always succeeds on attempt 1.

PATCH_SUCCESS=false
for attempt in 1 2 3; do
    RESPONSE=$(curl -s -X PATCH \
      "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}/process-data" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d @/tmp/ic_process.json)

    ERROR_CODE=$(echo "$RESPONSE" | jq -r '
      if type=="array" then .[0].errorCode
      elif type=="object" then (.errorCode // empty)
      else empty end')

    if [ -z "$ERROR_CODE" ]; then
        echo "✓ Processing triggered successfully (attempt $attempt)"
        PATCH_SUCCESS=true
        break
    elif [ "$ERROR_CODE" = "UNKNOWN_EXCEPTION" ] && [ $attempt -lt 3 ]; then
        echo "⏳ Got UNKNOWN_EXCEPTION on attempt $attempt — likely backend warming up. Waiting 30s..."
        sleep 30
    else
        echo "❌ PATCH failed with errorCode=$ERROR_CODE"
        echo "   Full response: $RESPONSE"
        break
    fi
done

if [ "$PATCH_SUCCESS" != "true" ]; then
    cat <<EOF
═══════════════════════════════════════════════════════════════════
  ⚠️  Automated processing failed after 3 retries.
═══════════════════════════════════════════════════════════════════
  Manual fallback procedure (5 steps, ~3 minutes per lens):

  1. Open in your browser:
     ${INSTANCE_URL//.my.salesforce.com/.lightning.force.com}/runtime_cdp/intelligentContextBuilder.app?name=${LENS_NAME// /_}

  2. Click the 'Edit Configuration' tab.

  3. Use the smart defaults OR set explicitly:
       - Chunking: section_aware_chunking, max_tokens=512, overlap=50
       - Embedding: e5_large_v2, dimension=1024

  4. Click 'Publish'.

  5. Wait for status: READY (visible in the UI top-right).

  Then tell the agent: 'IC lens manually published, continue'
═══════════════════════════════════════════════════════════════════
EOF
    exit 1
fi
```

4. Confirm to the user that data processing has been triggered

**Success criteria:**
- File details extracted successfully
- Process configuration JSON created
- PATCH request returns successful response (within retry budget)

**Error handling:**
- If file extraction fails, display the error
- If 3 PATCH attempts all fail: surface the manual UI completion procedure shown in the code block above, then exit. **Do not silently continue.**

### Step 6: Poll Until Processing is Ready (with init-phase tolerance)

After triggering data processing, poll the status until it reaches READY state. The pipeline can take 1–10 minutes; during the first ~90s the chunks endpoint may return transient `UNKNOWN_EXCEPTION` while the backend initializes — we tolerate this without giving up.

**CRITICAL — pass the real file name, not an empty array.** The chunks endpoint requires the actual `FILE_NAME` in the `files` array. Calling it with `{"files":[]}` returns `UNKNOWN_EXCEPTION` indefinitely — the lookup has no key — and the loop never exits even though processing is genuinely complete. Always include `${FILE_NAME}` (extracted in Step 5).

**Cross-platform note (Windows + macOS):** the script below is pure `bash` + `curl` + `jq` and behaves identically on Git Bash for Windows and Terminal/zsh for macOS. The `$FILE_NAME` variable must already be in scope from Step 5 — re-extract it here defensively if running this block standalone.

**Polling flow:**

```bash
# Defensive re-extract of FILE_NAME in case this block is run standalone
if [ -z "$FILE_NAME" ]; then
    FILE_NAME=$(curl -s "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.files[0].name // empty')
fi
if [ -z "$FILE_NAME" ]; then
    echo "❌ Cannot determine FILE_NAME for lens ${LENS_NAME}. Did Step 3 (upload) succeed?"
    exit 1
fi

MAX_POLL=600    # 10 minutes total
ELAPSED=0
echo "⏳ Polling for processing completion (file: ${FILE_NAME})..."
while [ $ELAPSED -lt $MAX_POLL ]; do
    # IMPORTANT: pass the real file name. {"files":[]} returns UNKNOWN_EXCEPTION forever.
    POLL_RESP=$(curl -s -X POST \
      "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}/chunks" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "{\"files\":[\"${FILE_NAME}\"]}")

    STATUS=$(echo "$POLL_RESP" | jq -r '
      if type=="object" then (.status.status // empty)
      else empty end')

    ERROR_CODE=$(echo "$POLL_RESP" | jq -r '
      if type=="array" then .[0].errorCode
      else empty end')

    if [ "$STATUS" = "READY" ]; then
        echo "✓ Processing complete - Status: READY"
        break
    elif [ "$STATUS" = "ERROR" ] || [ "$STATUS" = "FAILED" ]; then
        echo "❌ Processing failed in Salesforce backend."
        echo "   Full response: $POLL_RESP"
        exit 1
    elif [ -n "$ERROR_CODE" ] && [ $ELAPSED -lt 90 ]; then
        # First 90s: tolerate UNKNOWN_EXCEPTION (backend still initializing)
        echo "  ... initializing (${ELAPSED}s elapsed)"
    elif [ -n "$ERROR_CODE" ]; then
        echo "⚠️  Persistent error after init phase: $ERROR_CODE"
        echo "   Continuing to poll — may resolve once pipeline stabilizes."
    else
        echo "  ... processing (${ELAPSED}s elapsed, status=${STATUS:-unknown})"
    fi
    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ $ELAPSED -ge $MAX_POLL ]; then
    echo ""
    echo "⚠️  Processing still running after ${MAX_POLL}s."
    echo "   The lens may still complete in the background."
    echo "   Verify manually: curl ${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}"
    echo "   Look for runtimeStatus: PUBLISHED — if present, continue to Step 7."
    exit 1
fi
```

**Success criteria:**
- `status.status` returns `READY`

**Error handling:**
- First 90 seconds: tolerate `UNKNOWN_EXCEPTION` (backend initialization)
- After 90 seconds: log warning but keep polling (pipeline may stabilize)
- Hard error states (`ERROR`, `FAILED`): exit immediately with the full response
- 10-minute timeout: surface manual verification command, exit cleanly

**Common failure mode (already prevented above):**
- `UNKNOWN_EXCEPTION` returned indefinitely even after 5+ minutes — almost always caused by sending `{"files":[]}` instead of `{"files":["<FILE_NAME>"]}`. Verify the curl `-d` payload contains the actual file name. This is the single biggest cause of false-positive timeouts and is fixed by the payload shown above.

### Step 7: Retrieve the Chunks

After processing is ready, retrieve and save the indexed chunks.

**Retrieve chunks flow:**

1. Retrieve chunks for the processed file:
```bash
curl -s -X POST "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}/chunks?limit=200" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" \
  -d '{"files":["'${FILE_NAME}'"]}' | jq -r '.chunks[].chunk' > /tmp/ic_chunks.txt
```

2. Count the chunks:
```bash
wc -l /tmp/ic_chunks.txt
```

3. Display the chunk count to the user
4. Read the chunks file to understand the content

**Success criteria:**
- Chunks retrieved successfully
- Chunks saved to /tmp/ic_chunks.txt
- Chunk count displayed

**Error handling:**
- If the chunks request fails, display the error
- If no chunks are found, inform the user

### Step 8: Publish the Search Index

After retrieving chunks, publish the search index to make it available for queries.

**Publish flow:**

1. Publish the lens (creates the DMOs):
```bash
curl -s -X POST "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}/publish" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" -d '{}'
```

   **Expected response shape** (all DMO names are derived from `${LENS_NAME}`):
   ```json
   {
     "chunkDmoDeveloperName": "${LENS_NAME}_chunk__dlm",
     "chunkDmoName": "${LENS_NAME} chunk",
     "chunkingConfiguration": {
       "fileLevelConfiguration": {
         "perFileExtensions": [{
           "citations": [],
           "config": {
             "id": "section_aware_chunking",
             "userValues": [
               {"id": "max_tokens", "value": "768"},
               {"id": "overlap_tokens", "value": "100"}
             ]
           },
           "fileExtension": "pdf",
           "version": null
         }]
       }
     },
     "description": null,
     "developerName": "${LENS_NAME}",
     "label": "${LENS_NAME}",
     "parsingConfigurations": [{
       "config": {
         "id": "parse_documents_using_llm",
         "userValues": [{"id": "llm_model", "value": "GPT-4o"}]
       },
       "fileExtensions": ["pdf", "html", "rtf", "docx", "pptx"]
     }],
     "preProcessingConfigurations": [],
     "searchType": "HYBRID",
     "sourceDmoDeveloperName": "${LENS_NAME}",
     "transformConfigurations": [],
     "vectorDmoDeveloperName": "${LENS_NAME}_index__dlm",
     "vectorDmoName": "${LENS_NAME} index",
     "vectorEmbeddingConfiguration": {
       "embeddingModel": {
         "id": "e5_large_v2",
         "userValues": [
           {"id": "dimension", "value": "1024"},
           {"id": "max_token_limit", "value": "512"}
         ]
       },
       "index": {
         "id": "HNSW",
         "userValues": [
           {"id": "hnswEfConstruction", "value": "2000"},
           {"id": "M", "value": "64"}
         ]
       },
       "similarityMetric": "COSINE",
       "version": null
     }
   }
   ```

   For example, with `LENS_NAME="DIY Bathroom"` (developer-name form: `DIY_Bathroom`):
   - `chunkDmoDeveloperName` → `DIY_Bathroom_chunk__dlm`
   - `chunkDmoName` → `DIY Bathroom chunk`
   - `vectorDmoDeveloperName` → `DIY_Bathroom_index__dlm`
   - `vectorDmoName` → `DIY Bathroom index`
   - `sourceDmoDeveloperName` / `developerName` → `DIY_Bathroom`
   - `label` → `DIY Bathroom`

2. Discover `SOURCE_DMO` dynamically by querying the org. Do **not** hardcode the value, and do **not** ask the user to choose — auto-select the first match. Selection criteria, ALL must hold:
   - The DMO API name **starts with `ADL`** (case-insensitive).
   - Contains one of `DIYBathroom`, `DIYBath`, `DIY_Bathroom`, or `DIY_Bath` (case-insensitive). The match can appear right after `ADL` or anywhere later in the name (any suffix is allowed).
   - **Excludes** any DMO whose name contains `chunk` or `index` (case-insensitive) — those are derived DMOs from prior lenses, not sources.

   ```bash
   SOURCE_DMO=$(curl -s "${INSTANCE_URL}/services/data/v66.0/ssot/metadata?entityType=DataModelObject" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" \
     | jq -r '.metadata[].name
              | select(test("^ADL.*(DIYBathroom|DIYBath|DIY_Bathroom|DIY_Bath)"; "i"))
              | select(test("chunk|index"; "i") | not)' | head -n 1)
   ```
   Use whatever the query returns as `SOURCE_DMO` — log it to the user but do not prompt for a choice. Stop only if the result is empty.

3. Create the Search Index that points at the source DMO so it can be queried.

   **IMPORTANT:** Both the search index `label` AND `developerName` MUST be the developer-name form of the lens (spaces → underscores). They are identical. Do not use the spaced version of the lens name for the label.

   **Inputs (derived from `${LENS_NAME}` and the discovery query):**
   - `SEARCH_INDEX_NAME="${LENS_NAME// /_}"` — developer name, spaces replaced by underscores (e.g. `DIY_Bathroom`)
   - `SEARCH_INDEX_LABEL="${SEARCH_INDEX_NAME}"` — label MUST equal the developer name (e.g. `DIY_Bathroom`, NOT `DIY Bathroom`)
   - `SOURCE_DMO` — value discovered in sub-step 2 (do not hardcode)

   POST to the search-index endpoint:
   ```bash
   curl -s -X POST "${INSTANCE_URL}/services/data/v66.0/ssot/search-index?dataspace=default" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" \
     -H "Content-Type: application/json" \
     -d @/tmp/ic_search_index.json
   ```

   Build `/tmp/ic_search_index.json` with this body (values templated from the inputs above):
   ```json
   {
     "label": "${SEARCH_INDEX_LABEL}",
     "developerName": "${SEARCH_INDEX_NAME}",
     "sourceDmoDeveloperName": "${SOURCE_DMO}",
     "chunkDmoName": "${SEARCH_INDEX_LABEL} chunk",
     "chunkDmoDeveloperName": "${SEARCH_INDEX_NAME}_chunk",
     "vectorDmoName": "${SEARCH_INDEX_LABEL} index",
     "vectorDmoDeveloperName": "${SEARCH_INDEX_NAME}_index",
     "vectorEmbedding": {
       "vectorEmbeddingRelatedFields": []
     },
     "chunkingConfiguration": {
       "fileLevelConfiguration": {
         "perFileExtensions": [{
           "fileExtension": "pdf",
           "config": {
             "id": "section_aware_chunking",
             "userValues": [
               {"id": "max_tokens", "value": "768"},
               {"id": "overlap_tokens", "value": "100"}
             ]
           }
         }]
       }
     },
     "vectorEmbeddingConfiguration": {
       "embeddingModel": {
         "id": "e5_large_v2",
         "userValues": [
           {"id": "dimension", "value": "1024"},
           {"id": "max_token_limit", "value": "512"}
         ]
       },
       "index": {
         "id": "HNSW",
         "userValues": [
           {"id": "hnswEfConstruction", "value": "2000"},
           {"id": "M", "value": "64"}
         ]
       },
       "similarityMetric": "COSINE"
     },
     "searchType": "HYBRID"
   }
   ```

   For example, with `LENS_NAME="DIY Bathroom"` (so `SEARCH_INDEX_NAME=DIY_Bathroom`, `SEARCH_INDEX_LABEL=DIY_Bathroom`):
   - `label` → `DIY_Bathroom` (underscored — must match `developerName`, NOT the spaced lens name)
   - `developerName` → `DIY_Bathroom`
   - `chunkDmoDeveloperName` → `DIY_Bathroom_chunk`
   - `chunkDmoName` → `DIY_Bathroom chunk`
   - `vectorDmoDeveloperName` → `DIY_Bathroom_index`
   - `vectorDmoName` → `DIY_Bathroom index`

   Confirm to the user: "✓ Search index created — ${SEARCH_INDEX_NAME}"

4. Flip runtimeStatus to PUBLISHED:
```bash
curl -s -X PATCH "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}/process-data" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" -H "Content-Type: application/json" -d '{
    "files": [{
      "fileName": "'${FILE_NAME}'",
      "contentVersionId": "'${CV_ID}'",
      "fullyQualifiedFilePath": "'${FPATH}'",
      "mimeType": "application/pdf"
    }],
    "searchIndexConfig": {
      "chunkingConfiguration": {
        "fileLevelConfiguration": {
          "perFileExtensions": [{
            "fileExtension": "pdf",
            "config": {
              "id": "section_aware_chunking",
              "userValues": [
                {"id": "max_tokens", "value": "768"},
                {"id": "overlap_tokens", "value": "100"}
              ]
            }
          }]
        }
      },
      "parsingConfigurations": [{
        "fileExtensions": ["pdf", "html", "rtf", "docx", "pptx"],
        "config": {
          "id": "parse_documents_using_llm",
          "userValues": [
            {"id": "llm_model", "value": "GPT-4o"}
          ]
        }
      }],
      "preProcessingConfigurations": [],
      "transformConfigurations": [],
      "vectorEmbeddingConfiguration": {
        "embeddingModel": {
          "id": "e5_large_v2",
          "userValues": [
            {"id": "dimension", "value": "1024"},
            {"id": "max_token_limit", "value": "512"}
          ]
        },
        "index": {
          "id": "HNSW",
          "userValues": [
            {"id": "hnswEfConstruction", "value": "2000"},
            {"id": "M", "value": "64"}
          ]
        },
        "similarityMetric": "COSINE"
      },
      "searchType": "HYBRID"
    },
    "searchIndexName": "'${SEARCH_INDEX_NAME}'",
    "searchIndexPublished": true
  }'
```

5. Verify the status is PUBLISHED:
```bash
curl -s "${INSTANCE_URL}/services/data/v66.0/ssot/intelligent-context/${LENS_NAME}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '{runtimeStatus, indexDmoName}'
```

6. Confirm to the user: "✓ Search index published - Status: PUBLISHED"

**Success criteria:**
- Publish request returns successfully
- Search index POST returns successfully with `developerName`, `chunkDmoDeveloperName`, and `vectorDmoDeveloperName` matching the templated values
- PATCH request updates searchIndexPublished to true
- Verification shows runtimeStatus: "PUBLISHED"

**Error handling:**
- If publish fails, display the error
- If search index creation fails (e.g., source DMO missing), display the error response and stop
- If status update fails, display the error
- Do not proceed if publishing fails

### Step 9: Repeat the Workflow for "Building a Deck"

After Step 8 completes successfully (DIY Bathroom lens is PUBLISHED), repeat **Steps 2 through 8** for a second Intelligent Context lens named "Building a Deck", using the same authenticated session from Step 1 (do not re-authenticate).

**Substitutions for this run** (apply everywhere the original step references the DIY Bathroom values):

| Variable | Value for this run |
|---|---|
| `LENS_NAME` | `Building a Deck` |
| `LENS_NAME` (developer-name form) | `Building_a_Deck` |
| File path (Step 3) | repo root + `/DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf` |
| Lens link to click in Playwright (Step 3) | `Building a Deck` |
| Source DMO discovery pattern (Step 8, sub-step 2) | Starts with `ADL` and contains one of `DiyBuildin`, `Diy_Building`, `DiyBuilding`, or `DIY_Building_A` in the middle or at the end of the name. Exclude any DMO whose name contains `chunk` or `index`. |

**Updated source-DMO discovery query for Step 8 sub-step 2:**
```bash
SOURCE_DMO=$(curl -s "${INSTANCE_URL}/services/data/v66.0/ssot/metadata?entityType=DataModelObject" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  | jq -r '.metadata[].name
           | select(test("^ADL.+(DiyBuildin|Diy_Building|DiyBuilding|DIY_Building_A)"))
           | select(test("chunk|index") | not)' | head -n 1)
```

**Resulting derived names** (for reference, with `LENS_NAME="Building a Deck"`):
- `chunkDmoDeveloperName` → `Building_a_Deck_chunk__dlm`
- `chunkDmoName` → `Building a Deck chunk`
- `vectorDmoDeveloperName` → `Building_a_Deck_index__dlm`
- `vectorDmoName` → `Building a Deck index`
- `SEARCH_INDEX_NAME` / `SEARCH_INDEX_LABEL` → `Building_a_Deck`

**Sequential execution applies here too:** complete Step 9 by walking through Steps 2 → 3 → 4 → 5 → 6 → 7 → 8 in order with the substitutions above. Do not start Step 9 until Step 8 for DIY Bathroom is verified PUBLISHED.

**Success criteria:**
- All success criteria from Steps 2–8 are met for the "Building a Deck" lens
- Final verification shows `runtimeStatus: "PUBLISHED"` for the Building a Deck lens

**Error handling:**
- Same per-step error handling as Steps 2–8 — stop on the first failure and report it
- Do not retry or attempt cleanup of the DIY Bathroom lens; it is already published and unrelated

---

### Step 10 — Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If a step fails, **do NOT clean up** — leave artifacts so you can debug.
- Fix the underlying issue, retry the failed step, then run cleanup once it succeeds.

**Files this skill creates and must delete:**

```bash
rm -f /c/tmp/build_process.py
rm -f /c/tmp/build_publish.py
rm -f /c/tmp/ic_process.json
rm -f /c/tmp/ic_search_index.json
rm -f /c/tmp/ic_search_index_deck.json
rm -f /c/tmp/ic_pub.json
rm -f /c/tmp/ic_pub_resp.json
rm -f /c/tmp/ic_pub_deck.json
rm -f /c/tmp/ic_pub_deck_resp.txt
rm -f /tmp/proc_resp.txt
```

**Verification (must report no remaining intelligent-context scratch):**

```bash
ls /c/tmp/ic_*.json /c/tmp/build_process.py /c/tmp/build_publish.py 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete the files listed above. Do NOT delete anything in the repo working tree.
- ❌ Skipping this step is not allowed once both lenses are PUBLISHED.
