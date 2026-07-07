---
name: datakit-api-deploy
description: "Deploy Data360 Retail Data Kit using Salesforce Connect REST API with async mode. Triggers Data Kit installation after metadata deployment. Returns job ID for monitoring. Requires metadata deployment completed first (612 components). Use when user wants to deploy data kit via API, trigger data kit installation, or activate data kit after metadata deployment."
---

# datakit-api-deploy

## Purpose

Deploy the Data360 Retail Data Kit using Salesforce Connect REST API in asynchronous mode.

This skill triggers the Data Kit installation process after metadata components have been deployed. The deployment runs asynchronously and typically takes 25-35 minutes.

Prerequisites:
- Metadata deployment must be completed first (612 components)
- Target org must have Data Cloud enabled
- User must have Data Cloud permissions

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

Before running:

- Salesforce CLI must be installed
- Target org must be authenticated with Salesforce CLI
- Metadata deployment must be completed successfully (612 components)
- Target org must have Data Cloud enabled and licensed
- User must have "Manage Data Cloud" permission
- User must have "View Setup and Configuration" permission
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
  Without this, `sf org display` and `curl` commands will prompt for approval. The skill requires these commands to get the access token and trigger the API deployment.

---

## Workflow

### Step 1 — Skip org authentication verification

**CRITICAL: Skip org authentication check entirely**

**Reason:** If datakit-metadata-deploy skill already ran successfully, the org is authenticated and connected. No need to verify again - this wastes time and adds unnecessary approval prompts.

**Skip these commands:**
- ❌ `sf org list` (not needed)
- ❌ `sf org login web` (not needed)

**Proceed directly to Step 2.**

---

### Step 2 — Get org access token and instance URL

**Run ONCE to get credentials:**

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

Store these values for API call.

---

### Step 3 — Skip metadata deployment verification

**CRITICAL: Skip metadata deployment verification**

**Reason:** If datakit-metadata-deploy skill just ran successfully, we already know that 612 components were deployed. No need to verify again.

**Assume:**
- ✅ Metadata deployment completed successfully
- ✅ 612 components deployed to target org
- ✅ Data Kit metadata is ready

**Proceed directly to Step 4.**

---

### Step 4 — Prepare Connect API request

**API Endpoint:**

```
POST {instance_url}/services/data/v66.0/ssot/data-kits/Data360RetailDIYDataKit?asyncMode=true
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

**IMPORTANT - Empty JSON Body Required:**
- ✅ Use empty JSON object `{}` as request body
- ❌ DO NOT include `dataKitName` field (API rejects it)
- ❌ DO NOT include `asyncMode` in body (it's in URL query param only)
- The API requires a body but it must be empty JSON

**Important:**
- API version must be v66.0 or higher
- `asyncMode=true` query parameter is required (synchronous mode times out)
- Data Kit name is in the URL path: `Data360RetailDIYDataKit`
- Body must be exactly `{}`

---

### Step 5 — Execute API deployment

**CRITICAL: Use empty JSON body `{}`**

Run curl command:

```bash
curl -X POST \
  "{instance_url}/services/data/v66.0/ssot/data-kits/Data360RetailDIYDataKit?asyncMode=true" \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{}' \
  --silent \
  --show-error
```

**Why empty body?**
- The API endpoint requires a JSON body but doesn't accept any fields
- Sending `dataKitName` or other fields causes `JSON_PARSER_ERROR`
- The Data Kit name comes from the URL path, not the body
- `asyncMode` is a query parameter, not a body field

This returns immediately with job ID.

Actual deployment runs asynchronously in background.

---

### Step 6 — Parse API response

**Success Response (HTTP 202 Accepted):**

```json
{
  "jobId": "08Paj00000kcLaRCAU",
  "status": "Queued",
  "message": "Data Kit deployment started successfully"
}
```

Extract:
- `jobId`: Used for monitoring (starts with 08P)
- `status`: Initial status (Queued)

**Error Response (HTTP 400/401/403/500):**

```json
{
  "errorCode": "INVALID_REQUEST",
  "message": "Data Kit not found or user lacks permissions"
}
```

---

### Step 7 — Calculate monitoring URL

Build Salesforce UI monitoring URL:

```
{instance_url}/lightning/setup/DataKits/home
```

This takes user directly to Data Kits setup page.

User can monitor deployment progress in real-time.

---

### Step 8 — Report deployment status

On success (after deployment completes):

```text
✅ Data Kit API Deployment Complete!

Org: <org_alias>
Instance: {instance_url}

✅ Job ID: 08Paj00000kcLaRCAU
✅ Status: Installed
✅ Components Deployed: 31/31
⏱️ Total Time: {actual_time} minutes

Deployment Process Completed:
✅ Data streams initialization
✅ Calculated insights compilation
✅ Identity resolution rules processing
✅ Data model field mappings
✅ Related list enrichments

🔗 Verification:
{instance_url}/lightning/setup/DataKits/home

Next Steps:
Proceed to Step 6: Data Stream File Upload
```

On deployment started (initial response):

```text
🚀 Data Kit API Deployment Started!

Org: <org_alias>
Instance: {instance_url}

✅ Job ID: 08Paj00000kcLaRCAU
✅ Status: Queued
⏳ Estimated Time: 25-35 minutes
⏳ Waiting for deployment to complete...

Polling deployment status every 60 seconds...
```

On error:

```text
❌ API Deployment Failed

Org: <org_alias>
Error Code: INVALID_REQUEST
Error Message: Data Kit not found or user lacks permissions

Possible Causes:
1. Metadata deployment not completed (need 612 components)
2. Data Cloud not enabled in org
3. Missing Data Cloud license
4. User lacks "Manage Data Cloud" permission
5. API version too old (need v66.0+)

