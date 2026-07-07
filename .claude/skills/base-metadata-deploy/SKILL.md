---
name: base-metadata-deploy
description: Deploy base Retail Solution Kit metadata using Salesforce CLI. Clones repo if needed, deploys diy-base metadata, assigns permission sets, activates price books, imports sample data, and executes Apex scripts. CLI-only workflow with no browser automation.
---

# base-metadata-deploy

## Purpose

Deploy base metadata for the Data360 Retail Solution Kit using Salesforce CLI exclusively.

**Critical Constraints:**
- ✅ Use Salesforce CLI commands only
- ❌ No browser automation
- ❌ No Playwright tools
- ❌ No JavaScript file generation
- ✅ Windows PowerShell compatible commands

**Temporary File Policy (MANDATORY):**
Some steps require creating temporary files (SOQL queries, Apex scripts) to work around CLI limitations on Windows. These files MUST follow strict lifecycle rules:
- ✅ Create temp file ONLY when the step requires it (e.g. SOQL via --file flag for Windows compatibility)
- ✅ Use the file, parse output, extract values
- ✅ DELETE the file IMMEDIATELY after the step completes (`rm <filename>`)
- ✅ Use `/tmp/` paths when possible (auto-cleaned by OS) instead of repo root
- ❌ NEVER leave temporary SOQL/Apex/query files in the repo working tree
- ❌ NEVER skip cleanup, even on failure paths — wrap in try/finally semantics

This skill handles the complete base metadata deployment workflow including metadata deployment, permission set assignment, price book activation, and sample data import.

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

- Salesforce CLI must be installed
- Target org must be authenticated with Salesforce CLI
- Git must be installed (for cloning repository if needed)
- User must have System Administrator profile or equivalent permissions
- Windows PowerShell environment
- **IMPORTANT:** For uninterrupted execution, Salesforce CLI commands should be pre-approved in `.claude/settings.json`:
  ```json
  {
    "permissions": {
      "allow": [
        "bash:sf *"
      ]
    }
  }
  ```
  Without this, each `sf` command will prompt for approval, significantly slowing down deployment.

---

## Workflow

### Step 0 — Check Current Directory (Skip Repository Verification if Already in Repo)

**CRITICAL: Detect the repo by FINGERPRINT in the *current* working directory — never by folder name.**

The repository may live in any folder the user has open in VS Code (e.g. `Downloads/TestSkill`, `Data360AgentforceSolutionKitRetail`, a fork, a renamed clone, etc.). Do NOT match on the folder's name. Match on the presence of the repo's required files/folders inside the current working directory.

Check current directory and its fingerprint:

```bash
pwd
test -f "./sfdx-project.json" && test -d "./diy-base" && test -d "./diy-datacloud" && test -d "./scripts" && echo "REPO_OK" || echo "REPO_MISSING"
```

**If the fingerprint check prints `REPO_OK` (regardless of what `pwd` returns):**
- ✅ Report: "Repository detected in current working directory: $(pwd) — skipping repository verification"
- ✅ Skip Step 1 completely
- ✅ Proceed directly to Step 2 (Deploy Metadata)

**If the fingerprint check prints `REPO_MISSING`:**
- Proceed to Step 1 (the agent will clone INTO the current folder)

---

### Step 1 — Verify Repository Context

The Data360 installer agent (or the user) must have already ensured cwd is the repo root before this skill runs. Quick sanity check:

```bash
test -f sfdx-project.json && test -d diy-base
```

If either check fails, abort with: `ERROR: not in repo root. Re-invoke the agent so Step 0 can clone or detect the repo.`

Do **not** attempt to clone or `cd` from inside this skill — repo provisioning is handled centrally by the agent.

---

### Step 2 — Deploy Base Metadata (with 5-min polling gate)

**CRITICAL: Skip org authentication verification**

**Reason:** If feature-enablement skill already ran successfully, the org is authenticated and connected. No need to verify again - this wastes time and adds unnecessary checks.

**Proceed directly to deployment without checking org authentication.**

---

#### Step 2a — Kick off the deployment (asynchronous)

Start the deploy in **async mode** so the CLI returns immediately with a Deployment Id. We then poll status ourselves on a fixed 5-minute cadence. This is the only way to truthfully tell the user "still running" between checks — `--wait` would block the agent silently.

```bash
sf project deploy start \
  -d diy-base \
  --target-org <org_alias> \
  --async \
  --json > /tmp/diy_base_deploy_kickoff.json
```

Flags:
- `-d diy-base`: Deploy from diy-base directory (one bundled deployment — classes, objects, permsets, layouts, etc., all in one job)
- `--target-org <org_alias>`: Target org
- `--async`: Return immediately with the Deployment Id; do NOT block
- `--json`: Structured output

**Extract the Deployment Id:**

```bash
DEPLOY_ID=$(python3 -c "import json; print(json.load(open('/tmp/diy_base_deploy_kickoff.json'))['result']['id'])")
echo "Deployment Id: $DEPLOY_ID"
```

If `DEPLOY_ID` is empty or the kickoff JSON has `status != 0`, STOP and report the kickoff error verbatim. Do NOT enter the polling loop.

---

#### Step 2b — Polling gate: total 30–45 min window, re-check every 5 minutes (BLOCKING)

**Cadence contract:** the diy-base deployment is expected to take **30 to 45 minutes**. Poll the deployment status every **5 minutes** during that window (up to **9 status checks** at minutes 0, 5, 10, 15, 20, 25, 30, 35, 40). If the deployment is still not in a terminal state at minute 45, STOP and hand control back to the user. Do NOT exit the loop early before minute 30 unless the deployment has already reached a terminal state (`Succeeded` / `Failed` / `Canceled`) — never declare success on partial progress.

**HARD RULE — DO NOT PROCEED.** Until this gate prints `✅ Deployment Succeeded`, you MUST NOT:
- run Step 3 (SOQL verification)
- run any later step of this skill
- invoke any other skill in the installer chain
- run any "while we wait" check, probe, or sample command

The agent's only allowed action between polls is `sleep 300` followed by exactly **one** `sf project deploy report` call. No Connect REST API probes. No SOQL queries. No `ls`. No `cat`. The user wants a clean, predictable cadence.

```bash
# Cadence config — DO NOT change without user approval
POLL_INTERVAL_SECONDS=300        # 5 minutes between status checks
MIN_EXPECTED_MINUTES=30          # the deployment is expected to take 30–45 minutes
MAX_POLL_MINUTES=45              # hard ceiling — if still not terminal at 45 min, STOP and ask the user
ELAPSED=0

while : ; do
    # Re-check deployment status — exactly one call per cycle
    sf project deploy report \
        --job-id "$DEPLOY_ID" \
        --target-org <org_alias> \
        --json > /tmp/diy_base_deploy_status.json

    STATUS=$(python3 -c "import json; print(json.load(open('/tmp/diy_base_deploy_status.json'))['result']['status'])")
    DONE=$(python3 -c "import json; print(json.load(open('/tmp/diy_base_deploy_status.json'))['result'].get('done', False))")
    DEPLOYED=$(python3 -c "import json; print(json.load(open('/tmp/diy_base_deploy_status.json'))['result'].get('numberComponentsDeployed', 0))")
    TOTAL=$(python3 -c "import json; print(json.load(open('/tmp/diy_base_deploy_status.json'))['result'].get('numberComponentsTotal', 0))")
    ERRORS=$(python3 -c "import json; print(json.load(open('/tmp/diy_base_deploy_status.json'))['result'].get('numberComponentErrors', 0))")

    echo "[+${ELAPSED}m] status=$STATUS  done=$DONE  ${DEPLOYED}/${TOTAL}  errors=$ERRORS"

    # Terminal states ----------------------------------------------------
    if [ "$STATUS" = "Succeeded" ]; then
        echo "✅ Deployment Succeeded — proceeding to Step 3"
        break
    fi
    if [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Canceled" ]; then
        echo "❌ Deployment $STATUS — STOP. Reporting failure to user."
        # Print first 5 component failures
        python3 -c "
import json
d = json.load(open('/tmp/diy_base_deploy_status.json'))['result']
for f in (d.get('details', {}).get('componentFailures') or [])[:5]:
    print('  -', f.get('fullName'), '|', f.get('problem'))
"
        exit 1
    fi

    # Still in progress — wait and poll again
    if [ "$ELAPSED" -ge "$MAX_POLL_MINUTES" ]; then
        echo "⚠️ Deployment still running after ${MAX_POLL_MINUTES} minutes — STOP and ask user how to proceed"
        exit 2
    fi
    echo "   ↻ Still in progress. Sleeping ${POLL_INTERVAL_SECONDS}s before next check…"
    sleep "$POLL_INTERVAL_SECONDS"
    ELAPSED=$((ELAPSED + 5))
done
```

