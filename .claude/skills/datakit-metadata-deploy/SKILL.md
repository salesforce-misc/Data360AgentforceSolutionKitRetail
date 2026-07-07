---
name: datakit-metadata-deploy
description: "Deploy Data360 Retail Data Kit metadata components (diy-datacloud) to a Salesforce org. Deploys 612 metadata components including DataPackageKitDefinitions, DataPackageKitObjects, dataSourceBundleDefinitions, DLO objects, and supporting metadata. Handles KeyQualifier field cleanup, managed DLO filtering, and deployment retries. Use when user wants to deploy retail data kit metadata, deploy diy-datacloud folder, or install data kit metadata components."
---

# datakit-metadata-deploy

## Purpose

Deploy the Data360 Retail Data Kit metadata components from the `diy-datacloud` folder to a target Salesforce org.

This skill deploys 612 metadata components using Salesforce CLI, including:
- DataPackageKitDefinitions
- DataPackageKitObjects
- dataSourceBundleDefinitions
- dataKitObjectTemplates
- DLO objects (__dlm)
- supporting metadata

The skill handles cleanup of problematic metadata and automatic retry on common errors.

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username

---

## Preconditions

Before running:

- Salesforce CLI must be installed
- Target org must be authenticated with Salesforce CLI
- User must be in repository directory containing `sfdx-project.json`
- `diy-datacloud/` folder must exist in repository
- Data Cloud must be enabled in target org (for Data Kit metadata)
- **IMPORTANT:** For uninterrupted execution, Salesforce CLI commands should be pre-approved in `.claude/settings.json`:
  ```json
  {
    "permissions": {
      "allow": [
        "bash:sf *",
        "bash:grep *",
        "bash:find *",
        "bash:sed *",
        "bash:cat *",
        "bash:echo *",
        "bash:pwd",
        "bash:test *"
      ]
    }
  }
  ```
  Without this, each command (sf, grep, sed, etc.) will prompt for approval, significantly slowing down the deployment process. The deployment involves multiple commands for validation, cleanup, deployment, and parsing results.

---

## Workflow

### Step 1 — Validate repository structure (Quick Check Only)

**CRITICAL: Minimal validation only - assume we're already in the correct directory from previous steps**

Quick validation:

```bash
pwd && test -f "sfdx-project.json" && echo "✓ sfdx-project.json found" && test -d "diy-datacloud" && echo "✓ diy-datacloud folder found"
```

**Why minimal validation?**
- If base-metadata-deploy already ran successfully, we're in the correct directory
- No need for full error handling and directory navigation
- Saves time and reduces approval prompts

If validation fails:
- stop execution
- report which file/folder is missing

---

### Step 2 — Skip org authentication verification

**CRITICAL: Skip org authentication check entirely**

**Reason:** If base-metadata-deploy skill already ran successfully, the org is authenticated and connected. No need to verify again - this wastes time and adds unnecessary approval prompts.

**Skip these commands:**
- ❌ `sf org list` (not needed)
- ❌ `sf org login web` (not needed)

**Proceed directly to Step 3.**

---

### Step 3 — Search for KeyQualifier fields

Search all metadata in diy-datacloud:

```bash
grep -rl "KeyQualifier" diy-datacloud/
```

KeyQualifier fields contain:

```xml
<usageTag>KeyQualifier</usageTag>
```

These are system-generated fields that cannot reliably deploy across orgs.

---

### Step 4 — Remove KeyQualifier fields if found

If grep returns matching files:

```bash
find diy-datacloud/ -type f -name "*.xml" -exec sed -i '/<KeyQualifier>/d' {} \;
```

This removes lines containing `<KeyQualifier>` from all XML files.

Report removed fields to user.

Salesforce regenerates KeyQualifier fields automatically in target org.

---

### Step 5 — Deploy metadata to target org

**CRITICAL: Deploy ONLY ONCE. Capture output on first execution.**

Deploy with 30-minute timeout and capture full output:

```bash
sf project deploy start -d diy-datacloud -o <org_alias> --wait 30 --json > /tmp/datakit_deploy_result.json 2>&1
```

**NEVER run deployment command multiple times to check status or capture output.**