Suggested Fix:
✅ Verify metadata deployment: /datakit-metadata-deploy <org_alias>
✅ Check Data Cloud enabled: Setup → Data Cloud → Settings
✅ Verify license: Setup → Company Information → Licenses
✅ Check permissions: Setup → Users → Permission Sets → Data Cloud Admin
✅ Re-authenticate if needed: sf org login web -a <org_alias>
```

---

### Step 9 — Auto-Monitor Deployment Every 5 Minutes Until Complete (45 min total wait)

**🚨 CRITICAL EXECUTION MODE — READ BEFORE WRITING ANY POLLING CODE:**

**This skill runs inside a sub-agent context (the `data360-retail-installer` orchestrator invokes it as a sub-agent). Sub-agents DO NOT receive `<task-notification>` callbacks for `run_in_background: true` tasks — those notifications go to the *parent* main loop, not to the sub-agent that spawned them. If a sub-agent kicks off a 30-45 min background task and returns final text, the sub-agent is DONE. The background task may complete successfully later, but no one is left in the sub-agent to act on it, and the orchestrator records "Check 1/9 = Running. Waiting for notification." as the sub-agent's final answer — even though the deploy actually finished.**

**This was an observed failure: Data Kit jobId `08PHn00000lZMgb` reached `Complete` at minute 30, but the sub-agent had already exited at minute 0 after the initial `run_in_background: true` Bash call returned. The orchestrator never proceeded to Step 5 of the installer.**

**MANDATORY: Use FOREGROUND CHUNKED POLLING. One poll per Bash call. The sub-agent loops by re-invoking Bash up to 9 times. Each Bash call stays under the 10-min foreground cap, and the sub-agent stays alive across the full 45 min because it keeps issuing tool calls.**

**Expected Deployment Time:** 30-45 minutes
**Polling Interval:** Every 5 minutes (300 s)
**Maximum Polls:** 9 (45 minutes total — at minutes 5, 10, 15, 20, 25, 30, 35, 40, 45)
**Execution Mode:** **FOREGROUND, one Bash call per poll, sub-agent loops in its main loop.** Do NOT use `run_in_background: true` from this skill.

**Implementation — chunked foreground polling (sub-agent driven):**

The sub-agent issues ONE foreground Bash call per poll. Each Bash call:
1. Sleeps until the next 5-min mark (5 min = 300 s — well under the 10-min foreground cap).
2. Calls the status endpoint ONCE.
3. Prints `jobStatus` and exits with a code the sub-agent inspects.

The sub-agent loops in ITS OWN main loop by re-invoking the same Bash command (with check number incremented) until exit code 0 (Complete), 2 (Timeout — i.e. check 9 still Running), or 3 (terminal-failed → hands to Step 9.5).

**Single-poll Bash call shape (the sub-agent runs this 1..9 times in foreground):**

```bash
#!/bin/bash
# Inputs: ACCESS_TOKEN, INSTANCE_URL, JOB_ID, CHECK_NUM (1..9)
# Sleep first so the call respects the 5-min interval. On check 1 you may
# pass SKIP_SLEEP=1 if you want the first poll to be immediate; otherwise
# sleep 300 between checks. Default: always sleep, including before check 1
# (the deploy needs warm-up time anyway).
SKIP_SLEEP="${SKIP_SLEEP:-0}"
[ "$SKIP_SLEEP" = "1" ] || sleep 300

RESPONSE=$(curl -X GET \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v66.0/ssot/datakit-deployment-job/${JOB_ID}" \
  --silent)

JOB_STATUS=$(echo "$RESPONSE" | grep -o '"jobStatus":"[^"]*"' | cut -d'"' -f4)
echo "Check ${CHECK_NUM}/9 (at minute $((CHECK_NUM*5))): Job Status = $JOB_STATUS"

if [ "$JOB_STATUS" = "Complete" ]; then
  echo "✅ Data Kit deployment complete!"
  exit 0
fi

case "$JOB_STATUS" in
  Failed|Error|Cancelled|Canceled|Aborted)
    ERR_MSG=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    if isinstance(d, list) and d:
        print(d[0].get('message', d[0].get('errorCode', '')))
    elif isinstance(d, dict):
        errs = d.get('errors') or []
        if errs and isinstance(errs, list):
            print('; '.join(str(e) for e in errs[:3]))
        else:
            print(d.get('message', d.get('errorCode', '')))
except: print('')
" 2>/dev/null || echo "")
    echo "❌ Deployment terminal-failed: jobStatus=$JOB_STATUS"
    echo "   Error message: $ERR_MSG"
    echo "   Full response: $RESPONSE"
    exit 3   # retry-eligible — Step 9.5 wrapper handles re-deploy
    ;;
esac

# Still Running / InProgress / Queued — exit 10 means "keep polling, advance CHECK_NUM"
echo "⏳ Status = $JOB_STATUS. Sub-agent: advance CHECK_NUM and re-invoke."
[ "$CHECK_NUM" -ge 9 ] && exit 2   # 9th check still not terminal → timeout
exit 10
```

**Sub-agent loop pseudocode (this is what the orchestrator's invocation of the skill must do):**

```
CHECK = 1
while CHECK <= 9:
    rc = Bash(command=<single-poll script with CHECK_NUM=CHECK>, timeout=420000)
    case rc:
        0  → break, success → invoke /agentforce-data-library
        2  → timeout, exit skill with code 2
        3  → terminal failure, hand to Step 9.5
       10  → still running, CHECK += 1, continue
        *  → unknown failure, surface to user, exit 1