**What "done" means:**
- ✅ `result.status == "Succeeded"` AND `result.done == true` AND `numberComponentErrors == 0` → exit the loop, proceed to Step 3.
- ❌ `result.status` ∈ { `Failed`, `Canceled` } → **STOP IMMEDIATELY. DO NOT MOVE TO STEP 3, DO NOT MOVE TO ANY LATER STEP, DO NOT INVOKE THE NEXT SKILL IN THE INSTALLER CHAIN.** Surface the deploy id, the failed status, and the first 5 component failures, then hand control back to the user. The installer chain is broken until the user fixes the root cause and explicitly tells the agent to retry from this skill.
- ⏳ Anything else (`Pending`, `InProgress`, `Queued`) → sleep 5 minutes, re-poll. No other tool calls in between.

**Failure-stop rule (mandatory, applies even if other rules say "auto-chain"):**

```
IF deployment status is Failed OR Canceled
   OR numberComponentErrors > 0
   OR the loop hit MAX_POLL_MINUTES without reaching a terminal state
THEN
   STOP this skill (non-zero exit).
   DO NOT call /datakit-metadata-deploy.
   DO NOT call any other downstream skill.
   DO NOT auto-retry the deploy.
   Wait for the user to investigate and explicitly say "retry" before doing anything else.
```

This rule overrides the installer agent's "auto-chain on success" behavior — the chain only auto-advances on **clean** success of this gate.

**Cadence summary that the agent must print to the user on every cycle:**

```
[+0m]  status=Pending      0/612    errors=0   ↻ Still in progress. Sleeping 300s before next check…
[+5m]  status=InProgress   90/612   errors=0   ↻ Still in progress. Sleeping 300s before next check…
[+10m] status=InProgress   180/612  errors=0   ↻ Still in progress. Sleeping 300s before next check…
[+15m] status=InProgress   270/612  errors=0   ↻ Still in progress. Sleeping 300s before next check…
[+20m] status=InProgress   360/612  errors=0   ↻ Still in progress. Sleeping 300s before next check…
[+25m] status=InProgress   460/612  errors=0   ↻ Still in progress. Sleeping 300s before next check…
[+30m] status=InProgress   560/612  errors=0   ↻ Still in progress. Sleeping 300s before next check…
[+35m] status=Succeeded    612/612  errors=0   ✅ Deployment Succeeded — proceeding to Step 3
```

If the deployment is still `InProgress` at the **+45m** check, the loop hits `MAX_POLL_MINUTES` and exits with code 2 — the agent must STOP and surface the deploy id to the user so they can decide whether to keep waiting or investigate.

**Why this gate exists (do not skip):**
- Past runs jumped to Step 3 / Step 4 while the deploy was still mid-flight, then mis-reported the deployment as "stuck" because SOQL queries against not-yet-committed metadata returned nothing.
- The user explicitly asked for a 5-minute polling cadence with **no other commands running between polls**. That is a hard contract — honor it.
- The gate is the ONLY thing in this skill that may run while the deploy is in flight. Steps 3+ are gated.

Store `$DEPLOY_ID` for the final summary.

---

### Step 2.5 — Sweep stuck/orphan deployments before continuing (MANDATORY GATE)

**Purpose:** After the diy-base deploy reports `Succeeded`, the org may still contain other deployments stuck in `InProgress` / `Pending` / `Canceling` from prior runs (Storm/orgfarm/xDO QBrix bootstrap, earlier installer attempts, etc.). These can hold metadata locks and silently break later steps in the installer chain (especially `datakit-api-deploy`, which fails with `We couldn't retrieve available objects for <orgId>. Try again later.` when the platform thinks a deploy is still mid-flight).

**PRECONDITION (NON-NEGOTIABLE):**
- Step 2's polling gate must have already exited with `✅ Deployment Succeeded` (i.e. our diy-base `$DEPLOY_ID` is in a terminal `Succeeded` state with `numberComponentErrors == 0`).
- If Step 2 has not yet returned `Succeeded`, this step MUST NOT run. **Never sweep mid-deploy.** Cancelling a peer deploy while our own is in flight risks releasing a lock the platform was deliberately holding for our deploy.

**Hard rule (bound by user requirement):**
- ✅ Run AFTER our diy-base deploy is done.
- ✅ Only inspect deploys still in `InProgress` / `Pending` / `Queued` / `Canceling` at that moment.
- ✅ Only cancel a peer deploy if its component list is **clearly not related** to this installer (xDO QBrix bootstrap residue, leftover IndustriesUnifiedPromotions retries, etc.).
- ❌ DO NOT cancel anything that contains diy-base / diy-datacloud / diy-pd-pack components, or anything whose origin you can't classify with confidence.
- ❌ DO NOT proceed to Step 3 until this gate completes. The gate is mandatory even when the diy-base deploy itself is clean.

**Step 2.5a — Identify all non-terminal DeployRequests OTHER than the one we just ran.**

Important: this query runs ONLY after Step 2 returned `Succeeded`. The `Id != '${DEPLOY_ID}'` clause guarantees we will never touch our own diy-base deploy. If the query returns zero rows, **skip directly to Step 3** — there is nothing to sweep, no PATCH calls, no logs, no temp files written.

```bash
ACCESS_TOKEN=$(sf org display --target-org <org_alias> --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['accessToken'])")
INSTANCE_URL=$(sf org display --target-org <org_alias> --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")

# DEPLOY_ID is the diy-base deploy from Step 2 — never cancel that one
curl -s -G -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode "q=SELECT Id, Status, NumberComponentsTotal, NumberComponentsDeployed, NumberComponentErrors, CreatedDate FROM DeployRequest WHERE Status IN ('InProgress','Pending','Queued','Canceling') AND Id != '${DEPLOY_ID}' ORDER BY CreatedDate ASC" \
  "$INSTANCE_URL/services/data/v62.0/tooling/query" > /tmp/stuck_deploys.json
```

If `totalSize == 0`, no stuck deploys → skip to Step 3.

**Step 2.5b — Inspect each stuck deployment's component list and classify:**

For every stuck deploy, fetch the component detail and decide if it's "irrelevant to this installer" (cancel) or "potentially load-bearing" (surface to user, do NOT auto-cancel):