If you need deployment details after execution:
```bash
cat /tmp/datakit_deploy_result.json
```

Flags:
- `-d diy-datacloud`: Deploy from diy-datacloud directory
- `-o <org_alias>`: Target org
- `--wait 30`: Wait up to 30 minutes
- `--json`: Return structured JSON output
- `> /tmp/datakit_deploy_result.json`: Save output to file for later parsing

Typical deployment time: 5-10 minutes

**Important:**
- ✅ Run deployment command ONCE
- ✅ Capture output to file
- ✅ Parse file for deployment details
- ❌ DO NOT re-run deployment to get status
- ❌ DO NOT run multiple times to capture different outputs

---

### Step 6 — Verify deployment status against the org FIRST (MANDATORY GATE)

**🚨 STRICT RULE — DO THIS FIRST, BEFORE ANYTHING ELSE 🚨**

**You MUST query the org's Tooling API to confirm the actual deployment status BEFORE:**
- ❌ Reading or trusting `/tmp/datakit_deploy_result.json`
- ❌ Reporting "deployment failed" to the user
- ❌ Entering Step 7 (failure handling)
- ❌ Running ANY destructive command (`rm -rf`, `find ... -delete`, folder removal)
- ❌ Asking the user to approve a fix
- ❌ Retrying the deployment

**The org is the ONLY source of truth. The local result file can be stale, partial, or from a prior run.**

**Mandatory verification command — run this immediately after Step 5:**

```bash
ACCESS_TOKEN=$(sf org display --target-org <org_alias> --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['accessToken'])")
INSTANCE_URL=$(sf org display --target-org <org_alias> --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")

curl -s -G -H "Authorization: Bearer $ACCESS_TOKEN" \
  --data-urlencode "q=SELECT Id, Status, NumberComponentsDeployed, NumberComponentsTotal, NumberComponentErrors, CreatedDate, CompletedDate FROM DeployRequest ORDER BY CreatedDate DESC LIMIT 1" \
  "$INSTANCE_URL/services/data/v62.0/tooling/query"
```

**Decision logic — use ONLY the org-returned values:**

| Org `Status` | `NumberComponentErrors` | `NumberComponentsDeployed` | Action |
|---|---|---|---|
| `Succeeded` | `0` | `612` | ✅ TRUE SUCCESS — skip Step 7 entirely, jump to Step 8 |
| `Succeeded` | `0` | `< 612` | ⚠️ Investigate missing components (warning, not failure) |
| `Failed` | `> 0` | any | ❌ TRUE FAILURE — only NOW may you enter Step 7 |
| `InProgress` / `Pending` | — | — | ⏳ Wait and re-poll. Do NOT trigger Step 7 |

**Hard rules — violating these is a defect:**
- ❌ NEVER declare deployment failed without first running the Tooling API query above
- ❌ NEVER run `rm -rf`, `find ... -delete`, or any destructive command unless the org returns `Status = Failed` with `NumberComponentErrors > 0`
- ❌ NEVER enter Step 7 based on `/tmp/datakit_deploy_result.json` content alone
- ❌ NEVER prompt the user to approve a fix until org-status is verified as failed
- ✅ If the org says `Succeeded` but the local file says failed, TRUST THE ORG, ignore the file, and proceed to Step 8

**If — and only if — the Tooling API confirms a real failure, then proceed to Step 7. Otherwise skip Step 7 entirely.**

---

### Step 7 — Handle deployment failures

**PRECONDITION (NON-NEGOTIABLE):** Step 6 (the Tooling API gate) must have returned `Status = Failed` with `NumberComponentErrors > 0` against the ORG. If you have not run that check, or if the org returned `Succeeded`, you MUST NOT enter this step. The local result file alone is NEVER sufficient grounds to enter Step 7.

**Step 7.1 — Read per-component error details from the local result file:**

The org-side `DeployRequest` query (Step 6) does not return per-component error messages — only counts. To classify the failure, read `componentFailures[]` from the local result file:

```bash
cat /tmp/datakit_deploy_result.json | python3 -c "
import json, sys
d = json.load(sys.stdin)
failures = d.get('result', {}).get('details', {}).get('componentFailures', [])
for f in failures[:20]:
    print(f\"{f.get('componentType','?')}: {f.get('fullName','?')} → {f.get('problem','?')}\")
print(f'... ({len(failures)} total failures)')"
```

