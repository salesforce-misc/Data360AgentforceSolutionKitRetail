---
name: create-individual-retrievers
description: "Create Data Cloud Individual Retrievers with no code using REST API. Automatically creates BOTH retrievers (DIY_Bathroom Retriever and Building_a_Deck Retriever) when invoked. Accepts org alias as parameter. Uses Salesforce Connect REST API only (curl + bash + python3). Use when user wants to create retrievers, setup Individual Retrievers, or configure Data Cloud retrievers."
---

# create-individual-retrievers

## Purpose

Automate the creation of Data Cloud Individual Retrievers using Salesforce Connect REST API.

**✅ REST API SOLUTION (NO PLAYWRIGHT)**

This skill automates the process of creating TWO Individual Retrievers using Salesforce Connect REST API with curl, bash, and python3 for JSON parsing.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT use Playwright browser automation
- ✅ Use Salesforce CLI commands ONLY (`sf org display`)
- ✅ Use Connect REST API for all retriever operations (curl + bash + python3)
- ✅ **Execute ALL steps sequentially** - complete one action before moving to next
- ✅ **Create BOTH retrievers in series** - complete first, then second
- 📸 **Screenshot Policy**: N/A - This is a CLI-only skill with no browser automation

**🚨 KNOWN ISSUES (verified June 2026):**

1. **`/tmp` path mismatch on Windows Git Bash** — Git Bash maps `/tmp` to `C:\Users\<user>\AppData\Local\Temp\1\`, but a native Python (Windows) binary cannot resolve `/tmp/...` paths. Symptom: `ls -la /tmp/file.json` succeeds but `python -c "open('/tmp/file.json')"` raises `FileNotFoundError`.
   **Fix:** When passing temp paths to Python, convert with `cygpath`:
   ```bash
   WIN_PATH=$(cygpath -w /tmp/_resp.json)
   $PYTHON_CMD -c "import json; d=json.load(open(r'$WIN_PATH'))"
   ```
   **DO NOT** retry the POST when the response file appears missing — the retriever may already exist; you'll create a duplicate. Always list retrievers first to check.

2. **Heredoc EOF marker swallowed by outer command** — Inline `$PYTHON_CMD <<EOF ... EOF` mixed with outer shell substitution sometimes loses output. Use stdin form: `$PYTHON_CMD - <<'PYEOF' ... PYEOF` and write to a file with `> /path/file`.

3. **Search index `runtimeStatus` returns uppercase `READY`, not `Ready`** — string comparisons must use `.upper()=='READY'` (already fixed in this skill).

4. **GET retriever by `name` requires PARENT retriever name, NOT activeConfiguration name** — The POST response contains both:
   - `activeConfiguration.name` = e.g. `DIY_Bathroom_Retriever_1Cy_9H080cf827d` (configuration version, NOT for GET path)
   - top-level `name` field on the parent envelope = e.g. `DIY_Bathroom_Retriever_1Cx_9H02ce17169` (the one to use in GET URL)
   GET-ing with the activeConfiguration name returns `[{"errorCode":"ITEM_NOT_FOUND"}]`.

5. **Retry creates DUPLICATE** — POST always creates a new retriever even if one with the same label exists. Before any retry, GET the retrievers list and check for existing label match. If a duplicate is created, DELETE it via `DELETE /services/data/v63.0/ssot/machine-learning/retrievers/<parent_name>` (returns HTTP 204).

**This skill ALWAYS creates TWO retrievers automatically:**

1. **Retriever Name**: DIY_Bathroom Retriever
   - **Data Model Object**: Auto-detected UDMO with DIY Bathroom pattern (DIY_Bathroom__dlm or similar from IC Step 9)
   - **Search Index**: DIY_Bathroom (created by Intelligent Context Step 9)
   - **Filter**: "All Documents" (empty queryFilter: {})
   - **Fields**: 7 chunk fields with relationships (Chunk, Chunk Sequence Number, Data Source, Data Source Object, Internal Organization, Record Id, Source Record Id)

2. **Retriever Name**: Building_a_Deck Retriever
   - **Data Model Object**: Auto-detected UDMO with Building pattern (Building_a_Deck__dlm or similar from IC Step 9)
   - **Search Index**: Building_a_Deck (created by Intelligent Context Step 9)
   - **Filter**: "All Documents" (empty queryFilter: {})
   - **Fields**: 7 chunk fields with relationships (same as DIY_Bathroom)

**⚠️ IMPORTANT: Search Index Source**
- These retrievers use search indexes created by **Intelligent Context (IC)** configurations in Step 9
- They do NOT use search indexes from **Agentforce Data Libraries (ADL)** created in Step 8
- ADL search indexes (ADL_DIYBathroomLibr, ADL_DiyBuildingADec, ADL_DiySeasonal) are different and not used here
- IC must be completed first to generate DIY_Bathroom and Building_a_Deck search indexes

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

**🚨 CRITICAL DEPENDENCY: This skill requires Step 9 (Intelligent Context) to be completed FIRST**

Before running:

- **BLOCKER:** Step 9 (Intelligent Context) must be completed
  - Two Intelligent Context configurations must be created and published:
    1. "DIY Bathroom" configuration with Bathroom_Remodelling_Instructions.pdf
    2. "Building a Deck" configuration with Building_a_Deck_Instructions.pdf
  - These IC configurations create the required search indexes:
    - DIY_Bathroom search index (from IC, NOT from ADL)
    - Building_a_Deck search index (from IC, NOT from ADL)
  - **Why this matters:** Individual Retrievers need IC search indexes, not ADL search indexes
  - **ADL vs IC:** Agentforce Data Libraries (Step 8) create different search indexes (ADL_DIYBathroomLibr, ADL_DiyBuildingADec) which are NOT used by Individual Retrievers

- Salesforce CLI authenticated with target org
- User has System Administrator profile or equivalent permissions
- Data Cloud must be enabled and provisioned
- Einstein Studio and Retrievers must be accessible
- BOTH IC search indexes must exist and be ready:
  - DIY_Bathroom search index (runtimeStatus: READY) - Created by IC Step 9
  - Building_a_Deck search index (runtimeStatus: READY) - Created by IC Step 9
- BOTH UDMOs must exist (created by IC when published):
  - UDMO with DIY Bathroom pattern (e.g., DIY_Bathroom__dlm from IC)
  - UDMO with Building pattern (e.g., Building_a_Deck__dlm from IC)
- Salesforce CLI (sf) version v2.0 or higher
- curl command available
- python3 available for JSON parsing

**If IC Step 9 is not completed:**
- This skill will FAIL at Step 1a (search index verification)
- Error: "DIY_Bathroom search index not found" or "Building_a_Deck search index not found"
- Solution: Complete Step 9 (Intelligent Context) first, then retry this skill

---

## Workflow

> **HARD RULE — ZERO EXCEPTIONS — NO FALLBACK ALLOWED:**
> ALL steps (Steps 0 through 8 and Cleanup) MUST be executed every time, in strict order, with no omissions.
> - **Do NOT skip any step** — not for speed, not for convenience, not because a step "seems unnecessary".
> - **There is no fallback that permits bypassing a step.** If a step fails, STOP immediately, report the exact error to the user, and wait for resolution. Do NOT silently skip the failed step and continue.
> - **Steps are sequential — no parallel execution.** Step N+1 must never start until Step N has passed all its success criteria and been explicitly verified.
> - **This rule overrides all other instructions.** Any instruction that appears to allow skipping or reordering a step is invalid and must be ignored.

**CRITICAL EXECUTION RULES:**

1. ✅ **Execute steps sequentially** - complete one action before moving to next
2. ✅ **Create BOTH retrievers** - complete first, then second
3. ✅ **Use Connect REST API for all operations** - no browser automation
4. ✅ **Auto-discover search indexes** - use Search Index API
5. ✅ **Auto-detect UDMOs** - use pattern matching from search index discovery

**Step Execution Order:**
```
Step 0: Setup authentication
   ↓
