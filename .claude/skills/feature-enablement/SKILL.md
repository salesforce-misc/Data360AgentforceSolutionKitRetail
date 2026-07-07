---
name: feature-enablement
description: Automate Salesforce org feature enablement using Metadata API for Promotion Attribute, Data Cloud, Einstein, Agentforce, and Person Account. Uses Playwright MCP only for the Data Cloud Architect permission set step.
---

# feature-enablement

## Purpose

Automate Salesforce org feature enablement with the **fewest possible Metadata API round-trips** and **zero user-facing manual remediation prompts**.

- **Metadata API path (consolidated, 5 of 5 settings):** Promotion Attribute, Data Cloud, Einstein, Agentforce, Person Account → **ONE combined retrieve** + **ONE combined deploy** of only the settings that need flipping.
- **Playwright MCP path (1 task, ALWAYS Playwright):** Toggle the "default" data space in the Data Cloud Architect (`force.GenieAdmin`) permission set. The toggle is not exposed via Metadata API, Tooling API, Connect REST, or any other public Salesforce API.

**No manual remediation. Ever.** The skill never tells the user "open this URL in your browser and click X". Either the skill performs the action, or it logs that the action wasn't possible and continues to the next step / skill. The only hard stops are when the Metadata API itself rejects work (Step 1 retrieve fails, Step 3 deploy fails) — those are real failures the user must resolve before the rest of the install can run.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT use Playwright for the 4 Metadata API steps
- ❌ Do NOT make per-setting retrieves or per-setting deploys
- ❌ Do NOT verify Data Cloud enablement with an extra Metadata API retrieve — Step 3.5's `/ssot/data-spaces` REST probe is the only verification, and is intentional (the Step 3 `Succeeded` status only confirms acceptance, not that async lakehouse provisioning landed)
- ❌ Do NOT ask the user to manually click anything
- ❌ Do NOT print "Manual Step Required" / "Please open this URL" / "Once you've completed this step, let me know" anywhere
- ✅ Use SF CLI + Metadata API for the 5 settings (one retrieve, one deploy)
- ✅ Use MCP Playwright tools ONLY for the permission set step (Step 4)
- ✅ Person Account is IRREVERSIBLE — must NEVER appear in the deploy package if the retrieve already showed it as enabled
- ✅ Step 4 always closes the browser before returning, whether it succeeded, gracefully skipped, or errored

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username
- `tasks` (optional): Comma-separated list of tasks to run. If omitted, runs all tasks.
  - Valid values: `metadata` (covers all 5 Settings types in one shot), `permission-set`
  - Example: `metadata,permission-set`
  - Legacy aliases still accepted: `promotions`, `data-cloud`, `einstein`, `agentforce`, `person-account` → all map to `metadata`

---

## Preconditions

- **Caller has already run `sf org login web --alias <org_alias>` — this skill does NOT authenticate.** It will fail-fast in Step 0 if the cached session is missing.
- User has System Administrator profile or equivalent permissions
- For the `permission-set` step only: MCP Playwright tools must be available

---

## Workflow

**Step Execution Order — strictly linear:**
```
Step 0:   Verify SF CLI authentication                          [ STOP if no token ]
   ↓
Step 1:   ONE combined retrieve of all 5 Settings types         [ STOP if retrieve fails ]   ~1-2 min
   ↓
Step 2:   Local XML parse → build "needs flipping" list         [ 0 API calls ]
   ↓
Step 3:   ONE combined deploy (only if list non-empty)          [ STOP if deploy fails ]   ~10-30 s
   ↓
Step 3.5: Data Cloud provisioning verification                  [ Only if CustomerDataPlatform was flipped; bounded probe + 1 re-deploy; NEVER STOPs the skill ]   ~0-2.5 min
   ↓
Step 4:   Data Cloud Architect Permission Set → Playwright MCP  [ Graceful skip if "default" row not found; never STOPs the skill ]   ~30-60 s
   ↓
Step 5:   Cleanup + report                                      [ Always runs ]
```

**Data Cloud provisioning verification — where and why.** Step 3's `Succeeded` status means Salesforce accepted the `CustomerDataPlatform` flag, NOT that the lakehouse and `default` data space are queryable. That async provisioning is what **Step 3.5** verifies — and re-deploys once if it silently stalled. Step 4 then assumes provisioning is either done or known-degraded; its refresh logic only addresses the Lightning/Aura render race, not provisioning.

**One bounded recovery per failure mode, no loops.** Step 3.5 has at most ONE re-deploy (with bounded probe windows). Step 4 has at most ONE page refresh. Neither retries beyond that, neither prompts the user, neither STOPs the skill. The only hard stops are Step 0 / 1 / 3 (Metadata API rejections the user must resolve).

---

### Step 0 — Verify cached org session (NO login)

The org is authenticated **once by the calling agent** before this skill runs. This skill must NOT call `sf org login web`.

```bash
sf org display --target-org <org_alias> --json
```

- Exit code 0 and JSON contains `result.accessToken` → session is valid, proceed to Step 1.
- Command fails or no token returned → **STOP** the skill and report: `"Org session not authenticated. Caller must run: sf org login web --alias <org_alias> before invoking feature-enablement."` Do not attempt login here.

---

### Step 1 — Combined retrieve of all 5 Settings types (ONE call)

This single retrieve captures the live state of every setting in one Metadata API round-trip.

```bash
mkdir -p /tmp/feat-check/force-app
cat > /tmp/feat-check/sfdx-project.json <<'EOF'
{
  "packageDirectories": [{"path": "force-app", "default": true}],
  "namespace": "",
  "sfdcLoginUrl": "https://login.salesforce.com",
  "sourceApiVersion": "64.0"
}
EOF
cat > /tmp/feat-check/package.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>IndustriesUnifiedPromotions</members>
        <members>CustomerDataPlatform</members>
        <members>EinsteinGpt</members>
        <members>AgentPlatform</members>
        <members>Account</members>
        <name>Settings</name>
    </types>
    <version>64.0</version>
</Package>
EOF

cd /tmp/feat-check && sf project retrieve start \
  --target-org <org_alias> \
  --manifest /tmp/feat-check/package.xml \
  --output-dir /tmp/feat-check/retrieved \
  --api-version 64.0 \
  --json > /tmp/feat-check/retrieve.json 2>&1
```

