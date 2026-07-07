---
name: refresh-data-cloud-components
description: "Refresh Data Cloud components in sequence: Identity Resolution, Calculated Insights (5 insights), and Segment. Queries Data Cloud for component IDs and triggers refresh via Connect REST API. Refreshes 'Unified Customer' IR, 5 calculated insights (CLV, AOV, etc.), and 'Power Buyer Program Members' segment. Use when user wants to refresh data cloud components, trigger IR/CI/Segment refresh, or update data cloud calculations."
---

# refresh-data-cloud-components

## Purpose

Refresh Data Cloud components in the correct sequence: Identity Resolution → Calculated Insights (one-by-one) → Segment (fire-and-forget).

This skill:
1. Refreshes Identity Resolution "Unified Customer" and waits for `lastJobStatus = SUCCESS` (uppercase, observed against this org).
2. Refreshes 5 Calculated Insights ONE AT A TIME, waiting for each to show `lastRunStatus = SUCCESS` before triggering the next:
   - CI 1/5: Average Order Value Lifetime → wait for SUCCESS
   - CI 2/5: Average Purchase Value → wait for SUCCESS
   - CI 3/5: Average Purchase Frequency → wait for SUCCESS
   - CI 4/5: Customer Lifespan → wait for SUCCESS
   - CI 5/5: Customer Lifetime Value → wait for SUCCESS
3. Triggers Segment "Power Buyer Program Members" publish (fire-and-forget — does NOT wait for the publish to finish).

**🚨 STATUS FIELDS — CASE AND NAMES VERIFIED AGAINST THIS ORG ON 2026-06-10:**

| Component | Status field | Observed values |
|---|---|---|
| Identity Resolution | `lastJobStatus` (camelCase, NOT `LastRunStatus`) | `IN_PROGRESS`, `SUCCESS`, `FAILED` (UPPERCASE) |
| Calculated Insight  | `lastRunStatus` (camelCase) | `PENDING`, `PROCESSING`, `SUCCESS`, `FAILED` (UPPERCASE) |
| Segment             | `publishStatus` | `PUBLISHING`, `PUBLISHED`, `FAILED` (UPPERCASE) |

ALL string comparisons MUST normalize via `${STATUS^^}` in bash (or `.upper()` in Python) — comparing against `Success` / `InProgress` / `Running` (Title Case) will silently never match and the polling loop will time out forever. This skill's polling shell snippets already use `[ "$STATUS" = "SUCCESS" ] || [ "$STATUS" = "Success" ]` to handle either casing.

All status verification is done via direct **Connect REST GET** calls (`GET /services/data/v66.0/ssot/identity-resolutions/{id}` and `GET /services/data/v66.0/ssot/calculated-insights/{api_name}`) — NO SOQL, NO tooling API, NO temp files. The earlier SOQL+tooling approach was unnecessarily complex and is no longer used; all examples below use REST GET. The skill completes immediately after the segment publish API returns `publishStatus: "PUBLISHING"` (or any HTTP 2xx with a `jobId`).

Prerequisites:
- Target org must have Data Cloud enabled
- Identity Resolution, Calculated Insights, and Segments must exist
- User must have Data Cloud permissions

**Temp file policy:** This skill no longer writes any SOQL files (we removed the SOQL polling approach in favor of Connect REST GET). The only temp artifacts are the curl-result captures in your shell variables — no on-disk cleanup needed. Older versions of this skill referenced `query_ir_status.soql` / `query_ci_status.soql`; if you see those files in the working tree from a prior run, delete them.

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

Before running:

- Salesforce CLI must be installed
- Target org must be authenticated with Salesforce CLI
- Target org must have Data Cloud enabled and licensed
- User must have "Manage Data Cloud" permission
- Identity Resolution "Unified Customer" must exist
- 5 Calculated Insights must exist
- Segment "Power Buyer Program Members" must exist
- **IMPORTANT:** For uninterrupted execution, commands should be pre-approved in `.claude/settings.json`:
  ```json
  {
    "permissions": {
      "allow": [
        "bash:sf *",
        "bash:curl *"
      ]
    }
  }
  ```
  Without this, `sf org display` and `curl` commands will prompt for approval.

---

## Workflow

### Step 1 — Get org access token and instance URL

Run:

```bash
sf org display --target-org <org_alias> --json
```

Extract from JSON response:

| Field | Description | Example |
|---|---|---|
| `result.accessToken` | OAuth access token | eyJraWQ... |
| `result.instanceUrl` | Org instance URL | https://myorg.my.salesforce.com |
| `result.username` | Org username | user@example.com |

Store these values for API calls and SOQL queries.

---

### Step 2 — Query Identity Resolution ID

**Use REST API to get Identity Resolution list:**

```bash
curl -X GET \
  "{instance_url}/services/data/v66.0/ssot/identity-resolutions" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  --silent \
  --show-error
```

**Success Response:**

```json
{
  "identityResolutions": [
    {
      "id": "1irxxxxxxxxxxxxxxx",
      "label": "Unified Customer",
      "configurationType": "individual",
      "rulesetStatus": "PUBLISHED"
    }
  ]
}
```

**Parse JSON response:**
1. Extract the `identityResolutions` array
2. Find the object where `label` = "Unified Customer"
3. Extract the `id` field (format: `1irxxxxxxxxxxxxxxx`)