```

Each Bash call has a wall-clock of `sleep 300 + curl (~1s) ≈ 5 min 1 s` — comfortably under the 10-min foreground cap. The sub-agent stays alive across all 9 iterations because it keeps issuing tool calls. There is no background task, no notification dependency, and no "agent already exited when notification arrived" failure mode.

**Why match all five terminal states:** the Salesforce Data Kit deployment API returns `Error` (not `Failed`) for platform-contention failures, lock conflicts, and partial-component failures. The previous version only handled `Failed`, so `Error` fell through to the wildcard "still in progress, keep polling" branch — wasting up to 45 minutes per attempt and never triggering the retry. We now match all five known terminal-failure values explicitly.

**How to run this from the Bash tool (sub-agent execution model):**
- Run each poll as a FOREGROUND Bash call (`run_in_background: false`, the default).
- Set `timeout: 420000` (7 min) on each call to leave headroom over the `sleep 300 + curl` time.
- After each call, inspect the exit code (the Bash tool returns it). If 10, increment `CHECK_NUM` and re-invoke. If 0/2/3, branch and stop polling.
- Do NOT use `run_in_background: true`. Sub-agents do not receive `<task-notification>` callbacks for background tasks — those go to the parent main loop, and the sub-agent will exit before the deploy finishes (observed failure: jobId `08PHn00000lZMgb` reached Complete at minute 30 but sub-agent had returned at minute 0).

**Exit-code contract for each single-poll Bash call:**
| Exit | Meaning | Sub-agent next action |
|---|---|---|
| 0  | jobStatus reached `Complete` | STOP polling. Auto-invoke `/agentforce-data-library`. |
| 2  | This was check 9 and status is still non-terminal | STOP polling. Surface jobId + last status to user. Do NOT auto-retry. |
| 3  | jobStatus reached terminal-failed (`Failed` / `Error` / `Cancelled` / `Canceled` / `Aborted`) | STOP polling. Hand to Step 9.5 retry block. |
| 10 | Still `Running` / `InProgress` / `Queued`, more checks remain | INCREMENT `CHECK_NUM` and re-invoke the same Bash command. |
| *  | Unknown failure | STOP. Surface raw output to user. |

**Why this fixes the previous failure mode:**
1. The pre-fix version ran the polling loop with `run_in_background: true` and assumed a `<task-notification>` would come back. Inside a sub-agent context, those notifications are delivered to the *parent* main loop, NOT to the sub-agent that spawned the task. So the sub-agent returned final text after seeing only the first poll, and the orchestrator recorded "Check 1/9 = Running, waiting for notification" as the deploy's final answer — even when the deploy actually finished. Observed instance: jobId `08PHn00000lZMgb` reached Complete at minute 30, but the sub-agent had been dead since minute 0.
2. An earlier version of this skill ran the entire 45-min loop in a single foreground Bash call. That hit Bash's 10-min foreground hard cap on the first `sleep 300`, the call was killed, and any retry restarted at Check 1 — the loop never advanced past minute 5-10.
3. The chunked foreground pattern above sidesteps both bugs: each Bash call is ~5 min (well under the 10-min cap), the sub-agent stays alive because it keeps issuing tool calls, and there is no background notification dependency.

**After jobStatus = "Complete", AUTOMATICALLY invoke next skill (NEVER ask user):**

```
/agentforce-data-library <org_alias>
```

**What to Report (Keep Minimal):**
- ✅ "Polling started (foreground chunked, 5 min interval, max 45 min — 9 polls)"
- ✅ "Check 1/9 (at 5 min): Job Status = Running"
- ✅ "Check 2/9 (at 10 min): Job Status = Running"
- ✅ "Check 6/9 (at 30 min): Job Status = Complete"
- ✅ "✅ Data Kit deployment complete!"
- ✅ Then immediately: Invoke `/agentforce-data-library` automatically (no user prompt)

**Sub-agent must not return final text between polls.** Issue the next Bash call directly. If the sub-agent emits final text after Check 1 with status Running, the orchestrator records that as the skill's outcome and the chain breaks — exactly the failure pattern this rewrite eliminates.

**What NOT to Report:**
- ❌ Detailed deployment timeline
- ❌ UI monitoring instructions
- ❌ Verification steps requiring user action
- ❌ "Would you like to..." questions
- ❌ "Should I proceed?" prompts

**IMPORTANT:**
- Poll using endpoint: `/services/data/v66.0/ssot/datakit-deployment-job/{JobId}`
- Check every **5 minutes** (300 seconds)
- Maximum **9 polls (45 minutes total)** — covers the 30-45 min expected window
- Auto-proceed when Complete — NEVER ask user
- Do NOT wait for user input

---

### Step 9.5 — Auto-retry on terminal failure (re-deploy via API, max 5 total attempts)

**CRITICAL: When Step 9 polling returns any terminal-failed `jobStatus` (`Failed`, `Error`, `Cancelled`, `Canceled`, `Aborted`), do NOT exit immediately.** The retry wrapper re-POSTs the Data Kit deployment by hitting `/ssot/data-kits/Data360RetailDIYDataKit?asyncMode=true` again (same empty body), captures the new `jobId`, and resumes polling on the same 5-minute / 45-minute cadence.

**Retry policy — UPDATED:**
- **5 total deployment attempts**: 1 initial (Step 5) + up to **4 retries** when an attempt ends in any terminal-failed state.
- **Each attempt polls for up to 45 minutes**, checking every 5 minutes (9 polls per attempt).
- Wait **30 seconds** between failure detection and the next retry POST for attempts 2–3 (gives the platform time to release locks the failed run held).
- Wait **60 seconds** between failure detection and retry POST for attempts 4–5 (escalates the platform-recovery window for stickier contention).
- **Fail-fast list** — if the captured error message matches a deterministic platform error (license missing, feature off, permission denied), abort retries immediately. No point burning 4 more attempts on the same root cause.
- After **all 5 attempts fail**, STOP and report. The installer chain DOES NOT proceed.
- **Worst-case wall-clock** of this block: 5 × 45 min poll + 2 × 30s gap + 2 × 60s gap ≈ **228 minutes** (~3 hr 48 min). Drive the entire block from the sub-agent's main loop using **chunked foreground polling** — one Bash call per poll (≈5 min each), exactly as Step 9 specifies. Do NOT use `run_in_background: true`; sub-agents do not receive the completion notification, so a backgrounded retry block silently abandons the deploy.

**Fail-fast error patterns (abort retries immediately):**

| Error code / message contains | Why we abort |
|---|---|
| `INSUFFICIENT_ACCESS` | User lacks Data Cloud admin permission — retries will all fail identically |
| `LICENSE_LIMIT_EXCEEDED` | Org doesn't have the Data Cloud license — admin must add license |
| `FEATURE_NOT_ENABLED` | Data Cloud feature isn't enabled — Step 1 (feature-enablement) didn't apply |
| `INVALID_TYPE` | Data Kit API version mismatch — retries won't fix |
| `permission` (case-insensitive) | Generic perm error — surface to user |
| `not licensed` | Same — license issue, not transient |

**Reference shell script (DO NOT execute as a single Bash call — see chunked-execution note below).** This documents the full state machine: 1 initial deploy + up to 4 retries, fail-fast classification, tiered backoff, audit log. The sub-agent must re-implement this state machine across multiple foreground tool calls — one Bash call per poll inside each attempt (Step 9's chunked pattern), and one separate Bash call per re-deploy POST + per inter-attempt sleep. The sub-agent tracks `ATTEMPT`, `JOB_ID`, `FINAL_STATUS`, and `ATTEMPT_LOG` in its own conversation context between calls. Running this whole script as a single Bash call is forbidden because (a) the inner `sleep 300` blows the 10-min foreground cap, and (b) `run_in_background: true` doesn't deliver `<task-notification>`s to sub-agents.

```bash
ACCESS_TOKEN="..."        # from Step 2
INSTANCE_URL="https://..." # from Step 2
JOB_ID="08PHp000..."       # from Step 6 (initial POST response)

