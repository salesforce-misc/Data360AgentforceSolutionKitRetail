---
name: agentforce-data-library
description: "Create single or multiple Agentforce Data Libraries (ADL) with PDF file uploads. Handles library creation, AWS S3 file upload via presigned URL, and indexing. Supports batch creation of multiple libraries. Uses correct Einstein API endpoint (/einstein/data-libraries, NOT /connect/einstein). Use when user wants to create data libraries for Agentforce grounding with documents."
---

# agentforce-data-library

## Purpose

Create one or multiple Agentforce Data Libraries (ADL) with file upload capability using Salesforce Einstein REST API.

This skill automates the complete workflow for creating data libraries, uploading PDF files to Salesforce's AWS S3 storage, and starting the indexing process for Agentforce grounding.

**Key Features:**
- Supports creating **single or multiple libraries** in one execution
- Uses correct Einstein API endpoint: `/services/data/v66.0/einstein/data-libraries`
- Uploads files to Salesforce's managed AWS S3 infrastructure
- Polls upload readiness with configurable timeout (default 120 seconds)
- Monitors indexing progress through multiple stages
- Returns library IDs for agent configuration
- Processes libraries sequentially to avoid token expiration

Prerequisites:
- Salesforce CLI authenticated with target org
- Target org must have Agentforce Data Library feature enabled (visible at Setup → Agentforce Data Library)
- PDF files must exist at specified paths
- User must have "Manage Einstein Features" or equivalent permission

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username
- `mode` (optional): Execution mode - "retail" or "custom" (default: "retail")
- `libraries` (optional): JSON array of library configurations (only used when mode="custom")

**Mode Options:**

**1. Retail Kit Mode (default):**
- Automatically creates all 3 libraries required for Data360 Retail Solution Kit
- No additional parameters needed
- Libraries created:
  1. DIY Bathroom Library (Bathroom_Remodelling_Instructions.pdf)
  2. Diy Building A Deck (Building_a_Deck_Instructions.pdf)
  3. Diy Seasonal (DIY Seasonal Product .pdf)

**2. Custom Mode:**
- Requires `mode="custom"` parameter
- Requires `libraries` JSON array with custom library configurations

**Example Custom Libraries JSON:**
```json
[
  {
    "masterLabel": "My Custom Library",
    "developerName": "MyCustomLibrary",
    "description": "Custom library description",
    "pdfFile": "path/to/file.pdf"
  }
]
```

**Common Use Cases:**

1. **Retail Kit (default):** `/agentforce-data-library OrgRetailTest3`
2. **Custom libraries:** `/agentforce-data-library OrgRetailTest3 --mode custom --libraries '[{...}]'`

---

## Preconditions

Before running:

- Salesforce CLI must be installed and authenticated with target org
- Target org must have Agentforce Data Library feature enabled
- Verify feature availability: Setup → Quick Find → "Agentforce Data Library" (page must exist)
- PDF file must exist at specified path
- User must have "Manage Einstein Features" or equivalent permission
- **IMPORTANT:** For uninterrupted execution, commands should be pre-approved in `.claude/settings.json`:
  ```json
  {
    "permissions": {
      "allow": [
        "Bash:sf *",
        "Bash:curl *",
        "Bash:stat *",
        "Bash:wc *"
      ]
    }
  }
  ```

---

## Workflow

**CRITICAL: Mode Detection**

**Step 0A — Check if libraries already exist:**

Before creating libraries, check if they already exist in the org:

```bash
curl -X GET \
  "{instance_url}/services/data/v66.0/einstein/data-libraries" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  --silent \
  --show-error
```

**Parse response:**
```json
{
  "libraries": [
    {
      "libraryId": "1JDxx000000ABCD123",
      "masterLabel": "DIY Bathroom Library",
      "developerName": "DIYBathroomLibrary",
      "status": "IN_PROGRESS",
      "groundingSource": {
        "groundingFileRefs": [...]
      }
    }
  ],
  "totalSize": 3
}
```

**Check for each library in Retail Kit mode:**
- DIY Bathroom Library (developerName: "DIYBathroomLibrary")
- Diy Building A Deck (developerName: "DiyBuildingADeck")
- Diy Seasonal (developerName: "DiySeasonal")

**If library already exists:**
1. Skip creation (Step 3)
2. Skip upload readiness check (Step 4)
3. Check if file already uploaded (look for groundingFileRefs array)
4. If groundingFileRefs is empty → Proceed with Steps 5-8 (upload file)
5. If groundingFileRefs has file → Report library already complete, skip to next library

**Step 0B — Determine execution mode:**