**Expected output files (all 5 must be present):**
- `/tmp/feat-check/retrieved/settings/IndustriesUnifiedPromotions.settings-meta.xml`
- `/tmp/feat-check/retrieved/settings/CustomerDataPlatform.settings-meta.xml`
- `/tmp/feat-check/retrieved/settings/EinsteinGpt.settings-meta.xml`
- `/tmp/feat-check/retrieved/settings/AgentPlatform.settings-meta.xml`
- `/tmp/feat-check/retrieved/settings/Account.settings-meta.xml`

**Single API version v64.0 everywhere** — Agentforce requires v64+, the other 4 are backward-compatible at v64.

**Failure behaviour:** If the retrieve returns `status: Failed`, or any of the 5 expected XML files is missing → **STOP** the skill. Report the verbatim `result.messages[]` and `result.files[].error` content. Nothing is deployed when retrieve fails.

---

### Step 2 — Local XML parse → build the "needs flipping" list (0 API calls)

For each setting, **add it to `NEEDS_FLIP` only if the retrieve XML did NOT show it at its desired state.**

```bash
NEEDS_FLIP=()

# 1. Promotion Attribute — both flags must be true
PROMO_FILE=/tmp/feat-check/retrieved/settings/IndustriesUnifiedPromotions.settings-meta.xml
if grep -q "<enableUnifiedPromotions>true</enableUnifiedPromotions>" "$PROMO_FILE" \
   && grep -q "<enableGlobalPromotionsProductCatalogManagement>true</enableGlobalPromotionsProductCatalogManagement>" "$PROMO_FILE"; then
    echo "✅ Promotion Attribute already enabled — skipping"
else
    NEEDS_FLIP+=("IndustriesUnifiedPromotions")
fi

# 2. Data Cloud
CDP_FILE=/tmp/feat-check/retrieved/settings/CustomerDataPlatform.settings-meta.xml
if grep -q "<enableCustomerDataPlatform>true</enableCustomerDataPlatform>" "$CDP_FILE"; then
    echo "✅ Data Cloud already enabled — skipping"
else
    NEEDS_FLIP+=("CustomerDataPlatform")
fi

# 3. Einstein
EIN_FILE=/tmp/feat-check/retrieved/settings/EinsteinGpt.settings-meta.xml
if grep -q "<enableEinsteinGptPlatform>true</enableEinsteinGptPlatform>" "$EIN_FILE"; then
    echo "✅ Einstein already enabled — skipping"
else
    NEEDS_FLIP+=("EinsteinGpt")
fi

# 4. Agentforce
AP_FILE=/tmp/feat-check/retrieved/settings/AgentPlatform.settings-meta.xml
if grep -q "<enableAgentPlatform>true</enableAgentPlatform>" "$AP_FILE"; then
    echo "✅ Agentforce already enabled — skipping"
else
    NEEDS_FLIP+=("AgentPlatform")
fi

# 5. Person Account — IRREVERSIBLE, strictest check
PA_FILE=/tmp/feat-check/retrieved/settings/Account.settings-meta.xml
if grep -q "<enableAccountTeams>true</enableAccountTeams>" "$PA_FILE"; then
    echo "✅ Person Account already enabled — OMITTED from deploy (irreversible safety)"
else
    NEEDS_FLIP+=("Account")
fi
```

**The "skip if already enabled" rule:**

| Setting | XML check | If passes (already enabled) | If fails (not yet enabled) |
|---|---|---|---|
| `IndustriesUnifiedPromotions` | both `enableUnifiedPromotions=true` AND `enableGlobalPromotionsProductCatalogManagement=true` | Omit from deploy | Add to `NEEDS_FLIP` |
| `CustomerDataPlatform` | `enableCustomerDataPlatform=true` | Omit | Add to `NEEDS_FLIP` |
| `EinsteinGpt` | `enableEinsteinGptPlatform=true` | Omit | Add to `NEEDS_FLIP` |
| `AgentPlatform` | `enableAgentPlatform=true` | Omit | Add to `NEEDS_FLIP` |
| `Account` (Person Account) | `enableAccountTeams=true` | **Omit (irreversible)** | Add to `NEEDS_FLIP` |

If `NEEDS_FLIP` is empty after parsing → log `✅ All 5 settings already at desired state — no deploy needed` and **skip Step 3**, jump straight to Step 4.

---

### Step 3 — Combined deploy of only settings that need flipping (ONE call)

Build a single deploy zip containing **only the settings in `NEEDS_FLIP`**. Settings that were already enabled never appear in the deploy package.