```bash
python3 -c "
import json
d = json.load(open('/tmp/stuck_deploys.json'))
for r in d['records']:
    print(r['Id'], r['Status'], r['CreatedDate'], 'components=' + str(r['NumberComponentsTotal']))
"
```

For each `STUCK_ID` in that list:

```bash
curl -s -X GET -H "Authorization: Bearer $ACCESS_TOKEN" \
  "${INSTANCE_URL}/services/data/v62.0/metadata/deployRequest/${STUCK_ID}?includeDetails=true" \
  > /tmp/stuck_${STUCK_ID}.json

python3 <<'PY'
import json, os
sid = os.environ['STUCK_ID']
d = json.load(open(f'/tmp/stuck_{sid}.json'))
det = d.get('deployResult', {}).get('details', {}) or {}
succ = det.get('componentSuccesses') or []
fail = det.get('componentFailures') or []
all_msgs = succ + fail
# Build the deploy fingerprint: distinct (componentType, fullName) pairs, excluding package.xml
fingerprint = sorted({(c.get('componentType','') or '?', c.get('fullName','') or '?')
                       for c in all_msgs
                       if (c.get('fullName') or '') != 'package.xml'})
print(f'--- {sid} ---')
for ct, fn in fingerprint:
    print(f'  {ct}: {fn}')

# Classification rules (extend conservatively — when unsure, surface to user)
IRRELEVANT_PATTERNS = (
    'xDO_Base_QBrix_Register',         # Storm/orgfarm xDO QBrix registry
    'QBrix_',                          # Any QBrix-* CustomMetadata row
    'DemoBrix_',                       # DemoBrix-* CustomMetadata row
    'xDO_',                            # Any xDO-prefixed CustomMetadata
    'IndustriesUnifiedPromotionsSettings',  # already enabled by feature-enablement
)
def is_irrelevant(ct, fn):
    if ct == 'CustomMetadata' and any(p in fn for p in IRRELEVANT_PATTERNS):
        return True
    return False

irrelevant = all(is_irrelevant(ct, fn) for ct, fn in fingerprint) and len(fingerprint) > 0
print(f'  → irrelevant_to_installer = {irrelevant}')
PY
```

**Classification rules (be conservative — false positives are worse than leaving a deploy alone):**

A peer deploy is eligible for auto-cancel ONLY when **every component** in its `componentSuccesses` + `componentFailures` list (excluding `package.xml`) matches one of the IRRELEVANT_PATTERNS. If even ONE component falls outside the irrelevant list, the deploy is treated as load-bearing → surface to user, do not cancel.

| Pattern | Origin | Action |
|---|---|---|
| `CustomMetadata: xDO_Base_QBrix_Register.QBrix_*` / `DemoBrix_*` / `xDO_*` | Storm/orgfarm xDO QBrix bootstrap residue | **Cancel (only if ALL components match)** |
| `IndustriesUnifiedPromotionsSettings: IndustriesUnifiedPromotions` (when feature-enablement already passed) | leftover from feature-enablement retry | **Cancel (only if ALL components match)** |
| Anything matching `diy-base` / `diy-datacloud` / `diy-pd-pack` content (CustomField on Account/Contact/Order/Product2/Promotion, ApexClass `DIYStoreUtil`, PermissionSet `DIYRetailBasePS`, DLO/DLM components) | Could be a **prior installer run** that wasn't cleaned up | **DO NOT cancel.** Surface to user. Wait for user instruction. |
| Anything else (managed package install, customer-owned customizations, mixed bundle) | Unknown / load-bearing | **DO NOT cancel.** Surface to user. Wait for user instruction. |