**Step 7.2 — Classify the error and apply the matching fix:**

| Error Pattern | Cause | Fix |
|---|---|---|
| `ssot__*__dlm` entity not accessible | Managed DLO restriction | Remove DLO folders, retry |
| KeyQualifier field error | System-generated field | Remove KeyQualifier fields, retry |
| InvalidProjectWorkspaceError | Not in SFDX project | Navigate to repo root |
| Authentication failure | Org disconnected | Re-authenticate org |
| Missing Data Cloud | Feature not enabled | Enable Data Cloud first |

**Fix for managed DLO errors:**

```bash
# Remove problematic DLO folders automatically
find diy-datacloud/ -type d -name "*__dlm" -exec rm -rf {} \;

# Retry deployment ONCE with output capture
sf project deploy start -d diy-datacloud -o <org_alias> --wait 30 --json > /tmp/datakit_deploy_retry.json 2>&1
```

**Retry Rules:**
- Only retry ONCE after fixing the error
- Capture retry output to separate file: `/tmp/datakit_deploy_retry.json`
- Parse the retry file for results
- Do NOT retry multiple times — if second attempt fails, report error and stop

---

### Step 8 — Verify deployment success

On success, deployment should show:

```json
{
  "status": "Succeeded",
  "result": {
    "id": "0Afaj00000ZacKLCAZ",
    "status": "Succeeded",
    "numberComponentsDeployed": 612,
    "numberComponentsTotal": 612,
    "numberComponentErrors": 0
  }
}
```

Component count must be 612.

If count differs:
- investigate missing components
- check for deployment warnings
- report discrepancy to user

---

### Step 9 — Report deployment status

On success:

```text
✅ Metadata Deployment Successful!

Org: <org_alias>
Components Deployed: 612
Duration: 8 minutes
Deployment ID: 0Afaj00000ZacKLCAZ

Deployed Components:
  - DataPackageKitDefinition (1)
  - DataPackageKitObjects (99)
  - dataCalcInsightTemplates (5)
  - dataKitObjectDependencies (38)
  - dataKitObjectTemplates (41)
  - dataSourceBundleDefinitions (2)
  - dataSourceObjects (22)
  - dataSrcDataModelFieldMaps (319)
  - dataStreamTemplates (16)
  - DLO objects (56)
  - supporting metadata (13)
```

On failure:

```text
❌ Metadata Deployment Failed

Org: <org_alias>
Error: ssot__BillingAccountMasterReceipt__dlm entity not accessible
Deployment ID: 0Afaj00000ZacKLCAZ

Failed Components:
  - ssot__BillingAccountMasterReceipt__dlm

Suggested Fix:
1. Removing managed DLO folders...
2. Retrying deployment...
```

---

### Step 10 — Report Final Summary and Automatically Proceed

**CRITICAL: Trust deployment API result - no additional verification needed**

**Why skip SOQL verification?**
- Deployment API already confirmed: status="Succeeded"
- Component count validated: 612 deployed, 0 errors
- Deployment ID confirms successful completion
- SOQL queries for Data Kit metadata may not be immediately available
- Deployment API is authoritative source of truth

Report comprehensive summary:

```text
✅ Data Kit Metadata Deployment Complete!

Org: <org_alias>
Components Deployed: 612
Duration: <duration>
Deployment ID: <deployment_id>

═══════════════════════════════════════════════════

✅ Deployment Verified:
- Status: Succeeded
- Component Errors: 0
- All 612 components deployed successfully

═══════════════════════════════════════════════════

Next Step:
➡️ Automatically proceeding to /datakit-api-deploy
```

**CRITICAL: After reporting summary, AUTOMATICALLY invoke next skill:**

Use Skill tool to invoke: `/datakit-api-deploy <org_alias>`

**Do NOT:**
- ❌ Ask user to verify in Salesforce UI
- ❌ Run SOQL queries for verification
- ❌ Wait for user confirmation
- ❌ Stop execution