MAX_ATTEMPTS=5
ATTEMPT=1
FINAL_STATUS=""
FINAL_ERRORS=""
declare -a ATTEMPT_LOG=()    # captures one line per attempt for the final report

# Helper: classify an error as fail-fast (deterministic) or retry-eligible
is_fail_fast() {
  local msg_lc=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  case "$msg_lc" in
    *insufficient_access*|*license_limit_exceeded*|*feature_not_enabled*|\
    *invalid_type*|*permission*|*not\ licensed*|*not_licensed*)
      return 0 ;;   # fail-fast (deterministic)
  esac
  return 1          # retry-eligible (transient)
}

while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
  echo "==== Deploy attempt $ATTEMPT / $MAX_ATTEMPTS (jobId=$JOB_ID) ===="

  # ---- Reuse Step 9 polling (every 5 min, max 9 polls = 45 min) ----
  POLL_RESULT="Timeout"   # default if loop exhausts without terminal state
  ATTEMPT_FAIL_REASON=""
  for i in $(seq 1 9); do
    echo "Check $i/9 (at minute $((i*5))): Polling deployment status..."

    RESPONSE=$(curl -X GET \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "${INSTANCE_URL}/services/data/v66.0/ssot/datakit-deployment-job/${JOB_ID}" \
      --silent)

    JOB_STATUS=$(echo "$RESPONSE" | grep -o '"jobStatus":"[^"]*"' | cut -d'"' -f4)
    echo "Attempt $ATTEMPT — Check $i/9: Job Status = $JOB_STATUS"

    if [ "$JOB_STATUS" = "Complete" ]; then
      POLL_RESULT="Complete"
      break
    fi

    # Match ALL terminal-failed states. Capture error message at first
    # detection (before the platform garbage-collects the job record).
    case "$JOB_STATUS" in
      Failed|Error|Cancelled|Canceled|Aborted)
        POLL_RESULT="Failed"
        ATTEMPT_FAIL_REASON=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    if isinstance(d, list) and d:
        print(d[0].get('message', d[0].get('errorCode','')))
    elif isinstance(d, dict):
        errs = d.get('errors') or []
        if errs and isinstance(errs, list):
            print('; '.join(str(e) for e in errs[:3]))
        else:
            print(d.get('message', d.get('errorCode','')))