```bash
mkdir -p /tmp/feat-deploy/settings

# Build dynamic package.xml from NEEDS_FLIP
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<Package xmlns="http://soap.sforce.com/2006/04/metadata">'
  echo '    <types>'
  for s in "${NEEDS_FLIP[@]}"; do echo "        <members>$s</members>"; done
  echo '        <name>Settings</name>'
  echo '    </types>'
  echo '    <version>64.0</version>'
  echo '</Package>'
} > /tmp/feat-deploy/package.xml

# Write only the .settings files we need to flip
for s in "${NEEDS_FLIP[@]}"; do
  case "$s" in
    IndustriesUnifiedPromotions)
      cat > /tmp/feat-deploy/settings/IndustriesUnifiedPromotions.settings <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<IndustriesUnifiedPromotionsSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableUnifiedPromotions>true</enableUnifiedPromotions>
    <enableGlobalPromotionsProductCatalogManagement>true</enableGlobalPromotionsProductCatalogManagement>
</IndustriesUnifiedPromotionsSettings>
EOF
      ;;
    CustomerDataPlatform)
      cat > /tmp/feat-deploy/settings/CustomerDataPlatform.settings <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CustomerDataPlatformSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableCustomerDataPlatform>true</enableCustomerDataPlatform>
</CustomerDataPlatformSettings>
EOF
      ;;
    EinsteinGpt)
      cat > /tmp/feat-deploy/settings/EinsteinGpt.settings <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<EinsteinGptSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableEinsteinGptPlatform>true</enableEinsteinGptPlatform>
</EinsteinGptSettings>
EOF
      ;;
    AgentPlatform)
      cat > /tmp/feat-deploy/settings/AgentPlatform.settings <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<AgentPlatformSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableAgentPlatform>true</enableAgentPlatform>
</AgentPlatformSettings>
EOF
      ;;
    Account)
      cat > /tmp/feat-deploy/settings/Account.settings <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<AccountSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <personAccountsEnabled>true</personAccountsEnabled>
</AccountSettings>
EOF
      ;;
  esac
done

# Single combined deploy
sf project deploy start \
  --target-org <org_alias> \
  --metadata-dir /tmp/feat-deploy \
  --api-version 64.0 \
  --json > /tmp/feat-deploy-result.json 2>&1
```

**Inspect deploy result:** parse `/tmp/feat-deploy-result.json` for `result.status`. Classify each setting by `result.files[].state`:

- `state == "Changed"` → newly enabled (real flip)
- `state == "Unchanged"` → already at desired state (no-op deploy, harmless)
- `state == "Failed"` → deploy failed for this setting

**Failure behaviour:** If the deploy returns `status: Failed`, Salesforce's default `rollbackOnError: true` rolls back the entire zip. **STOP** the skill. Report the verbatim error and the list of settings that were rolled back.

**Data Cloud provisioning verification happens in Step 3.5, not here.** Step 3 only confirms that Salesforce accepted the `CustomerDataPlatform` setting (`status: Succeeded`). The async lakehouse provisioning that makes the `default` data space queryable is verified by **Step 3.5** — which probes `/ssot/data-spaces` and triggers ONE re-deploy if provisioning silently stalled. We do NOT run an extra Metadata API `retrieve` here; the cheap REST probe in Step 3.5 is the source of truth for "Data Cloud is actually queryable now."

**Validated empirically:** on `storm.46e42ea62d8cc6@salesforce.com`, a 4-setting combined deploy (`IndustriesUnifiedPromotions` + `CustomerDataPlatform` + `EinsteinGpt` + `AgentPlatform`, with `Account` correctly omitted) returned `status: Succeeded`, all four `state: Changed`, deploy id `0AfHp00003ogWz3KAE`, in ~13 seconds.

---

### Step 3.5 — Post-deploy Data Cloud provisioning verification (only when CustomerDataPlatform was flipped)

**Why this step exists:** Step 3's `Succeeded` status means Salesforce **accepted** the `CustomerDataPlatform` flag; it does NOT mean Data Cloud's lakehouse and `default` data space are fully provisioned and queryable. Provisioning is async — it can complete in 5–60 seconds, occasionally up to 2 minutes. When it stalls or fails silently, Step 4 hits a blank UI not because of a Lightning render race but because there's no provisioning to surface. The refresh in Step 4 cannot fix that.

This step closes that gap by probing the public Data Cloud REST surface and, if needed, re-deploying the same `CustomerDataPlatform` settings exactly once.

**When this step runs:**

- ✅ Runs only if `CustomerDataPlatform` was in `NEEDS_FLIP` (i.e. Step 3 actually flipped Data Cloud on).
- ⏭ Skipped entirely if `CustomerDataPlatform` was NOT in `NEEDS_FLIP` (Data Cloud was already enabled, so provisioning is already complete).
- ⏭ Skipped entirely if Step 3 was skipped (no settings needed flipping at all).

**Step 3.5.1 — Probe `/ssot/data-spaces` for the `default` space**

Reuse the access token and instance URL from Step 0. Allow up to 90 seconds for the async provisioning to land (one HTTP call every 10 s, max 9 attempts). This is bounded and non-interactive.

```bash
INSTANCE_URL=<from Step 0>
ACCESS_TOKEN=<from Step 0>

MAX_ELAPSED=90    # seconds
INTERVAL=10
ELAPSED=0
DEFAULT_FOUND="no"

while [ $ELAPSED -lt $MAX_ELAPSED ]; do
    HTTP=$(curl -s -o /tmp/feat-dc-spaces.json -w "%{http_code}" \
      "${INSTANCE_URL}/services/data/v66.0/ssot/data-spaces" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")
    if [ "$HTTP" = "200" ]; then
        DEFAULT_FOUND=$(python3 -c "
import json
try:
    d = json.load(open('/tmp/feat-dc-spaces.json'))
    spaces = d.get('dataSpaces') or d.get('records') or []
    print('yes' if any((s.get('name') or s.get('developerName') or '').lower() == 'default' for s in spaces) else 'no')
except Exception:
    print('no')
")
        if [ "$DEFAULT_FOUND" = "yes" ]; then
            echo "✓ Data Cloud provisioning confirmed — 'default' data space present (after ${ELAPSED}s)"
            break
        fi
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done
```

- **`DEFAULT_FOUND == "yes"`** → provisioning landed. **Continue to Step 4.**
- **`DEFAULT_FOUND == "no"` after 90 s** → provisioning did not surface the `default` space. **Proceed to Step 3.5.2 (re-deploy once).**

**Step 3.5.2 — One-shot re-deploy of `CustomerDataPlatform`**

Re-deploy the exact same `CustomerDataPlatform.settings` already on disk under `/tmp/feat-deploy/settings/`. Salesforce treats this as idempotent — if the org's flag is already `true`, the redeploy is a no-op (`state: Unchanged`); if provisioning silently rolled back, the redeploy re-triggers it.