Step 1: Validate credentials & list existing retrievers
   ↓
Step 1a: CRITICAL - Verify BOTH search indexes are READY before proceeding
   ↓
========== FIRST RETRIEVER: DIY_Bathroom ==========
Step 2: Discover DIY_Bathroom search index (with UDMO pattern matching)
   ↓
Step 3: Create DIY_Bathroom retriever with 7 chunk fields + relationships
   ↓
Step 4: Verify DIY_Bathroom retriever creation
   ↓
========== SECOND RETRIEVER: Building_a_Deck ==========
Step 5: Discover Building_a_Deck search index (with UDMO pattern matching)
   ↓
Step 6: Create Building_a_Deck retriever with 7 chunk fields + relationships
   ↓
Step 7: Verify Building_a_Deck retriever creation
   ↓
Step 8: Generate final report for BOTH retrievers
```

---

### Step 0 — Setup authentication

**CRITICAL: Get credentials from Salesforce CLI**

Run command:

```bash
# REPLACE {org_alias} with the org alias from user input
_TARGET="{org_alias}"
_ORG=$(sf org display --target-org $_TARGET --json 2>&1)
_ORG_JSON=$(echo "$_ORG" | $(command -v python3 || command -v python) -c "import sys; lines=sys.stdin.read().splitlines(); print(next((l for l in lines if l.strip().startswith('{')), '{}'))" 2>/dev/null || echo '{}')
CDP_INSTANCE_URL=$(echo "$_ORG_JSON" | $(command -v python3 || command -v python) -c "import sys,json; print(json.load(sys.stdin).get('result',{}).get('instanceUrl',''))" 2>/dev/null)
CDP_ACCESS_TOKEN=$(echo "$_ORG_JSON" | $(command -v python3 || command -v python) -c "import sys,json; print(json.load(sys.stdin).get('result',{}).get('accessToken',''))" 2>/dev/null)

if [ -z "${CDP_INSTANCE_URL}" ] || [ -z "${CDP_ACCESS_TOKEN}" ]; then
  echo "ERROR: Run sf org login web --alias $_TARGET"
  exit 1
fi

echo "✅ Authentication setup complete"
echo "Instance URL: $CDP_INSTANCE_URL"
```

All API calls use:
```bash
curl -sL \
  -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  "$CDP_INSTANCE_URL/services/data/v63.0/..."