**If not found:**
- Report error: Identity Resolution "Unified Customer" not found
- Cannot proceed without IR
- User must create IR first

---

### Step 3 — Refresh Identity Resolution

**API Endpoint:**

```
POST {instance_url}/services/data/v66.0/ssot/identity-resolutions/{IR_Id}/actions/run-now
```

**Request Headers:**

```
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{}
```

Run curl command:

```bash
curl -X POST \
  "{instance_url}/services/data/v66.0/ssot/identity-resolutions/{IR_Id}/actions/run-now" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --silent \
  --show-error
```

**Success Response:**

```json
{
  "resultCode": "SuccessfullySubmittedIdentityResolutionJobRunRequest"
}
```

Report:
```text
✅ Identity Resolution "Unified Customer" refresh started
   Result: SuccessfullySubmittedIdentityResolutionJobRunRequest
```

**If error:**
- Report error code and message
- Check permissions
- Verify IR exists and is active

---

### Step 3A — Wait for Identity Resolution to complete (CRITICAL)

**DO NOT proceed to Calculated Insights until Identity Resolution shows `lastJobStatus = SUCCESS`**

**Use Connect REST GET to check IR status (NO SOQL, NO tooling API):**

```bash
curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v66.0/ssot/identity-resolutions/${IR_ID}"
```

The response is a JSON object with these status-relevant fields:

| Field | Type | What it means |
|---|---|---|
| `lastJobStatus` | string (UPPERCASE) | The current run state — `IN_PROGRESS`, `SUCCESS`, or `FAILED`. **This is the only field to gate on.** |
| `lastJobCompleted` | ISO timestamp | ⚠️ **Stale-field warning:** This timestamp reflects the PREVIOUS completed run, not the current one. While the current run is `IN_PROGRESS`, `lastJobCompleted` will keep showing the old completion time. Do NOT compare it against "now" — use `lastJobStatus` only. |
| `rulesetStatus` | string | `PUBLISHED` if the IR ruleset itself is published. NOT a per-run status — don't gate on this. |

**3A.1 Polling loop (max 20 min, 60 s cadence):**

```bash
for i in $(seq 1 20); do
  STATUS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${INSTANCE_URL}/services/data/v66.0/ssot/identity-resolutions/${IR_ID}" \
    | grep -o '"lastJobStatus":"[^"]*"' | cut -d'"' -f4)
  echo "IR poll $i (minute $i): lastJobStatus=$STATUS"

  # Match either UPPERCASE (current API) or Title Case (defensive — in case Salesforce changes it back)
  if [ "$STATUS" = "SUCCESS" ] || [ "$STATUS" = "Success" ]; then
    echo "✅ IR Success on minute $i"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "Failed" ]; then
    echo "❌ IR Failed on minute $i"
    break  # → hand to Step 3B retry block
  fi
  sleep 60
done
```

**Maximum wait time: 20 minutes** (20 iterations × 60 seconds). On the 2026-06-10 baseline run against this org, the IR finished at exactly minute 15 — the previous 15-min ceiling was a hair from triggering a false timeout, so the ceiling is bumped to 20 min for safety.

**3A.2 Report IR completion:**

```text
✅ Identity Resolution "Unified Customer" completed successfully
   lastJobStatus: SUCCESS
   
Proceeding to Calculated Insights refresh...
```

**If timeout (20 minutes elapsed, still IN_PROGRESS):**
```text
❌ Identity Resolution did not complete within 20 minutes

Current lastJobStatus: {STATUS}

🛑 STOPPING: Cannot proceed to Calculated Insights until IR completes.
   Hand to Step 3B retry block ONLY if status is FAILED. Timeout (still IN_PROGRESS) is NOT auto-retried — surface to user.
```

---

### Step 3B — Auto-retry IR on Failed (max 3 total attempts)

**CRITICAL: When Step 3A polling returns `lastJobStatus = FAILED` (UPPERCASE — match either casing in shell), do NOT stop.** Re-trigger the IR run by re-issuing the POST from Step 3, capture the new run, and resume polling from Step 3A.

**Retry policy — fixed:**
- **3 total attempts**: 1 initial (Step 3) + up to **2 retries** if a run ends in `Failed`.
- Wait **30 seconds** between failure detection and the retry POST.
- After **all 3 attempts fail**, stop and report — do NOT proceed to Step 4 (CIs depend on IR completing).
- A `Timeout` (15-minute poll exhaust) is NOT auto-retried — surface it per the Step 3A timeout block above so the user can decide.

**Wrap Steps 3 + 3A in a 3-attempt loop:**