**Do:**
- ✅ Trust deployment API result (status + componentErrors)
- ✅ Report summary immediately
- ✅ Automatically proceed to next skill
- ✅ Maintain deployment momentum

---

## Important Rules

**🚨 CRITICAL - Deployment Status Verification (MANDATORY GATE):**
- 🚨 **STRICTLY check the org's DeployRequest status FIRST before treating any deployment as failed**
- 🚨 **NEVER trust `/tmp/datakit_deploy_result.json` alone — query the org via Tooling API (Step 6) every time**
- 🚨 **NEVER run destructive commands (`rm -rf`, `find ... -delete`, folder removal) without an org-verified `Status = Failed` AND `NumberComponentErrors > 0`**
- 🚨 **NEVER prompt the user to approve a fix unless the org-verified status is `Failed`**
- 🚨 **If org says `Succeeded` and local file says failed → TRUST THE ORG, ignore the file, proceed to Step 8**
- 🚨 **Step 7 (failure handling) is gated behind Step 6 (org status verification) — no exceptions**

**CRITICAL - Deployment Execution:**
- 🚨 **DEPLOY ONLY ONCE** - Run `sf project deploy start` command ONE TIME ONLY
- 🚨 **CAPTURE OUTPUT TO FILE** - Use `> /tmp/datakit_deploy_result.json 2>&1` to save results
- 🚨 **PARSE FILE FOR DETAILS** - Use `cat /tmp/datakit_deploy_result.json` to read results
- 🚨 **NEVER RE-RUN DEPLOYMENT** to check status or capture different output
- 🚨 **DO NOT RUN MULTIPLE TIMES** for any reason except retry after error fix

**CRITICAL - No Approval Prompts:**
- ✅ **Pre-approve all commands** in `.claude/settings.json` to avoid approval prompts
- ✅ Commands to pre-approve: `bash:sf *`, `bash:grep *`, `bash:find *`, `bash:sed *`, `bash:cat *`, `bash:echo *`, `bash:pwd`, `bash:test *`
- ✅ Without pre-approval, user will be prompted 10+ times during deployment
- ✅ This significantly slows down the process (from 2 minutes to 10+ minutes)

**Workflow Optimization:**
- ✅ **Skip org authentication check** - Assume org already authenticated from base-metadata-deploy
- ✅ **Minimal repository validation** - Quick check only, assume correct directory
- ✅ **No redundant checks** - Trust previous steps completed successfully

**General Rules:**
- NEVER hardcode org names — always use provided org_alias parameter
- ALWAYS use --json flag for parseable output
- ALWAYS check for KeyQualifier fields before deployment
- ALWAYS retry deployment after cleanup if initial deployment fails (but only ONCE per attempt)
- ALWAYS validate component count is 612 after deployment
- ALWAYS verify deployment with SOQL query (Step 10)
- ALWAYS automatically proceed to next skill (/datakit-api-deploy) after successful deployment
- Remove managed DLO folders only if deployment errors occur
- Timeout is 30 minutes — typical deployment takes 5-10 minutes (actual deployment ~18 seconds)
- Report both success and failure with structured output
- Provide deployment ID for tracking in Salesforce
- SOQL validation confirms deployment - never request manual UI verification
- If deployment shows "unchanged" for all components, they were already deployed previously

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If the org-side `DeployRequest` query (Step 6) reports `Status = Failed`, **do NOT clean up** — keep `/tmp/datakit_deploy_result.json` (and `/tmp/datakit_deploy_retry.json` if Step 7 ran) so the failure can be inspected.
- Fix the underlying issue, retry the deploy, then run cleanup once Step 6 confirms `Status = Succeeded`.

**Files this skill creates and must delete:**

```bash
rm -f /tmp/datakit_deploy_result.json
rm -f /tmp/datakit_deploy_retry.json
```

**Verification (must show no leftovers):**

```bash
ls /tmp/datakit_deploy_result.json /tmp/datakit_deploy_retry.json 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete the two files listed above. Do NOT delete any repo source.
- ✅ The `diy-datacloud/` folder and its contents are repo source — never touched by this cleanup.
- ❌ Skipping this step is not allowed once Step 6 confirms `Status = Succeeded`.