1. If `mode` parameter NOT provided or `mode="retail"`:
   - **Use Retail Kit Mode**
   - Automatically create 3 libraries:
     ```
     libraries = [
       {
         "masterLabel": "DIY Bathroom Library",
         "developerName": "DIYBathroomLibrary",
         "description": "Bathroom Remodelling instructions for Agentforce grounding",
         "pdfFile": "DIY Documents/DIY Documents/Bathroom_Remodelling_Instructions.pdf"
       },
       {
         "masterLabel": "Diy Building A Deck",
         "developerName": "DiyBuildingADeck",
         "description": "DIY Building a Deck instructions for Agentforce grounding",
         "pdfFile": "DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf"
       },
       {
         "masterLabel": "Diy Seasonal",
         "developerName": "DiySeasonal",
         "description": "DIY Seasonal Product instructions for Agentforce grounding",
         "pdfFile": "DIY Documents/DIY Documents/DIY Seasonal Product .pdf"
       }
     ]
     ```

2. If `mode="custom"`:
   - **Use Custom Mode**
   - Require `libraries` parameter
   - If `libraries` not provided, error and stop

**CRITICAL: Multiple Library Processing**

For both Retail Kit and Custom modes:
- Process each library sequentially (NOT in parallel)
- Reuse same authentication token throughout
- Track success/failure for each library
- Report combined summary at end

**Workflow applies to all modes:**

### Step 1 — Get org credentials and validate

**1.1 Get access token and org details:**

```bash
sf org display --target-org <org_alias> --json
```