```bash
ACCESS_TOKEN="..."         # from Step 1
INSTANCE_URL="..."         # from Step 1
IR_ID="..."                # from Step 2

ATTEMPT=1
IR_FINAL="Pending"

while [ "$ATTEMPT" -le 3 ]; do
  echo "==== IR attempt $ATTEMPT / 3 ===="

  # ---- Re-trigger IR refresh (Step 3) ----
  curl -s -X POST \
    "${INSTANCE_URL}/services/data/v66.0/ssot/identity-resolutions/${IR_ID}/actions/run-now" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}'

  # ---- Poll lastJobStatus (Step 3A, max 20 min — bumped from 15 to leave headroom; baseline run completed at minute 15 exactly) ----
  POLL="Pending"
  for i in $(seq 1 20); do
    STATUS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "${INSTANCE_URL}/services/data/v66.0/ssot/identity-resolutions/${IR_ID}" \
      | grep -o '"lastJobStatus":"[^"]*"' | cut -d'"' -f4)
    echo "Attempt $ATTEMPT — minute $((i-1)): lastJobStatus=$STATUS"

    if [ "$STATUS" = "SUCCESS" ] || [ "$STATUS" = "Success" ]; then
      POLL="Success"; break
    elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "Failed" ]; then
      POLL="Failed"; break
    fi
    sleep 60
  done

  if [ "$POLL" = "Success" ]; then
    IR_FINAL="Success"
    echo "✅ IR succeeded on attempt $ATTEMPT"
    break
  fi

  if [ "$POLL" = "Failed" ] && [ "$ATTEMPT" -lt 3 ]; then
    echo "🔁 IR failed on attempt $ATTEMPT. Waiting 30s before retry..."
    sleep 30
    ATTEMPT=$((ATTEMPT + 1))
    continue
  fi

  if [ "$POLL" = "Failed" ]; then
    IR_FINAL="FailedAllAttempts"; break
  fi

  # POLL == "Pending" → 20-min timeout exhausted on this attempt
  IR_FINAL="Timeout"; break
done

case "$IR_FINAL" in
  Success)            ;;  # proceed to Step 4
  FailedAllAttempts)  echo "❌ IR failed after 3 attempts. Stopping."; exit 1 ;;
  Timeout)            echo "⏱️ IR did not finish in 20 min on attempt $ATTEMPT. See Step 3A timeout guidance."; exit 2 ;;
esac
```

**Reporting on retries:**
- ✅ First-try success → `IR attempt 1/3: Success`
- 🔁 Recovered after retry → `IR attempt 1/3: Failed → 2/3: Success`
- ❌ All 3 failed → `IR attempts 1, 2, 3 all Failed. Stopping. Cannot proceed to CIs.`

---

### Step 4 — Refresh Calculated Insights ONE AT A TIME (Strictly Sequential)

**ONLY execute this step after Identity Resolution shows "Success" status (Step 3A confirmed)**

**🚨 CRITICAL EXECUTION RULE:**
- ✅ Refresh each CI ONE AT A TIME
- ✅ Wait for each CI to show "Success" BEFORE refreshing the next CI
- ✅ NEVER trigger multiple CIs in parallel
- ✅ NEVER trigger the next CI until the previous one's `lastRunStatus = SUCCESS` (camelCase field, UPPERCASE value)

**Calculated Insight Refresh Order (strictly sequential):**

| # | Display Name | API Name (developer name) |
|---|---|---|
| 1 | Average Order Value Lifetime | `Average_Order_Value_Lifetime__cio` |
| 2 | Average Purchase Value | `Average_Purchase_Value__cio` |
| 3 | Average Purchase Frequency | `Average_Purchase_Frequency__cio` |
| 4 | Customer Lifespan | `Customer_Lifespan__cio` |
| 5 | Customer Lifetime Value | `Customer_Lifetime_Value__cio` |

**Process for EACH CI (repeat for all 5 in order):**

For each CI in the order above, perform these 4 sub-steps before moving to the next CI:

#### 4.1 — Trigger CI refresh

```bash
curl -X POST \
  "{instance_url}/services/data/v66.0/ssot/calculated-insights/{CI_API_Name}/actions/run" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --silent \
  --show-error
```

**Success Response:**
```json
{
  "errors": [],
  "success": true
}
```

Report:
```text
🔄 CI {N}/5: {Display Name} ({CI_API_Name}) — refresh triggered
```

#### 4.2 — Poll THIS CI's status until SUCCESS via Connect REST GET (NO SOQL)

The CI status field is `lastRunStatus` (camelCase) on the Connect REST resource. Values are UPPERCASE — `PENDING`, `PROCESSING`, `SUCCESS`, `FAILED`. Wait 30 s initially (the trigger registers as `PENDING` for ~30 s before flipping to `PROCESSING`), then poll the GET endpoint every 30 s:

```bash
sleep 30
for i in $(seq 1 20); do
  STATUS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${INSTANCE_URL}/services/data/v66.0/ssot/calculated-insights/${CI_API_NAME}" \
    | grep -o '"lastRunStatus":"[^"]*"' | cut -d'"' -f4)
  echo "CI ${CI_DISPLAY} poll $i ($((i*30))s): lastRunStatus=$STATUS"

  # Match either UPPERCASE (current API) or Title Case (defensive)
  if [ "$STATUS" = "SUCCESS" ] || [ "$STATUS" = "Success" ]; then
    echo "✅ CI ${CI_DISPLAY} Success"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "Failed" ]; then
    echo "❌ CI ${CI_DISPLAY} Failed → hand to Step 4.3.1 retry"
    break
  fi
  sleep 30
done
```

**Verification logic (matching status values UPPERCASE — string compare via `${STATUS^^}` in newer bash, or the OR-fallback above):**
- ✅ If `lastRunStatus = SUCCESS` → CI complete, proceed to step 4.4
- ⏳ If `lastRunStatus = PENDING` or `PROCESSING` → Wait 30 seconds, query again
- ❌ If `lastRunStatus = FAILED` → trigger Step 4.3 retry (max 3 total attempts for THIS CI)