except: print('')
" 2>/dev/null || echo "")
        FINAL_ERRORS="$ATTEMPT_FAIL_REASON"
        echo "❌ Attempt $ATTEMPT terminal-failed at minute $((i*5)): $JOB_STATUS"
        echo "   Error message: $ATTEMPT_FAIL_REASON"
        break
        ;;
    esac

    if [ $i -lt 9 ]; then
      echo "⏳ Status = $JOB_STATUS. Waiting 5 minutes for next check..."
      sleep 300
    fi
  done

  # ---- Record this attempt's outcome in the audit log ----
  ATTEMPT_LOG+=("Attempt $ATTEMPT (jobId=$JOB_ID) → $POLL_RESULT${ATTEMPT_FAIL_REASON:+: $ATTEMPT_FAIL_REASON}")

  # ---- Decide: success, retry, or give up ----
  if [ "$POLL_RESULT" = "Complete" ]; then
    FINAL_STATUS="Complete"
    echo "✅ Data Kit deployment complete on attempt $ATTEMPT (jobId=$JOB_ID)"
    break
  fi

  if [ "$POLL_RESULT" = "Timeout" ]; then
    FINAL_STATUS="Timeout"
    echo "⚠️ Attempt $ATTEMPT did not reach a terminal state in 45 minutes. NOT retrying."
    break
  fi

  # POLL_RESULT == "Failed" → check fail-fast list before consuming a retry
  if is_fail_fast "$ATTEMPT_FAIL_REASON"; then
    FINAL_STATUS="FailFastDeterministic"
    echo "🛑 Fail-fast: error message indicates a deterministic platform issue."
    echo "   Reason: $ATTEMPT_FAIL_REASON"
    echo "   Retries would all fail identically. Aborting after attempt $ATTEMPT."
    break
  fi

  # Retry only if attempts remain
  if [ "$ATTEMPT" -lt "$MAX_ATTEMPTS" ]; then
    # Tiered backoff: 30s for attempts 1-2 → next, 60s for attempts 3-4 → next
    if [ "$ATTEMPT" -lt 3 ]; then
      GAP=30
    else
      GAP=60
    fi
    echo "🔁 Failure on attempt $ATTEMPT of $MAX_ATTEMPTS. Waiting ${GAP}s before re-deploying..."
    sleep "$GAP"

    # Re-trigger the Data Kit deploy (same POST body as Step 5)
    REDEPLOY_RESPONSE=$(curl -X POST \
      "${INSTANCE_URL}/services/data/v66.0/ssot/data-kits/Data360RetailDIYDataKit?asyncMode=true" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{}' \
      --silent --show-error)

    NEW_JOB_ID=$(echo "$REDEPLOY_RESPONSE" | grep -o '"jobId":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$NEW_JOB_ID" ]; then
      FINAL_STATUS="ReDeployRejected"
      echo "❌ Re-deploy POST rejected: $REDEPLOY_RESPONSE"
      ATTEMPT_LOG+=("Re-deploy POST after attempt $ATTEMPT rejected: $REDEPLOY_RESPONSE")
      break
    fi

    echo "🔁 Retry POST accepted. New jobId=$NEW_JOB_ID. Polling on the same 5-min/45-min cadence..."
    JOB_ID="$NEW_JOB_ID"
    ATTEMPT=$((ATTEMPT + 1))
    continue
  else
    FINAL_STATUS="FailedAllAttempts"
    echo "❌ All $MAX_ATTEMPTS deploy attempts failed."
    break
  fi
done

# ============================================================================
# FINAL FAILURE REPORT — printed for any non-Complete outcome
# ============================================================================
if [ "$FINAL_STATUS" != "Complete" ]; then
  echo ""
  echo "🛑 ============================================================"
  echo "🛑 DATA KIT DEPLOYMENT FAILED — INSTALLER CHAIN STOPPED"
  echo "🛑 ============================================================"
  echo ""
  echo "Skill:        /datakit-api-deploy"
  echo "Final status: $FINAL_STATUS"
  echo "Last error:   $FINAL_ERRORS"
  echo ""
  echo "Per-attempt summary:"
  for line in "${ATTEMPT_LOG[@]}"; do
    echo "  $line"
  done
  echo ""
  echo "Common root causes:"
  echo "  • Data Cloud feature license missing or expired"
  echo "  • Required permission set not assigned to the running user"
  echo "  • Metadata deployment (Step 3) didn't actually finish — verify 612 components"
  echo "  • Org is in a maintenance/contention window — try again later"
  echo "  • Managed package conflict with an existing Data Kit"
  echo ""
  echo "🛑 INSTALLER WILL NOT PROCEED."
  echo "   Steps NOT run (blocked):"
  echo "     5. /agentforce-data-library"
  echo "     6. /intelligent-context"
  echo "     7. /create-individual-retrievers"
  echo "     ... and all remaining steps"
  echo ""
  echo "Next steps for the user:"
  echo "  1. Inspect the org at: ${INSTANCE_URL}/lightning/setup/DataKits/home"
  echo "  2. Resolve the underlying error using the per-attempt errors above"
  echo "  3. Re-run /datakit-api-deploy <org_alias> manually,"
  echo "     OR re-run the data360-retail-installer agent (it will skip the"
  echo "     already-completed earlier steps and resume from Step 4)."
  echo ""
fi

case "$FINAL_STATUS" in
  Complete)
    # Auto-proceed to next skill (installer chain may continue to /agentforce-data-library)
    exit 0
    ;;
  Timeout)
    echo "⏱️ Deployment did not reach a terminal state in 45 minutes on the final attempt."
    exit 2
    ;;
  FailedAllAttempts | ReDeployRejected | FailFastDeterministic)
    exit 1
    ;;
  *)
    # Should never happen — defensive fallback
    echo "❌ Unknown final status: $FINAL_STATUS"
    exit 1
    ;;