```bash
# Build a minimal package directory with ONLY CustomerDataPlatform.
# Create the settings/ subdir FIRST so both the cp and the fallback heredoc have a valid target.
mkdir -p /tmp/feat-dc-reverify/settings

# Prefer reusing the exact .settings file Step 3 wrote. If that file is missing
# (e.g. Step 3 was skipped, or /tmp was wiped between runs), write a fresh copy.
SRC=/tmp/feat-deploy/settings/CustomerDataPlatform.settings
DST=/tmp/feat-dc-reverify/settings/CustomerDataPlatform.settings
if [ -f "$SRC" ]; then
    cp "$SRC" "$DST"
    echo "Step 3.5.2: reusing CustomerDataPlatform.settings from Step 3 (/tmp/feat-deploy)"
else
    cat > "$DST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<CustomerDataPlatformSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableCustomerDataPlatform>true</enableCustomerDataPlatform>
</CustomerDataPlatformSettings>
EOF
    echo "Step 3.5.2: source from Step 3 missing — wrote fresh CustomerDataPlatform.settings"
fi

cat > /tmp/feat-dc-reverify/package.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>CustomerDataPlatform</members>
        <name>Settings</name>
    </types>
    <version>64.0</version>
</Package>
EOF

sf project deploy start \
  --target-org <org_alias> \
  --metadata-dir /tmp/feat-dc-reverify \
  --api-version 64.0 \
  --json > /tmp/feat-dc-reverify-result.json 2>&1
RE_RC=$?
echo "Re-deploy exit code: $RE_RC"
```

**Step 3.5.3 — Re-probe `/ssot/data-spaces` once more (60 s budget)**

```bash
ELAPSED=0
MAX_ELAPSED=60
DEFAULT_FOUND2="no"
while [ $ELAPSED -lt $MAX_ELAPSED ]; do
    HTTP=$(curl -s -o /tmp/feat-dc-spaces2.json -w "%{http_code}" \
      "${INSTANCE_URL}/services/data/v66.0/ssot/data-spaces" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")
    if [ "$HTTP" = "200" ]; then
        DEFAULT_FOUND2=$(python3 -c "
import json
try:
    d = json.load(open('/tmp/feat-dc-spaces2.json'))
    spaces = d.get('dataSpaces') or d.get('records') or []
    print('yes' if any((s.get('name') or s.get('developerName') or '').lower() == 'default' for s in spaces) else 'no')
except Exception:
    print('no')
")
        if [ "$DEFAULT_FOUND2" = "yes" ]; then
            echo "✓ Data Cloud provisioning confirmed after re-deploy (after additional ${ELAPSED}s)"
            break
        fi
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done
```

- **`DEFAULT_FOUND2 == "yes"`** → log `✅ Data Cloud provisioned after re-deploy` and **continue to Step 4.**
- **`DEFAULT_FOUND2 == "no"` after 60 s**, OR re-deploy itself errored → log a single line:

  ```
  ⚠️  Data Cloud provisioning did not surface the 'default' data space within the verification window. Continuing to Step 4 — the toggle will graceful-skip if the row still isn't visible.
  ```

  **Continue to Step 4 anyway.** Step 4 will graceful-skip on its own if the UI also fails. Step 3.5 does NOT STOP the skill — its job is to give provisioning every reasonable chance, then hand off.

**Step 3.5 outcome reporting (record one of these for the Step 5 report):**

| Step 3.5 outcome | What gets logged | Skill behaviour |
|---|---|---|
| Step skipped — `CustomerDataPlatform` not in `NEEDS_FLIP` | `⏭ Data Cloud was already enabled — provisioning check skipped` | Continue to Step 4 |
| `default` space found on initial probe (no re-deploy needed) | `✅ Data Cloud provisioned — 'default' data space present` | Continue to Step 4 |
| `default` space missing initially → re-deploy → found on re-probe | `ℹ️  Data Cloud provisioning lagged; re-deployed CustomerDataPlatform → ✅ provisioned` | Continue to Step 4 |
| `default` space still missing after re-deploy + re-probe | `⚠️  Data Cloud provisioning did not surface 'default' within the verification window — continuing to Step 4 (will graceful-skip)` | Continue to Step 4 |
| Re-deploy itself errored | `⚠️  Step 3.5 re-deploy errored: <error>. Continuing to Step 4.` | Continue to Step 4 |

**Step 3.5 binding rules:**

- At most ONE re-deploy. Never loop. Never re-deploy twice.
- Initial probe budget: 90 s. Re-probe budget: 60 s. Both bounded. No interactive waits.
- Step 3.5 NEVER STOPS the skill. Worst case it logs a warning and hands Step 4 a known-degraded org; Step 4's graceful-skip absorbs the rest.
- The redeploy uses ONLY `CustomerDataPlatform` — never the full 5-setting package. This step does not re-flip any other setting.

---

### Step 4 — Data Cloud Architect → "default" data space toggle (ALWAYS Playwright MCP, graceful skip)

**Why Playwright (no API alternative exists, ever):** The "Data Cloud Data Space Management → default data space → enabled" toggle inside the managed `force.GenieAdmin` permission set is **not exposed via any public Salesforce API**. Confirmed empirically:
- ❌ Metadata API `retrieve` of `PermissionSet:GenieAdmin` → `"Entity of type 'PermissionSet' named 'GenieAdmin' cannot be found"`
- ❌ Metadata API `retrieve` of `PermissionSet:force__GenieAdmin` → `"Metadata API received improper input"`
- ❌ Metadata types `DataspaceScope` and `DataSpace` are NOT registered in the Metadata Coverage Report
- ❌ Tooling API SOQL on `DataspaceScopeAccess` → `"sObject type 'DataspaceScopeAccess' is not supported"`
- ❌ `sf org list metadata --metadata-type PermissionSet` does NOT include `GenieAdmin`