Extract from JSON response:
- `result.accessToken` - OAuth access token
- `result.instanceUrl` - Org instance URL (e.g., https://myorg.my.salesforce.com)
- `result.username` - Org username
- `result.apiVersion` - Org API version (use for Einstein API calls)

Store these values for subsequent API calls.

**1.2 Validate Salesforce CLI authentication:**

If command fails with error:
```
Error: No authorization information found for <org_alias>
```

**Recovery:**
```bash
sf org login web -a <org_alias>
```
Wait for browser login to complete, then retry Step 1.

**1.3 Validate access token:**

Test token with a simple API call:
```bash
curl -X GET \
  "{instance_url}/services/data/v66.0/limits" \
  -H "Authorization: Bearer {access_token}" \
  --silent \
  --show-error
```

**If HTTP 401 (Invalid Session ID):**
- Token expired or invalid
- Re-run `sf org display --json` to get fresh token
- Salesforce session tokens typically valid for 2 hours

**Authentication token reuse:**
- Token valid for multiple library creations
- No need to re-authenticate between libraries
- Reuse same token for all API calls in workflow
- **Monitor for 401 errors** during workflow - if token expires mid-workflow, refresh and continue

---

### Step 2 — Verify PDF file exists

**Check if PDF file exists at specified path:**

```bash
test -f "DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf" && echo "EXISTS" || echo "NOT_FOUND"
```

**If file NOT_FOUND:**
- Report error: "PDF file not found at: DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf"
- Stop execution
- Suggest checking file path

**If file EXISTS:**
- Proceed to Step 3

---

### Step 3 — Create Data Library

**CRITICAL: Correct API Endpoint Path**

```
POST {instance_url}/services/data/v66.0/einstein/data-libraries
```

**NOT:** `/connect/einstein/data-libraries` (this returns 404)

**Request Headers:**

```
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{
  "masterLabel": "Diy Building A Deck",
  "developerName": "DiyBuildingADeck",
  "description": "DIY Building a Deck instructions for Agentforce grounding",
  "groundingSource": {
    "sourceType": "SFDRIVE"
  }
}
```

**Execute curl command:**

```bash
curl -X POST \
  "{instance_url}/services/data/v66.0/einstein/data-libraries" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "masterLabel": "Diy Building A Deck",
    "developerName": "DiyBuildingADeck",
    "description": "DIY Building a Deck instructions for Agentforce grounding",
    "groundingSource": {
      "sourceType": "SFDRIVE"
    }
  }' \
  --silent \
  --show-error
```

**Parse response:**

Success (HTTP 200):
```json
{
  "dataSpaceScopeId": "9gTxx000001Q1UXEA0",
  "description": "DIY Building a Deck instructions for Agentforce grounding",
  "developerName": "DiyBuildingADeck",
  "groundingSource": {
    "groundingFileRefs": [],
    "groundingSourceType": "SFDRIVE"
  },
  "libraryId": "1JDxx000000ABCDAAA",
  "masterLabel": "Diy Building A Deck",
  "sourceType": "SFDRIVE"
}
```

Extract `libraryId` field - this is the Library ID (starts with 1JD).

Store as: `LIBRARY_ID`

**Handle errors:**

- **HTTP 400: Invalid request** 
  - Check groundingSource structure: `{"sourceType": "SFDRIVE"}`
  - Verify developerName is alphanumeric (no spaces)
  - Check masterLabel is not empty
  - **If error contains "duplicate" or "already exists":** Library already exists, get library ID from error message or list endpoint, skip to Step 4

- **HTTP 401: Unauthorized** 
  - Access token expired
  - Re-authenticate: `sf org display --target-org <org_alias> --json`
  - Extract new accessToken and retry

- **HTTP 403: Missing permissions** 
  - User lacks "Manage Einstein Features" permission
  - Check: Setup → Users → Permission Sets → Einstein Features
  - Assign permission set and retry

- **HTTP 404: Feature not enabled** 
  - Agentforce Data Library feature not available in org
  - Verify: Setup → Quick Find → "Agentforce Data Library" page exists
  - Enable feature if available or contact Salesforce support

---

### Step 4 — Check upload readiness

**API Endpoint:**

```
GET {instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/upload-readiness?waitMaxTime=120000
```

**Query parameters:**
- `waitMaxTime` (optional): Maximum wait time in milliseconds (default 120000 = 120 seconds)

**Execute curl command:**

```bash
curl -X GET \
  "{instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/upload-readiness?waitMaxTime=120000" \
  -H "Authorization: Bearer {access_token}" \
  --silent \
  --show-error
```

**Why polling is needed:**
- Salesforce must activate the Unified Data Lake Object first
- API supports long-polling with waitMaxTime parameter
- Typically takes 10-30 seconds

**Success response:**

```json
{
  "libraryId": "1JDxx000000ABCDAAA",
  "message": "Data object is active. Ready for file uploads.",
  "ready": true,
  "sourceType": "SFDRIVE"
}
```

**Handle errors:**

- **HTTP 404: Library not found**
  - Library ID invalid or library was deleted
  - Verify library exists: GET /einstein/data-libraries
  - If library exists but endpoint returns 404, retry once (transient API issue)

- **Timeout (ready: false after 120 seconds)**
  - Data Lake Object activation taking longer than expected
  - Report: "Upload readiness timeout - Data Lake Object not ready"
  - **Automatic recovery:**
    1. Automatically retry with longer timeout: `waitMaxTime=300000` (5 minutes)
    2. If still not ready, wait 60 seconds and retry once more
    3. Continue with next library if all retries exhausted

- **HTTP 500: Internal server error**
  - Salesforce backend issue
  - Wait 30 seconds and retry once
  - If second attempt fails, report error and suggest trying later

---

### Step 5 — Generate presigned upload URL

**API Endpoint:**

```
POST {instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/file-upload-urls
```

**Request Body:**

```json
{
  "files": [
    {
      "fileName": "Building_a_Deck_Instructions.pdf"
    }
  ]
}
```

**IMPORTANT:** Do NOT include `mimeType` in request - it's returned in response headers

**Execute curl command:**

```bash
curl -X POST \
  "{instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/file-upload-urls" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "files": [
      {
        "fileName": "Building_a_Deck_Instructions.pdf"
      }
    ]
  }' \
  --silent \
  --show-error
```

**Parse response:**

Success:
```json
{
  "libraryId": "1JDxx000000ABCDAAA",
  "uploadUrls": [
    {
      "fileName": "Building_a_Deck_Instructions.pdf",
      "filePath": "$agentforce_data_library$/1JDxx000000ABCDAAA/Building_a_Deck_Instructions.pdf",
      "headers": {
        "Content-Type": "application/pdf"
      },
      "uploadUrl": "https://aws-prod8-cacentral1-cdp2-lakehouse-2.s3.ca-central-1.amazonaws.com/sfdrive/..."
    }
  ]
}
```

Extract:
- `uploadUrls[0].uploadUrl` - AWS S3 presigned URL (valid for 15 minutes)
- `uploadUrls[0].filePath` - File path for Step 7
- `uploadUrls[0].headers` - Required headers for upload

Store as: `UPLOAD_URL`, `FILE_PATH`, `HEADERS`

**Note:** The upload URL points to Salesforce's managed AWS S3 infrastructure

---

### Step 6 — Upload file to AWS S3

**Upload PDF to Salesforce's S3 bucket using presigned URL:**

```bash
curl -X PUT \
  "{upload_url}" \
  -H "Content-Type: application/pdf" \
  --upload-file "DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf" \
  --silent \
  --show-error
```

**What's happening:**
- File uploads directly to **Salesforce's AWS S3 storage**
- Uses presigned URL with temporary AWS credentials
- No additional authentication required
- File stored in Salesforce's Data Lake infrastructure

**Success:** HTTP 200 with empty response body

**Handle errors:**

- **HTTP 403: Forbidden**
  - Presigned URL expired (valid for 15 minutes)
  - **Recovery:** Go back to Step 5, generate new presigned URL, retry upload
  - **Prevention:** Complete upload within 15 minutes of URL generation

- **HTTP 400: Bad Request**
  - Invalid file format or corrupted PDF
  - **Check:** Verify PDF is valid: `file "path/to/file.pdf"` should show "PDF document"
  - **Check:** File size > 0 bytes
  - **Recovery:** If PDF valid, regenerate presigned URL and retry

- **Connection timeout/Network error**
  - Network connectivity issue or firewall blocking AWS S3
  - **Recovery:** Wait 10 seconds and retry once
  - **If retry fails:** Report error, suggest checking network/firewall settings

- **Timeout on large files**
  - File upload taking too long
  - **Recovery:** Increase curl timeout: `--max-time 600` (10 minutes)
  - **For files > 100MB:** Consider splitting upload or using streaming

- **HTTP 500/503: AWS S3 service error**
  - Temporary AWS infrastructure issue
  - **Recovery:** Wait 30 seconds and retry up to 3 times
  - **Exponential backoff:** Wait 30s, 60s, 120s between retries

---

### Step 7 — Get file size

**Get PDF file size in bytes for indexing request:**

```bash
stat -c%s "DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf" 2>/dev/null || wc -c < "DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf"
```

Store as: `FILE_SIZE`

Example output: `478680` (bytes)

---

### Step 8 — Trigger indexing

**API Endpoint:**

```
POST {instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/indexing
```

**Request Body:**

```json
{
  "uploadedFiles": [
    {
      "filePath": "$agentforce_data_library$/1JDxx000000ABCDAAA/Building_a_Deck_Instructions.pdf",
      "fileSize": 478680
    }
  ]
}
```

**Execute curl command:**

```bash
curl -X POST \
  "{instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/indexing" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "uploadedFiles": [
      {
        "filePath": "'"$FILE_PATH"'",
        "fileSize": '"$FILE_SIZE"'
      }
    ]
  }' \
  --silent \
  --show-error
```

**Success response:**

```json
{
  "filesAccepted": 1,
  "libraryId": "1JDxx000000ABCDAAA",
  "message": "Provisioning started",
  "sourceType": "SFDRIVE",
  "status": "IN_PROGRESS"
}
```

Indexing runs asynchronously in background.

Typically takes 2-10 minutes depending on file size.

**Handle errors:**

- **HTTP 400: Bad Request**
  - **Invalid filePath format:** Must be `$agentforce_data_library$/{library_id}/{filename}`
  - **Invalid fileSize:** Must be positive integer (bytes), not string
  - **Missing fields:** Both filePath and fileSize are required
  - **Recovery:** Verify filePath format and fileSize type, retry

- **HTTP 404: Library not found**
  - Library ID invalid or deleted
  - **Recovery:** Re-create library (Step 3) or verify library exists

- **HTTP 409: Conflict - File already indexed**
  - File with same name already indexed for this library
  - **Action:** Skip indexing (file already present), continue with next library

- **HTTP 500: Indexing service error**
  - Backend indexing service unavailable
  - **Recovery:** Wait 60 seconds and retry once
  - **If retry fails:** Report error and continue with next library

---

### Step 9 — Report completion

**For Retail Kit Mode and Custom Mode:**

On completion (all libraries processed):

```text
✅ Multiple Agentforce Data Libraries Created!

Org: <org_alias>
Instance: {instance_url}

📊 Summary: {success_count} succeeded, {failure_count} failed

════════════════════════════════════════════

✅ Successfully Created Libraries:

1. Diy Building A Deck
   Library ID: 1JDxx000000ABCD001
   File: Building_a_Deck_Instructions.pdf ({file_size_1} KB)
   Status: INDEXING

2. Diy Seasonal
   Library ID: 1JDxx000000ABCD002
   File: DIY Seasonal Product .pdf ({file_size_2} KB)
   Status: INDEXING

3. DIY Bathroom Library
   Library ID: 1JDxx000000ABCD003
   File: Bathroom_Remodelling_Instructions.pdf ({file_size_3} KB)
   Status: INDEXING

════════════════════════════════════════════

❌ Failed Libraries (if any):

1. Library Name: {failed_library_name}
   Error: {error_message}

════════════════════════════════════════════

⏳ Indexing Status: All libraries indexing (2-10 minutes each)

🔗 View in Salesforce:
{instance_url}/lightning/setup/EinsteinDataLibraries/home

Next Steps:
1. Wait for indexing to complete (2-10 minutes per library)
2. Navigate to Agent Builder
3. Go to Agent → Data tab
4. Add all created libraries as data sources
5. Save agent configuration
6. Test agent with questions about the documents
```

---

### Step 9 — Monitor indexing status

**API Endpoint:**

```
GET {instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/status
```

**Execute curl command:**

```bash
curl -X GET \
  "{instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/status" \
  -H "Authorization: Bearer {access_token}" \
  --silent \
  --show-error
```

**Response shows indexing progress:**

```json
{
  "indexingStatus": {
    "currentStage": "SEARCH_INDEX",
    "lastUpdatedAt": 1779201936211,
    "libraryId": "1JDxx000000KCQODGA5",
    "stages": {
      "DATA_LAKE_OBJECT": {
        "completedAt": 1779201815000,
        "status": "SUCCESS"
      },
      "DATA_MODEL_OBJECT": {
        "completedAt": 1779201815000,
        "status": "SUCCESS"
      },
      "SEARCH_INDEX": {
        "startedAt": 1779201815000,
        "status": "IN_PROGRESS"
      },
      "RETRIEVER": {
        "status": "SCHEDULED"
      }
    },
    "status": "IN_PROGRESS"
  }
}
```

**Indexing Stages:**

1. **DATA_LAKE_OBJECT** - File stored in Salesforce Data Lake (AWS S3)
2. **DATA_MODEL_OBJECT** - Data model created
3. **SEARCH_INDEX** - Search index and vector embeddings generated
4. **RETRIEVER** - Retriever configured for Agentforce grounding

**🚨 CRITICAL: API Status Inconsistency (Known Issue)**

**Issue:** Library overall `status` may remain `"IN_PROGRESS"` even after all 4 stages complete with `"SUCCESS"`.

**Detection:** Check both conditions to determine if library is actually ready:

**Condition 1 (Ideal):**
```json
{
  "indexingStatus": {
    "status": "READY",
    "stages": { /* all SUCCESS */ }
  }
}
```

**Condition 2 (API Bug - Functional but shows IN_PROGRESS):**
```json
{
  "indexingStatus": {
    "status": "IN_PROGRESS",  // ← Shows IN_PROGRESS
    "stages": {
      "DATA_LAKE_OBJECT": {"status": "SUCCESS"},
      "DATA_MODEL_OBJECT": {"status": "SUCCESS"},
      "SEARCH_INDEX": {"status": "SUCCESS"},
      "RETRIEVER": {"status": "SUCCESS"}  // ← All stages SUCCESS
    }
  }
}
```

**Real-world validation:** GET library details endpoint to confirm:
```bash
curl -X GET \
  "{instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}" \
  -H "Authorization: Bearer {access_token}"
```

**Check for:**
- `groundingSource.groundingFileRefs` is NOT empty (file uploaded)
- `retrieverId` field exists (retriever created)
- `retrieverLabel` field exists

**If all 3 conditions met → Library is READY regardless of status field**

**Completion criteria (use EITHER condition):**
1. Overall `status: "READY"` (ideal)
2. **OR** All 4 stages show `"SUCCESS"` + groundingFileRefs not empty + retrieverId exists (functional)

Typically takes 2-10 minutes for all stages to complete.

---

### Step 9.5 — MANDATORY: Wait for ALL libraries to reach READY before reporting success

**This step is a hard gate. The skill MUST NOT report success — and the orchestrator MUST NOT advance to the next skill (`/intelligent-context`) — until every library created in this run has reached READY (or the functional-equivalent state described in Step 9).**

**Polling parameters (fixed, do NOT shorten):**

| Parameter | Value |
|---|---|
| Check interval | **2 minutes** (`sleep 120` between checks) |
| Maximum total wait | **15 minutes** (≤ 8 polls per library) |
| Per-library check | GET `/services/data/v66.0/einstein/data-libraries/{library_id}/status` |
| Per-library completion | `indexingStatus.status == "READY"` **OR** all 4 stages == `"SUCCESS"` + `groundingFileRefs` non-empty + `retrieverId` present |
| Failure-on-stage | Any stage `status == "FAILED"` → fail-fast for that library, do NOT keep waiting |

**Implementation:**

```bash
# Step 9.5: Wait for all libraries to be READY
# LIBRARY_IDS comes from Steps 1–8 (set after each successful create+upload+index trigger)

CHECK_INTERVAL=120          # 2 minutes between checks
MAX_TOTAL_WAIT=900          # 15 minutes total
ELAPSED=0
declare -a PENDING_IDS=("${LIBRARY_IDS[@]}")
declare -a READY_IDS=()
declare -a FAILED_IDS=()

echo ""
echo "⏳ Waiting for ${#PENDING_IDS[@]} libraries to reach READY (poll every 2 min, max 15 min)..."

while [ ${#PENDING_IDS[@]} -gt 0 ] && [ $ELAPSED -lt $MAX_TOTAL_WAIT ]; do
  sleep $CHECK_INTERVAL
  ELAPSED=$((ELAPSED + CHECK_INTERVAL))
  STILL_PENDING=()

  for LIB_ID in "${PENDING_IDS[@]}"; do
    # Get status
    STATUS_JSON=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "${INSTANCE_URL}/services/data/v66.0/einstein/data-libraries/${LIB_ID}/status")

    READY_OR_FUNCTIONAL=$(echo "$STATUS_JSON" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    idx = d.get('indexingStatus', {})
    overall = idx.get('status', '')
    stages = idx.get('stages', {})
    if overall == 'READY':
        print('READY')
    elif overall == 'FAILED' or any(s.get('status') == 'FAILED' for s in stages.values()):
        # Find which stage failed
        failed_stages = [k for k,v in stages.items() if v.get('status') == 'FAILED']
        print('FAILED:' + ','.join(failed_stages) if failed_stages else 'FAILED')
    else:
        # Functional check — all 4 stages SUCCESS + groundingFileRefs + retrieverId
        required = ['DATA_LAKE_OBJECT', 'DATA_MODEL_OBJECT', 'SEARCH_INDEX', 'RETRIEVER']
        all_success = all(stages.get(s, {}).get('status') == 'SUCCESS' for s in required)
        if all_success:
            # Need to fetch library details to verify groundingFileRefs + retrieverId
            print('FUNCTIONAL_CHECK_NEEDED')
        else:
            current = idx.get('currentStage', 'unknown')
            print(f'PENDING:{current}')
except Exception as e:
    print(f'PARSE_ERROR:{e}')
")

    if [ "$READY_OR_FUNCTIONAL" = "FUNCTIONAL_CHECK_NEEDED" ]; then
      # Confirm via library details endpoint
      DETAIL_JSON=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        "${INSTANCE_URL}/services/data/v66.0/einstein/data-libraries/${LIB_ID}")
      FUNCTIONAL=$(echo "$DETAIL_JSON" | python -c "
import sys, json
try:
    d = json.load(sys.stdin)
    refs = (d.get('groundingSource', {}) or {}).get('groundingFileRefs', [])
    ret_id = d.get('retrieverId') or d.get('retrieverDeveloperName') or ''
    print('READY' if (refs and ret_id) else 'PENDING:retriever-not-ready')
except Exception as e:
    print(f'PARSE_ERROR:{e}')
")
      READY_OR_FUNCTIONAL="$FUNCTIONAL"
    fi

    case "$READY_OR_FUNCTIONAL" in
      READY)
        READY_IDS+=("$LIB_ID")
        echo "  ✅ ${LIB_ID}: READY (${ELAPSED}s elapsed)"
        ;;
      FAILED*)
        FAILED_IDS+=("$LIB_ID|${READY_OR_FUNCTIONAL}")
        echo "  ❌ ${LIB_ID}: ${READY_OR_FUNCTIONAL} (fail-fast — will not retry)"
        ;;
      *)
        STILL_PENDING+=("$LIB_ID")
        echo "  ⏳ ${LIB_ID}: ${READY_OR_FUNCTIONAL} (${ELAPSED}s elapsed)"
        ;;
    esac
  done

  PENDING_IDS=("${STILL_PENDING[@]}")
done

echo ""
echo "Final state after ${ELAPSED}s:"
echo "  READY:   ${#READY_IDS[@]} → ${READY_IDS[*]}"
echo "  PENDING: ${#PENDING_IDS[@]} → ${PENDING_IDS[*]}"
echo "  FAILED:  ${#FAILED_IDS[@]} → ${FAILED_IDS[*]}"

# Hard gate
if [ ${#PENDING_IDS[@]} -gt 0 ] || [ ${#FAILED_IDS[@]} -gt 0 ]; then
  echo ""
  echo "❌ ADL READY-STATE GATE FAILED"
  echo "   ${#READY_IDS[@]} of ${#LIBRARY_IDS[@]} libraries reached READY within ${MAX_TOTAL_WAIT}s."
  echo ""
  echo "Skill MUST NOT report success."
  echo "Orchestrator MUST NOT advance to /intelligent-context."
  echo ""
  echo "Inspect each pending/failed library:"
  for LIB_ID in "${PENDING_IDS[@]}"; do
    echo "  curl -s -H \"Authorization: Bearer \$TOKEN\" \\"
    echo "    \"\$INSTANCE_URL/services/data/v66.0/einstein/data-libraries/${LIB_ID}/status\" | python -m json.tool"
  done
  exit 1
fi

echo ""
echo "✅ All ${#READY_IDS[@]} libraries verified READY. Safe to proceed to /intelligent-context."
```

**Hard rules:**

- ✅ The skill is **only complete** when `READY_IDS` count == count of libraries created in this run, AND `PENDING_IDS` is empty, AND `FAILED_IDS` is empty.
- ❌ Do NOT shorten the 2-minute interval — Salesforce's indexing pipeline is back-end-rate-limited; polling more aggressively wastes API calls without speeding anything up.
- ❌ Do NOT extend the 15-minute timeout in this skill. If a library legitimately needs longer (rare — typical is 2–10 min), surface it to the user and let them re-run after manual inspection. Hiding a slow indexing failure behind a longer wait makes downstream failures (e.g. `/create-individual-retrievers` not finding the retriever) much harder to diagnose.
- ❌ Do NOT skip Step 9.5 even if Step 8 (trigger indexing) returned `IN_PROGRESS` for all libraries — that response only confirms the request was accepted, not that anything indexed.
- ⚠️ On **fail-fast** (any stage `FAILED`), the skill MUST `exit 1` immediately for that library — there's no recovery from a stage failure within the same run. The user has to delete the library, fix the root cause (file too large, malformed PDF, missing permission), and re-run the skill.
- ⚠️ The orchestrator (`data360-retail-installer`) treats any non-zero exit from this skill as a hard stop. The next skill (`/intelligent-context`) is **never** auto-invoked when Step 9.5 fails.

---

### Step 10 — Report completion and provide guidance

On success:

```text
✅ Agentforce Data Library Created Successfully!

Org: <org_alias>
Instance: {instance_url}

📚 Library Details:
   Name: Diy Building A Deck
   Library ID: {library_id}
   Developer Name: DiyBuildingADeck
   Status: IN_PROGRESS → READY (after indexing completes)

📄 File Uploaded:
   File: Building_a_Deck_Instructions.pdf
   Path: $agentforce_data_library$/{library_id}/Building_a_Deck_Instructions.pdf
   Size: {file_size} bytes ({file_size_kb} KB)
   Uploaded to: Salesforce's AWS S3 (Data Lake)

⏳ Indexing Progress:
   ✅ DATA_LAKE_OBJECT: SUCCESS
   ✅ DATA_MODEL_OBJECT: SUCCESS
   🔄 SEARCH_INDEX: IN_PROGRESS
   ⏰ RETRIEVER: SCHEDULED

   Estimated completion: 2-10 minutes

🔗 View in Salesforce:
{instance_url}/lightning/setup/EinsteinDataLibrary/home

Next Steps:
1. Wait for indexing to complete (check status via API or UI)
2. Navigate to Agent Builder in Salesforce
3. Select your Agentforce Agent
4. Go to Data tab
5. Click "Add Data Source"
6. Select "Diy Building A Deck" library
7. Save agent configuration
8. Test agent with questions:
   - "How do I build a deck?"
   - "What materials do I need for deck construction?"
   - "What are the steps for building a deck?"
```

On error:

```text
❌ Data Library Creation Failed

Org: <org_alias>
Error: {error_message}

Possible Causes:
1. Feature not enabled - Agentforce Data Library not visible in Setup
2. Wrong API endpoint - Must use /einstein/data-libraries (not /connect/einstein)
3. Missing permissions - Need "Manage Einstein Features" permission
4. File upload failed - Presigned URL expired or network issue
5. Invalid PDF format - File corrupted or wrong MIME type
6. Org type limitation - Feature may not be available in scratch orgs

Suggested Fix:
✅ Verify feature enabled: Setup → Quick Find → "Agentforce Data Library"
✅ Check API endpoint: /services/data/v66.0/einstein/data-libraries
✅ Check permissions: Setup → Users → Permission Sets → Einstein Features
✅ Verify PDF file: DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf
✅ Re-authenticate if needed: sf org login web -a <org_alias>
✅ Check file upload: Ensure presigned URL used within 15 minutes
```

---

### Monitoring via Einstein API (Programmatic)

Poll status endpoint every 30 seconds:
```bash
curl -X GET \
  "{instance_url}/services/data/v66.0/einstein/data-libraries/{library_id}/status" \
  -H "Authorization: Bearer {access_token}"
```

When `indexingStatus.status` changes to `"READY"` and all stages show `"SUCCESS"`, indexing is complete.

**Indexing Timeline:**

| Time | Stage | Status | Activity |
|------|-------|--------|----------|
| 0-1 min | DATA_LAKE_OBJECT | SUCCESS | File uploaded to AWS S3 |
| 0-1 min | DATA_MODEL_OBJECT | SUCCESS | Data model created |
| 1-5 min | SEARCH_INDEX | IN_PROGRESS | Vector embeddings generated |
| 5-10 min | RETRIEVER | SUCCESS | Retriever configured |
| 5-10 min | Overall | READY | Library ready for Agentforce |

---

## Important Rules

**CRITICAL - Correct API Endpoint:**
- 🚨 **ALWAYS use:** `/services/data/v66.0/einstein/data-libraries`
- 🚨 **NEVER use:** `/services/data/v66.0/connect/einstein/data-libraries` (returns 404)
- The `/connect/` path is INCORRECT and will fail
- Use Einstein API directly, not Connect API

**CRITICAL - Request Body Structure:**
- 🚨 **Use:** `masterLabel`, `developerName`, `groundingSource` structure
- 🚨 **NOT:** `name`, `dataSourceType` (old/incorrect structure)
- groundingSource must contain: `{"sourceType": "SFDRIVE"}`
- developerName must be alphanumeric without spaces (e.g., "DiyBuildingADeck")

**CRITICAL - File Upload Flow:**
- 🚨 **Do NOT include `mimeType` in file-upload-urls request**
- 🚨 **mimeType comes back in response headers**
- 🚨 **Upload directly to AWS S3** using presigned URL
- 🚨 **Must include file size** in indexing request (get via `stat` or `wc -c`)
- 🚨 **Use `/indexing` endpoint** (not `/index`)
- 🚨 **Body uses `uploadedFiles` array** with `filePath` and `fileSize`

**General Rules:**
- NEVER hardcode org names - always use provided org_alias parameter
- ALWAYS verify PDF file exists before starting upload
- ALWAYS wait for upload readiness (use waitMaxTime=120000 parameter)
- ALWAYS use correct file path format: `$agentforce_data_library$/{library_id}/{filename}`
- ALWAYS get file size before triggering indexing
- Library ID starts with 1JD (18-character Salesforce ID)
- Presigned URLs expire after 15 minutes (900 seconds) - complete upload quickly
- Indexing is asynchronous with 4 stages - takes 2-10 minutes
- Monitor indexing status via /status endpoint
- Guide user to assign library to agent in Agent Builder after completion

**Mode Rules:**
- **Retail Kit Mode (default):** Automatically creates 3 libraries without requiring libraries parameter
- **Custom Mode:** Requires `mode="custom"` and `libraries` parameter
- Process libraries sequentially (NEVER in parallel)
- Reuse same authentication token for all libraries
- If one library fails, continue processing remaining libraries
- Track success/failure for each library separately
- Report combined summary at end with all successes and failures
- Complete all Steps 2-8 for each library before moving to next library
- Do NOT create new org authentication between libraries (reuse token from Step 1)

**API Requirements:**
- **Use API version v66.0 or higher** (current: v66.0, latest: v67.0 as of 2026)
- **Check supported API version:** Before starting, verify org API version
  ```bash
  sf org display --target-org <org_alias> --json | grep apiVersion
  ```
- **API version selection:**
  - Use org's `apiVersion` from `sf org display`
  - If org API version < v66.0, use v66.0 (minimum for ADL)
  - If org API version >= v66.0, use org's version (e.g., v67.0)
- Content-Type must be "application/json" for all Salesforce API requests
- S3 upload must use "Content-Type: application/pdf"
- Access token required for all Salesforce API calls
- NO authentication needed for S3 upload (uses presigned URL)
- Upload readiness endpoint supports long-polling via waitMaxTime parameter

**Error Handling & Recovery:**

**Step 3 (Library Creation) Errors:**
| Error | Cause | Recovery Action |
|-------|-------|----------------|
| HTTP 404 | Wrong endpoint (has /connect/) | Fix URL: Remove /connect/ from path |
| HTTP 400 | Invalid body structure | Check masterLabel, developerName, groundingSource format |
| HTTP 400 (duplicate) | Library already exists | Get existing library ID, skip to Step 4 |
| HTTP 401 | Expired token | Re-run: `sf org display --json`, extract new token |
| HTTP 403 | Missing permissions | Assign "Manage Einstein Features" permission |

**Step 4 (Upload Readiness) Errors:**
| Error | Cause | Recovery Action |
|-------|-------|----------------|
| HTTP 404 | Library not found | Verify library exists, retry once |
| Timeout (ready: false) | Data Lake Object slow | Retry with `waitMaxTime=300000` (5 min) |
| HTTP 500 | Backend error | Wait 30s, retry once |

**Step 5 (Presigned URL) Errors:**
| Error | Cause | Recovery Action |
|-------|-------|----------------|
| HTTP 400 | Invalid request | Check fileName format, verify file exists |
| HTTP 404 | Library not found | Re-create library or verify library ID |

**Step 6 (S3 Upload) Errors:**
| Error | Cause | Recovery Action |
|-------|-------|----------------|
| HTTP 403 | URL expired (>15 min) | Go back to Step 5, regenerate URL, retry |
| HTTP 400 | Invalid PDF | Verify PDF valid: `file path/to/file.pdf` |
| Connection timeout | Network/large file | Increase timeout: `--max-time 600` |
| HTTP 500/503 | AWS S3 issue | Retry 3x with exponential backoff: 30s, 60s, 120s |

**Step 8 (Indexing) Errors:**
| Error | Cause | Recovery Action |
|-------|-------|----------------|
| HTTP 400 | Invalid filePath/fileSize | Fix format, ensure fileSize is integer |
| HTTP 404 | Library not found | Re-create library |
| HTTP 409 | File already indexed | Skip (already complete) OR delete and re-index |
| HTTP 500 | Indexing service down | Wait 60s, retry once |

**General Error Recovery Pattern:**
1. **Identify error type** (HTTP code, message)
2. **Log full error response** for debugging
3. **Check if retryable** (401, 403, 500, 503, timeout)
4. **Apply recovery action** from table above
5. **If recovery fails** → Skip library, continue with next (don't fail entire workflow)
6. **Report all failures** in final summary with recovery suggestions

**AWS S3 Upload Details:**
- Files upload to Salesforce's managed AWS S3 buckets
- Example URL domain: `aws-prod8-cacentral1-cdp2-lakehouse-2.s3.ca-central-1.amazonaws.com`
- This is Salesforce's infrastructure (not customer's AWS account)
- Presigned URLs contain temporary AWS credentials
- Files stored in Salesforce Data Lake for Agentforce processing

---

## File Path Handling

**Default file path:**
```
DIY Documents/DIY Documents/Building_a_Deck_Instructions.pdf
```

**Note:** The directory structure has nested "DIY Documents" folders. This is intentional based on the actual repository structure.

**If custom pdf_file argument provided:**
- Verify path is relative to project root
- Check file exists before starting workflow
- Extract filename from path for API calls

**Example with custom path:**
```
pdf_file = "documents/my-file.pdf"
→ fileName = "my-file.pdf"
→ filePath (after upload) = "$agentforce_data_library$/1JDxx000000ABCDAAA/my-file.pdf"
```

**File size calculation:**
```bash
# Works on Linux/Git Bash
stat -c%s "path/to/file.pdf"

# Fallback for all platforms
wc -c < "path/to/file.pdf"
```

---

## Post-Creation

After library creation and indexing complete, libraries are automatically configured for use in subsequent skills (Agent setup configuration adds them to agents programmatically).