esac
```

**What to Report (one line per outcome):**
- ✅ Success on first try → `Deploy attempt 1 / 5: Complete`
- 🔁 Recovered after retry → `1: Failed → 2: Complete` (or any path through 1–5)
- ❌ All 5 attempts failed → full per-attempt summary printed above + troubleshooting items from Step 10
- 🛑 Fail-fast → printed deterministic-error message, aborted before exhausting retries
- ⏱️ Timeout on final attempt → jobId surfaced for user to investigate manually

**MANDATORY HARD-STOP RULE (bound by user requirement):**

> If `FINAL_STATUS` is anything other than `Complete` (i.e. `FailedAllAttempts`, `ReDeployRejected`, `FailFastDeterministic`, or `Timeout`), the installer chain MUST STOP at this skill. The orchestrator MUST NOT auto-invoke `/agentforce-data-library` (Step 5). The orchestrator MUST NOT auto-invoke any other downstream skill. The user must investigate the failure, fix the root cause in the org, and explicitly re-run the agent or this skill before any later skill is allowed to execute. This rule overrides the orchestrator's "auto-chain on success" behavior — non-zero exits from this skill are a hard stop with no exception.

**Failure escalation (only after all 5 attempts fail OR fail-fast triggers):**
1. Surface the `errors` array AND the per-attempt `ATTEMPT_LOG` to the user verbatim — they usually point at the offending Data Kit component (missing DLO, wrong API version, license missing) or a deterministic platform issue (license/perm/feature).
2. Common root causes that retries will NOT fix on their own (these often show up via fail-fast — the script aborts retries early):
   - Data Cloud feature license missing or expired (`LICENSE_LIMIT_EXCEEDED`).
   - Required permission set not assigned to the running user (`INSUFFICIENT_ACCESS`, `permission`).
   - Data Cloud feature not enabled on the org (`FEATURE_NOT_ENABLED`).
   - Metadata deployment (Step 3) didn't actually finish — verify 612 components landed.
   - Stale managed DLO references (re-run `datakit-metadata-deploy` cleanup, then redeploy).
   - Managed package conflict with an existing Data Kit.
3. Common root causes that DO benefit from retries (the 5-attempt budget is sized for these):
   - Platform contention / locked DLOs from the recent metadata deploy.
   - Async metadata still settling (1–3 min after Step 3 finished).
   - Org in a maintenance / contention window.
4. Do NOT auto-proceed to `agentforce-data-library` if `FINAL_STATUS != Complete`. The user must explicitly re-run the agent or this skill.

**Why retries help here:**
- Salesforce Data Kit installation can transiently fail on platform contention (locked DLOs, async metadata still settling) within the first 1–2 minutes after metadata deploy. A second POST after a 30s pause typically succeeds because the platform has released the locks.
- Empirically observed: real-world Data Kit deploys can take 2–3 attempts on a healthy day. The 5-attempt budget gives safety margin.
- Retries do NOT re-deploy metadata — they only re-trigger the *installation* of the already-deployed Data Kit components. Step 3 (skipped metadata-deploy verification) remains valid; this section only covers the install/activate phase.

**Do NOT skip this section.** It supersedes the legacy "exit 1 on Failed" behavior shown inline in the Step 9 example and Step 11 polling sample. The hard cap is **5 attempts total** — never more, and never less.

---

### Step 10 — Handle common API errors

| Error Code | HTTP Status | Cause | Fix |
|---|---|---|---|
| INVALID_REQUEST | 400 | Data Kit not found | Verify metadata deployed |
| UNAUTHORIZED | 401 | Invalid/expired token | Re-authenticate org |
| FORBIDDEN | 403 | Missing permissions | Add "Manage Data Cloud" permission |
| NOT_FOUND | 404 | Endpoint not available | Check API version (need v66.0+) |
| INTERNAL_ERROR | 500 | Salesforce platform issue | Retry after 5 minutes |

**Re-authentication command:**

```bash
sf org login web --alias <org_alias>
```

**Permission check:**

1. Setup → Users → [username]
2. Permission Set Assignments
3. Verify "Data Cloud Admin" assigned

---

### Step 11 — Wait for deployment completion (background polling, up to 45 minutes per attempt)

**CRITICAL: Do NOT proceed to next step until Data Kit deployment job shows "Complete" status**

**Data Kit deployment can take 30-45 minutes. You MUST wait for completion before proceeding. Drive the polling from the sub-agent's main loop using chunked foreground Bash calls (one poll per call, ~5 min each) as documented in Step 9. Do NOT use `run_in_background: true` — sub-agents do not receive `<task-notification>` callbacks, so a backgrounded poll loop silently abandons the deploy. And do NOT pack the whole 45-min loop into one foreground call — Bash's 10-min foreground timeout will kill it on the first `sleep 300` and any retry restarts at Check 1 ("auto sleep and re-run" bug).**

**Note:** This step is the *reference* polling spec. The active polling loop is the one in Step 9 (single-attempt) and the retry-wrapped loop in Step 9.5 (multi-attempt). Both already implement this 5-min / 45-min / 9-poll contract. Step 11 exists for documentation; do NOT re-launch a third polling loop.

**CORRECT API ENDPOINT for checking deployment status:**

```bash
GET /services/data/v66.0/ssot/datakit-deployment-job/{jobId}
```

**Response format (CdpDataKitDeployJobOutputRepresentation):**
```json
{
  "jobId": "08PHu000027WW6b",
  "jobStatus": "Complete" | "Running" | "InProgress" | "Failed" | "Error" | "Cancelled" | "Aborted",
  "jobResults": ["componentId1", "componentId2"],
  "errors": ["error1", "error2"]
}
```

**Wait strategy: Poll every 5 minutes for up to 45 minutes (30-45 min expected window — 9 polls)**

1. Poll deployment job status every 5 minutes using CORRECT API endpoint:

```bash
curl -X GET \
  -H "Authorization: Bearer {access_token}" \
  "{instance_url}/services/data/v66.0/ssot/datakit-deployment-job/{jobId}" \
  --silent