If the deploy has zero components in its details (extremely rare, usually means a fresh `Pending` row that the platform hasn't expanded yet), treat it as **unknown → DO NOT cancel** and wait one more minute, then re-classify. If still empty, surface to user.

**Step 2.5c — Cancel only the irrelevant ones via Tooling/Metadata API:**

```bash
# For each STUCK_ID classified as irrelevant:
curl -s -X PATCH \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  "${INSTANCE_URL}/services/data/v62.0/metadata/deployRequest/${STUCK_ID}" \
  -d '{"deployResult":{"status":"Canceling"}}' \
  -w "\nHTTP %{http_code}\n"
```

The platform accepts the request with HTTP 202 and moves the deploy to `Canceling`. Many of these deploys are actually no-ops (component already exists in the org), so the `Canceling` row may sit for a while before Salesforce GC reaps it — that's fine. The platform-level lock the deploy was holding is released as soon as the cancel is accepted.

**Step 2.5d — Verify the cancel was accepted (do NOT wait for terminal `Canceled`):**

```bash
sleep 15
for STUCK_ID in $CANCELED_IDS; do
  curl -s -G -H "Authorization: Bearer $ACCESS_TOKEN" \
    --data-urlencode "q=SELECT Status FROM DeployRequest WHERE Id = '${STUCK_ID}'" \
    "$INSTANCE_URL/services/data/v62.0/tooling/query"
done
```

Acceptable terminal-or-transitional statuses after the cancel: `Canceling`, `Canceled`, `Failed`. Any of those means the lock is released. **Do NOT block on `Canceled` — the platform may take hours to GC the row, but locks are released at `Canceling`.**

**Step 2.5e — If any stuck deploy was classified as "load-bearing":**

```
🛑 STOP — Step 2.5 found a stuck deploy that is NOT clearly irrelevant.

DeployRequest: <stuck_id>
Status:        InProgress
CreatedDate:   <date>
Components:    <n>

Sample components:
  - <componentType>: <fullName>
  - ...

This deploy may be from a prior installer attempt. Auto-cancelling it could
discard work the user wants to keep. Surfacing to the user.

Next step: ask the user whether to cancel this DeployRequest before proceeding.
DO NOT auto-proceed to Step 3.
```

**Step 2.5f — Cleanup temp files (always, even on failure):**

```bash
rm -f /tmp/stuck_deploys.json /tmp/stuck_*.json
```

**Why this gate exists (DO NOT skip):**
- Observed failure: a prior Storm-org bootstrap left DeployRequest `0Afg70000066ukeCAA` (a `CustomMetadata: xDO_Base_QBrix_Register.QBrix_1_xDO_Trialforce` write) stuck in `InProgress` for ~33 hours. While that row sat in flight, the `datakit-api-deploy` POST returned `jobStatus=Error` with the message `We couldn't retrieve available objects for <orgId>. Try again later.` — because the platform thought a deploy was still mid-flight and refused to compute the org's full object catalog for the Data Kit installer.
- Cancelling the orphan released the lock and let `datakit-api-deploy` succeed.
- This gate prevents that failure mode from recurring on every install.

---

### Step 3 — Verify Deployment Success with SOQL Query

**CRITICAL: Cross-check deployment by verifying key metadata exists**

After deployment completes, verify that critical metadata was actually deployed:

```bash
# Create SOQL query file
Write tool:
file_path: verify_deployment.soql
content: SELECT COUNT() FROM PermissionSet WHERE Name = 'DIYRetailBasePS'

# Execute verification query
sf data query --file verify_deployment.soql --json --target-org <org_alias>
```

**Parse verification result:**

```bash
if result.result.totalSize == 1:
    Report: "✓ Deployment verified: DIYRetailBasePS permission set exists"
else:
    Report ERROR: "Deployment verification failed: DIYRetailBasePS not found"
    STOP EXECUTION

# Cleanup query file
rm verify_deployment.soql
```

**Why this validation?**
- Deployment API may report "Success" but metadata might not be accessible
- Verifies DIYStoreUtil class and permission sets are deployed and queryable
- Catches silent failures before proceeding to data import

Store deployment ID for final summary.

---

### Step 4 — Assign Base Permission Set

**Assign DIYRetailBasePS permission set:**

```bash
sf org assign permset -n DIYRetailBasePS --target-org <org_alias> --json
```

Flags:
- `-n DIYRetailBasePS`: Permission set API name
- `--target-org <org_alias>`: Target org
- `--json`: Structured output

**Parse result:**

Check `result.successes` array for successful assignment.

Expected output:
```json
{
  "result": {
    "successes": [
      {
        "name": "DIYRetailBasePS",
        "value": "Assigned"
      }
    ]
  }
}
```

**Handle assignment errors:**

If permission set not found:
- Error: "Permission set 'DIYRetailBasePS' does not exist"
- Check if metadata deployment completed successfully
- Suggest redeploying metadata
- Stop execution

If assignment fails:
- Report error message
- Check user has permission to assign permission sets
- Stop execution

**Success criteria:**
- Permission set assigned successfully
- User now has DIYRetailBasePS permissions

---

### Step 5 — Activate Standard Price Book

**Execute Apex script to activate Standard Price Book:**

```bash
sf apex run -f scripts/apex/activatePricebook.apex --target-org <org_alias>
```

Flags:
- `-f scripts/apex/activatePricebook.apex`: Apex script file path
- `--target-org <org_alias>`: Target org

**Parse output:**

Check for success message in output.

Typical success output:
```
Compiled successfully.
Executed successfully.
```

**Handle execution errors:**

If Apex compilation fails:
- Report compilation error
- Check if activatePricebook.apex file exists
- Stop execution

If Apex execution fails:
- Report runtime error
- Check org has Standard Price Book
- Stop execution

**Success criteria:**
- Apex compiled successfully
- Apex executed successfully
- Standard Price Book activated

---

### Step 6 — Load Sample Data via the Strict Idempotent Loader

**Replaces the legacy Step 6 (SOQL Pricebook query), Step 7 (`sed`-patch `pricebookentries.json`), Step 7.5 (`@ref` resolver), and Step 8 (`sf data tree import --plan`).** All four were unreliable when the org already had any of the sample data — duplicate-key cascades, all-or-nothing failure, and the `data/.resolved/` scratch dir all caused real installer breakage.

The replacement is one Python script that:

1. Reads each `data/*.json` file in dependency order (same order as `data/plan.json`).
2. Resolves `@refs` and the literal `STANDARD_PRICEBOOK_ID` placeholder in memory at runtime — the data file on disk is never modified.
3. For every record, looks up the org by **natural key** (see table below). If found, uses the existing Id. If not found, inserts via Composite REST API (200/batch).
4. After every tier, asserts `len(file_rows) == matched_count + inserted_count`. Any unaccounted-for row halts the script — dependent tiers do NOT run, so children with broken FKs never get attempted.

#### Natural keys (per object)

| File | sObject | Natural key | Existence-query filter |
|---|---|---|---|
| `accounts.json` | Account (Person) | `(FirstName, LastName, PersonEmail)` — case-insensitive | `WHERE isDIYRecord__pc = true` |
| `products.json` | Product2 | `StockKeepingUnit` | (none — SKU is org-unique) |
| `pricebooks.json` | Pricebook2 (custom) | `Name` | `WHERE IsStandard = false` |
| `pricebookentries.json` | PricebookEntry | `(Pricebook2Id, Product2Id)` composite | (none) |
| `assets.json` | Asset | `SerialNumber` | (none) |
| `assetwarranties.json` | AssetWarranty | `(AssetId, StartDate)` composite | (none) |
| `promotions.json` | Promotion | `PromotionCode` | (none) |
| `promotionproducts.json` | PromotionProduct | `(PromotionId, ProductId)` composite | (none) |
| `orders.json` | Order | `(AccountId, Name)` composite | (none) |
| `orderitems.json` | OrderItem | `(OrderId, Product2Id)` composite | (none) |
| `serviceappointments.json` | ServiceAppointment | `(ParentRecordId, Subject)` composite | (none) |

**Adding a new plan file?** You MUST add its natural-key entry to `scripts/load_diy_base_data.py` (`TIERS` constant). The script refuses to silently process unknown sObjects — that's how silent inserts of duplicates would creep back in.

#### Duplicate handling (do NOT delete existing data)

If the org already has 4 Person Accounts for `m.smith@example.com` (e.g. from prior installer runs):

- The script picks the **oldest by `CreatedDate`** as the canonical match.
- The other 3 dups stay in the org untouched. Any prior Orders/Assets/etc. that point to them remain attached to them.
- All downstream `@accountRef1` references in this run resolve to the canonical Id (the oldest).

This is the documented policy. The script never issues a DELETE.

#### Strict completeness — no silent skips

After each tier, the script asserts every file row is now mapped to an org Id. If any row is unaccounted for:

```
❌ COMPLETENESS FAILURE for Account:
   File rows:        8
   Matched in org:   5
   Newly inserted:   2
   Missing/failed:   1

   - refId=accountRef3  keys={'FirstName':'Caleb','LastName':'George','PersonEmail':'caleb.george@mail.com'}
       REQUIRED_FIELD_MISSING: PersonGenderIdentity is required for Person Account

🛑 STOPPING — completeness check failed at this tier.
   Per design, dependent tiers will not run because their @refs would be broken.
   Fix the underlying issue (validation rule, missing field, etc.) and re-run.
```

The user fixes the root cause (e.g. permission set missing FLS, validation rule blocking the row) and re-runs. The script is idempotent, so the second run is safe — already-loaded rows simply match.

#### Run the loader

```bash
python3 scripts/load_diy_base_data.py --target-org <org_alias>
```

That single command replaces everything Step 6, 7, 7.5, and 8 used to do.

**Exit codes:**
- `0` — every tier passed; all file rows are present in the org
- `1` — a tier failed completeness; re-run after fixing the root cause
- `2` — hard error (auth failed, file missing, etc.)

**What the script does NOT do:**
- ❌ Modify any file in `data/` (the JSON files stay pristine; placeholder substitution is in-memory only)
- ❌ Delete any existing org row (your standing rule)
- ❌ Skip any file row (strict completeness halts on first gap)
- ❌ Generate a `data/.resolved/` directory (the legacy resolver scratch path is dead)
- ❌ Touch the Standard Pricebook (only resolves it as a reference — `activatePricebook.apex` in Step 5 already activated it)

**Cleanup:** the script writes only one transient file per Composite POST (`_curl_body_<pid>.json`), and deletes it before returning. The `finally` block in `main()` also sweeps any leftover `_curl_body_*.json` in cwd. No persistent state. No tokens written to disk (all auth happens via the live `sf` CLI session).

---

### Step 9 — Adjust Order Effective Date

**Execute Apex script to update Order effective dates:**

```bash
sf apex run -f scripts/apex/updateEffectiveDatesonOrder.apex --target-org <org_alias> --json
```

Flags:
- `-f scripts/apex/updateEffectiveDatesonOrder.apex`: Apex script
- `--target-org <org_alias>`: Target org
- `--json`: Structured output

**What this script does (DIYStoreUtil.updateEffectiveDate):**
1. `syncContactIdsForRelatedRecords()` - Syncs Contact IDs on Orders, Assets, ServiceAppointments from Person Account
2. Updates Order EffectiveDate, EndDate
3. Sets Order Status to 'Activated'
4. Calls `updateOrderStatusToActivated()` internally
5. Calls `assignCopyFieldPermission()` @future method (updates 22 Customer 360 field permissions)

**Parse output:**

Check for success message:
```
Compiled successfully.
Executed successfully.
```

**ENHANCED VALIDATION - Verify Apex execution with SOQL:**

```bash
# Parse Apex execution result
if result.status != 0 or !result.result.success:
    Report ERROR: "updateEffectiveDatesonOrder failed"
    Report: "Apex logs: {result.result.logs}"
    STOP EXECUTION

Report: "✓ updateEffectiveDatesonOrder executed successfully"

# CRITICAL: Verify Orders were actually updated
Write tool:
file_path: verify_activated_orders.soql
content: SELECT COUNT() FROM Order WHERE BillToContact.isDIYRecord__c = true AND Status = 'Activated' AND EffectiveDate != null

activatedQuery = sf data query --file verify_activated_orders.soql --json --target-org <org_alias>
activatedOrders = activatedQuery.result.totalSize

Write tool:
file_path: verify_contact_sync.soql  
content: SELECT COUNT() FROM Order WHERE CreatedDate = TODAY AND BillToContactId != null

contactSyncQuery = sf data query --file verify_contact_sync.soql --json --target-org <org_alias>
ordersWithContacts = contactSyncQuery.result.totalSize

Report: "  - Activated Orders: {activatedOrders}"
Report: "  - Orders with BillToContact: {ordersWithContacts}"

if activatedOrders == 0:
    Report ERROR: "No orders were activated - script execution may have failed silently"
    Report: "Check if Orders meet criteria: BillToContact.isDIYRecord__c = true"
    STOP EXECUTION

Report: "✓ Order activation verified"

# Cleanup verification files
rm verify_activated_orders.soql verify_contact_sync.soql
```

**Why this validation?**
- **DML operations must succeed:** Script performs multiple update operations on Orders, Assets, ServiceAppointments
- **Silent failures:** Apex may compile/execute but fail to update records due to validation rules, triggers, or field-level security
- **Data integrity:** Without activated Orders, downstream processing and Data Cloud sync will fail

**Handle execution errors:**

If compilation fails:
- Report compilation error
- Check if file exists
- Stop execution

If execution fails:
- Report runtime error
- Check if Orders exist in org
- Check if Orders have OrderItems (required for activation)
- Stop execution

**Success criteria:**
- Apex compiled successfully
- Apex executed successfully
- SOQL verification confirms Orders activated with EffectiveDate
- Contact sync completed (BillToContactId populated)

**Note on @future method:**
- `assignCopyFieldPermission()` executes asynchronously
- Validation for this will occur in Step 11 after allowing time for completion

---

### Step 10 — Activate Orders

**Execute Apex script to activate Order status:**

```bash
sf apex run -f scripts/apex/activateOrderStatus.apex --target-org <org_alias> --json
```

Flags:
- `-f scripts/apex/activateOrderStatus.apex`: Apex script
- `--target-org <org_alias>`: Target org
- `--json`: Structured output

**What this script does (DIYStoreUtil.updateOrderStatusToActivated):**
1. Queries Draft Orders with:
   - `BillToContact.isDIYRecord__c = true`
   - `Status = 'Draft'`
   - `Name IN ('HVAC Maintenance', 'HVAC Installation')`
2. Filters for Orders that have OrderItems (required for activation)
3. Updates Status to 'Activated'

**Parse output:**

Check for success message:
```
Compiled successfully.
Executed successfully.
```

**ENHANCED VALIDATION - Verify with pre/post SOQL queries:**

```bash
# Query BEFORE execution
Write tool:
file_path: count_draft_hvac.soql
content: SELECT COUNT() FROM Order WHERE BillToContact.isDIYRecord__c = true AND Status = 'Draft' AND Name IN ('HVAC Maintenance','HVAC Installation')

beforeQuery = sf data query --file count_draft_hvac.soql --json --target-org <org_alias>
draftOrdersBefore = beforeQuery.result.totalSize

Report: "  Draft HVAC Orders Before: {draftOrdersBefore}"

# Execute Apex script
if result.status != 0 or !result.result.success:
    Report ERROR: "activateOrderStatus failed"
    Report: "Apex logs: {result.result.logs}"
    STOP EXECUTION

Report: "✓ activateOrderStatus executed successfully"

# Query AFTER execution  
afterQuery = sf data query --file count_draft_hvac.soql --json --target-org <org_alias>
draftOrdersAfter = afterQuery.result.totalSize

Write tool:
file_path: count_activated_hvac.soql
content: SELECT COUNT() FROM Order WHERE BillToContact.isDIYRecord__c = true AND Status = 'Activated' AND Name IN ('HVAC Maintenance','HVAC Installation')

activatedQuery = sf data query --file count_activated_hvac.soql --json --target-org <org_alias>
activatedTargetOrders = activatedQuery.result.totalSize

Report: "  - Draft HVAC Orders Before: {draftOrdersBefore}"
Report: "  - Draft HVAC Orders After: {draftOrdersAfter}"
Report: "  - Activated HVAC Orders: {activatedTargetOrders}"

# Validation logic
if draftOrdersBefore > 0 and draftOrdersAfter == draftOrdersBefore:
    Report WARNING: "No draft orders were activated"
    Report: "Verify orders meet criteria:"
    Report: "  1. Must have OrderItems (script skips orders without line items)"
    Report: "  2. Status must be 'Draft'"
    Report: "  3. Name must be 'HVAC Maintenance' or 'HVAC Installation'"
    # Don't stop - this may be expected if orders were already activated in Step 9

Report: "✓ Order activation verified"

# Cleanup verification files
rm count_draft_hvac.soql count_activated_hvac.soql
```

**Why this validation?**
- **Targeted activation:** Script only activates specific HVAC orders, not all orders
- **Prerequisite check:** Orders without OrderItems will be skipped (script logs this)
- **May be redundant:** Step 9's `updateEffectiveDate()` already calls `updateOrderStatusToActivated()` internally
- **Verifies intent:** Confirms HVAC Maintenance/Installation orders are in Activated status

**Handle execution errors:**

If compilation fails:
- Report compilation error
- Check if file exists
- Stop execution

If execution fails:
- Report runtime error
- Check if Orders exist
- Check if Orders have OrderItems (required for activation)
- Check Order activation rules
- Stop execution

**Success criteria:**
- Apex compiled successfully
- Apex executed successfully
- Target HVAC Orders verified in Activated status
- Pre/post query comparison shows state change (or explains why not)

---

### Step 11 — Verify @future Method Completion (assignCopyFieldPermission)

**CRITICAL: Validate async permission assignment completed**

The `updateEffectiveDatesonOrder.apex` script in Step 9 triggered a @future method `assignCopyFieldPermission()` that:
- Updates FieldPermissions for 22 Customer 360 fields on Contact object
- Updates ObjectPermissions for Account and Contact objects
- Runs asynchronously in background

**Wait for @future method completion:**

```bash
# @future methods typically complete in 5-15 seconds
# Add buffer for safety
Report: "Waiting for @future method (assignCopyFieldPermission) to complete..."
sleep 15
```

**Verify field permissions were created/updated:**

```bash
Write tool:
file_path: verify_field_perms.soql
content: SELECT COUNT() FROM FieldPermissions WHERE Parent.Label = 'Customer 360 Data Platform Integration' AND Field LIKE 'Contact.Customer_%'

fieldPermQuery = sf data query --file verify_field_perms.soql --json --target-org <org_alias>
fieldPermCount = fieldPermQuery.result.totalSize

Report: "  - Customer 360 Field Permissions: {fieldPermCount}"

if fieldPermCount < 22:
    Report WARNING: "Expected 22 Customer 360 field permissions, found {fieldPermCount}"
    Report: "The @future method may still be executing - waiting additional 30 seconds..."
    sleep 30
    # Re-query and report final count
    fieldPermQuery = sf data query --file verify_field_perms.soql --json --target-org <org_alias>
    fieldPermCount = fieldPermQuery.result.totalSize
    Report: "  - Final Field Permissions Count: {fieldPermCount}"
else:
    Report: "✓ @future method completed: All 22 field permissions verified"

# Cleanup verification file
rm verify_field_perms.soql
```

**Expected fields (22 total):**
- Average_Order_Value__c
- Average_Purchase_Value__c
- Customer_Since__c
- Lifetime_Value__c
- Customer_BrandAffinity__c
- Customer_OwnershipStatus__c
- Customer_PurchaseFrequency__c
- Customer_MaritalStatus__c
- Customer_IsSingleFamilyHome__c
- Customer_Seasonality__c
- Customer_FamilySizes__c
- Customer_ResidenceType__c
- Customer_Unified_Individual_Id__c
- Customer_ProjectFrequency__c
- Customer_StorePreference__c
- Customer_IncomeLevel__c
- Customer_GarageSize__c
- Customer_Type__c
- Customer_IsWorkshopSpacePresent__c
- Customer_VehicleType__c
- Customer_ServicePreference__c
- Customer_SkillLevel__c

**Why this validation?**
- **Data Cloud sync dependency:** These Customer 360 fields are used for Data Cloud identity resolution and segmentation
- **Silent failure risk:** @future methods don't propagate exceptions to caller
- **Critical for Copy Fields:** Data Kit's copy field sync in later steps depends on these permissions

**Success criteria:**
- 22 FieldPermissions exist for Customer 360 fields
- Permissions grant Read and Edit access
- Associated with 'Customer 360 Data Platform Integration' permission set

**If validation fails:**
- Warn user but don't stop execution
- Note that Copy Field sync may fail in later steps and will be auto-retried there

---

### Step 12 — Generate Final Summary

Report comprehensive deployment summary:

```text
✅ Base Metadata Deployment Complete!

Target Org: <org_alias>
Repository Path: <current working directory>

═══════════════════════════════════════════════════

📦 Metadata Deployment:
✅ Status: Succeeded
✅ Components Deployed: <count>
✅ Deployment ID: <deployment_id>
✅ Duration: <duration> minutes

═══════════════════════════════════════════════════

🔐 Permission Set Assignment:
✅ DIYRetailBasePS assigned successfully

═══════════════════════════════════════════════════

💰 Price Book Configuration:
✅ Standard Price Book activated
✅ Standard Price Book Id: <pricebook_id>
✅ Price Book Entries updated

═══════════════════════════════════════════════════

📊 Sample Data Import:
✅ Status: Completed
✅ Records Imported: <record_count>

Imported Objects:
  • Products
  • Price Book Entries
  • Accounts
  • Contacts
  • Orders
  • Order Items
  • [other objects from plan.json]

═══════════════════════════════════════════════════

⚙️ Apex Script Execution:
✅ activatePricebook.apex - Success
✅ updateEffectiveDatesonOrder.apex - Success
✅ activateOrderStatus.apex - Success

═══════════════════════════════════════════════════

✅ Base Metadata Deployment Successful!

Next Steps:
1. Verify sample data in Salesforce UI
2. Check Orders are activated
3. Verify Price Book Entries exist
4. Proceed with Data Kit deployment if needed
```

---

## Error Handling

### Repository Errors

**Repository not found:**
```text
❌ Repository Error

Error: cwd is not the Data360 repo root (sfdx-project.json missing)

Suggested Fix:
1. Re-invoke the data360-retail-installer agent — its Step 0 will clone
   the repo (public or internal mirror) automatically.
2. Or, clone manually INTO the folder VS Code currently has open
   (do NOT cd into a subfolder — the installer expects the repo
   contents to live directly in the current working directory):
     # From the folder VS Code has open:
     git init
     git remote add origin <repo-url-the-user-provides>
     git fetch origin --depth=1
     git checkout -f -B main origin/main   # or whatever the default branch is
   then re-run the installer.
```

**Missing directories:**
```text
❌ Repository Structure Error

Error: Required directory missing
  Missing: diy-base

Suggested Fix:
1. Verify repository is complete (the clone may have been interrupted)
2. Delete the partial clone and re-invoke the data360-retail-installer
   agent — Step 0 will re-clone cleanly.
```

---

### Authentication Errors

**Org not authenticated:**
```text
❌ Authentication Error

Error: Org '<org_alias>' not found in authenticated orgs

Suggested Fix:
1. Authenticate with org:
   sf org login web --alias <org_alias>
2. Verify org alias is correct
3. Retry deployment
```

**Authentication expired:**
```text
❌ Authentication Expired

Error: Org session expired for '<org_alias>'

Suggested Fix:
1. Re-authenticate:
   sf org login web --alias <org_alias>
2. Retry deployment
```

---

### Deployment Errors

**Metadata deployment failed:**
```text
❌ Metadata Deployment Failed

Org: <org_alias>
Deployment ID: <deployment_id>

Failed Components (first 5):
1. <component_type>.<component_name>: <error_message>
2. <component_type>.<component_name>: <error_message>
3. ...

Suggested Fix:
1. Check deployment status in Setup → Deployment Status
2. Review full error details with deployment ID
3. Fix component errors and retry
```

**Deployment timeout:**
```text
❌ Deployment Timeout

Error: Deployment exceeded 15-minute timeout

Deployment ID: <deployment_id>

Suggested Fix:
1. Check deployment status in Salesforce UI
2. Increase timeout if needed
3. Check org limits (API usage, storage)
4. Retry with: sf project deploy start -d diy-base --target-org <org_alias> --wait 30
```

---

### Permission Set Errors

**Permission set not found:**
```text
❌ Permission Set Assignment Failed

Error: Permission set 'DIYRetailBasePS' not found

Possible Causes:
- Metadata deployment incomplete
- Permission set not in diy-base metadata
- Different permission set name

Suggested Fix:
1. Verify metadata deployment completed successfully
2. Check if DIYRetailBasePS exists in org:
   sf data query -q "SELECT Id, Name FROM PermissionSet WHERE Name = 'DIYRetailBasePS'" --target-org <org_alias>
3. Retry metadata deployment if needed
```

**Assignment permission denied:**
```text
❌ Permission Set Assignment Failed

Error: Insufficient permissions to assign permission sets

Suggested Fix:
1. Verify user has 'Manage Profiles and Permission Sets' permission
2. Assign System Administrator profile
3. Retry assignment
```

---

### Price Book Errors

**Price Book activation failed:**
```text
❌ Price Book Activation Failed

Error: Apex execution failed in activatePricebook.apex

Apex Error: [error message]

Suggested Fix:
1. Check if Standard Price Book exists:
   sf data query -q "SELECT Id, Name, IsStandard FROM Pricebook2 WHERE IsStandard = true" --target-org <org_alias>
2. Review Apex script for errors
3. Retry the apex script automatically
```

**Price Book query returned no results:**
```text
❌ Standard Price Book Not Found

Error: Query returned 0 records for active Standard Price Book

Possible Causes:
- activatePricebook.apex failed silently
- Standard Price Book deleted
- Org configuration issue

Suggested Fix:
1. Check Standard Price Book status:
   sf data query -q "SELECT Id, Name, IsStandard, IsActive FROM Pricebook2 WHERE IsStandard = true" --target-org <org_alias>
2. Auto-retry Step 5 (activatePricebook.apex)
```

---

### Data Import Errors

**Data load failed (loader exit code 1):**
```text
❌ Sample Data Load Failed

The loader (scripts/load_diy_base_data.py) exited 1 — completeness check failed
for one of the tiers. Per the strict-completeness policy, dependent tiers were
NOT attempted, so child rows with broken FKs never got inserted.

The loader's stdout shows exactly which file row failed and the SF error.
Example:
  ❌ COMPLETENESS FAILURE for Account:
       refId=accountRef3 keys={'FirstName':'Caleb','LastName':'George','PersonEmail':'caleb.george@mail.com'}
       REQUIRED_FIELD_MISSING: PersonGenderIdentity is required for Person Account

Suggested Fix:
1. Read the loader's per-row error message — it's the SF API's verbatim response
2. Address the root cause:
   - Validation rule blocking the insert? Disable / amend.
   - Required field missing? Update data/<file>.json to include it.
   - FLS / permset issue? Fix the assignment.
3. Re-run the loader. It is idempotent — already-loaded rows match by natural key
   and won't be re-inserted:
     python3 scripts/load_diy_base_data.py --target-org <org_alias>
```

**Loader exited 0 but a tier reported zero net inserts (informational):**
This is normal and expected when the org already has all the sample data from
a prior run. The loader matched every file row to an existing org row, inserted
nothing, and reports `matched=N, inserted=0` per tier. No action needed.

---

### Apex Execution Errors

**Apex compilation failed:**
```text
❌ Apex Execution Failed

Script: <script_name>.apex
Error: Compilation failed

Apex Error:
<compilation_error_message>

Suggested Fix:
1. Check if script file exists
2. Review script syntax
3. Check org API version compatibility
4. Fix errors and retry
```

**Apex runtime error:**
```text
❌ Apex Execution Failed

Script: <script_name>.apex
Error: Runtime exception

Apex Error:
<runtime_error_message>

Suggested Fix:
1. Check if required data exists (Orders, Price Books, etc.)
2. Review error message for root cause
3. Auto-retry the apex script after data validation
```

---

## Important Rules

### Absolute Requirements

- ✅ ALWAYS use Salesforce CLI commands only
- ✅ ALWAYS verify org authentication before starting
- ✅ ALWAYS stop execution on errors (do not proceed)
- ✅ ALWAYS report clear error messages with suggested fixes
- ✅ ALWAYS provide deployment IDs for troubleshooting
- ✅ ALWAYS ask for org_alias if not provided
- ✅ ALWAYS use Windows PowerShell-compatible commands for file operations
- ✅ ALWAYS validate each step before proceeding to next

### Absolute Prohibitions

- ❌ NEVER use browser automation
- ❌ NEVER use Playwright tools
- ❌ NEVER generate JavaScript files
- ❌ NEVER skip error handling
- ❌ NEVER proceed after a failed step
- ❌ NEVER hardcode org names

---

## Step Execution Order

**CRITICAL: Steps must execute in this exact order:**

```
0. Check Current Directory (if already in repo, skip Step 1)
   ↓
1. Verify/Clone Repository (SKIP if cwd fingerprint already matches the repo — folder name is irrelevant)
   ↓
2. Deploy Metadata (diy-base) - Skip org authentication check
   ↓ VALIDATION: Parse JSON, verify status="Succeeded", componentErrors=0
   ↓
2.5 Sweep stuck/orphan deployments (NEW, MANDATORY GATE)
    ↓ Identify all non-terminal DeployRequests in the org other than $DEPLOY_ID
    ↓ Inspect each one's component list, classify irrelevant vs load-bearing
    ↓ Auto-cancel irrelevant deploys (xDO QBrix bootstrap, leftover IndustriesUnifiedPromotionsSettings, etc.)
    ↓ STOP and surface to user if any stuck deploy looks load-bearing (diy-* components, unknown patterns)
    ↓
3. Verify Deployment (NEW) - SOQL query confirms DIYRetailBasePS exists
   ↓
4. Assign Permission Set (DIYRetailBasePS)
   ↓
5. Activate Standard Price Book (activatePricebook.apex)
   ↓
6. Load Sample Data (scripts/load_diy_base_data.py)
   ↓ Replaces legacy Steps 6, 7, 7.5, 8.
   ↓ Resolves Standard Pricebook Id at runtime.
   ↓ For each tier: SOQL by natural key → match-or-insert via Composite REST.
   ↓ Strict completeness: STOP on first tier with any unaccounted-for row.
   ↓ Never deletes existing org rows. Picks oldest CreatedDate on dup match.
   ↓
9. Update Order Effective Dates (updateEffectiveDatesonOrder.apex)
   ↓ VALIDATION: SOQL confirms Orders activated, BillToContactId populated
   ↓ TRIGGERS @future method: assignCopyFieldPermission (22 field permissions)
   ↓
10. Activate Orders (activateOrderStatus.apex)
    ↓ VALIDATION: Pre/post SOQL queries verify HVAC orders activated
    ↓
11. Verify @future Method Completion (NEW)
    ↓ Wait 15 seconds, verify 22 Customer 360 field permissions exist
    ↓
12. Generate Summary Report
```

**Key Enhancements (NEW in this version):**
- ✅ **Step 2 Validation:** Parse JSON deployment result, verify component count and errors
- ✅ **Step 2.5 NEW (MANDATORY):** Sweep the org for stuck/orphan DeployRequests after `Succeeded`. Auto-cancel deploys whose components are clearly irrelevant to this installer (xDO QBrix bootstrap residue, stray feature-enablement retries). STOP and surface to user when a stuck deploy could be load-bearing (any diy-* component or unknown pattern). Prevents `datakit-api-deploy` from failing with `We couldn't retrieve available objects for <orgId>. Try again later.` due to platform locks held by orphan deploys.
- ✅ **Step 3 NEW:** Cross-check deployment with SOQL query for critical metadata
- ✅ **Step 6 Validation:** Strict completeness check inside the loader — `len(file_rows) == matched + inserted` per tier; halts on first gap
- ✅ **Step 9 Validation:** SOQL verification confirms Orders activated and Contact sync completed
- ✅ **Step 10 Validation:** Pre/post SOQL queries track HVAC order activation
- ✅ **Step 11 NEW:** Validate @future method completion with retry logic for async operations
- ✅ All SF CLI commands use `--json` flag for structured, parseable output
- ✅ Comprehensive error handling stops execution on critical failures
- ✅ Data integrity validated before Apex scripts execute (prevents cryptic DML errors)

**Original Optimizations (retained):**
- ✅ Step 0 added: Check if already in repository
- ✅ Step 1: Skip entirely if already in repo directory
- ✅ Step 2: Skip org authentication verification (trust feature-enablement)
- ✅ Step 6: Use `--file` flag instead of `-q` to avoid Windows path issues

---

## Dependencies

### Required Tools

- Salesforce CLI (`sf` command)
- Git (for cloning repository)
- Windows PowerShell (for file replacement)
- Bash or Git Bash (for running commands)

### Required Permissions

User must have:
- System Administrator profile OR
- Customize Application permission
- Manage Profiles and Permission Sets permission
- Modify All Data permission
- Author Apex permission

### Required Org Features

- Standard Price Book must exist
- Orders must be enabled
- Products must be enabled
- Price Books must be enabled

---

## Success Criteria

Deployment is successful when ALL of the following are verified:

### Repository & Metadata (Steps 0-3)
✅ Current directory verified (already in repo) OR repository cloned/navigated to
✅ Metadata deployed successfully - JSON confirms status="Succeeded", componentErrors=0
✅ **NEW:** Deployment verified via SOQL - DIYRetailBasePS permission set exists
✅ Permission set assigned successfully

### Price Book Configuration (Step 5)
✅ Standard Price Book activated via `activatePricebook.apex`
ℹ️ Standard Pricebook Id resolution and `STANDARD_PRICEBOOK_ID` substitution
   now happen in-memory inside the loader (Step 6) — no `query_pricebook.soql`
   temp file, no `sed` in-place patch of `data/pricebookentries.json`.

### Data Load & Validation (Step 6)
✅ Loader (`scripts/load_diy_base_data.py`) exited 0 — every tier passed
   its strict completeness assertion: `len(file_rows) == matched + inserted`
✅ For each plan file, every row is now mapped to an org Id (either matched
   by natural key, or freshly inserted via Composite REST API)
✅ Loader output shows per-tier breakdown (matched / inserted / failures)
✅ No org rows were deleted (loader policy)
✅ When dups exist in the org, the oldest by `CreatedDate` was picked as
   the canonical match — newer dups remain in place, untouched

### Apex Execution & Validation (Steps 9-10)
✅ updateEffectiveDatesonOrder.apex executed successfully
✅ **NEW:** SOQL verification confirms Orders activated:
  - ✅ Orders with BillToContact.isDIYRecord__c = true have Status = 'Activated'
  - ✅ Order EffectiveDate and EndDate populated
  - ✅ BillToContactId populated (Contact sync completed)
✅ activateOrderStatus.apex executed successfully
✅ **NEW:** Pre/post SOQL verification confirms HVAC orders activated:
  - ✅ Target orders (HVAC Maintenance, HVAC Installation) in Activated status
  - ✅ Draft order count decreased (or explained if already activated)

### Async Operations (Step 11)
✅ **NEW:** @future method completion verified:
  - ✅ Waited 15 seconds for async execution
  - ✅ 22 Customer 360 field permissions exist on Contact object
  - ✅ Permissions associated with 'Customer 360 Data Platform Integration' permission set

### Final Reporting (Step 12)
✅ Final summary generated with:
  - ✅ Deployment ID and component count
  - ✅ Data import record count
  - ✅ Order activation statistics
  - ✅ Field permission validation results
  - ✅ All validation checkpoints passed

**Note:** Org authentication validation is skipped to avoid redundancy and speed up deployment.

**Enhanced Reliability:**
- **Zero trust on CLI output:** All critical operations validated with SOQL queries
- **Early failure detection:** Stops execution immediately when validation fails
- **Data integrity guaranteed:** Apex scripts only execute after verifying required data exists
- **Async operation tracking:** Validates @future method completion before reporting success

---

## Integration with Other Skills

This skill is part of the complete Retail Solution Kit deployment workflow:

```
Deployment Sequence:

1. /feature-enablement <org_alias>
   └─ Enable Data Cloud, Einstein, Agentforce, Person Accounts

2. /base-metadata-deploy <org_alias>          ← THIS SKILL
   └─ Deploy base app metadata and sample data

3. /datakit-metadata-deploy <org_alias>
   └─ Deploy Data Kit metadata (612 components)

4. /datakit-api-deploy <org_alias>
   └─ Trigger Data Kit installation
```

**This skill should run AFTER feature enablement and BEFORE Data Kit deployment.**

---

## Example Usage

### Example 1: User provides org (after feature-enablement)

**User:** "Deploy base metadata to MyRetailOrg"

**Skill:**
1. Checks current directory (already in repo, skips verification)
2. Deploys diy-base metadata (skips org auth check)
3. Assigns DIYRetailBasePS
4. Activates Standard Price Book
5. Creates query_pricebook.soql file
6. Queries Standard Price Book Id using --file flag
7. Replaces Pricebook2Id in data file
8. Imports sample data
9. Updates Order dates
10. Activates Orders
11. Reports summary

**Time saved:** ~10-15 seconds by skipping redundant checks

---

### Example 2: User doesn't provide org

**User:** "Deploy base metadata"

**Skill:** "Which org would you like to deploy to? Please provide the org alias or username."

**User:** "StormRetailOrg1"

**Skill:** [Proceeds with deployment workflow]

---

### Example 3: Repository doesn't exist

**User:** "Deploy base metadata to MyOrg"

**Skill:**
```text
📦 Verifying repository context...
❌ cwd is not the Data360 repo root.

This skill expects the data360-retail-installer agent to have run Step 0
(repo provisioning) first. Re-invoke the agent to clone or detect the repo,
then it will chain into this skill automatically.
```

---

## Notes

- This skill deploys BASE metadata only (diy-base folder)
- For Data Kit metadata, use `/datakit-metadata-deploy` skill separately
- Sample data import may take 2-5 minutes depending on data volume
- Apex scripts may take 10-30 seconds each
- Total deployment time: 5-10 minutes typically
- All operations are CLI-based with no UI automation

---

## Cleanup temp artifacts (MANDATORY before skill returns)

This skill creates the following scratch files/folders during a successful run. **All of them must be deleted before the skill returns** — see the agent's "Workspace Hygiene" rule for the global policy. Do this only on clean success; on failure, leave artifacts so the user can inspect.

**Files this skill creates (in repo root unless noted):**

```bash
# Step 2 — async deploy kickoff + polling
rm -f /tmp/diy_base_deploy_kickoff.json
rm -f /tmp/diy_base_deploy_status.json

# Step 3 — SOQL verification of DIYRetailBasePS
rm -f verify_deployment.soql

# Step 6 — strict idempotent loader
# The loader writes one transient `_curl_body_<pid>.json` per Composite POST
# and deletes it inside http_post(). The script's finally-block also sweeps
# any leftover `_curl_body_*.json` in cwd before exiting. Belt-and-suspenders:
rm -f _curl_body_*.json
```

**Files this skill explicitly does NOT create anymore (legacy artifacts that the loader replaces):**
- ❌ `query_pricebook.soql` — the loader resolves Standard Pricebook in-process
- ❌ `data/pricebookentries.json.bak` — the loader never modifies the data file
- ❌ `data/.resolved/` — no scratch directory
- ❌ `scripts/resolve_refs.py` — the broken pre-resolver is gone
- ❌ `tree_import_log.txt` / `tree_import_result.json` — `sf data tree import` is no longer used

**Verification (must show no leftovers):**

```bash
ls verify_deployment.soql _curl_body_*.json 2>&1 | grep -v "cannot access"
# All four legacy artifacts must be absent too:
ls query_pricebook.soql data/pricebookentries.json.bak \
   tree_import_log.txt tree_import_result.json 2>&1 | grep -v "cannot access"
ls -d data/.resolved 2>&1 | grep -v "cannot access"
```

**What NOT to delete:**
- `data/plan.json`, `data/*.json` — repo-tracked sample-data files (the loader reads them in place; never modifies them)
- `scripts/load_diy_base_data.py` — repo-tracked, this is the loader itself
- `scripts/apex/*.apex`, `scripts/python_wrapper.sh` — repo-tracked

**Cleanup-on-failure policy (do NOT clean up on these):**
- ❌ Deploy returned `Failed` / `Canceled`
- ❌ Polling loop hit the 45-min ceiling
- ❌ SOQL verification (Step 3) didn't find `DIYRetailBasePS`
- ❌ Loader exited non-zero (Step 6) — leave any debug output in place

In all those cases, leave the JSON dumps and logs in place so the user can read them.