UI automation via Playwright is the **only** available path.

**Graceful skip principle:** If the "Data Cloud Data Space Management" page does not render the `default` row (e.g. Data Cloud was just deployed in Step 3 and the org hasn't surfaced the data-space UI yet, or licensing keeps the section hidden), **do NOT prompt the user to do anything manually**. Log a single short note, close the browser, and let the calling agent proceed to the next skill in the install sequence.

**Step 4.0 — Load Playwright MCP tools**

```
ToolSearch("select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_snapshot,mcp__plugin_playwright_playwright__browser_click,mcp__plugin_playwright_playwright__browser_wait_for,mcp__plugin_playwright_playwright__browser_handle_dialog,mcp__plugin_playwright_playwright__browser_close")
```

**Step 4.1 — Get instance URL and access token**

```bash
sf org display --target-org <org_alias> --json
```

Extract `result.instanceUrl` and `result.accessToken`.

**Step 4.2 — Query the permission set ID**

```bash
mkdir -p /tmp/permset-query
echo "SELECT Id FROM PermissionSet WHERE Name = 'GenieAdmin' LIMIT 1" > /tmp/permset-query/q.soql
sf data query --target-org <org_alias> --file /tmp/permset-query/q.soql --json
```

Extract `PERMSET_ID` from `result.records[0].Id`.

**If the SOQL returns 0 records** (Data Cloud not provisioned, GenieAdmin permset doesn't exist on this org) → log `ℹ️  Data Cloud Architect permission set not found in this org — skipping default data space enablement` and **continue to Step 5 (cleanup)**. Do NOT launch Playwright. Do NOT prompt the user.

**Step 4.3 — Build frontdoor URL that lands DIRECTLY on the DataspaceScopes edit page**

```
{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}&retURL=/{PERMSET_ID}/e?s=DataspaceScopes
```

The `retURL` query parameter `/{PERMSET_ID}/e?s=DataspaceScopes` lands the user on the **edit form for the Data Cloud Data Space Management section** of the Data Cloud Architect permission set, bypassing two manual clicks. The page opens already in edit mode with the data-space checkboxes rendered.

**Step 4.4 — Navigate via Playwright**

```
Tool: mcp__plugin_playwright_playwright__browser_navigate
  url: <frontdoor URL from 4.3>

Tool: mcp__plugin_playwright_playwright__browser_wait_for
  time: 3
```

**Step 4.5 — Snapshot, then look for the `default` data space row**

```
Tool: mcp__plugin_playwright_playwright__browser_snapshot
```

Inspect the snapshot for a row labeled `default` containing an `Enabled` checkbox.

**Decision tree (this is the heart of the graceful-skip logic):**

- **`default` row IS in the snapshot** → proceed to Step 4.6 (click + save).

- **`default` row is NOT in the snapshot** → run **Step 4.5a** (single refresh). If the row still does not appear after the refresh, fall through to the graceful-skip block below.

  **Rationale:** a blank `DataspaceScopes` page on first render is almost always a Lightning/Aura render race — one reload fixes it. Data Cloud provisioning verification and any provisioning-level remediation are handled **upstream in Step 3.5** (`/ssot/data-spaces` probe + one bounded re-deploy of `CustomerDataPlatform`), **not** inside this UI-toggle step. Keeping Step 4's contract narrow ("ALWAYS Playwright MCP, graceful skip") is intentional.

**Step 4.5a — Refresh the same URL once and re-snapshot**

Reuse the exact frontdoor URL from Step 4.3 — do not change it, do not re-fetch the access token, do not re-query the permset ID.

```
Tool: mcp__plugin_playwright_playwright__browser_navigate
  url: <same frontdoor URL from Step 4.3>

Tool: mcp__plugin_playwright_playwright__browser_wait_for
  time: 4

Tool: mcp__plugin_playwright_playwright__browser_snapshot
```

Inspect the new snapshot for the `default` row.

- **`default` row appears after refresh** → log `ℹ️  Default data space row appeared after page refresh` and **proceed to Step 4.6** (click + save).
- **`default` row still missing** → fall through to the graceful-skip block below. Do NOT refresh again. Do NOT redeploy. Do NOT probe additional APIs from this step.

**Graceful-skip fallback (only reached when Step 4.5a refresh did not surface the row):**

Log a single line:

```
ℹ️  Data Cloud Data Space Management option not available for enabling the Data Space — skipping this option and continuing
```

Then **immediately close the browser** (Step 4.7) and **continue to Step 5 (cleanup)**. Do NOT prompt the user. Do NOT print a frontdoor URL. Do NOT say "manual step required". Do NOT wait for confirmation.

**Step 4 recovery rules (binding):**

- At most one refresh attempt (Step 4.5a). Never loop. Never refresh twice.
- Step 4 does NOT diagnose Data Cloud provisioning and does NOT redeploy `CustomerDataPlatform`. Those responsibilities live in **Step 3.5** — never inside this step. This keeps Step 4 single-responsibility: toggle the UI, or graceful-skip.
- Step 4 STILL never STOPs the skill and STILL never prompts the user. The two terminal outcomes remain: enable, or graceful skip.

**Step 4.6 — Click the `default` checkbox, then Save**

```
Tool: mcp__plugin_playwright_playwright__browser_click
  target: <default checkbox ref>
  element: "default data space Enabled checkbox"

Tool: mcp__plugin_playwright_playwright__browser_click
  target: <Save button ref>
  element: "Save"
```

A browser-native alert dialog will appear with the text `"Your selections were saved."`. Handle it:

```
Tool: mcp__plugin_playwright_playwright__browser_handle_dialog
  accept: true
```

**Step 4.7 — Close browser (always runs)**

```
Tool: mcp__plugin_playwright_playwright__browser_close
```

The browser is closed regardless of which Step 4.5 branch was taken.

**Step 4 outcome reporting (record one of these for the Step 5 report):**

| Step 4 outcome | What gets logged | Skill behaviour |
|---|---|---|
| `default` row found on first snapshot, clicked, saved successfully | `✅ Default data space enabled in Data Cloud Architect` | Continue to Step 5 |
| `default` row appeared after Step 4.5a refresh, clicked, saved successfully | `ℹ️  Default data space row appeared after page refresh` then `✅ Default data space enabled in Data Cloud Architect` | Continue to Step 5 |
| `default` row not in first snapshot AND not in refresh snapshot | `ℹ️  Data Cloud Data Space Management option not available for enabling the Data Space — skipping this option and continuing` | Continue to Step 5 |
| Permset SOQL returned 0 records | `ℹ️  GenieAdmin permset not present — skipped` | Continue to Step 5 (refresh not run) |
| Playwright errored (timeout, page failed to load, etc.) | `⚠️  Step 4 errored: <error>. Default data space not toggled — continuing.` | Continue to Step 5 |

**Step 4 NEVER stops the skill. Step 4 NEVER prompts the user.** Whatever happens, the browser closes and Step 5 (cleanup + report) runs.

---

### Step 5 — Cleanup + generate completion report

See "Cleanup" and "Success Report" below.

---

## Error Handling

The skill has exactly **one execution path with one graceful skip**:

| Failure point | Behaviour |
|---|---|
| Step 0 (auth check) fails | STOP — report "session not authenticated" |
| Step 1 (combined retrieve) fails | STOP — report verbatim retrieve error; user fixes root cause and re-runs |
| Step 3 (combined deploy) fails | STOP — report verbatim deploy error; rollback already happened (rollbackOnError=true); user fixes root cause and re-runs |
| Step 3.5 — `default` data space not found within probe window, or re-deploy errored | LOG + CONTINUE to Step 4 — never STOPs the skill, never prompts the user; Step 4 will graceful-skip on its own |
| Step 4 (Playwright) — `default` row not visible | LOG + CLOSE BROWSER + CONTINUE — never STOPs the skill, never prompts the user |
| Step 4 (Playwright) — any other Playwright error | LOG + CLOSE BROWSER + CONTINUE — never STOPs the skill, never prompts the user |

The Step 0 / 1 / 3 failures are about Metadata API operations the user must resolve before the install can continue. **Step 3.5 and Step 4 are both best-effort** — if Data Cloud hasn't fully provisioned today, the install proceeds without the default-data-space toggle. The toggle can be set later by re-running the skill once provisioning completes.

---

## Important Rules

### Absolute Prohibitions

- ❌ NEVER generate `.js`, `.mjs`, `.ts` files
- ❌ NEVER use Playwright/browser automation for Steps 1–3
- ❌ NEVER use Metadata API, Tooling API, Connect REST, or any other API substitute for Step 4 — it MUST be Playwright
- ❌ NEVER skip the Tier 1 cleanup of `org_creds.json` and `frontdoor_url.txt` (credential safety — Tier 2 scratch cleanup is best-effort, see Cleanup section)
- ❌ NEVER call `sf` CLI with interactive flags that prompt for confirmation
- ❌ NEVER include `Account` (Person Account) in the deploy package if the retrieve XML showed `enableAccountTeams=true` (irreversible)
- ❌ NEVER make per-setting retrieves — Step 1 is one combined retrieve only
- ❌ NEVER make per-setting deploys — Step 3 is one combined deploy only
- ❌ NEVER retry a failed step in a loop — Step 3.5 may re-deploy `CustomerDataPlatform` AT MOST ONCE, Step 4 may refresh AT MOST ONCE; nothing else retries
- ❌ NEVER fall back to an alternate code path on failure — STOP (Steps 0/1/3) or LOG + CONTINUE (Steps 3.5 / 4)
- ❌ NEVER verify Data Cloud enablement with an extra Metadata API retrieve — Step 3.5 uses the cheap `/ssot/data-spaces` REST probe instead; full retrieves are not used for verification
- ❌ NEVER print "Manual Step Required" / "Please open this URL" / "Please click X" / "Once you've completed this step, let me know" / similar handoff messages anywhere in the skill output
- ❌ NEVER pause Step 4 to wait for the user to do anything — Playwright either does it or skips it

### Required Behaviors

- ✅ Step 1 ALWAYS runs ONE combined retrieve of all 5 Settings types in a single call
- ✅ Step 2 ALWAYS parses XMLs locally (no API calls)
- ✅ Step 3 ALWAYS runs ONE combined deploy of only settings in `NEEDS_FLIP`, OR is skipped entirely if `NEEDS_FLIP` is empty
- ✅ Step 3.5 ALWAYS runs ONLY if `CustomerDataPlatform` was in `NEEDS_FLIP`; uses at most ONE re-deploy (`CustomerDataPlatform`-only) with bounded 90 s / 60 s probe windows; ALWAYS continues to Step 4 regardless of outcome
- ✅ Step 4 ALWAYS uses Playwright MCP, ALWAYS closes the browser before returning, ALWAYS continues to Step 5 regardless of outcome
- ✅ ALWAYS classify deploy results by `result.files[].state`:
  - All `state == "Unchanged"` → report `⏭ Already enabled — no-op deploy (no changes applied)`
  - At least one `state == "Changed"` or `"Created"` → report `✅ Deployed (newly enabled)`
- ✅ Person Account: omit from deploy if XML showed `enableAccountTeams=true`
- ✅ Single API version v64.0 everywhere (retrieve and deploy)
- ✅ ALWAYS execute steps in series (sequential) — never in parallel

---

## Success Report

```text
✅ Salesforce Feature Enablement Completed

Org: <org_alias>
Instance: {instance_url}
Duration: {total_time}

Step 1 — Combined retrieve (all 5 Settings types in one call):
✅ Completed in {N} sec — captured live state of all 5 settings

Step 2 — Per-setting decisions (skip-if-already-enabled):
  Promotion Attribute: <⏭ Already enabled | 🔧 Needs flipping>
  Data Cloud:          <⏭ Already enabled | 🔧 Needs flipping>
  Einstein:            <⏭ Already enabled | 🔧 Needs flipping>
  Agentforce:          <⏭ Already enabled | 🔧 Needs flipping>
  Person Account:      <⏭ Already enabled (omitted from deploy — irreversible safety) | 🔧 Needs flipping>

Step 3 — Combined deploy:
  ✅ {N} setting(s) deployed in one zip
  Each setting state per Salesforce:
    <setting1>: <Changed | Unchanged>
    ...
  [or: ⏭ Skipped — every setting was already enabled]

Step 3.5 — Data Cloud provisioning verification:
  <one of:>
    ⏭ Skipped — CustomerDataPlatform was not in NEEDS_FLIP (already enabled)
    ✅ Data Cloud provisioned — 'default' data space present (no re-deploy needed)
    ℹ️  Data Cloud provisioning lagged — re-deployed CustomerDataPlatform → ✅ provisioned
    ⚠️  Data Cloud provisioning did not surface 'default' within the verification window — continued to Step 4
    ⚠️  Step 3.5 re-deploy errored: <error> — continued to Step 4

Step 4 — Data Cloud Architect → default data space (Playwright):
  <one of:>
    ✅ Default data space enabled — "Your selections were saved." dialog confirmed
    ℹ️  Default data space row appeared after page refresh → ✅ Default data space enabled
    ℹ️  Data Cloud Data Space Management not available — skipped (no impact on remaining install steps)
    ℹ️  GenieAdmin permset not present — skipped
    ⚠️  Step 4 errored: <error> — default data space not toggled, continuing

Total Metadata API calls: <1 if no flips needed | 2 if flips needed>

✅ Org is now ready for Data Kit deployment

Next Steps:
1. Run: /datakit-metadata-deploy <org_alias>
2. Run: /datakit-api-deploy <org_alias>
3. Monitor Data Kit installation (25-35 minutes)
```

---

## Failure Report (Step 0, 1, or 3 stopped the skill)

```text
🛑 Salesforce Feature Enablement — STOPPED at Step <0|1|3>

Org: <org_alias>

✅ Steps that completed before the failure: <list>

🛑 Failed step: Step <N> — <step name>

Error reported by Salesforce:
   <verbatim error message>

What this means:
   <one-sentence explanation tied to the specific failure, e.g.
    • Step 0: cached SF CLI session is missing or expired
    • Step 1: the org rejected the Settings retrieve — typically a missing PSL
    • Step 3: the deploy was rolled back — typically a license/feature provisioning issue>

Re-run the skill once the underlying issue is resolved:
   /feature-enablement <org_alias>
```

Note: Step 4 never produces a failure report — its outcomes (success / graceful skip / error) are all reported as part of the **Success Report**, not the Failure Report. Step 4 is best-effort; the skill always completes if Steps 0/1/3 completed.

---

## Dependencies

### Required for Metadata API steps (1–3)

- Salesforce CLI installed and authenticated (`sf` command available)
- Target org has the relevant Permission Set Licenses Active:
  - `GenieDataPlatformStarterPsl` (Data Cloud)
  - `EinsteinGPTPromptTemplatesPsl` and related Einstein PSLs
  - `GlobalPromotionsManagementPsl` and `ProductCatalogManagementAdministratorPsl`

### Required for Playwright step (Step 4 only)

- MCP Playwright tools available in deferred tools list
- System Administrator profile on target org

---

## Integration with Data Kit Deployment

This skill must run BEFORE Data Kit deployment:

```
Workflow Order:
1. /feature-enablement <org_alias>         ← Run FIRST
   └─ One retrieve + one deploy via Metadata API + Playwright (best-effort) for permission set

2. /datakit-metadata-deploy <org_alias>    ← Run SECOND
   └─ Deploys 612 metadata components

3. /datakit-api-deploy <org_alias>         ← Run THIRD
   └─ Triggers Data Kit installation (25-35 min)
```

If Step 4 gracefully skipped (default data space couldn't be enabled), the Data Kit install continues normally. The default data space can be enabled later by re-running `/feature-enablement <org_alias> tasks=permission-set` once Data Cloud has fully provisioned.

---

## ✅ COMPLETION CHECKLIST

Verify all items before marking complete:

| # | Task | Verification |
|---|------|--------------|
| 0 | Org session verified | `sf org display` returned `result.accessToken` |
| 1 | Combined retrieve | All 5 `*.settings-meta.xml` files present in `/tmp/feat-check/retrieved/settings/` |
| 2 | Local parse classified each setting | `NEEDS_FLIP` array contains only settings where the XML did NOT show the desired-state values; Person Account omitted if `enableAccountTeams=true` |
| 3 | Combined deploy | If `NEEDS_FLIP` empty → deploy skipped. If non-empty → `sf project deploy start` returned `Succeeded` for all members. |
| 3.5 | Data Cloud provisioning verified | Either: `CustomerDataPlatform` was NOT in `NEEDS_FLIP` so the step was skipped; OR `/ssot/data-spaces` confirmed `default` exists (with or without one re-deploy); OR a "did not surface within window" warning was logged and skill continued to Step 4. |
| 4 | Data Cloud Architect default data space | Either: "Your selections were saved." dialog appeared, OR a graceful-skip log was emitted (default row not present, permset not found, or Playwright errored). Browser was closed. Skill continued to Step 5. |
| 5 | Cleanup | **Tier 1 (mandatory):** `org_creds.json` and `frontdoor_url.txt` are deleted. **Tier 2 (best-effort, 2-second budget):** `/tmp/feat-*`, `/tmp/permset-query`, `.playwright-mcp/` removed when possible; leftover empty dirs are non-sensitive and acceptable on Windows. |

---

## Cleanup temp artifacts (two tiers — security-critical vs best-effort)

Cleanup has **two tiers** with different guarantees. This split exists because the SF CLI metadata-cache scanner keeps file handles open on the retrieve directory for 30-60s after retrieve completes. On Linux/macOS that's invisible (POSIX permits unlink while a file is open). On Windows it raises `WinError 32` and a retry loop can stall the skill for 30+ seconds for **no security benefit** — the held-open files are non-sensitive XML setting flags. Don't burn wall-clock on leftovers that don't matter.

### Tier 1 — Credential files (MANDATORY, synchronous, no retries, no timeout)

These files contain a Salesforce access token or session URL. **Delete them every time, on both success and failure paths. Never skip. Never retry-loop.** Per-file `os.unlink` is reliable on Windows for these files because nothing else holds handles to them.

```bash
# Tier 1 — credential exposure: delete immediately, fail loud if delete itself fails
rm -f frontdoor_url.txt
rm -f org_creds.json
```

Cross-platform alternative when running from Python/bash on Windows:

```bash
python3 -c "
import pathlib
for f in ('frontdoor_url.txt', 'org_creds.json'):
    p = pathlib.Path(f)
    if p.exists():
        p.unlink()
"
```

If a Tier 1 deletion raises an error, **surface it** — that's a real problem (e.g. file is locked by another process the user must know about). Do not swallow.

### Tier 2 — Scratch directories (best-effort, 2-second total budget)

These hold only `.settings-meta.xml` files (live-state snapshots of feature flags), deploy result JSON, Step 3.5's provisioning-probe responses + one-shot re-deploy package, and a SOQL query file. **None of them contain credentials or tokens.** They're hygiene, not security. If Windows file handles hold the directory open longer than 2 seconds, **log one line and move on** — the next skill run clobbers them anyway.

```bash
python3 << 'PYEOF'
import shutil, pathlib, time
BUDGET_SEC = 2.0
targets = [
    pathlib.Path(r'/tmp/feat-check'),
    pathlib.Path(r'/tmp/feat-deploy'),
    pathlib.Path(r'/tmp/permset-query'),
    pathlib.Path(r'/tmp/feat-deploy-result.json'),
    # Step 3.5 — provisioning probe + one-shot re-deploy scratch
    pathlib.Path(r'/tmp/feat-dc-spaces.json'),
    pathlib.Path(r'/tmp/feat-dc-spaces2.json'),
    pathlib.Path(r'/tmp/feat-dc-reverify'),
    pathlib.Path(r'/tmp/feat-dc-reverify-result.json'),
    pathlib.Path('.playwright-mcp'),
]
deadline = time.monotonic() + BUDGET_SEC
remaining = []
for t in targets:
    if not t.exists():
        continue
    try:
        if t.is_dir():
            shutil.rmtree(t, ignore_errors=False)
        else:
            t.unlink()
    except OSError:
        # Windows file-handle race — try ONCE more before deadline, then give up
        if time.monotonic() < deadline:
            try:
                if t.is_dir():
                    shutil.rmtree(t, ignore_errors=True)
                else:
                    t.unlink(missing_ok=True)
            except OSError:
                pass
        if t.exists():
            remaining.append(str(t))
if remaining:
    print(f"ℹ️  Tier 2 cleanup: {len(remaining)} scratch path(s) still held by OS (non-sensitive, will be overwritten on next run): {remaining}")
else:
    print("✓ All scratch artifacts removed")
PYEOF
```

Windows path note: if `/tmp` is Git-Bash-translated, the script works as-is. From cmd.exe / PowerShell, substitute `r'C:\tmp\feat-check'` etc. The behavior contract is the same: **2-second budget, log-and-continue on leftover.**

### Cleanup-on-failure policy

- ✅ **Tier 1 ALWAYS runs**, on success AND on every failure path (Step 0 / 1 / 3 STOPs, Step 3.5 warnings, Step 4 errors). Credential files must never persist.
- ❌ **Tier 2 does NOT run on Step 3 deploy failure** — the user needs `/tmp/feat-deploy/` (package.xml + `*.settings`) to debug the deploy.
- ❌ **Tier 2 does NOT run when Step 3.5 logged a "did not surface within window" warning OR its re-deploy errored** — the user needs `/tmp/feat-dc-reverify-result.json` and the probe responses to investigate why provisioning stalled. (Skill still continued to Step 4, but the evidence is worth keeping.)
- ❌ **Tier 2 does NOT run on Step 4 Playwright error** — `.playwright-mcp/` snapshots + console logs are the failure evidence the user needs. Browser is still closed regardless.
- ✅ **Tier 1 still runs in all ❌ cases above** — credential safety is unconditional.

### Verification (informational only — Tier 2 leftovers are acceptable)

```bash
# Tier 1 verification — MUST be empty
ls frontdoor_url.txt org_creds.json 2>&1 | grep -v "cannot access" || echo "  (Tier 1 clean)"

# Tier 2 verification — leftovers are NON-FATAL informational
ls -d /tmp/feat-check /tmp/feat-deploy /tmp/permset-query /tmp/feat-dc-reverify .playwright-mcp 2>&1 | grep -v "cannot access" || echo "  (Tier 2 clean)"
ls /tmp/feat-deploy-result.json /tmp/feat-dc-spaces.json /tmp/feat-dc-spaces2.json /tmp/feat-dc-reverify-result.json 2>&1 | grep -v "cannot access"
```

If Tier 1 verification finds either file present after the cleanup ran, that's a **bug** — surface it. If Tier 2 verification finds leftovers, that's **expected on Windows when SF CLI scanner is still holding handles** — do not surface, do not retry, the next run handles it.

### What NOT to delete

- Anything under `.claude/` — your skill / agent definitions
- Anything in the repo root that existed at run start (`settings.json`, `sfdx-project.json`, root `package.xml`, etc.)