**Maximum wait time per CI: 10 minutes (20 iterations × 30 seconds)**

If timeout reached:
```text
❌ CI {Display Name} did not complete within 10 minutes

Current lastRunStatus: {STATUS}

🛑 STOPPING: Cannot proceed to next CI until this one shows SUCCESS status.
```

> **Note:** The skill previously used SOQL on `MktCalculatedInsight` with `--use-tooling-api`. That worked but required temp file creation/cleanup and a second API style. The Connect REST GET above returns the same `lastRunStatus` value with no temp file overhead and uses the same auth + endpoint family as the trigger POST in Step 4.1 — keep both calls in the same API style.

#### 4.3.1 — Auto-retry on Failed (max 3 total attempts per CI)

**CRITICAL: When polling in Step 4.2 returns `lastRunStatus = FAILED` (UPPERCASE — match either casing in shell), do NOT stop and do NOT skip to the next CI.** Re-trigger the SAME CI by re-issuing the POST from Step 4.1, then resume polling from Step 4.2.

**Retry policy — fixed:**
- **3 total attempts per CI**: 1 initial (Step 4.1) + up to **2 retries** if the run ends in `Failed`.
- Wait **30 seconds** between failure detection and the retry POST.
- Retries apply **per CI**: a Failed-then-recovered CI does NOT extend retries to subsequent CIs.
- After **all 3 attempts fail for the same CI**, stop the entire skill — do NOT proceed to the next CI (later CIs depend on earlier ones, e.g. CLV depends on APV/APF/Lifespan).
- A `Timeout` (10-minute poll exhaust) is NOT auto-retried — surface it per the existing timeout block above.

**Wrap Steps 4.1 + 4.2 for a single CI in a 3-attempt loop:**

```bash
ACCESS_TOKEN="..."         # from Step 1
INSTANCE_URL="..."         # from Step 1
CI_API_NAME="..."          # e.g. Average_Order_Value_Lifetime__cio
CI_DISPLAY="..."           # e.g. Average Order Value Lifetime

ATTEMPT=1
CI_FINAL="Pending"

while [ "$ATTEMPT" -le 3 ]; do
  echo "==== CI ${CI_DISPLAY} attempt $ATTEMPT / 3 ===="

  # ---- Re-trigger CI run (Step 4.1) ----
  curl -s -X POST \
    "${INSTANCE_URL}/services/data/v66.0/ssot/calculated-insights/${CI_API_NAME}/actions/run" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}'

  # ---- Poll lastRunStatus (Step 4.2, max 10 min = 20 polls × 30s) ----
  POLL="Pending"
  for i in $(seq 1 20); do
    sleep 30
    STATUS=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "${INSTANCE_URL}/services/data/v66.0/ssot/calculated-insights/${CI_API_NAME}" \
      | grep -o '"lastRunStatus":"[^"]*"' | cut -d'"' -f4)
    echo "Attempt $ATTEMPT — poll $i/20: lastRunStatus=$STATUS"

    if [ "$STATUS" = "SUCCESS" ] || [ "$STATUS" = "Success" ]; then
      POLL="Success"; break
    elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "Failed" ]; then
      POLL="Failed"; break
    fi
  done

  if [ "$POLL" = "Success" ]; then
    CI_FINAL="Success"
    echo "✅ CI ${CI_DISPLAY} succeeded on attempt $ATTEMPT"
    break
  fi

  if [ "$POLL" = "Failed" ] && [ "$ATTEMPT" -lt 3 ]; then
    echo "🔁 CI ${CI_DISPLAY} failed on attempt $ATTEMPT. Waiting 30s before retry..."
    sleep 30
    ATTEMPT=$((ATTEMPT + 1))
    continue
  fi

  if [ "$POLL" = "Failed" ]; then
    CI_FINAL="FailedAllAttempts"; break
  fi

  # POLL == "Pending" → 10-min timeout exhausted; do not retry, surface to user
  CI_FINAL="Timeout"; break
done

case "$CI_FINAL" in
  Success)            ;;  # proceed to Step 4.4 for THIS CI, then next CI
  FailedAllAttempts)  echo "❌ CI ${CI_DISPLAY} failed after 3 attempts. Stopping; CIs are sequential and downstream depends on this one."; exit 1 ;;
  Timeout)            echo "⏱️ CI ${CI_DISPLAY} did not finish in 10 min on attempt $ATTEMPT. See Step 4.2 timeout guidance."; exit 2 ;;
esac
```

**Reporting on retries:**
- ✅ First-try success → `CI {N}/5 {Display}: attempt 1/3: Success`
- 🔁 Recovered after retry → `CI {N}/5 {Display}: 1/3 Failed → 2/3 Success`
- ❌ All 3 failed → `CI {N}/5 {Display}: attempts 1, 2, 3 all Failed. Stopping; subsequent CIs not run.`

#### 4.4 — Report success and continue to next CI

```text
✅ CI {N}/5: {Display Name} — lastRunStatus: SUCCESS
   Proceeding to next CI...
```