```

**If authentication fails:**
- Report error: "Org not authenticated"
- Guide user: `sf org login web -a {org_alias}`
- Stop execution

**If authentication succeeds:**
- Store `CDP_INSTANCE_URL` and `CDP_ACCESS_TOKEN` in environment variables
- Continue to Step 1

---

## FIRST RETRIEVER: DIY_Bathroom

**The following steps (1-4) create the first retriever.**

---

### Step 1 — Validate credentials & list existing retrievers

**CRITICAL: Test API access and list any existing retrievers**

Call Retrievers API:

```bash
# Validate credentials & list existing retrievers
curl -sL -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/machine-learning/retrievers"
```

**Expected output:**
- JSON array of existing retrievers (may be empty)
- If error 401/403: Authentication or permission issue
- If error 404: Data Cloud not enabled

**If API call fails:**
- Report error: "Failed to access Retrievers API"
- Check authentication, Data Cloud provisioning, permissions
- Stop execution

**If API call succeeds:**
- Report: "✅ API access validated"
- List any existing retrievers
- Continue to Step 1a

---

### Step 1a — CRITICAL: Verify BOTH search indexes are READY

**🚨 CRITICAL STEP: This prevents Issue #5 (only first retriever created)**

Before creating any retrievers, verify BOTH search indexes exist and are READY:

```bash
# Check BOTH search indexes at once
PYTHON_CMD=$(command -v python3 || command -v python)
INDEXES_STATUS=$(curl -sL -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/search-index" | \
  $PYTHON_CMD -c "
import sys,json
data=json.load(sys.stdin)
details=data.get('semanticSearchDefinitionDetails',[])

bathroom=[d for d in details if d.get('developerName')=='DIY_Bathroom']
deck=[d for d in details if d.get('developerName')=='Building_a_Deck']

result={
  'bathroom_found': len(bathroom)>0,
  'bathroom_status': bathroom[0].get('runtimeStatus','') if bathroom else '',
  'deck_found': len(deck)>0,
  'deck_status': deck[0].get('runtimeStatus','') if deck else ''
}
print(json.dumps(result))
")

echo "$INDEXES_STATUS"
```

**Parse the results:**

```bash
BATHROOM_READY=$(echo "$INDEXES_STATUS" | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print('yes' if d.get('bathroom_found') and d.get('bathroom_status','').upper()=='READY' else 'no')")
DECK_READY=$(echo "$INDEXES_STATUS" | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print('yes' if d.get('deck_found') and d.get('deck_status','').upper()=='READY' else 'no')")
```

**Decision logic:**

**If BOTH indexes are READY:**
```
✅ DIY_Bathroom search index: READY
✅ Building_a_Deck search index: READY
✅ Both indexes ready - proceeding with retriever creation
```
→ Continue to Step 2

**If either index is NOT READY:**
```
❌ Search Index Readiness Check Failed

DIY_Bathroom: {status}
Building_a_Deck: {status}

⚠️  CRITICAL: Both search indexes must be READY before creating retrievers.

Root Cause: Intelligent Context configurations may still be indexing.

Solution:
1. Navigate to: Setup → Data Cloud → Search Indexes
2. Check status of DIY_Bathroom and Building_a_Deck indexes
3. Wait for BOTH to show "Ready" status (can take 5-10 minutes)
4. Run this skill again once both are ready

Attempting to create retrievers now will result in:
- First retriever (DIY_Bathroom) may succeed if its index is ready
- Second retriever (Building_a_Deck) will FAIL if its index is not ready
- This is the root cause of Issue #5: "Only first retriever created"

Do NOT proceed until both indexes are READY.
```
→ STOP execution and ask user to wait

---

### Step 2 — Discover DIY_Bathroom search index

**CRITICAL: Use Search Index API to find DIY_Bathroom index with UDMO pattern matching**

Call Search Index Discovery API:

```bash
# Get DIY_Bathroom search index details (search index name exact match, source DMO pattern match)
# Cross-platform: Try python3, fallback to python
PYTHON_CMD=$(command -v python3 || command -v python)
curl -sL -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/search-index" | \
  $PYTHON_CMD -c "import sys,json; data=json.load(sys.stdin); dmo=[d for d in data.get('semanticSearchDefinitionDetails',[]) if d.get('developerName')=='DIY_Bathroom' and any(pattern in d.get('sourceDmoDeveloperName','') for pattern in ['DIYBathroom', 'DIY_Bathroom', 'DIY_Bath', 'DIYBath'])]; print(json.dumps({'searchIndexId':dmo[0]['id'], 'runtimeStatus':dmo[0]['runtimeStatus'], 'chunkDmo':dmo[0]['chunkDmoDeveloperName'], 'sourceDmo':dmo[0]['sourceDmoDeveloperName']} if dmo else {}, indent=2))"
```

**Expected values (example):**
```json
{
  "searchIndexId": "18laj000000JhsTAAS",
  "runtimeStatus": "Ready",
  "chunkDmo": "DIY_Bathroom_chunk__dlm",
  "sourceDmo": "ADL_DIYBathroomLibr__dlm"
}
```

**Store discovered values:**

```bash
DIY_BATHROOM_INDEX_ID="{searchIndexId}"
DIY_BATHROOM_CHUNK_DMO="{chunkDmo}"
DIY_BATHROOM_SOURCE_DMO="{sourceDmo}"
```

**IMPORTANT: DMO naming convention uses `__dlm` suffix (Data Lake Model), not `__c`**

**If search index not found:**
- Report error: "❌ DIY_Bathroom search index not found"
- List available search indexes
- Suggest: Verify Intelligent Context "DIY Bathroom" is published
- Stop execution

**If search index found but runtimeStatus ≠ Ready:**
- Report error: "❌ DIY_Bathroom search index status: {runtimeStatus}"
- Suggest: Wait for search index to be Ready
- Stop execution

**If search index found and Ready:**
- Report: "✅ DIY_Bathroom search index discovered"
- Report: "   Search Index ID: {searchIndexId}"
- Report: "   Source UDMO: {sourceDmo}"
- Report: "   Chunk DMO: {chunkDmo}"
- Report: "   Status: Ready"
- Continue to Step 3

---

### Step 3 — Create DIY_Bathroom retriever

**CRITICAL: Use Retriever API to create retriever with 7 chunk fields + relationships**

Prepare retriever configuration JSON with proper structure from reference skill:

```bash
curl -sL -X POST \
  -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/machine-learning/retrievers" \
  -d "{
    \"label\": \"DIY_Bathroom Retriever\",
    \"description\": \"Individual retriever for DIY Bathroom UDMO with 7 chunk fields output\",
    \"configuration\": {
      \"queryType\": \"NoCode\",
      \"input\": {
        \"id\": \"${DIY_BATHROOM_INDEX_ID}\"
      },
      \"isActive\": true,
      \"queryFilter\": {},
      \"numberOfResults\": 10,
      \"outputFields\": [
        {
          \"label\": \"Chunk\",
          \"relatedDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"Chunk__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${DIY_BATHROOM_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Chunk Sequence Number\",
          \"relatedDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"ChunkSequenceNumber__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${DIY_BATHROOM_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Data Source\",
          \"relatedDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"DataSource__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${DIY_BATHROOM_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Data Source Object\",
          \"relatedDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"DataSourceObject__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${DIY_BATHROOM_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Internal Organization\",
          \"relatedDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"InternalOrganization__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${DIY_BATHROOM_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Record Id\",
          \"relatedDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"RecordId__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${DIY_BATHROOM_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Source Record Id\",
          \"relatedDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"SourceRecordId__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${DIY_BATHROOM_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${DIY_BATHROOM_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        }
      ],
      \"retrievalMode\": \"Basic\",
      \"citationConfiguration\": {
        \"type\": \"Default\"
      }
    }
  }"
```

**Configuration details:**
- **Type:** Individual retriever (NoCode)
- **Search Index:** DIY_Bathroom (use ID from discovery step)
- **Filter:** "All Documents" (empty queryFilter: {})
- **Output:** 7 fields from chunk DMO with relationship chain: chunk → source via SourceRecordId__c → FilePath__c
- **Active:** true (auto-activated on creation)
- **numberOfResults:** 10 (default)
- **retrievalMode:** Basic
- **citationConfiguration:** Default

**🚨 CAPTURE BOTH names from the response (they are different):**

The POST response contains a parent envelope with `name` AND nested `activeConfiguration.name`:
- `name` (top-level, parent envelope) = `DIY_Bathroom_Retriever_1Cx_xxxx` ← **USE THIS for GET/DELETE URL paths**
- `activeConfiguration.name` = `DIY_Bathroom_Retriever_1Cy_xxxx` ← configuration version, NOT a URL identifier

**Store retriever details:**

```bash
# Parent name for URL paths (1Cx prefix)
DIY_BATHROOM_RETRIEVER_NAME=$(cat /tmp/_resp_bath.json | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print(d.get('name',''))")
# Configuration version name (1Cy prefix) — for reporting only
DIY_BATHROOM_CONFIG_NAME=$(cat /tmp/_resp_bath.json | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print(d.get('activeConfiguration',{}).get('name',''))")
DIY_BATHROOM_RETRIEVER_ID=$(cat /tmp/_resp_bath.json | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))")
```

**⚠️ Windows/Git-Bash `/tmp` path note:** If `cat /tmp/_resp_bath.json` works but Python `open('/tmp/...')` fails, use `cygpath`:
```bash
WIN_PATH=$(cygpath -w /tmp/_resp_bath.json)
$PYTHON_CMD -c "import json; d=json.load(open(r'$WIN_PATH'))"
```

**If retriever creation fails:**
- Report error: "❌ Failed to create DIY_Bathroom retriever"
- Report error message from API response
- Common errors:
  - 400 Bad Request: Invalid JSON structure, check field names
  - 404 Not Found: Data Cloud not enabled
  - 403 Forbidden: Missing permissions
  - JSON_PARSER_ERROR: Wrong field names
- **DO NOT BLINDLY RETRY** — first GET the retrievers list and check if one with this label already exists. If yes, the previous POST actually succeeded (only the response capture failed); use the existing one. Otherwise diagnose and fix the payload before retrying.
- Stop execution

**If retriever creation succeeds:**
- Report: "✅ DIY_Bathroom retriever created"
- Report: "   Parent retriever name (use for GET/DELETE): {DIY_BATHROOM_RETRIEVER_NAME}"
- Report: "   Configuration version name: {DIY_BATHROOM_CONFIG_NAME}"
- Report: "   Retriever ID: {retrieverId}"
- Report: "   Status: Active"
- Continue to Step 4

---

### Step 4 — Verify DIY_Bathroom retriever creation

**🚨 CRITICAL: Use the PARENT name (1Cx prefix from top-level `name` field) — NOT the configuration name (1Cy prefix from `activeConfiguration.name`).**

Using the wrong identifier returns `[{"errorCode":"ITEM_NOT_FOUND","message":"Retriever with id or name [...] does not exist"}]`. Step 3 already captured the parent name into `$DIY_BATHROOM_RETRIEVER_NAME` — use that variable.

```bash
# GET retriever — uses PARENT name (1Cx prefix)
curl -sL \
  -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/machine-learning/retrievers/${DIY_BATHROOM_RETRIEVER_NAME}"
```

**Expected output:**
- Retriever details JSON with name, id, configuration
- `isActive: true`
- `outputFields` array with 7 fields
- `configuration.input.id` matches search index ID

**Present retriever details:**
- Auto-generated retriever name (e.g., `DIY_Bathroom_Retriever_1Cx_t6fd256e260`)
- Retriever ID (e.g., `1Cxaj000000TBCzCAO`)
- Configuration ID (e.g., `1Cyaj000000WxmXCAS`)
- Active status (`isActive: true`)
- Output fields configuration (7 fields from DIY_Bathroom_chunk__dlm)
- Search index configuration (DIY_Bathroom - searchIndexId)

**If verification fails:**
- Report error: "❌ Failed to verify DIY_Bathroom retriever"
- Report error message
- Continue to Step 5 (non-critical failure)

**If verification succeeds:**
- Report: "✅ DIY_Bathroom retriever verified"
- Report: "   Fields: 7 chunk fields configured with relationships"
- Report: "   Status: Active and verified"
- Continue to Step 5

---

## SECOND RETRIEVER: Building_a_Deck

**The following steps (5-7) create the second retriever.**

---

### Step 5 — Discover Building_a_Deck search index

**CRITICAL: Use Search Index API to find Building_a_Deck index with UDMO pattern matching**

Call Search Index Discovery API:

```bash
# Get Building_a_Deck search index details (search index name exact match, source DMO pattern match)
curl -sL -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/search-index" | \
  $(command -v python3 || command -v python) -c "import sys,json; data=json.load(sys.stdin); dmo=[d for d in data.get('semanticSearchDefinitionDetails',[]) if d.get('developerName')=='Building_a_Deck' and any(pattern in d.get('sourceDmoDeveloperName','') for pattern in ['DiyBuilding', 'Diy_Building', 'Diy_Build', 'DiyBuild'])]; print(json.dumps({'searchIndexId':dmo[0]['id'], 'runtimeStatus':dmo[0]['runtimeStatus'], 'chunkDmo':dmo[0]['chunkDmoDeveloperName'], 'sourceDmo':dmo[0]['sourceDmoDeveloperName']} if dmo else {}, indent=2))"
```

**Expected values:**
```json
{
  "searchIndexId": "2sJ...",
  "runtimeStatus": "Ready",
  "chunkDmo": "Building_a_Deck_chunk__dlm",
  "sourceDmo": "ADL_Diy_Building_A"
}
```

**Store discovered values:**

```bash
BUILDING_DECK_INDEX_ID="{searchIndexId}"
BUILDING_DECK_CHUNK_DMO="{chunkDmo}"
BUILDING_DECK_SOURCE_DMO="{sourceDmo}"
```

**If search index not found:**
- Report error: "❌ Building_a_Deck search index not found"
- List available search indexes
- Suggest: Verify Intelligent Context "Building a Deck" is published
- Stop execution

**If search index found but runtimeStatus ≠ Ready:**
- Report error: "❌ Building_a_Deck search index status: {runtimeStatus}"
- Suggest: Wait for search index to be Ready
- Stop execution

**If search index found and Ready:**
- Report: "✅ Building_a_Deck search index discovered"
- Report: "   Search Index ID: {searchIndexId}"
- Report: "   Source UDMO: {sourceDmo}"
- Report: "   Chunk DMO: {chunkDmo}"
- Report: "   Status: Ready"
- Continue to Step 6

---

### Step 6 — Create Building_a_Deck retriever

**CRITICAL: Use Retriever API to create retriever with 7 chunk fields + relationships**

Prepare retriever configuration JSON:

```bash
curl -sL -X POST \
  -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/machine-learning/retrievers" \
  -d "{
    \"label\": \"Building_a_Deck Retriever\",
    \"description\": \"Individual retriever for Building a Deck UDMO with 7 chunk fields output\",
    \"configuration\": {
      \"queryType\": \"NoCode\",
      \"input\": {
        \"id\": \"${BUILDING_DECK_INDEX_ID}\"
      },
      \"isActive\": true,
      \"queryFilter\": {},
      \"numberOfResults\": 10,
      \"outputFields\": [
        {
          \"label\": \"Chunk\",
          \"relatedDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"Chunk__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${BUILDING_DECK_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Chunk Sequence Number\",
          \"relatedDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"ChunkSequenceNumber__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${BUILDING_DECK_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Data Source\",
          \"relatedDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"DataSource__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${BUILDING_DECK_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Data Source Object\",
          \"relatedDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"DataSourceObject__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${BUILDING_DECK_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Internal Organization\",
          \"relatedDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"InternalOrganization__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${BUILDING_DECK_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Record Id\",
          \"relatedDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"RecordId__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${BUILDING_DECK_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        },
        {
          \"label\": \"Source Record Id\",
          \"relatedDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
          \"relatedDmoFieldName\": \"SourceRecordId__c\",
          \"relationships\": [{
            \"relationSourceDmoName\": \"${BUILDING_DECK_CHUNK_DMO}\",
            \"relationSourceDmoFieldName\": \"SourceRecordId__c\",
            \"relationTargetDmoName\": \"${BUILDING_DECK_SOURCE_DMO}\",
            \"relationTargetDmoFieldName\": \"FilePath__c\"
          }]
        }
      ],
      \"retrievalMode\": \"Basic\",
      \"citationConfiguration\": {
        \"type\": \"Default\"
      }
    }
  }"
```

**Configuration details:**
- **Type:** Individual retriever (NoCode)
- **Search Index:** Building_a_Deck (use ID from discovery step)
- **Filter:** "All Documents" (empty queryFilter: {})
- **Output:** 7 fields from chunk DMO with relationship chain: chunk → source via SourceRecordId__c → FilePath__c
- **Active:** true (auto-activated on creation)

**🚨 CAPTURE BOTH names (same as Step 3) — top-level `name` is the parent (1Cx prefix); `activeConfiguration.name` is the config version (1Cy prefix). Use the PARENT for GET/DELETE URLs.**

**Store retriever details:**

```bash
BUILDING_DECK_RETRIEVER_NAME=$(cat /tmp/_resp_deck.json | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print(d.get('name',''))")
BUILDING_DECK_CONFIG_NAME=$(cat /tmp/_resp_deck.json | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print(d.get('activeConfiguration',{}).get('name',''))")
BUILDING_DECK_RETRIEVER_ID=$(cat /tmp/_resp_deck.json | $PYTHON_CMD -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))")
```

**⚠️ Windows/Git-Bash `/tmp` path note:** If `cat` works but Python `open('/tmp/...')` raises `FileNotFoundError`, convert with `cygpath`:
```bash
WIN_PATH=$(cygpath -w /tmp/_resp_deck.json)
$PYTHON_CMD -c "import json; d=json.load(open(r'$WIN_PATH'))"
```

**If retriever creation fails:**
- Report error: "❌ Failed to create Building_a_Deck retriever"
- Report error message from API response
- **DO NOT BLINDLY RETRY** — first GET the retrievers list and check if a retriever with label "Building_a_Deck Retriever" already exists. If yes, the previous POST succeeded silently; capture its parent name and continue. Otherwise diagnose payload before retrying.
- If retry creates a duplicate (same label, different parent name), DELETE the duplicate: `curl -X DELETE -H "Authorization: Bearer $CDP_ACCESS_TOKEN" "$CDP_INSTANCE_URL/services/data/v63.0/ssot/machine-learning/retrievers/<duplicate_parent_name>"` — returns HTTP 204.
- Stop execution

**If retriever creation succeeds:**
- Report: "✅ Building_a_Deck retriever created"
- Report: "   Parent retriever name (use for GET/DELETE): {BUILDING_DECK_RETRIEVER_NAME}"
- Report: "   Configuration version name: {BUILDING_DECK_CONFIG_NAME}"
- Report: "   Retriever ID: {retrieverId}"
- Report: "   Status: Active"
- Continue to Step 7

---

### Step 7 — Verify Building_a_Deck retriever creation

**🚨 CRITICAL: Use the PARENT name (1Cx prefix) captured in Step 6 — NOT the configuration name (1Cy prefix).**

GET with the configuration name returns `[{"errorCode":"ITEM_NOT_FOUND"}]`.

```bash
# GET retriever — uses PARENT name (1Cx prefix)
curl -sL \
  -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/machine-learning/retrievers/${BUILDING_DECK_RETRIEVER_NAME}"
```

**Expected output:**
- Retriever details JSON
- `isActive: true`
- `outputFields` array with 7 fields

**Present retriever details:**
- Auto-generated retriever name (e.g., `Building_a_Deck_Retriever_1Cx_t6fd256e260`)
- Retriever ID
- Configuration ID
- Active status (`isActive: true`)
- Output fields configuration (7 fields from Building_a_Deck_chunk__dlm)
- Search index configuration (Building_a_Deck)

**If verification fails:**
- Report error: "❌ Failed to verify Building_a_Deck retriever"
- Continue to Step 8 (non-critical failure)

**If verification succeeds:**
- Report: "✅ Building_a_Deck retriever verified"
- Report: "   Fields: 7 chunk fields configured with relationships"
- Report: "   Status: Active and verified"
- Continue to Step 8

---

### Step 8 — Generate final report for BOTH retrievers

Generate comprehensive completion report:

```text
✅ Data Cloud Individual Retrievers Created Successfully!

Org: {org_alias}
Instance: {CDP_INSTANCE_URL}

═══════════════════════════════════════════════════

📋 Retriever 1: DIY_Bathroom Retriever

Auto-generated Name: {DIY_BATHROOM_RETRIEVER_NAME}
Retriever ID: {DIY_BATHROOM_RETRIEVER_ID}
Data Model Object: {DIY_BATHROOM_SOURCE_DMO}
Chunk DMO: {DIY_BATHROOM_CHUNK_DMO}
Search Index: DIY_Bathroom
Search Index ID: {DIY_BATHROOM_INDEX_ID}
Filter: All Documents (empty queryFilter)

Output Fields (7):
✅ Chunk (with relationship chain)
✅ Chunk Sequence Number (with relationship chain)
✅ Data Source (with relationship chain)
✅ Data Source Object (with relationship chain)
✅ Internal Organization (with relationship chain)
✅ Record Id (with relationship chain)
✅ Source Record Id (with relationship chain)

Status: Active and Verified
Type: Individual retriever (NoCode)

═══════════════════════════════════════════════════

📋 Retriever 2: Building_a_Deck Retriever

Auto-generated Name: {BUILDING_DECK_RETRIEVER_NAME}
Retriever ID: {BUILDING_DECK_RETRIEVER_ID}
Data Model Object: {BUILDING_DECK_SOURCE_DMO}
Chunk DMO: {BUILDING_DECK_CHUNK_DMO}
Search Index: Building_a_Deck
Search Index ID: {BUILDING_DECK_INDEX_ID}
Filter: All Documents (empty queryFilter)

Output Fields (7):
✅ Chunk (with relationship chain)
✅ Chunk Sequence Number (with relationship chain)
✅ Data Source (with relationship chain)
✅ Data Source Object (with relationship chain)
✅ Internal Organization (with relationship chain)
✅ Record Id (with relationship chain)
✅ Source Record Id (with relationship chain)

Status: Active and Verified
Type: Individual retriever (NoCode)

═══════════════════════════════════════════════════

⏳ Processing Summary:

Both Individual Retrievers created and activated successfully.
Total Time: ~1-2 minutes (REST API approach)

═══════════════════════════════════════════════════

🔗 Test Retrievers in Retriever Playground:

Direct Link: {CDP_INSTANCE_URL}/lightning/setup/RetrieverPlayground

Instructions:
1. Navigate to: Setup → Search for "Retriever Playground"
2. Select retriever from dropdown
3. Test queries:

For DIY_Bathroom Retriever:
- "bathroom sink"
- "shower head"
- "toilet installation"

For Building_a_Deck Retriever:
- "deck materials"
- "wood planks"
- "deck construction"
- "deck building steps"

4. Verify results:
   ✅ Results appear with all 7 fields
   ✅ Relevance scores are present
   ✅ Content matches query

═══════════════════════════════════════════════════

✅ Retriever setup complete for BOTH retrievers!

Next: Test retrievers in Retriever Playground to verify results.

**Note:** Retriever testing is performed automatically by downstream skills (prompt-template-add-retriever and agent-setup-configuration) which integrate retrievers into agents.
```

---

## Important Rules

**CRITICAL - Execution Sequence:**
- 🚨 **Execute all steps sequentially** - never skip or parallelize
- 🚨 **Create BOTH retrievers** - complete first, then second
- 🚨 **Use Connect REST API for all operations** - no browser automation
- 🚨 **Auto-discover search indexes** - use Search Index API
- 🚨 **Auto-detect UDMOs** - use pattern matching from discovery

**CRITICAL - UDMO Detection:**
- ✅ **First retriever**: Pattern match "DIYBathroom", "DIY_Bathroom", "DIY_Bath", "DIYBath"
- ✅ **Second retriever**: Pattern match "DiyBuilding", "Diy_Building", "Diy_Build", "DiyBuild"
- ✅ **Auto-detect from Search Index API** - use sourceDmoDeveloperName field
- ✅ **DMO naming uses __dlm suffix** - not __c

**CRITICAL - Output Fields Structure:**
- ✅ **Each field must have relationships array** - chunk → source via SourceRecordId__c → FilePath__c
- ✅ **Use exact structure from reference skill** - label, relatedDmoName, relatedDmoFieldName, relationships
- ✅ **All 7 fields use same relationship chain**

**CRITICAL - Configuration:**
- ✅ **queryType: "NoCode"** - Individual retriever type
- ✅ **input: { "id": "<searchIndexId>" }** - from discovery step
- ✅ **isActive: true** - auto-activate on creation
- ✅ **queryFilter: {}** - empty object for "All Documents"
- ✅ **numberOfResults: 10** - default
- ✅ **retrievalMode: "Basic"**
- ✅ **citationConfiguration: { "type": "Default" }**

**CRITICAL - Field Configuration:**
- ✅ **All 7 fields must be added** for each retriever
- ✅ **Same field list for both** retrievers
- ✅ **Field API names** (all use __c suffix):
  - Chunk__c
  - ChunkSequenceNumber__c
  - DataSource__c
  - DataSourceObject__c
  - InternalOrganization__c
  - RecordId__c
  - SourceRecordId__c

**CRITICAL - REST API:**
- ✅ **ONLY use Salesforce CLI and curl** - no JavaScript, no browser automation
- ✅ **Use python3 for JSON parsing** - no jq dependency
- ✅ **Authentication via sf org display** - extract accessToken and instanceUrl
- ✅ **API endpoint**: /services/data/v63.0/ssot/machine-learning/retrievers
- ✅ **Search Index endpoint**: /services/data/v63.0/ssot/search-index

**CRITICAL - Error Handling:**
- ✅ **If search index not found, report error with available options**
- ✅ **If UDMO pattern not matched, report error and stop**
- ✅ **If retriever creation fails, report API error message**
- ✅ **Verification failures are non-critical** - continue to next step

**General Rules:**
- NEVER hardcode org names — always use provided org_alias parameter
- NEVER generate JavaScript files
- NEVER use Playwright browser automation
- ALWAYS use curl for REST API calls
- ALWAYS use python3 for JSON parsing
- ALWAYS capture auto-generated retriever name from API response
- ALWAYS provide comprehensive summary report for BOTH retrievers
- ALWAYS include direct link to Retriever Playground
- Estimated time: 1-2 minutes for complete process (both retrievers)

---

## Troubleshooting

```bash
# List all retrievers
curl -sL -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/machine-learning/retrievers"

# Check DIY_Bathroom search index status
curl -sL -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/search-index" | \
  $(command -v python3 || command -v python) -c "import sys,json; data=json.load(sys.stdin); dmo=[d for d in data.get('semanticSearchDefinitionDetails',[]) if d.get('developerName')=='DIY_Bathroom']; print(json.dumps(dmo[0] if dmo else {}, indent=2))"

# Check Building_a_Deck search index status
curl -sL -H "Authorization: Bearer $CDP_ACCESS_TOKEN" \
  "$CDP_INSTANCE_URL/services/data/v63.0/ssot/search-index" | \
  $(command -v python3 || command -v python) -c "import sys,json; data=json.load(sys.stdin); dmo=[d for d in data.get('semanticSearchDefinitionDetails',[]) if d.get('developerName')=='Building_a_Deck']; print(json.dumps(dmo[0] if dmo else {}, indent=2))"
```

| Error | Cause | Fix |
|-------|-------|-----|
| `400 Bad Request` | Invalid JSON structure | Check searchIndexId, field names, relationship structure |
| `404 Not Found` | Data Cloud not enabled | Verify Data Cloud provisioned in org |
| `403 Forbidden` | Missing permissions | Need Data Cloud admin permission set |
| `JSON_PARSER_ERROR` | Wrong field names | Use exact field names from discovery |
| `Retriever not found` | Wrong API name | Use exact auto-generated name from create response |

**If no data in DMO:** User needs to ingest data first (blocker)

**Zero results in Retriever Playground:**
1. Is the search index active? Check Setup → Search Index Builder
2. Is data ingested? Verify UDMO has records
3. Are filters too restrictive? This skill uses "All Documents" (no filters)
4. Is the query relevant? Try queries matching actual content

---

## Success Criteria

Skill is successful when BOTH retrievers are complete:

✅ Org authentication validated via `sf org display`
✅ instanceUrl and accessToken extracted successfully
✅ Retrievers API accessible (Step 1 validation passed)

**First Retriever (DIY_Bathroom):**
✅ DIY_Bathroom search index discovered
✅ Search index status is Ready
✅ UDMO pattern matched (DIYBathroom, DIY_Bathroom, etc.)
✅ chunkDmo and sourceDmo extracted (with __dlm suffix)
✅ Retriever created via POST API with correct payload structure
✅ All 7 chunk fields configured with relationships
✅ isActive set to true
✅ Auto-generated name captured
✅ Retriever verified via GET API

**Second Retriever (Building_a_Deck):**
✅ Building_a_Deck search index discovered
✅ Search index status is Ready
✅ UDMO pattern matched (DiyBuilding, Diy_Building, etc.)
✅ chunkDmo and sourceDmo extracted (with __dlm suffix)
✅ Retriever created via POST API with correct payload structure
✅ All 7 chunk fields configured with relationships
✅ isActive set to true
✅ Auto-generated name captured
✅ Retriever verified via GET API

**Completion:**
✅ Comprehensive summary report provided for BOTH retrievers
✅ Both auto-generated retriever names reported
✅ All field counts verified (7 fields each with relationships)
✅ Direct link to Retriever Playground provided

---

## Example Usage

### Example 1: User provides org name

**User:** "Create retrievers in MyRetailOrg"

**Skill:**
1. Gets org credentials: `sf org display --json`
2. Extracts instanceUrl and accessToken using python3
3. Validates API access by listing existing retrievers
4. **FIRST RETRIEVER:** Creates "DIY_Bathroom Retriever"
   - Discovers DIY_Bathroom search index via API
   - Extracts searchIndexId, chunkDmo (__dlm), sourceDmo (__dlm)
   - Creates retriever with 7 chunk fields + relationships via POST API
   - Verifies retriever via GET API
5. **SECOND RETRIEVER:** Creates "Building_a_Deck Retriever"
   - Discovers Building_a_Deck search index via API
   - Extracts searchIndexId, chunkDmo (__dlm), sourceDmo (__dlm)
   - Creates retriever with 7 chunk fields + relationships via POST API
   - Verifies retriever via GET API
6. Reports success for BOTH retrievers with auto-generated names
7. Provides direct link to Retriever Playground

---

### Example 2: Error handling - Search index not found

**User:** "Create retrievers in TestOrg"

**Skill:** [Attempts to discover DIY_Bathroom search index]

**Error:** `DIY_Bathroom search index not found`

**Skill:**
```text
❌ Search Index Not Found

Org: TestOrg

Missing Index: DIY_Bathroom
Expected Status: Ready

Available Search Indexes:
- Customer_Profile
- Product_Catalog
- (list other visible indexes from API response)

Suggested Fix:
1. Verify Intelligent Context "DIY Bathroom" is published
2. Navigate to: Setup → Search Index Builder
3. Check if "DIY_Bathroom" index exists
4. Verify index status is "Ready" (not Processing or Failed)
5. Retry after confirming index is Ready

Cannot proceed without DIY_Bathroom search index.
```

---

### Example 3: Error handling - UDMO pattern not matched

**User:** "Create retrievers in MyOrg"

**Skill:** [Discovers search index but UDMO pattern doesn't match]

**Error:** `UDMO pattern not matched for DIY_Bathroom`

**Skill:**
```text
❌ UDMO Pattern Not Matched

Org: MyOrg

Search Index: DIY_Bathroom (Found)
Source UDMO: ADL_Custom_Name (Unexpected)

Expected Patterns:
- DIYBathroom
- DIY_Bathroom
- DIY_Bath
- DIYBath

Current UDMO: ADL_Custom_Name

Suggested Fix:
1. Verify Intelligent Context "DIY Bathroom" is published correctly
2. Check UDMO naming: Setup → Data Cloud → Data Model Objects
3. Ensure UDMO name contains "DIY" and "Bathroom"
4. Republish Intelligent Context if needed

Cannot proceed with unexpected UDMO naming.
```

---

## Notes

- Both retrievers use the same 7 chunk fields with relationships
- Search indexes must be Ready before retriever creation
- UDMOs are auto-created by ADL when IC configurations are published
- DMO naming uses __dlm suffix (Data Lake Model), not __c
- Retrievers are immediately activated after creation (isActive: true)
- REST API approach is faster than browser automation (1-2 minutes vs 5-8 minutes)
- No browser required - fully CLI-based workflow
- Uses python3 for JSON parsing (no jq dependency)
- Auto-generated retriever names include timestamp/unique suffix
- Total process takes approximately 1-2 minutes for both retrievers

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If a step fails, **do NOT clean up** — leave artifacts so you can debug.
- Fix the underlying issue, retry the failed step, then run cleanup once it succeeds.

**Files this skill creates and must delete:**

```bash
rm -f /c/tmp/retriever_bathroom.json
rm -f /c/tmp/retriever_deck.json
rm -f /c/tmp/resp_bath.json
rm -f /c/tmp/resp_deck.json
rm -f /tmp/_resp.json
rm -f /tmp/_resp_bath.json
rm -f /tmp/_resp_deck.json
```

**Verification (must report no remaining retriever scratch):**

```bash
ls /c/tmp/retriever_*.json /c/tmp/resp_*.json 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete the files listed above. Do NOT delete anything in the repo working tree.
- ❌ Skipping this step is not allowed once both retrievers are verified active.