```

2. Parse JSON response to check job status:
   - `jobStatus`: "Complete" → ✅ success, auto-proceed to next skill
   - `jobStatus`: "InProgress" / "Running" / "Queued" → still deploying, wait 5 min, continue polling
   - `jobStatus`: "Failed" / "Error" / "Cancelled" / "Canceled" / "Aborted" → ❌ terminal failure, defer to **Step 9.5 retry block** (do NOT exit yet — re-deploy the Data Kit, max 5 total attempts)
   - `errors`: Array of error messages — capture verbatim for the per-attempt audit log

3. If still "InProgress", wait 5 minutes and repeat:
```bash
sleep 300  # 5 minutes
```

**Poll every 5 minutes until one of these conditions is met:**
- ✅ jobStatus = "Complete" AND errors array is empty
- ❌ jobStatus ∈ {"Failed", "Error", "Cancelled", "Canceled", "Aborted"} → defer to **Step 9.5 retry block** (do NOT exit yet — re-deploy the Data Kit, max **5** total attempts)
- ⏱️ Maximum 45 minutes elapsed (9 polls × 5 min — covers expected 30-45 min window)

**Status progression (single attempt):**
| Time | Check | Expected Status | Action |
|------|-------|----------------|--------|
| 5 min  | Check 1/9 | InProgress | Wait 5 min |
| 10 min | Check 2/9 | InProgress | Wait 5 min |
| 15 min | Check 3/9 | InProgress | Wait 5 min |
| 20 min | Check 4/9 | InProgress | Wait 5 min |
| 25 min | Check 5/9 | InProgress | Wait 5 min |
| 30 min | Check 6/9 | Complete or InProgress | Auto-proceed if Complete |
| 35 min | Check 7/9 | Complete (typical) | ✅ Auto-proceed to next skill |
| 40 min | Check 8/9 | Complete or InProgress | Auto-proceed if Complete |
| 45 min | Check 9/9 | Complete or Timeout | Final check — exit timeout if still InProgress |

**If after 45 minutes still not Complete (timeout):**
- ⚠️ Report: "Data Kit deployment did not finish within 45 min on this attempt"
- ⚠️ Current job status: {jobStatus}
- ⚠️ Job ID: {jobId}
- ⚠️ STOP and surface to user. Do NOT auto-extend, do NOT auto-retry on Timeout (only `Failed` triggers Step 9.5).

**If deployment terminal-fails (jobStatus ∈ {Failed, Error, Cancelled, Canceled, Aborted}):**
- 🔁 Hand off to **Step 9.5 retry block** — do NOT exit yet.
- Step 9.5 re-POSTs to `/ssot/data-kits/Data360RetailDIYDataKit?asyncMode=true` and re-polls on the same 5-min / 45-min cadence.
- Up to **5 total attempts** (1 initial + 4 retries) before giving up.
- Tiered backoff between retries: 30 s for attempts 1→2 and 2→3, then 60 s for attempts 3→4 and 4→5.
- **Fail-fast** for deterministic platform errors (`INSUFFICIENT_ACCESS`, `LICENSE_LIMIT_EXCEEDED`, `FEATURE_NOT_ENABLED`, `INVALID_TYPE`, `permission`, `not licensed`) — abort retries immediately.
- Only after **all 5 attempts fail** (or fail-fast triggers) does the skill stop and report the failure to the user — and even then, the installer chain MUST NOT auto-proceed to `/agentforce-data-library` or any other downstream skill.

**Polling implementation example — for reference only.** This single-script form must NOT be invoked directly; it exists to document the per-poll status logic. The active execution model is the chunked foreground loop in Step 9 (one Bash call per poll, sub-agent loops in its main loop). Background mode is FORBIDDEN here because sub-agents don't receive `<task-notification>`s.

```bash
#!/bin/bash
# Store credentials and job ID
ACCESS_TOKEN="..."
INSTANCE_URL="https://..."
JOB_ID="08PHu000027WW6b"

# Poll loop: every 5 min, max 9 polls = 45 min (covers 30-45 min expected window)
echo "✅ Starting deployment status polling (every 5 min, max 45 min — 9 polls)..."
for i in $(seq 1 9); do
  RESPONSE=$(curl -X GET \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    "${INSTANCE_URL}/services/data/v66.0/ssot/datakit-deployment-job/${JOB_ID}" \
    --silent 2>&1)

  # Parse jobStatus from response
  JOB_STATUS=$(echo "$RESPONSE" | grep -o '"jobStatus":"[^"]*"' | cut -d'"' -f4)

  echo "🔄 Check $i/9 (at minute $((i*5))): Job Status = ${JOB_STATUS}"

  if [ "$JOB_STATUS" = "Complete" ]; then
    echo "✅ Deployment complete! Auto-proceeding to next skill (agentforce-data-library)"
    exit 0
  fi

  # Match ALL terminal-failed states the Salesforce API may return.
  case "$JOB_STATUS" in
    Failed|Error|Cancelled|Canceled|Aborted)
      # Defer to Step 9.5 retry block — do NOT exit 1 here.
      # Exit 3 signals "retry-eligible failure" so the Step 9.5 wrapper re-POSTs the deploy.
      echo "❌ Deployment terminal-failed (jobStatus=$JOB_STATUS) — handing to Step 9.5 retry block."
      echo "   Response: $RESPONSE"
      exit 3
      ;;
  esac

  if [ $i -lt 9 ]; then
    echo "⏳ Waiting 5 minutes before next check..."
    sleep 300
  fi
done