(No SOQL temp file to clean up — the Connect REST GET in Step 4.2 doesn't create any.)

---

#### 4.5 — Execute order

Repeat steps 4.1 → 4.4 sequentially for all 5 CIs in this exact order:

1. **CI 1/5:** Average Order Value Lifetime → trigger → wait → success → next
2. **CI 2/5:** Average Purchase Value → trigger → wait → success → next
3. **CI 3/5:** Average Purchase Frequency → trigger → wait → success → next
4. **CI 4/5:** Customer Lifespan → trigger → wait → success → next
5. **CI 5/5:** Customer Lifetime Value → trigger → wait → success → done

**🚨 DO NOT trigger CI N+1 until CI N shows `lastRunStatus = SUCCESS` (UPPERCASE — match either casing in shell).**

After all 5 CIs complete successfully, proceed to Step 5 (Segment).

```text
✅ All 5 Calculated Insights completed successfully (sequential)

Status Summary:
1. Average Order Value Lifetime: lastRunStatus=SUCCESS
2. Average Purchase Value: lastRunStatus=SUCCESS
3. Average Purchase Frequency: lastRunStatus=SUCCESS
4. Customer Lifespan: lastRunStatus=SUCCESS
5. Customer Lifetime Value: lastRunStatus=SUCCESS

Proceeding to Segment publish...
```

---

### Step 5 — Query Segment ID (TWO-STEP — NOT one-step)

**ONLY execute this step after ALL 5 Calculated Insights show `lastRunStatus = SUCCESS` (Step 4.5 confirmed)**

**🚨 CRITICAL — verified against this org on 2026-06-10:**

The segment publish endpoint requires the **`marketSegmentId`** (format `1sgHn...`) in the URL path, NOT the `apiName` (`Power_Buyer_Program_Members`) and NOT the `id` field returned by the list endpoint.

But the `id` field on the list response is **null** for segments — only the per-segment GET response carries the real `marketSegmentId`. So this step is a TWO-STEP lookup:

**5.1 Find the segment's apiName from the list:**

```bash
curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v66.0/ssot/segments"
```

Response shape:
```json
{
  "segments": [
    {
      "apiName": "Power_Buyer_Program_Members",
      "displayName": "Power Buyer Program Members",
      "id": null,                         ← always null on list response, do NOT use
      "segmentStatus": "ACTIVE",
      ...
    }
  ]
}
```

Find the entry where `displayName == "Power Buyer Program Members"` (or where `apiName == "Power_Buyer_Program_Members"`) and capture its `apiName`. **Do NOT use the `id` field** — it is null on the list endpoint.

**5.2 GET the segment by apiName to get the real `marketSegmentId`:**

```bash
SEGMENT_API_NAME="Power_Buyer_Program_Members"
curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v66.0/ssot/segments/${SEGMENT_API_NAME}"
```

The single-segment GET response carries:
```json
{
  "segments": [
    {
      "apiName": "Power_Buyer_Program_Members",
      "displayName": "Power Buyer Program Members",
      "marketSegmentId": "1sgHn000000TNRTIA4",      ← USE THIS for publish path
      "marketSegmentDefinitionId": "3HXHn000000TNOyOAO",
      "segmentStatus": "ACTIVE",
      ...
    }
  ]
}
```

Capture `segments[0].marketSegmentId`. That ID (starts with `1sg`) is what goes into the publish URL in Step 6.

**Bash extraction example:**
```bash
SEGMENT_ID=$(curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v66.0/ssot/segments/Power_Buyer_Program_Members" \
  | grep -o '"marketSegmentId":"[^"]*"' | cut -d'"' -f4)
echo "Segment ID for publish: $SEGMENT_ID"
```

**If not found (empty string returned):**
- Report error: Segment "Power Buyer Program Members" not found
- Cannot proceed without Segment
- User must create Segment first

> **Why this is a two-step lookup:** Salesforce's Connect API for segments returns the apiName-keyed identifier in the list response (`id` field is null on the list), and exposes the publish-relevant `marketSegmentId` ONLY in the single-segment GET. The earlier version of this skill assumed `id` was the publish identifier — that produced HTTP 404 on the publish POST because `null` (or the apiName) is not accepted as the URL path segment.

---

### Step 6 — Publish Segment (Fire-and-Forget)

**🚨 CRITICAL: Trigger segment publish ONLY — DO NOT wait for completion**

Unlike IR and CIs, the Segment is fired and the skill proceeds immediately to the final report. No status polling, no SOQL verification, no waiting.

**API Endpoint:**

```
POST {instance_url}/services/data/v66.0/ssot/segments/{marketSegmentId}/actions/publish
```

The `{marketSegmentId}` value is whatever Step 5.2 captured (starts with `1sg`, e.g. `1sgHn000000TNRTIA4`). **NOT** `apiName`, **NOT** the null `id` from the list response.

**Request Headers:**

```
Authorization: Bearer {access_token}
Content-Type: application/json
```

**Request Body:**

```json
{}
```

Run curl command:

```bash
curl -X POST \
  "${INSTANCE_URL}/services/data/v66.0/ssot/segments/${SEGMENT_ID}/actions/publish" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --silent \
  --show-error
```

(`${SEGMENT_ID}` comes from Step 5.2 — it is the `marketSegmentId`.)

**Success Response (HTTP 201, observed against this org on 2026-06-10):**

```json
{
  "errors": [{}],
  "jobId": "5d3228e8-b09f-49e0-afb3-f90e7d3f6299",
  "partitionId": "1sgHn000000TNRT_3d06d48d-4e60-4041-9bf5-3aa7c59a758a",
  "publishStatus": "PUBLISHING",
  "segmentId": "1sgHn000000TNRTIA4",
  "success": true
}
```

The presence of `"jobId"` or `"publishStatus": "PUBLISHING"` confirms the trigger was accepted. Note that `errors: [{}]` appears even on success — it's an empty object inside the array, not a real error. Treat it as success if `jobId` is present.

Report:
```text
✅ Segment "Power Buyer Program Members" publish triggered
   marketSegmentId: {SEGMENT_ID}
   jobId: {jobId}
   publishStatus: PUBLISHING (running asynchronously - skill does NOT wait)
```

**If error on trigger:**
- Report error code and message
- Trigger Step 6.1 (auto-retry, max 3 total attempts) before continuing.

**🚨 DO NOT poll segment status. Proceed directly to Step 7 (final report) once a publish has been accepted (or all retries exhausted).**

#### 6.1 — Auto-retry Segment publish on trigger failure (max 3 total attempts)

**CRITICAL: When the Step 6 publish POST does NOT return `success: true` (e.g. HTTP 400/500, error array populated, network error), do NOT silently continue.** Re-issue the same POST up to 2 additional times.

**Retry policy — fixed:**
- **3 total attempts**: 1 initial (Step 6) + up to **2 retries** if the publish trigger does not return success.
- Wait **30 seconds** between failure detection and the retry POST.
- Segment publish is fire-and-forget — retries apply ONLY to the trigger HTTP response, NOT to async publishing progress (we still don't poll `publishStatus`).
- After **all 3 attempts fail to return success**, surface the error in the final report and continue (do NOT halt the skill — Segment is the last step and IR + CIs already succeeded).

**Wrap Step 6 in a 3-attempt loop:**

```bash
ACCESS_TOKEN="..."         # from Step 1
INSTANCE_URL="..."         # from Step 1
SEGMENT_ID="..."           # from Step 5

ATTEMPT=1
SEG_FINAL="Pending"
SEG_LAST_RESPONSE=""

while [ "$ATTEMPT" -le 3 ]; do
  echo "==== Segment publish attempt $ATTEMPT / 3 ===="

  RESPONSE=$(curl -s -X POST \
    "${INSTANCE_URL}/services/data/v66.0/ssot/segments/${SEGMENT_ID}/actions/publish" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{}')
  SEG_LAST_RESPONSE="$RESPONSE"

  # Accept any of these as a valid trigger acknowledgement:
  # - "success":true
  # - presence of "jobId" or "publishStatus":"PUBLISHING"
  if echo "$RESPONSE" | grep -qE '"success"\s*:\s*true|"jobId"\s*:|"publishStatus"\s*:\s*"PUBLISHING"'; then
    SEG_FINAL="Triggered"
    echo "✅ Segment publish triggered on attempt $ATTEMPT"
    break
  fi

  echo "❌ Segment publish trigger did not return success on attempt $ATTEMPT: $RESPONSE"
  if [ "$ATTEMPT" -lt 3 ]; then
    echo "🔁 Waiting 30s before retry..."
    sleep 30
    ATTEMPT=$((ATTEMPT + 1))
    continue
  fi
  SEG_FINAL="FailedAllAttempts"
  break
done

case "$SEG_FINAL" in
  Triggered)
    # Async publish runs in background — do NOT poll. Proceed to Step 7.
    ;;
  FailedAllAttempts)
    echo "⚠️ Segment publish trigger failed after 3 attempts. Last response: $SEG_LAST_RESPONSE"
    echo "    Continuing to Step 7 — IR + CIs already verified Successful."
    # Surface this in the final report; do NOT exit non-zero.
    ;;
esac
```

**Reporting on retries:**
- ✅ First-try success → `Segment publish: attempt 1/3: triggered`
- 🔁 Recovered after retry → `Segment publish: 1/3 failed → 2/3 triggered`
- ⚠️ All 3 failed → `Segment publish: attempts 1, 2, 3 all failed to trigger. Last response: {...}`. Final report still runs because IR + CIs already succeeded.

---

### Step 7 — Generate final report

**Generate report after Step 3A (IR), Step 4.5 (all 5 CIs sequentially), and Step 6 (Segment publish triggered)**

Note: IR and all 5 CIs are verified Successful. Segment publish is triggered (fire-and-forget) and runs asynchronously in background.

Provide comprehensive summary:

```text
✅ Data Cloud Components Refresh Complete!

Org: <org_alias>
Instance: {instance_url}

═══════════════════════════════════════════════════

🔍 Identity Resolution (verified):
✅ Name: Unified Customer
✅ rulesetStatus: PUBLISHED
✅ lastJobStatus: SUCCESS

═══════════════════════════════════════════════════

📊 Calculated Insights (5) — refreshed sequentially, all verified SUCCESS:
✅ 1/5 Average Order Value Lifetime - lastRunStatus: SUCCESS
✅ 2/5 Average Purchase Value - lastRunStatus: SUCCESS
✅ 3/5 Average Purchase Frequency - lastRunStatus: SUCCESS
✅ 4/5 Customer Lifespan - lastRunStatus: SUCCESS
✅ 5/5 Customer Lifetime Value - lastRunStatus: SUCCESS

═══════════════════════════════════════════════════

🎯 Segment (fire-and-forget):
✅ Name: Power Buyer Program Members
✅ Publish: Triggered (running asynchronously - not waiting for completion)

═══════════════════════════════════════════════════

⏱️ Total Processing Time: {actual_time} minutes

═══════════════════════════════════════════════════

✅ IR and CI refreshes verified Success! Segment publish triggered.

Next Steps:
This is the final installer skill — no auto-chain. Proceed to the installer's final summary.
```

---

### Step 9 — Handle errors gracefully

If any step fails, provide clear error message:

```text
❌ Data Cloud Component Refresh Failed

Org: <org_alias>

Component Failed: <component_name>
Error: <error_message>

Possible Causes:
• Component not found in org
• Data Cloud not enabled
• Missing permissions
• Invalid component configuration

Suggested Fixes:
✅ Verify Data Cloud enabled: Setup → Data Cloud → Settings
✅ Check permissions: Setup → Users → Permission Sets → Data Cloud Admin
✅ Verify component exists: Setup → Data Cloud → [Component Type]
✅ Re-authenticate if needed: sf org login web -a <org_alias>

Would you like me to retry?
```

Common errors:

| Error | Suggested Fix |
|---|---|
| Identity Resolution not found | Create "Unified Customer" IR first |
| Calculated Insight not found | Verify CI API name ends with __cio |
| Segment not found | Create "Power Buyer Program Members" segment first |
| UNAUTHORIZED (401) | Re-authenticate: `sf org login web -a <org_alias>` |
| FORBIDDEN (403) | Assign "Data Cloud Admin" permission set |
| Data Cloud not enabled | Enable Data Cloud in Setup |
| Component not active | Activate component before refresh |

---

## Important Rules

**CRITICAL - Execution Sequence:**
- 🚨 **ALWAYS execute in this order:** Identity Resolution → Calculated Insights (5 sequential) → Segment
- 🚨 **DO NOT run in parallel** - components must refresh sequentially
- 🚨 **Identity Resolution MUST complete first** (`lastJobStatus = SUCCESS` verified) before any CI
- 🚨 **Each CI MUST complete (`lastRunStatus = SUCCESS`) before triggering the next CI**
- 🚨 **CI refresh order:** Average Order Value Lifetime → Average Purchase Value → Average Purchase Frequency → Customer Lifespan → Customer Lifetime Value
- 🚨 **Segment is FIRE-AND-FORGET** — trigger publish and proceed immediately, do NOT wait for completion

**CRITICAL - Status Field Names and Casing (verified 2026-06-10):**
- 🚨 IR uses `lastJobStatus` (camelCase). NOT `LastRunStatus`. NOT `Status`.
- 🚨 CI uses `lastRunStatus` (camelCase). NOT `LastRunStatus`. NOT `CalculatedInsightStatus`.
- 🚨 Segment uses `publishStatus` (camelCase) and is keyed by `marketSegmentId` (NOT `id`, NOT `apiName`) for the publish URL.
- 🚨 ALL status values are UPPERCASE: `IN_PROGRESS`, `PROCESSING`, `PENDING`, `SUCCESS`, `FAILED`, `PUBLISHING`. Comparisons MUST use `${STATUS^^}` (bash) or `.upper()` (Python), or fall through to a defensive `[ "$X" = "SUCCESS" ] || [ "$X" = "Success" ]` OR-check.
- 🚨 IR `lastJobCompleted` is a STALE FIELD: it shows the previous run's timestamp while the current run is in progress. Gate ONLY on `lastJobStatus`.

**CRITICAL - API Request Body:**
- ✅ **ALWAYS use empty JSON body `{}`** in all curl requests
- ✅ **NO parameters needed in request body** - all info in URL path
- ✅ **Component identifiers in URL path only** (IR Id, CI API Name, Segment marketSegmentId)

**CRITICAL - Calculated Insights:**
- ✅ **DO NOT query for CI names** - use hardcoded API names provided
- ✅ **API names always end with __cio** (Calculated Insight Object)
- ✅ **Execute CIs ONE AT A TIME** - trigger CI N, wait for SUCCESS, then trigger CI N+1
- ✅ **Poll each CI status every 30 seconds** via Connect REST GET on `/ssot/calculated-insights/{api_name}` until `lastRunStatus = SUCCESS`
- ✅ **Maximum wait per CI: 10 minutes** before timing out
- ✅ **Report each CI refresh result** individually as you progress

**CRITICAL - Segment:**
- ✅ **Fire-and-forget pattern** - trigger publish via POST and proceed immediately
- ✅ **DO NOT poll segment status** - publish runs asynchronously in background
- ✅ **DO NOT wait for "Published" status** - skill completes after trigger succeeds (`publishStatus: PUBLISHING`)
- 🚨 **Use `marketSegmentId` (starts with `1sg`) in the publish URL.** NOT `apiName`. NOT the null `id` from the list endpoint. Step 5 captures `marketSegmentId` via a two-step lookup (list → single GET).

**CRITICAL - Status Verification Style:**
- ✅ **Use Connect REST GET on the same `/ssot/...` resources you triggered** — NO SOQL, NO `--use-tooling-api`, NO temp `.soql` files.
  - IR status:  `GET /services/data/v66.0/ssot/identity-resolutions/{id}` → read `lastJobStatus`
  - CI status:  `GET /services/data/v66.0/ssot/calculated-insights/{api_name}` → read `lastRunStatus`
  - Segment ID: `GET /services/data/v66.0/ssot/segments/{api_name}` → read `marketSegmentId`
- ❌ Earlier versions of this skill used `sf data query --use-tooling-api` against `IdentityResolution`, `MktCalculatedInsight`, and `MarketSegment` SObjects. That approach worked but mixed two API styles, required temp file creation/cleanup, and used different field name conventions (`LastRunStatus` vs `lastRunStatus`). Do NOT bring SOQL back.

**General Rules:**
- NEVER hardcode org names — always use provided org_alias parameter
- ALWAYS use API version v66.0 or higher
- ALWAYS use `-d '{}'` for empty JSON body in curl commands
- ALWAYS return job IDs for monitoring
- ALWAYS report each component refresh status
- ALWAYS execute components in sequence (IR → CIs → Segment)
- NEVER skip any component - all must be refreshed
- If one component fails, report error but continue with remaining components
- Provide clear error messages with suggested fixes
- Auto-monitor progress via Connect REST GET on the same `/ssot/...` resources you triggered. Never request manual UI verification. Never reach for SOQL.
- Estimated total processing time: 25-35 minutes for all components (IR ~15 min, 5 CIs ~10-15 min total, Segment trigger immediate)

---

## Example Usage

### Example 1: User provides org name

**User:** "Refresh Data Cloud components in MyRetailOrg"

**Skill:**
1. Gets org credentials: `sf org display`
2. Queries Identity Resolution: `GET /ssot/identity-resolutions` → find "Unified Customer", capture `id`
3. Refreshes IR: `POST /ssot/identity-resolutions/{id}/actions/run-now`, then poll `GET /ssot/identity-resolutions/{id}` until `lastJobStatus = SUCCESS`
4. Refreshes CI 1: `POST /ssot/calculated-insights/Average_Order_Value_Lifetime__cio/actions/run`, poll `GET /ssot/calculated-insights/Average_Order_Value_Lifetime__cio` until `lastRunStatus = SUCCESS`
5. Refreshes CI 2: `POST /ssot/calculated-insights/Average_Purchase_Value__cio/actions/run`, poll until SUCCESS
6. Refreshes CI 3: `POST /ssot/calculated-insights/Average_Purchase_Frequency__cio/actions/run`, poll until SUCCESS
7. Refreshes CI 4: `POST /ssot/calculated-insights/Customer_Lifespan__cio/actions/run`, poll until SUCCESS
8. Refreshes CI 5: `POST /ssot/calculated-insights/Customer_Lifetime_Value__cio/actions/run`, poll until SUCCESS
9. Queries Segment: `GET /ssot/segments/Power_Buyer_Program_Members` → capture `marketSegmentId`
10. Publishes Segment: `POST /ssot/segments/{marketSegmentId}/actions/publish` (fire-and-forget)
11. Reports summary with all job IDs

---

### Example 2: Error handling - Component not found

**User:** "Refresh Data Cloud components in TestOrg"

**Skill:** [Queries Identity Resolution]

**Error:** `Identity Resolution "Unified Customer" not found`

**Skill:**
```text
❌ Identity Resolution Refresh Failed

Org: TestOrg

Component Failed: Identity Resolution "Unified Customer"
Error: Not found in org

Possible Causes:
• Identity Resolution not created yet
• IR name is different
• Data Cloud not fully provisioned

Suggested Fixes:
✅ Navigate to Setup → Data Cloud → Identity Resolutions
✅ Verify "Unified Customer" exists
✅ Check IR is active (not draft)
✅ Create IR if missing

Cannot proceed without Identity Resolution. Please create "Unified Customer" IR first.
```

---

## Success Criteria

Refresh is successful when:

✅ Org authentication validated
✅ Identity Resolution "Unified Customer" refreshed and verified `lastJobStatus = SUCCESS` (Step 3A)
✅ CI 1/5 Average Order Value Lifetime refreshed and verified `lastRunStatus = SUCCESS`
✅ CI 2/5 Average Purchase Value refreshed and verified `lastRunStatus = SUCCESS` (only after CI 1 SUCCESS)
✅ CI 3/5 Average Purchase Frequency refreshed and verified `lastRunStatus = SUCCESS` (only after CI 2 SUCCESS)
✅ CI 4/5 Customer Lifespan refreshed and verified `lastRunStatus = SUCCESS` (only after CI 3 SUCCESS)
✅ CI 5/5 Customer Lifetime Value refreshed and verified `lastRunStatus = SUCCESS` (only after CI 4 SUCCESS)
✅ Segment "Power Buyer Program Members" publish triggered against `marketSegmentId` (fire-and-forget — `publishStatus = PUBLISHING` is sufficient; no wait for `PUBLISHED`)
✅ All API calls returned success (HTTP 200/201/202)