echo "⚠️ Timeout after 45 minutes — deployment did not reach a terminal state on this attempt"
exit 2
```

**IMPORTANT:** 
- Use the CORRECT API endpoint: `/ssot/datakit-deployment-job/{jobId}`
- Do NOT use `/ssot/data-kits/{dataKitName}` endpoint - that returns Data Kit definition, not deployment status
- Use polling via API, NOT browser automation for status checking
- API polling is more reliable and doesn't require UI interaction

---

### Step 12 — Verify deployment completion

API polling in Step 11 confirms when status = "Installed". The skill automatically proceeds to next step (Agentforce Data Library) after deployment is 100% complete.

---

## Important Rules

**CRITICAL - API Request Body:**
- 🚨 **ALWAYS use empty JSON body `{}`** in the curl request
- 🚨 **NEVER include `dataKitName` in body** - causes JSON_PARSER_ERROR
- 🚨 **NEVER include `asyncMode` in body** - it's a query parameter only
- 🚨 **Data Kit name comes from URL path**, not request body
- The API requires a body but rejects any fields in it

**CRITICAL - No Approval Prompts:**
- ✅ **Pre-approve all commands** in `.claude/settings.json` to avoid approval prompts
- ✅ Commands to pre-approve: `bash:sf *`, `bash:curl *`
- ✅ Without pre-approval, user will be prompted 2 times during deployment
- ✅ `sf org display` - gets access token (1 prompt)
- ✅ `curl -X POST` - triggers API deployment (1 prompt)

**Workflow Optimization:**
- ✅ **Skip org authentication check** - Assume org already authenticated from datakit-metadata-deploy
- ✅ **Skip metadata deployment verification** - Trust that 612 components were just deployed
- ✅ **No redundant checks** - Trust previous steps completed successfully
- ✅ **Minimal commands** - Only 2 commands needed: `sf org display` + `curl`

**General Rules:**
- NEVER hardcode org names — always use provided org_alias parameter
- ALWAYS use asyncMode=true query parameter — synchronous mode times out
- ALWAYS use API version v66.0 or higher
- ALWAYS use `-d '{}'` for empty JSON body in curl command
- ALWAYS poll job status every **5 minutes** using the chunked foreground pattern: one Bash call per poll (each call sleeps 300 s + 1 curl ≈ 5 min, well under the 10-min foreground cap). The sub-agent loops in its OWN main loop by re-invoking the Bash command up to 9 times. Do NOT use `run_in_background: true` from a sub-agent — `<task-notification>`s go to the parent main loop, not the sub-agent, so the sub-agent exits before the deploy finishes (observed: jobId `08PHn00000lZMgb` reached Complete at minute 30 but sub-agent had been dead since minute 0). Do NOT pack the whole 45-min loop into one foreground call either — that hits Bash's 10-min cap on the first `sleep 300` and re-starts at check 1.
- ALWAYS auto-proceed to next skill when jobStatus = "Complete" (never ask user)
- Job ID starts with 08P — used for tracking deployment
- Deployment deploys 31 Data Kit components (different from 612 metadata components)
- **Estimated deployment time: 30-45 minutes** (poll every 5 min, max 9 polls = 45 min, per attempt; up to **5 attempts** via Step 9.5 retry on terminal failure — Failed, Error, Cancelled, Canceled, Aborted)
- Worst-case wall clock if all 5 attempts fail or hit terminal state: ~228 min (~3 hr 48 min)
- Do NOT provide verbose deployment details or timelines
- Do NOT ask user what to do - automatically monitor and proceed
- Do NOT request manual verification - keep monitoring automated
- ONLY report simple status: "Check X/9: Job Status = Running/Complete/Failed/Error"
- Re-authenticate org if token expired (only if API returns 401)
- Verify permissions if forbidden error occurs (only if API returns 403)

**🛑 MANDATORY HARD-STOP ON FAILURE (per user requirement):**

If the skill exits with **any non-zero code** (1 = FailedAllAttempts/ReDeployRejected/FailFastDeterministic, 2 = Timeout, 3 = retry-eligible failure that bubbled out unexpectedly), the installer chain MUST STOP. The orchestrator MUST NOT auto-invoke `/agentforce-data-library` (Step 5 of installer) or any later skill. The user must investigate, fix the root cause in the org, and explicitly re-run the agent or this skill before any later skill is allowed to execute.

This rule is bound in code (the `case "$FINAL_STATUS"` block at the end of Step 9.5 sets the exit code) AND in the orchestrator's per-skill execution gate (see `.claude/agents/data360-retail-installer/AGENT.md` → "Per-Skill Execution Gate"). Both layers enforce the same contract:

| Exit code | Outcome | Orchestrator action |
|---|---|---|
| `0` | Complete on attempt 1–5 | Auto-chain to `/agentforce-data-library` |
| `1` | FailedAllAttempts / ReDeployRejected / FailFastDeterministic | **STOP. Do NOT chain. Surface failure report to user. Wait for user instruction.** |
| `2` | Timeout — final attempt did not reach terminal state | **STOP. Do NOT chain. Surface jobId + status to user. Wait for user instruction.** |
| `3` | Retry-eligible failure that bubbled out (bug in retry wrapper) | **STOP. Surface to user.** |
| any other non-zero | Unknown failure | **STOP. Surface to user.** |

---

## Cleanup temp artifacts (MANDATORY before skill returns)

This skill creates several scratch files during a successful run. **All of them must be deleted before the skill returns.** See the agent's "Workspace Hygiene" rule for the global policy. Do this only on clean success (jobStatus = `Complete`); on any failure outcome (`FailedAllAttempts`, `ReDeployRejected`, `FailFastDeterministic`, `Timeout`, or any non-zero exit), leave the artifacts so the user can inspect — except for `org_creds.json`, which always gets deleted (token leakage risk).

**Files this skill creates (in repo root):**

```bash
# Step 5/6 — initial async POST kickoff response
rm -f datakit_api_kickoff.json

# Step 9 / 9.5 / 11 — polling loop output and per-poll status response
rm -f datakit_api_poll.log
rm -f datakit_api_status.json

# Step 2 — credential dump (SECURITY: contains an access token, MUST be deleted)
rm -f org_creds.json

# Polling scripts the agent generated on the fly (only if THIS run wrote them).
# NEVER delete repo-tracked files in scripts/ — only the per-run shims this
# skill produced (e.g. scripts/poll_datakit_api.sh).
rm -f scripts/poll_datakit_api.sh
```

**Verification (must show no leftovers):**

```bash
ls datakit_api_kickoff.json datakit_api_poll.log datakit_api_status.json \
   org_creds.json scripts/poll_datakit_api.sh 2>&1 | grep -v "cannot access"
```

**SECURITY note on `org_creds.json`:** the file contains a live OAuth access token. **Never** leave it on disk after the skill returns. Even on failure, delete it but preserve the polling logs (which don't contain secrets) for the user.

**Cleanup-on-failure policy:**
- ✅ ALWAYS delete `org_creds.json` (token leakage risk) — even on failure paths
- ❌ Do NOT delete `datakit_api_kickoff.json` / `datakit_api_poll.log` / `datakit_api_status.json` on failure — they contain the jobId and error payload the user needs
- ❌ Do NOT auto-delete the polling shim script on failure — the user may want to re-run it manually with the same jobId

**What NOT to delete:**
- `scripts/python_wrapper.sh`, `scripts/apex/*` — repo-tracked
- `.claude/` — never touched by this skill
