---
name: embed-service-agent-on-experience-site
description: "Configure a Salesforce Embedded Service (Agentforce Service Agent) deployment for use on an external website. Built incrementally — currently covers Step 1: Enable Messaging Channel (LiveMessageSettings.enableLiveMessage = true via Metadata API), Step 2: Register Site Domain (Visualforce a4j POST against /udd/Site/customSubdomain.apexp accepting Sites Terms of Use), Step 3: Install Embedded Service Package + Activate Messaging Channel (sf project deploy start -d diy-embeddedservice + sf apex run -f scripts/apex/activateMessagingChannel.apex), Step 4: Trusted Domains for Inline Frames (Metadata API CustomSite deploy sets the ESW_ESA Site iframe whitelist to exactly one host-only entry — the Experience Cloud Sites Domain `<prefix>.my.site.com`), Step 5: Publish ESA Web Deployment (Playwright MCP — log in, navigate directly to /lightning/setup/EmbeddedServiceDeployments/<EmbeddedServiceConfigId>/view where the Id is looked up via Tooling SOQL on EmbeddedServiceConfig.DeveloperName='ESA_Web_Deployment', click the page's Publish button, leave it; no public API surfaces this), and Step 6: Create a New Version of the Omni-Channel Flow (SOQL lookup of current org's ServiceChannel/Queue/BotDefinition IDs + Python substitution of stale source-org IDs in the repo's Route_Conversations_to_Agentforce_Service_Agents flow XML + Metadata API deploy — Salesforce auto-handles the version transition). Steps 1-4 + 6 are pure CLI; Step 5 is the only Playwright step. Use when the user wants to: 'enable messaging channel', 'register site domain', 'install embedded service package', 'activate messaging channel', 'add trusted domain for inline frames', 'publish ESA web deployment', 'publish embedded service', 'create new version of omni-channel flow', 'route conversations to DIY Assistant', 'refresh stale flow IDs', or otherwise begin wiring up a Salesforce service agent for an external site."
---

# embed-service-agent-on-experience-site

## Purpose

Build the configuration required to embed an Agentforce Service Agent on an external website. The skill scope is **exactly 6 steps**: Step 1 (Enable Messaging Channel), Step 2 (Register Site Domain), Step 3 (Install Embedded Service Package + Activate Messaging Channel), Step 4 (Trusted Domains for Inline Frames), Step 5 (Publish ESA Web Deployment), Step 6 (Create a New Version of the Omni-Channel Flow). Each step was added one verified test at a time against a real org. **All 6 steps are implemented and verified.** Step 5 is the only Playwright-MCP step (no documented public API surfaces the Publish action — the Setup UI Publish button calls a private Aura action, so the skill drives that exact button via Playwright). CORS Configuration and Trusted URL / CSP Configuration are explicitly **out of scope** for this skill.

**Why incremental:** every Salesforce metadata type behaves slightly differently across API versions and org types. Adding all steps up front and hoping they work risks shipping broken automation. Each new step must be deployed once against a real org, the working command + response captured, and only then committed to this skill.

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username. The org must already be authenticated via `sf org login web -a <alias>`.
- `username` + `password` (required only for **Step 5 — Publish ESA Web Deployment**): Salesforce UI credentials for the same user as `org_alias`. Step 5 is the only Playwright-MCP step in the skill and Lightning Setup pages do not accept the CLI's API-only access token. If Step 5 is run as part of the full skill, the orchestrator must pass these. Example: `username=storm.359e620867b1f4@salesforce.com`, `password=orgfarm1234`. Steps 1-4 and 6 do NOT use these arguments.
- `external_website_url` (currently unused — placeholder for a future iframe-allowlist refinement): The external website URL where the agent will be embedded. **Must be `https://`, must NOT end with `/`.** Example: `https://www.example.com`.

---

## Preconditions

- Salesforce CLI installed and authenticated with the target org
- User has System Administrator profile or equivalent permissions
- For uninterrupted execution, `.claude/settings.json` should pre-approve:
  ```json
  {
    "permissions": {
      "allow": [
        "Bash:sf *",
        "Bash:mkdir *",
        "Bash:rm *"
      ]
    }
  }
  ```

---

## Workflow

```
Step 1: Enable Messaging Channel
   ↓ (runtime: retrieve LiveMessageSettings → flip enableLiveMessage to true → deploy → verify → cleanup)
Step 2: Register Site Domain
   ↓ (a) probe /udd/Site/customSubdomain.apexp — if registration form is absent, already done
   ↓ (b) if form is present: extract ViewState fields, POST with termsCB=on + registerDomain action
   ↓ (c) verify by re-probing the page (form must now be absent / page bounces to /0DM/o)
Step 3: Install Embedded Service Package + Activate Messaging Channel
   ↓ (a) sf project deploy start -d diy-embeddedservice
   ↓ (b) sf apex run -f scripts/apex/activateMessagingChannel.apex
   ↓ (c) verify MessagingChannel.ESA_Channel.IsActive = true
Step 4: Trusted Domains for Inline Frames (on the ESW_ESA Site provisioned by Step 3)
   ↓ (a) locate the ESW_ESA Site (Name LIKE 'ESW_ESA_Web_Deployment_%' AND UrlPathPrefix LIKE '%vforcesi')
   ↓ (b) detect My Domain prefix from instanceUrl
   ↓ (c) retrieve CustomSite, replace <siteIframeWhiteListUrls> block with the single Experience Cloud Sites Domain entry
   ↓     (<prefix>.my.site.com — NO scheme, NO path)
   ↓ (d) deploy → verify via SOQL → cleanup
Step 5: Publish ESA Web Deployment (Playwright MCP — only browser step in the skill)
   ↓ (a) Tooling SOQL: SELECT Id FROM EmbeddedServiceConfig WHERE DeveloperName='ESA_Web_Deployment'
   ↓ (b) browser_navigate to <instanceUrl>/lightning/setup/EmbeddedServiceDeployments/<Id>/view
   ↓ (c) if hit by /secur login redirect, fill the username + password textboxes + click Log In
   ↓ (d) wait for the page text "Publish" to render, then click the Publish button (name="Publish button to complete changes after editing a deployment.")
   ↓ (e) leave the page — no further verification (Salesforce queues the publish asynchronously)
Step 6: Create a New Version of the Omni-Channel Flow
   ↓ (a) look up current org's ServiceChannel(LiveMessage), Queue(Messaging_Queue), BotDefinition(DIY Assistant) IDs
   ↓ (b) stage repo flow XML and substitute the 4 stale values (serviceChannelId, queueId, copilotId, copilotLabel)
   ↓ (c) sf project deploy start --source-dir → Salesforce auto-deactivates v1 + auto-activates v2
   ↓ (d) verify v2.Status='Active' and v2.Metadata has the corrected IDs → cleanup
```

---

### Step 1 — Enable Messaging Channel

**🚨 Verified working approach (deployed successfully on OrgRetailTest35 on 2026-06-12, deploy id `0Afbm00000Vr4lJCAR`):** the org-level "Messaging" toggle on `Setup → Messaging Settings` is controlled by the **`LiveMessageSettings`** metadata type with field `enableLiveMessage`.

**Why this type and not others:**

- The toggle's DOM (input id `liveMessageToggle`, name `toggle-livemessage`) maps to `LiveMessageSettings.enableLiveMessage`.
- `sf org list metadata --metadata-type Settings` lists `LiveMessage | Settings` as an available member, confirming the type name.
- The legacy `LiveAgentSettings` type is for the retired Live-Agent-chat product and is NOT what the modern Setup page binds to. `EngagementMessagingSettings` is queryable as an SObject but is not a deployable Settings metadata type.

**🚨 NEVER-DISABLE GUARD.** This step ONLY enables Messaging — it must never set `enableLiveMessage` to `false`. The skill works by retrieving the current state, **only** flipping `false` → `true`, and skipping the deploy entirely if the state is already `true`. There is no code path in this skill that can demote the setting from `true` back to `false`. Do NOT add such logic.

**Why runtime-retrieve-then-deploy (instead of shipping a template file):**

- The retrieved file already has the correct schema, namespace, and any version-specific fields the org expects. Hand-authoring a template can drift from what the org actually accepts.
- One source of truth: the org's own retrieve output. No template file to keep in sync.
- Fewer files in the skill folder = less to maintain. Cleanup is just `rm` of the runtime temp dir.

#### 1.1 Pre-check: retrieve current `enableLiveMessage` state

```bash
mkdir -p /c/tmp/dsaew-step1
sf project retrieve start \
  --target-org <org_alias> \
  --metadata "Settings:LiveMessage" \
  --output-dir /c/tmp/dsaew-step1 \
  --json
```

Expected file path on success: `/c/tmp/dsaew-step1/settings/LiveMessage.settings-meta.xml`

Read the current value:

```bash
CURRENT=$(grep -o '<enableLiveMessage>[^<]*</enableLiveMessage>' \
  /c/tmp/dsaew-step1/settings/LiveMessage.settings-meta.xml \
  | sed 's/<[^>]*>//g')
echo "Pre-deploy enableLiveMessage = $CURRENT"
```

**Decision tree:**

| `CURRENT` value | What to do |
|---|---|
| `true` | Already enabled. **Skip 1.2 entirely.** Jump to Step 1.3 (verify) and Step 1.4 (cleanup). Report `state: NoChange (already enabled)`. |
| `false` | Expected initial state. Proceed to 1.2 to flip it. |
| File missing / parse error / anything else | STOP per the orchestrator's strict error-resolution rule. Surface `ls -la /c/tmp/dsaew-step1/settings/` and the file contents to the user. |

#### 1.2 Flip `false` → `true` and deploy

In-place edit the retrieved file (no template, no separate folder):

```bash
sed -i 's|<enableLiveMessage>false</enableLiveMessage>|<enableLiveMessage>true</enableLiveMessage>|' \
  /c/tmp/dsaew-step1/settings/LiveMessage.settings-meta.xml
```

Verify the edit landed:

```bash
grep enableLiveMessage /c/tmp/dsaew-step1/settings/LiveMessage.settings-meta.xml
# Must print: <enableLiveMessage>true</enableLiveMessage>
```

Deploy via `--source-dir`:

```bash
sf project deploy start \
  --target-org <org_alias> \
  --source-dir /c/tmp/dsaew-step1/settings \
  --json
```

> **Why `--source-dir` and not `--manifest` with a hand-rolled `package.xml`:** explicitly authoring `<name>LiveMessageSettings</name>` in `package.xml` triggered `Unknown type name 'LiveMessageSettings'` errors during local validation against this org's API version. The `--source-dir` form lets the CLI infer the manifest from the file itself and worked first try.

Expected JSON shape on success:

```json
{
  "result": {
    "status": "Succeeded",
    "success": true,
    "id": "0Afbm00000Vr4lJCAR",
    "details": {
      "componentSuccesses": [
        { "componentType": "LiveMessageSettings", "fullName": "LiveMessage", "state": "Changed" }
      ]
    }
  }
}
```

- `state: Changed` → toggle flipped from `false` to `true`. Proceed to 1.3.
- `state: NoChange` → already enabled (user pre-flipped it between 1.1 and 1.2). Proceed to 1.3.
- `status: Failed` → STOP per the strict error-resolution rule. Surface the `componentFailures[].problem` to the user.

#### 1.3 Verify via fresh retrieve

```bash
rm -rf /c/tmp/dsaew-step1-verify
mkdir -p /c/tmp/dsaew-step1-verify
sf project retrieve start \
  --target-org <org_alias> \
  --metadata "Settings:LiveMessage" \
  --output-dir /c/tmp/dsaew-step1-verify \
  --json

VERIFY=$(grep -o '<enableLiveMessage>[^<]*</enableLiveMessage>' \
  /c/tmp/dsaew-step1-verify/settings/LiveMessage.settings-meta.xml \
  | sed 's/<[^>]*>//g')
echo "Post-deploy enableLiveMessage = $VERIFY"
```

`VERIFY` MUST be `true`. If it's still `false`, the deploy didn't apply — STOP per the strict error-resolution rule and surface `/c/tmp/dsaew-step1-verify/settings/LiveMessage.settings-meta.xml` to the user.

#### 1.4 Cleanup runtime temp directories

Per the orchestrator's strict error-resolution rule: clean up only on full success. If any sub-step failed and was not resolved, leave artifacts in `/c/tmp/dsaew-step1*/` for debugging.

```bash
rm -rf /c/tmp/dsaew-step1
rm -rf /c/tmp/dsaew-step1-verify
```

Verify (must show no leftovers):

```bash
ls -d /c/tmp/dsaew-step1 /c/tmp/dsaew-step1-verify 2>&1 | grep -v "cannot access"
```

#### 1.5 Report

```text
✅ Step 1 — Enable Messaging Channel: COMPLETE

Org: <org_alias>
Pre-deploy state:  enableLiveMessage = <CURRENT>
Post-deploy state: enableLiveMessage = true (verified)
Deploy id:         <r.id from 1.2>
Component state:   <state from 1.2>  (Changed | NoChange)
```

---

### Step 2 — Register Site Domain

**🚨 Verified working approach on OrgRetailTest35 on 2026-06-12.** This action is the manual checklist step "Navigate to Setup → Sites → check the Sites Terms of Use checkbox → click Register My Salesforce Site Domain."

**Why no documented public API exists** (verified by elimination):

| Path tried | Result |
|---|---|
| Direct REST `PATCH /sobjects/Site/<id>` with `{Subdomain: ...}` | `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` — `Site` is not REST-writable |
| Metadata API `Settings:Site` (`SiteSettings`) | Has only `enableExpBuilderCopilot`, `enableProxyLoginICHeader`, `enableTopicsInSites` — no domain registration / ToU field |
| Metadata API `Settings:MyDomain` (`MyDomainSettings`) | Has `myDomainName` and `redirectForceComSiteUrls` but no Sites ToU acceptance flag |
| Metadata API `CustomSite` deploy with `<subdomain>` element added | Deploy reported `Succeeded` but `Site.Subdomain` stayed `null` — Salesforce silently ignored the element |
| Tooling SObject `CustomDomain` | `INVALID_TYPE` — does not exist on this org's API version |

**Working approach: Visualforce a4j POST against `/udd/Site/customSubdomain.apexp`** — the same endpoint the Setup UI uses. The page exposes a Visualforce + a4j AJAX form. Posting to it with `termsCB=on` + the `registerDomain` action key (plus the standard ViewState fields the page emits) registers the domain. Verified live: `Setup → Sites` page transitioned from showing the registration form to bouncing to `/0DM/o` (Sites list) after a single POST.

**🚨 Internal endpoint disclaimer.** `/udd/Site/customSubdomain.apexp` and the four `com.salesforce.visualforce.ViewState*` form fields are **not part of any documented public API**. They are Salesforce's internal Setup page wiring. They have been stable for years but Salesforce does not guarantee them. If a future Salesforce release breaks this pattern, fall back to a manual UI click and the rest of the skill still works (Step 2.0 detects the registered state on its own and short-circuits).

**No Playwright. Pure cURL.**

#### 2.0 Pre-check: detect whether the domain is already registered

The Setup page **renders the registration form only when the domain is not yet registered**. After registration, the same URL bounces to `/0DM/o` (the Sites list). This makes detection trivial: fetch the page, look for the literal text `"Register My Salesforce Site Domain"`. If absent → already registered, skip Step 2.

```bash
INSTANCE_URL=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")
ACCESS_TOKEN=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['accessToken'])")

# Establish a real web session via frontdoor.jsp (Visualforce setup pages need a session cookie, NOT a Bearer token)
mkdir -p /c/tmp/dsaew-step2
COOKIES=/c/tmp/dsaew-step2/cookies.txt
PAGE=/c/tmp/dsaew-step2/page.html
rm -f "$COOKIES" "$PAGE"

curl -s -L -c "$COOKIES" \
  "${INSTANCE_URL}/secur/frontdoor.jsp?sid=${ACCESS_TOKEN}" \
  -o /dev/null

curl -s -L -b "$COOKIES" -c "$COOKIES" \
  "${INSTANCE_URL}/udd/Site/customSubdomain.apexp" \
  -o "$PAGE"

if grep -q "Register My Salesforce Site Domain" "$PAGE"; then
  echo "STATE=NotRegistered"   # proceed to 2.1
else
  echo "STATE=AlreadyRegistered"   # skip 2.1, jump to 2.3 verify
fi
```

- `NotRegistered` → proceed to 2.1.
- `AlreadyRegistered` → skip 2.1, jump straight to Step 2.3 (verify probe again confirms registered state, then 2.4 cleanup, 2.5 report).

#### 2.1 Extract ViewState fields and POST the registration

The Visualforce page emits four required form fields plus the form's data and the action button name. Extract them from the page already retrieved in 2.0, then POST.

```bash
python << 'PYEOF' > /c/tmp/dsaew-step2/postbody.txt
import re, urllib.parse
content = open(r'C:\tmp\dsaew-step2\page.html', encoding='utf-8', errors='replace').read()
def grab(name):
    m = re.search(r'<input[^>]+name="' + re.escape(name) + r'"[^>]+value="([^"]*)"', content)
    if not m: raise SystemExit(f'missing form field: {name}')
    return m.group(1)
fields = [
    ('AJAXREQUEST', '_viewRoot'),
    ('thePage:theForm', 'thePage:theForm'),
    ('thePage:theForm:setDomainPB:termsCB', 'on'),
    ('com.salesforce.visualforce.ViewState', grab('com.salesforce.visualforce.ViewState')),
    ('com.salesforce.visualforce.ViewStateVersion', grab('com.salesforce.visualforce.ViewStateVersion')),
    ('com.salesforce.visualforce.ViewStateMAC', grab('com.salesforce.visualforce.ViewStateMAC')),
    ('com.salesforce.visualforce.ViewStateCSRF', grab('com.salesforce.visualforce.ViewStateCSRF')),
    ('thePage:theForm:setDomainPB:registerDomain', 'thePage:theForm:setDomainPB:registerDomain'),
]
print(urllib.parse.urlencode(fields), end='')
PYEOF

# POST it
RESP=/c/tmp/dsaew-step2/postresp.html
curl -s -X POST "${INSTANCE_URL}/udd/Site/customSubdomain.apexp" \
  -b "$COOKIES" -c "$COOKIES" \
  -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
  -H "X-Requested-With: XMLHttpRequest" \
  -H "Accept: text/xml,application/xml" \
  -H "Faces-Request: partial/ajax" \
  -H "Referer: ${INSTANCE_URL}/udd/Site/customSubdomain.apexp" \
  --data-binary @/c/tmp/dsaew-step2/postbody.txt \
  -o "$RESP" -w "HTTP %{http_code}\n"

# Success indicator: the response is an a4j redirect XML pointing to /0DM/o
grep -q 'Ajax-Response.*redirect' "$RESP" && grep -q '/0DM/o' "$RESP" \
  && echo "POST result: registration submitted (redirect → /0DM/o)" \
  || { echo "❌ unexpected response — see $RESP"; exit 1; }
```

- Response contains `Ajax-Response: redirect` and `Location: /0DM/o` → registration accepted. Proceed to 2.2 verify.
- Anything else → STOP per the strict error-resolution rule. Surface `$RESP` to the user.

#### 2.2 Verify by re-probing the page

The same probe used in 2.0. After a successful registration, the form must be gone — the page now bounces to `/0DM/o`.

```bash
PAGE2=/c/tmp/dsaew-step2/page-after.html
curl -s -L -b "$COOKIES" -c "$COOKIES" \
  "${INSTANCE_URL}/udd/Site/customSubdomain.apexp" \
  -o "$PAGE2"

if grep -q "Register My Salesforce Site Domain" "$PAGE2"; then
  echo "❌ Domain still NOT registered — registration POST failed silently"; exit 1
else
  echo "✅ Domain registered — Setup page no longer renders the registration form"
fi
```

#### 2.3 Cleanup runtime temp directory

```bash
rm -rf /c/tmp/dsaew-step2
```

Verify (must show no leftovers):

```bash
ls -d /c/tmp/dsaew-step2 2>&1 | grep -v "cannot access"
```

**Cleanup-on-failure policy** (security): the cookie jar `cookies.txt` contains a live OAuth session cookie. **Always delete on both success AND failure paths.** Token leakage risk if left on disk. The page HTML files contain the same session cookie embedded in CSRF tokens and should also always be deleted.

#### 2.4 Report

```text
✅ Step 2 — Register Site Domain: COMPLETE

Org:               <org_alias>
Pre-state:         <NotRegistered | AlreadyRegistered>
POST result:       <registration submitted | skipped (already registered)>
Post-state:        Domain registered (Setup page no longer renders the form)
```

---

### Step 3 — Install Embedded Service Package + Activate Messaging Channel

**🚨 Verified working approach on OrgRetailTest35 on 2026-06-12 (deploy id `0Afbm00000VsCtZCAV`, 30 components Created, 0 failures).** This step matches the manual checklist:

```
- Install Embedded Service Package:
  sf project deploy start -d diy-embeddedservice.

- Activate Messaging Channel:
  sf apex run -f scripts/apex/activateMessagingChannel.apex
```

Pure CLI — no API calls, no Visualforce magic, no metadata templates.

#### 3.1 Deploy `diy-embeddedservice`

```bash
sf project deploy start \
  --target-org <org_alias> \
  --source-dir diy-embeddedservice \
  --json
```

Expected components (verified live — order may vary):

| Type | Name |
|---|---|
| `EmbeddedServiceConfig` | `ESA_Web_Deployment` |
| `MessagingChannel` | `ESA_Channel` |
| `Flow` | `Route_Conversations_to_Agentforce_Service_Agents` |
| `CustomSite` | `ESW_ESA_Web_Deployment_<timestamp>` |
| `Network` | `ESW_ESA_Web_Deployment_<timestamp>` |
| `DigitalExperienceBundle` | `site/ESW_ESA_Web_Deployment_<timestamp>1` |
| `DigitalExperience` | 17 nested children of the bundle |
| `Queue` | `Messaging_Queue` |
| `QueueRoutingConfig` | `Messaging_Routing_Channel` |
| `BrandingSet`, `NetworkBranding`, `StaticResource`, `DigitalExperienceConfig` | one each |

Total: 30 components. Verify the JSON response shows `status: Succeeded`, `success: true`, and `componentFailures: []` (or null). Any failures → STOP per the strict error-resolution rule.

> **Why this also creates an ESW Site that needs a Trusted Domain entry later.** The deploy provisions a brand-new `CustomSite: ESW_ESA_Web_Deployment_<timestamp>` plus its `1`-suffixed sibling. The "Trusted Domains for Inline Frames" allowlist for embedding the agent on the external website lives on **this** new CustomSite. That is the future Roadmap step (currently shown in the Setup UI as `Trusted Domains for Inline Frames` on the ESW deployment site), and it will be added to this skill once verified. **Step 3 only deploys the package — it does not configure the iframe allowlist.**

#### 3.2 Activate the Messaging Channel

```bash
sf apex run \
  --target-org <org_alias> \
  -f scripts/apex/activateMessagingChannel.apex
```

The Apex file ships with the repo and contains:

```apex
MessagingChannel channel = [SELECT Id, IsActive FROM MessagingChannel WHERE DeveloperName='ESA_Channel' LIMIT 1];
channel.IsActive = true;
update channel;
```

Verify the CLI output reads `Compiled successfully.` and `Executed successfully.` (no exceptions). Any `Execute Anonymous error` → STOP per the strict error-resolution rule and surface the apex log.

#### 3.3 Verify via SOQL

```bash
INSTANCE_URL=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")
ACCESS_TOKEN=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['accessToken'])")

curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/query" \
  --data-urlencode "q=SELECT Id, DeveloperName, MasterLabel, IsActive FROM MessagingChannel WHERE DeveloperName='ESA_Channel'" \
  | python -c "
import json, sys
d = json.load(sys.stdin)
recs = d.get('records', [])
if not recs:
    print('❌ ESA_Channel MessagingChannel not found'); sys.exit(1)
ch = recs[0]
print(f\"ESA_Channel id={ch['Id']} | IsActive={ch['IsActive']}\")
sys.exit(0 if ch['IsActive'] else 1)
"
```

`IsActive=True` → proceed to 3.4. `False` or not found → STOP per the strict error-resolution rule.

#### 3.4 Report

```text
✅ Step 3 — Install Embedded Service Package + Activate Messaging Channel: COMPLETE

Org:                       <org_alias>
Deploy id:                 <r.id from 3.1>
Components Created:        <count from 3.1>
Component failures:        0
ESA_Channel.IsActive:      true (verified via SOQL)
ESW Site provisioned:      ESW_ESA_Web_Deployment_<timestamp>  ← Step 4 adds the iframe whitelist entries here
```

---

### Step 4 — Trusted Domains for Inline Frames

**🚨 Verified working approach on OrgRetailTest35 on 2026-06-12 (final deploy id `0Afbm00000VsJ8gCAF`).** Adds **the Experience Cloud Sites Domain** to the **`Trusted Domains for Inline Frames`** list on the ESW_ESA Site that Step 3 provisioned. The list lives on the `CustomSite` metadata as repeated `<siteIframeWhiteListUrls><url>...</url></siteIframeWhiteListUrls>` elements; no separate metadata type exists for it.

**Why exactly one URL — the Experience Cloud Sites Domain:** the only place the embedded service iframe is rendered for this installer is the **DIYStorefront Experience Cloud Site** at `<prefix>.my.site.com/DIYStorefront`. Salesforce only checks the **host** of the parent page (not the path) against this allowlist, so a single host-level entry `<prefix>.my.site.com` covers DIYStorefront and any other Experience Cloud site under the same host. The Salesforce Sites Domain (`*.my.salesforce-sites.com`) and My Domain (`*.my.salesforce.com`) are NOT needed for this installer because the agent is never embedded on Force.com Sites pages or directly on Lightning/Setup pages — only on the Experience Cloud storefront.

| Domain added | Source |
|---|---|
| `<myDomainPrefix>.my.site.com` | Experience Cloud Sites Domain — covers DIYStorefront and all other Experience sites on this org |

**🚨 Salesforce only accepts host-level entries — no scheme, no path.** Verified by deploy errors:

| Tried | Result |
|---|---|
| `https://storm-...my.site.com/DIYStorefront` (full URL with path) | ❌ `Enter a valid URL or URI. Use one of these formats: example.com, example.com:8080, *.example.com, https://example.com, or wss://example.com.` |
| `https://storm-...my.site.com` (host with scheme) | ✅ Works, but stored as-is — the UI shows the scheme |
| `storm-...my.site.com` (host only, no scheme) | ✅ Works — cleanest form, matches the format the UI displays |

**Use the host-only form (no scheme).**

**🚨 The deploy is a FULL replacement.** A `CustomSite` deploy replaces the full `<siteIframeWhiteListUrls>` set — what's in the deployed XML becomes the complete list. Re-deploying with 1 entry when the org has 3 will delete the other 2 (this is exactly how this skill simplified from the earlier 3-URL state to the current 1-URL state — by re-deploying with only the desired entry).

#### 4.1 Locate the ESW_ESA Site

The Step 3 deploy provisions two related Sites: a bare-name one (`ESW_ESA_Web_Deployment_<timestamp>` with `urlPathPrefix` ending in `vforcesi`) and a `1`-suffixed sibling (`...<timestamp>1`). The Setup → Embedded Service Deployments → ESA Web Deployment link points at the **bare-name** Site — that's where the iframe whitelist must live.

```bash
INSTANCE_URL=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")
ACCESS_TOKEN=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['accessToken'])")

ESW_ESA_SITE_NAME=$(curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/query" \
  --data-urlencode "q=SELECT Name FROM Site WHERE Name LIKE 'ESW_ESA_Web_Deployment_%' AND UrlPathPrefix LIKE '%vforcesi' AND Status='Active' ORDER BY Name LIMIT 1" \
  | python -c "
import json, sys
d = json.load(sys.stdin)
recs = d.get('records', [])
print(recs[0]['Name'] if recs else '')
")

if [ -z "$ESW_ESA_SITE_NAME" ]; then
  echo "❌ No active ESW_ESA Site with urlPathPrefix ending '...vforcesi' found. Has Step 3 (deploy diy-embeddedservice) completed?"; exit 1
fi
echo "ESW_ESA Site Name: $ESW_ESA_SITE_NAME"
```

If empty → STOP per the strict error-resolution rule. The most likely cause is Step 3 hasn't been run yet.

#### 4.2 Compute the target Experience Cloud Sites Domain from the instance URL

```bash
# instanceUrl looks like: https://storm-359e620867b1f4.my.salesforce.com
# Extract the My Domain prefix and append .my.site.com (Experience Cloud Sites Domain)
MY_DOMAIN_PREFIX=$(echo "$INSTANCE_URL" | sed -E 's|https?://([^.]+)\..*|\1|')
TARGET_URL="${MY_DOMAIN_PREFIX}.my.site.com"
echo "My Domain prefix:           $MY_DOMAIN_PREFIX"
echo "Target Experience Cloud URL: $TARGET_URL"
```

#### 4.3 Retrieve the CustomSite

```bash
mkdir -p /c/tmp/dsaew-step4
sf project retrieve start \
  --target-org <org_alias> \
  --metadata "CustomSite:${ESW_ESA_SITE_NAME}" \
  --output-dir /c/tmp/dsaew-step4 \
  --json

SITE_FILE="/c/tmp/dsaew-step4/sites/${ESW_ESA_SITE_NAME}.site-meta.xml"
[ -f "$SITE_FILE" ] || { echo "❌ Retrieve did not produce $SITE_FILE"; exit 1; }
```

#### 4.4 Set the iframe whitelist to exactly one entry + deploy

The skill enforces a **canonical single-entry state**: after this step the ESW_ESA Site's iframe whitelist contains exactly `<prefix>.my.site.com` and nothing else. Any pre-existing entries (host-only forms, `https://`-prefixed forms, leftover entries from earlier Step 4 attempts, or extra org-policy URLs the user may have added manually) are **replaced**, not merged. This matches the "set the trusted domain to the Experience Cloud Sites Domain" instruction in the manual checklist.

> If you need to ADD a new entry while preserving custom URLs the user has manually added, see the **Step 4.4 alt — union-merge** section at the end of Step 4 below. The default replace-all behavior is what was verified end-to-end on OrgRetailTest35.

```bash
python << 'PYEOF'
import os, re

site_file = os.environ['SITE_FILE']
target = os.environ['TARGET_URL']
content = open(site_file, encoding='utf-8').read()

# Extract existing <url> values for the report
existing = re.findall(r'<siteIframeWhiteListUrls>\s*<url>([^<]+)</url>\s*</siteIframeWhiteListUrls>', content)
print('Existing entries:', existing)

# Idempotency: if existing == [target] exactly, no-op
if existing == [target]:
    print(f'NoChange: iframe whitelist already contains exactly {target}')
    raise SystemExit(0)

# Replace the entire <siteIframeWhiteListUrls> block set with a single canonical entry
# Strip ALL existing <siteIframeWhiteListUrls>...</siteIframeWhiteListUrls> blocks first
content_new = re.sub(
    r'(    <siteIframeWhiteListUrls>\s*<url>[^<]+</url>\s*</siteIframeWhiteListUrls>\s*)+',
    '',
    content,
    flags=re.MULTILINE,
)
new_block = (
    f'    <siteIframeWhiteListUrls>\n'
    f'        <url>{target}</url>\n'
    f'    </siteIframeWhiteListUrls>\n'
)
content_new, n = re.subn(r'(    <siteType>)', new_block + r'\1', content_new, count=1)
if n != 1:
    raise SystemExit('failed to find <siteType> anchor')

open(site_file, 'w', encoding='utf-8', newline='').write(content_new)
print(f'Wrote 1 entry: {target}')
PYEOF

# Deploy
sf project deploy start \
  --target-org <org_alias> \
  --source-dir /c/tmp/dsaew-step4/sites \
  --json \
  | python -c "
import json, sys
d = json.load(sys.stdin); r = d.get('result', {})
print('status:', r.get('status'), 'success:', r.get('success'), 'id:', r.get('id'))
for c in r.get('details', {}).get('componentSuccesses') or []:
    print(' OK ', c.get('componentType'), '|', c.get('fullName'), '|', c.get('state'))
for c in r.get('details', {}).get('componentFailures') or []:
    print(' FAIL', c.get('componentType'), '|', c.get('fullName'), '|', c.get('problem'))
"
```

- `status: Succeeded` with one `CustomSite` component → proceed to 4.5.
- Any `componentFailures[].problem` mentioning `Enter a valid URL or URI` → STOP. The skill wrote a `<url>` value Salesforce rejects (path, scheme on wrong domain, malformed). Surface the exact failure message and the offending `<url>` line.
- Other deploy failures → STOP per the strict error-resolution rule.

#### 4.5 Verify via SOQL

```bash
SITE_ID=$(curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/query" \
  --data-urlencode "q=SELECT Id FROM Site WHERE Name='${ESW_ESA_SITE_NAME}'" \
  | python -c "import json,sys; print(json.load(sys.stdin)['records'][0]['Id'])")

curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/query" \
  --data-urlencode "q=SELECT Url FROM SiteIframeWhiteListUrl WHERE SiteId='${SITE_ID}' ORDER BY Url" \
  | python -c "
import json, sys, os
d = json.load(sys.stdin)
urls = [r['Url'] for r in d.get('records', [])]
target = os.environ['TARGET_URL']
print('Iframe whitelist on the ESW_ESA Site:')
for u in urls: print(' -', u)
print(f'Target ({target}) present:', target in urls)
print(f'Exactly one entry:', len(urls) == 1)
sys.exit(0 if (target in urls and len(urls) == 1) else 1)
"
```

Target present AND exactly one entry → proceed to 4.6. Either missing → STOP per the strict error-resolution rule and surface the SOQL response.

#### 4.6 Per-step cleanup

Per-step cleanup runs ONLY on success of this step. The Final cleanup section at the end of the skill runs unconditionally as a backstop.

```bash
rm -rf /c/tmp/dsaew-step4
```

#### 4.7 Report

```text
✅ Step 4 — Trusted Domains for Inline Frames: COMPLETE

Org:                  <org_alias>
ESW_ESA Site:         <ESW_ESA_SITE_NAME> (Site Id: <SITE_ID>)
My Domain prefix:     <MY_DOMAIN_PREFIX>
Target URL:           <TARGET_URL>  ← single Experience Cloud Sites Domain entry, host-only form
Pre-deploy entries:   <list from 4.4 Python>
Post-deploy entries:  1 (verified via SOQL)
Component state:      <Changed | NoChange (already exactly this single entry)>
Deploy id:            <id from 4.4 — only when state was Changed>
```

---

#### Step 4.4 alt — union-merge (NOT the default)

If a future need arises to **add** the Experience Cloud Sites Domain while preserving entries the user added manually (e.g. additional partner Experience sites), use this Python rewriter instead of the replace-all variant in 4.4. **This is NOT the default** — it's parked here for reference.

```python
existing_set = set(existing)
if target not in existing_set:
    # Append target to the existing list, preserve order
    final_urls = existing + [target]
else:
    final_urls = existing
# (then re-emit ALL final_urls as <siteIframeWhiteListUrls> blocks before <siteType>)
```

---

### Step 5 — Publish ESA Web Deployment

**🚨 Verified working approach on OrgRetailTest35 on 2026-06-12.** This is the ONLY Playwright-MCP step in the skill — every other step is pure CLI / REST. The Setup UI Publish button on the Embedded Service Deployment detail page calls a private Aura action that no public Metadata / Tooling / Connect REST API surfaces. Driving the actual Setup button is the smallest reliable surface.

**Why Playwright (and not yet another API attempt):** previously verified non-paths on this same org included blunt-PATCHing `EmbeddedServiceConfig.Metadata.urls`, attempting to query `EmbeddedServiceDetail.IsPublished` / `EmbeddedServiceConfigPub` (entity not queryable), and trying 5+ Connect REST `/publish` URL variants (all 404). The only thing that observably moves the deployment to a published state is clicking the page's Publish button.

**The URL is computed, not hardcoded.** The `EmbeddedServiceConfig.Id` is org-specific (15/18-char Salesforce ID where the 4–6th chars encode the org's pod). Look it up at runtime via Tooling SOQL on `EmbeddedServiceConfig.DeveloperName='ESA_Web_Deployment'`. On the verified test org (OrgRetailTest35) the Id was `04Ibm000000siP3EAI` and the working URL was `/lightning/setup/EmbeddedServiceDeployments/04Ibm000000siP3EAI/view` — that exact-shape URL bypasses the Embedded Service list and lands directly on the deployment's detail page where the Publish button lives.

**No verification step.** The Salesforce UI publishes asynchronously. The on-page "Published on:" / "Version:" labels often stay blank for 30+ seconds after a click and there is no public API to query the publish state directly. The user explicitly scoped this step as "click Publish then leave it" — the skill does exactly that and moves on.

#### 5.1 Pre-check: look up the EmbeddedServiceConfig Id via Tooling SOQL

```bash
INSTANCE_URL=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")
ACCESS_TOKEN=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['accessToken'])")

ESA_CONFIG_ID=$(curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/tooling/query" \
  --data-urlencode "q=SELECT Id FROM EmbeddedServiceConfig WHERE DeveloperName='ESA_Web_Deployment' LIMIT 1" \
  | python -c "import json,sys; r=json.load(sys.stdin)['records']; print(r[0]['Id'] if r else '')")

if [ -z "$ESA_CONFIG_ID" ]; then
  echo "❌ EmbeddedServiceConfig 'ESA_Web_Deployment' not found. Has Step 3 completed?"; exit 1
fi
echo "ESA_Web_Deployment Id: $ESA_CONFIG_ID"
echo "Publish URL: ${INSTANCE_URL}/lightning/setup/EmbeddedServiceDeployments/${ESA_CONFIG_ID}/view"
```

> **Why Tooling and not Data API:** `EmbeddedServiceConfig` is a setup metadata entity. The standard Data API (`/services/data/v62.0/query`) responds with `INVALID_TYPE: sObject type 'EmbeddedServiceConfig' is not supported.` — verified on OrgRetailTest35. Use the Tooling endpoint (`/services/data/v62.0/tooling/query`) for setup entities like this one.

#### 5.2 Get a UI session — Salesforce CLI access tokens won't work for Lightning Setup

```bash
# We need a username + password for browser login. The CLI session token is API-only.
# Skill caller passes USERNAME and PASSWORD as args alongside org_alias.
echo "USERNAME=$USERNAME"
echo "PASSWORD=*** (length: ${#PASSWORD})"
```

#### 5.3 Drive Playwright MCP — navigate, log in, click Publish, leave

The whole Playwright sequence is a fixed script. Each step uses the standard Playwright MCP tool from the harness. Pseudo-code to keep this skill file deterministic:

```text
mcp.browser_navigate(url = ${INSTANCE_URL}/lightning/setup/EmbeddedServiceDeployments/${ESA_CONFIG_ID}/view)
# If redirected to /?ec=302&startURL=... (login wall), the page renders Salesforce login.
mcp.browser_snapshot()
# Locate two textboxes (Username, Password) and the Log In button.
mcp.browser_type(target = <Username textbox ref>, text = ${USERNAME})
mcp.browser_type(target = <Password textbox ref>, text = ${PASSWORD})
mcp.browser_click(target = <Log In button ref>)
# After login, Salesforce auto-resolves the original startURL and lands on the deployment detail page.
mcp.browser_wait_for(text = "Publish", time = 20)
mcp.browser_snapshot()  # locate the page's Publish button — its accessible name is
                        # "Publish button to complete changes after editing a deployment."
                        # The button's clickable header text is the literal "Publish".
# Click the page's Publish button. If the snapshot ref is hard to find, fall back to
# evaluate(): document.querySelectorAll('button') filtered to label === 'Publish'.
mcp.browser_click(target = <Publish button ref>)
# Done — leave the page. The publish runs asynchronously in Salesforce.
```

**Concrete fallback when the Publish button is hard to address by Playwright ref** (verified working on OrgRetailTest35):

```javascript
// Run via mcp.browser_evaluate
() => {
  const btns = Array.from(document.querySelectorAll('button'));
  const pub = btns.find(b => /^publish/i.test((b.textContent || '').trim()));
  if (pub) pub.click();
  return { clicked: !!pub, label: pub ? (pub.textContent || '').trim() : null };
}
```

This worked when the snapshot's element ref had become stale after a re-render — the JS-side click goes through cleanly because the element is a plain `<button>` and Salesforce's Aura listener responds to native click events.

> **🚨 Internal Setup endpoint disclaimer.** `/lightning/setup/EmbeddedServiceDeployments/<Id>/view` is the standard Setup URL that `Setup → Feature Settings → Service → Embedded Service → Embedded Service Deployments → <ESA Web Deployment row>` resolves to. The URL shape has been stable across releases but Salesforce does not guarantee it. If a future release breaks it, the fallback is: navigate to `/lightning/setup/EmbeddedServiceDeployments/home`, click the row labeled `ESA Web Deployment`, then click Publish from the resulting detail page.

#### 5.4 No verification — leave the page

The user has explicitly scoped this step as "click Publish then leave it." Do not poll the page, do not re-fetch, do not query an API to confirm publish state. The publish runs asynchronously in Salesforce and there is no public API to query its state.

#### 5.5 Cleanup

Step 5 creates no on-disk artefacts. The Playwright MCP browser session may linger — close it explicitly to avoid a hanging process:

```text
mcp.browser_close()
```

The Final cleanup section at the end of the skill runs unconditionally as a backstop and does not need to delete any Step 5 artefacts.

#### 5.6 Report

```text
✅ Step 5 — Publish ESA Web Deployment: COMPLETE

Org:                       <org_alias>
EmbeddedServiceConfig Id:  <ESA_CONFIG_ID>
Publish URL navigated:     <INSTANCE_URL>/lightning/setup/EmbeddedServiceDeployments/<ESA_CONFIG_ID>/view
Publish button clicked:    yes
Verification:              skipped intentionally (no public API; user scope: "click then leave")
```

**Real-world reference (OrgRetailTest35, 2026-06-12):** EmbeddedServiceConfig Id `04Ibm000000siP3EAI`. Login via `storm.359e620867b1f4@salesforce.com`, navigated to `/lightning/setup/EmbeddedServiceDeployments/04Ibm000000siP3EAI/view`, clicked the Publish button labeled "Publish button to complete changes after editing a deployment.", left the page.

---

### Step 6 — Create a New Version of the Omni-Channel Flow

**🚨 Verified working approach on OrgRetailTest35 on 2026-06-12 (deploy id `0Afbm00000VsXA1CAN`).** The repo's `Route_Conversations_to_Agentforce_Service_Agents.flow-meta.xml` ships with **4 stale Salesforce IDs** that point at a different (source) org. The manual checklist's "deactivate → re-pick service channel → re-pick agent → re-pick queue → save as new version → activate" sequence is exactly Salesforce's UI nudge to refresh those 4 IDs against the current org. This skill does the same refresh declaratively: look up current IDs via SOQL, substitute them into a staged copy of the XML, deploy.

**Salesforce auto-handles version transitions on flow deploy.** When `sf project deploy start` deploys a flow XML whose previous version was `Active`, Salesforce automatically:
1. Deactivates the previous version (sets `Status: Obsolete`)
2. Creates a new version with `VersionNumber = previous + 1`
3. Activates the new version (sets `Status: Active`)

No Tooling API PATCH is needed. No explicit deactivate-first step is needed. **One `sf project deploy start` call replaces the entire 6-click manual sequence.**

**The 4 stale values to replace** (verified by inspecting the repo XML):

| Field name in XML | Stale value (foreign org, `*fj0*` prefix) | Fix: query the current org for |
|---|---|---|
| `serviceChannelId` | `0N9fj000001eKsICAU` | `SELECT Id FROM ServiceChannel WHERE DeveloperName='sfdc_livemessage'` |
| `queueId` | `00Gfj000006tturEAA` | `SELECT Id FROM Group WHERE Type='Queue' AND DeveloperName='Messaging_Queue'` |
| `copilotId` | `0Xxfj000001RpOXCA0` | `SELECT Id FROM BotDefinition WHERE MasterLabel='DIY Assistant'` |
| `copilotLabel` | `DIY Service Agent` | The literal string `DIY Assistant` (the label the user sees in Setup) |

The other input parameters in the flow (`serviceChannelLabel`, `serviceChannelDevName`, `routingType`, `queueLabel`) are **org-independent strings** — they don't need refreshing.

#### 6.1 Look up the 4 current org IDs

```bash
INSTANCE_URL=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['instanceUrl'])")
ACCESS_TOKEN=$(sf org display --target-org <org_alias> --json | python -c "import json,sys; print(json.load(sys.stdin)['result']['accessToken'])")

# ServiceChannel for LiveMessage
SERVICE_CHANNEL_ID=$(curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/query" \
  --data-urlencode "q=SELECT Id FROM ServiceChannel WHERE DeveloperName='sfdc_livemessage' LIMIT 1" \
  | python -c "import json,sys; r=json.load(sys.stdin)['records']; print(r[0]['Id'] if r else '')")

# Queue Messaging_Queue
QUEUE_ID=$(curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/query" \
  --data-urlencode "q=SELECT Id FROM Group WHERE Type='Queue' AND DeveloperName='Messaging_Queue' LIMIT 1" \
  | python -c "import json,sys; r=json.load(sys.stdin)['records']; print(r[0]['Id'] if r else '')")

# BotDefinition DIY Assistant
COPILOT_ID=$(curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/query" \
  --data-urlencode "q=SELECT Id FROM BotDefinition WHERE MasterLabel='DIY Assistant' LIMIT 1" \
  | python -c "import json,sys; r=json.load(sys.stdin)['records']; print(r[0]['Id'] if r else '')")

# All three must be non-empty
if [ -z "$SERVICE_CHANNEL_ID" ] || [ -z "$QUEUE_ID" ] || [ -z "$COPILOT_ID" ]; then
  echo "❌ Missing IDs:"
  echo "  ServiceChannel(LiveMessage): $SERVICE_CHANNEL_ID"
  echo "  Group(Messaging_Queue):      $QUEUE_ID"
  echo "  BotDefinition(DIY Assistant): $COPILOT_ID"
  echo "Has Step 3 (deploy diy-embeddedservice) completed? It provisions all three."
  exit 1
fi
echo "ServiceChannel(LiveMessage):   $SERVICE_CHANNEL_ID"
echo "Group(Messaging_Queue):        $QUEUE_ID"
echo "BotDefinition(DIY Assistant):  $COPILOT_ID"
```

If any ID is missing → STOP per the orchestrator's strict error-resolution rule. The most likely cause is Step 3 hasn't been run yet (it ships the messaging channel, queue, and bot).

#### 6.2 Stage the flow XML and substitute the 4 stale values

```bash
mkdir -p /c/tmp/dsaew-step6/flows
cp diy-embeddedservice/main/default/flows/Route_Conversations_to_Agentforce_Service_Agents.flow-meta.xml \
   /c/tmp/dsaew-step6/flows/

FLOW_FILE=/c/tmp/dsaew-step6/flows/Route_Conversations_to_Agentforce_Service_Agents.flow-meta.xml

python << PYEOF
p = r"$FLOW_FILE"
sc, q, c = "$SERVICE_CHANNEL_ID", "$QUEUE_ID", "$COPILOT_ID"
s = open(p, encoding='utf-8').read()

# The 4 stale values that the manual UI workflow refreshes
replacements = {
    '0N9fj000001eKsICAU': sc,                                              # serviceChannelId
    '00Gfj000006tturEAA': q,                                               # queueId
    '0Xxfj000001RpOXCA0': c,                                               # copilotId
    '<stringValue>DIY Service Agent</stringValue>':
        '<stringValue>DIY Assistant</stringValue>',                        # copilotLabel
}
for old, new in replacements.items():
    if old not in s:
        # Idempotency: if the file was already-corrected (e.g. previous Step 6 run), skip
        print(f'(skip) {old[:40]}... not found — already replaced or repo XML changed')
        continue
    s = s.replace(old, new)
    print(f'replaced {old[:40]}... -> {new[:40]}...')
open(p, 'w', encoding='utf-8', newline='').write(s)
PYEOF
```

> **Why the 4 stale IDs are in the repo at all:** the flow XML was authored in a different Salesforce org and committed to the repo. Salesforce IDs are 18-char org-specific identifiers (the 4–6th chars indicate the source org's pod/instance), so any flow that hardcodes IDs and gets shared across orgs has this problem. The manual checklist's "re-pick the dropdown values" sequence is the UI workaround; this skill's substitution is the declarative equivalent.

#### 6.3 Deploy — Salesforce handles the version dance

```bash
sf project deploy start \
  --target-org <org_alias> \
  --source-dir /c/tmp/dsaew-step6/flows \
  --json \
  | python -c "
import json, sys
d = json.load(sys.stdin); r = d.get('result', {})
print('status:', r.get('status'), 'success:', r.get('success'), 'id:', r.get('id'))
for c in r.get('details', {}).get('componentSuccesses') or []:
    print(' OK ', c.get('componentType'), '|', c.get('fullName'), '|', c.get('state'))
for c in r.get('details', {}).get('componentFailures') or []:
    print(' FAIL', c.get('componentType'), '|', c.get('fullName'), '|', c.get('problem'))
"
```

Expected JSON shape on success:

```json
{
  "result": {
    "status": "Succeeded",
    "success": true,
    "id": "0Afbm00000VsXA1CAN",
    "details": {
      "componentSuccesses": [
        { "componentType": "Flow", "fullName": "Route_Conversations_to_Agentforce_Service_Agents", "state": "Changed" }
      ]
    }
  }
}
```

- `status: Succeeded` → proceed to 6.4.
- `status: Failed` with `INVALID_CROSS_REFERENCE_KEY` on `serviceChannelId` / `queueId` / `copilotId` → STOP. The lookup in 6.1 returned a stale value or the entity was deleted between 6.1 and 6.3. Re-run 6.1.
- Other failures → STOP per the strict error-resolution rule.

#### 6.4 Verify v2 is Active and has the corrected IDs

```bash
curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/tooling/query" \
  --data-urlencode "q=SELECT Id, VersionNumber, Status, LastModifiedDate FROM Flow WHERE MasterLabel='Route Conversations to Agentforce Service Agents' ORDER BY VersionNumber DESC LIMIT 5" \
  | python -m json.tool

# Read the active version's Metadata and assert the 4 corrected values
ACTIVE_FLOW_ID=$(curl -s -G -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/tooling/query" \
  --data-urlencode "q=SELECT Id FROM Flow WHERE MasterLabel='Route Conversations to Agentforce Service Agents' AND Status='Active' LIMIT 1" \
  | python -c "import json,sys; r=json.load(sys.stdin)['records']; print(r[0]['Id'] if r else '')")

curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "${INSTANCE_URL}/services/data/v62.0/tooling/sobjects/Flow/${ACTIVE_FLOW_ID}" \
  | python -c "
import json, sys, os
d = json.load(sys.stdin)
md = d.get('Metadata', {})
print(f\"VersionNumber={d['VersionNumber']}, Status={d['Status']}\")
ip_map = {}
for ac in md.get('actionCalls', []) or []:
    if ac.get('name') == 'Route_to_agent':
        for ip in ac.get('inputParameters', []):
            v = ip.get('value', {})
            if v: ip_map[ip.get('name')] = v.get('stringValue')
expected = {
    'serviceChannelId': os.environ['SERVICE_CHANNEL_ID'],
    'queueId': os.environ['QUEUE_ID'],
    'copilotId': os.environ['COPILOT_ID'],
    'copilotLabel': 'DIY Assistant',
}
ok = True
for k, want in expected.items():
    got = ip_map.get(k)
    mark = '✅' if got == want else '❌'
    if got != want: ok = False
    print(f'  {mark} {k}: {got}')
sys.exit(0 if ok else 1)
" SERVICE_CHANNEL_ID="$SERVICE_CHANNEL_ID" QUEUE_ID="$QUEUE_ID" COPILOT_ID="$COPILOT_ID"
```

All 4 values must match. Any `❌` → STOP per the strict error-resolution rule and surface the SOQL response.

#### 6.5 Per-step cleanup

```bash
rm -rf /c/tmp/dsaew-step6
```

Per-step cleanup runs ONLY on success of this step. The Final cleanup section at the end of the skill runs unconditionally as a backstop.

#### 6.6 Report

```text
✅ Step 6 — Create a New Version of the Omni-Channel Flow: COMPLETE

Org:                      <org_alias>
Flow:                     Route Conversations to Agentforce Service Agents
Pre-deploy active version: v<N> (auto-deactivated)
New active version:        v<N+1> (verified Status='Active')
Refreshed IDs:
  • serviceChannelId =     <SERVICE_CHANNEL_ID>
  • queueId =              <QUEUE_ID>
  • copilotId (DIY Assistant) = <COPILOT_ID>
  • copilotLabel =         DIY Assistant
Deploy id:                 <r.id from 6.3>
Component state:           Changed
```

---

## Final cleanup (MANDATORY before skill returns)

After all completed steps' per-step cleanup runs (Step 1.4, Step 2.3), execute one final cleanup pass that nukes **every** artefact this skill could have created — even if a per-step cleanup was skipped, blocked by a `Permission denied`, or interrupted before reaching its own cleanup. This is a security backstop: several of these temp files contain a live OAuth session cookie or a frontdoor URL with the access token in the query string.

**Always run this on BOTH the success and failure paths.** On a partial-failure path (e.g. Step 2 succeeded, Step 3 failed) the per-step cleanups for completed steps already deleted their own files, but the failed step may have left token-bearing artefacts on disk — that's exactly why this final pass exists.

```bash
# Step 1 staging dirs
rm -rf /c/tmp/dsaew-step1
rm -rf /c/tmp/dsaew-step1-verify

# Step 2 staging dir (cookies.txt, page.html, page-after.html, postbody.txt, postresp.html)
rm -rf /c/tmp/dsaew-step2

# Step 3 has no on-disk staging — `sf project deploy start -d diy-embeddedservice` operates on
# the existing repo source and `sf apex run -f scripts/apex/...` reads an existing repo file. No
# temp dirs are created by Step 3, so nothing to delete here.

# Step 4 staging dir (retrieved CustomSite XML for the ESW_ESA Site)
rm -rf /c/tmp/dsaew-step4

# Step 5 has no on-disk staging — Playwright MCP browses Setup directly. The MCP browser is closed
# in 5.5 (mcp.browser_close()). Nothing to delete here.

# Step 6 staging dir (corrected Flow XML)
rm -rf /c/tmp/dsaew-step6

# Verification (must show no leftovers)
ls -d /c/tmp/dsaew-step1 /c/tmp/dsaew-step1-verify /c/tmp/dsaew-step2 /c/tmp/dsaew-step4 /c/tmp/dsaew-step6 2>&1 | grep -v "cannot access"
```

**Token-leakage rules** (these files MUST be deleted even on a failure path):

| File | Why it's sensitive |
|---|---|
| `/c/tmp/dsaew-step2/cookies.txt` | Contains the live `sid` session cookie set by `/secur/frontdoor.jsp?sid=<token>` |
| `/c/tmp/dsaew-step2/page.html` | Server-rendered HTML embeds the access token in a few internal links and the four ViewState fields can be replayed against this org for as long as the session lasts |
| `/c/tmp/dsaew-step2/postbody.txt` | URL-encoded form body that includes the four ViewState fields |
| `/c/tmp/dsaew-step2/postresp.html` | Response from the registration POST; replayable by anyone with shell access until the session expires |

**Repo files this skill never touches** — do NOT delete:
- `diy-embeddedservice/**` (repo source consumed by Step 3.1)
- `scripts/apex/activateMessagingChannel.apex` (repo source consumed by Step 3.2)
- `.claude/**` (this skill itself + other skills)

---

## Important Rules

- 🚨 **Strict error-resolution rule** (inherited from orchestrator AGENT.md): if any sub-step fails or returns an error, STOP, try the documented recovery first, and surface the error to the user with full details. Do NOT advance to the next sub-step until the user explicitly says "proceed".
- 🚨 **Never-disable guard:** the only allowed payload for `enableLiveMessage` is `true`. There is no path in this skill that writes `false`. Do not add one.
- ❌ **Do NOT modify any other working skill** under `.claude/skills/` to extend this one. New steps are added by editing THIS skill's `SKILL.md` only.
- ❌ **Do NOT ship a template `metadata/` folder.** Step 1 retrieves the relevant metadata from the org at runtime, edits in place, deploys, and cleans up. Templates would drift from what the org actually accepts across API versions.
- ❌ **Do NOT skip the Final cleanup section.** Step 2 writes a session-cookie jar and a frontdoor-token-bearing HTML page to `/c/tmp/dsaew-step2/`. Leaving those on disk is a token-leakage risk. The Final cleanup runs unconditionally on both the success path AND every failure path.
- ❌ **Do NOT use full-URL or path-bearing entries in the iframe whitelist (Step 4).** Salesforce only accepts host-only forms (`example.com`, `*.example.com`, `https://example.com`, `wss://example.com`, or `example.com:8080`). Anything else fails the deploy with `Enter a valid URL or URI`. The skill writes bare host names — no scheme, no path.
- ❌ **Do NOT trust the `<siteIframeWhiteListUrls>` block as additive.** A `CustomSite` deploy is a FULL replacement of the block. Re-deploying with 1 entry when the org has 3 deletes 2. Step 4's Python rewriter writes a canonical single-entry state (just the Experience Cloud Sites Domain) — any extra entries the user added manually will be dropped. Use the `Step 4.4 alt — union-merge` variant if you need additive behaviour.
- ❌ **Do NOT explicitly deactivate the previous flow version before deploying Step 6.** `sf project deploy start` against a flow XML whose previous version was Active triggers Salesforce's automatic version transition (old→Obsolete + new→Active). Deactivating first via Tooling API is unnecessary and risks leaving the org in a no-active-version state if the deploy then fails.
- ❌ **Do NOT use Tooling API PATCH to set `Flow.Status='Active'` after Step 6's deploy.** It's redundant — Salesforce already activated the new version automatically. The PATCH is only needed when the previous version was Inactive (rare in our installer chain).
- ✅ **Idempotent:** re-running Step 1 on an org where Messaging is already enabled is a no-op (Step 1.1 short-circuits). Re-running Step 2 on an org where the Sites domain is already registered is a no-op (Step 2.0 short-circuits — the page no longer renders the registration form). Re-running Step 3 deploys the same package; `MessagingChannel.IsActive=true` is already true on a re-run, the Apex `update` is a no-op DML. Re-running Step 4 when the iframe whitelist already contains exactly the single Experience Cloud Sites Domain entry is a no-op (Step 4.4's Python check `existing == [target]` exits before deploying). Re-running Step 6 when the staged XML matches the active version's content creates an identical v3 — Salesforce still does the version dance, but the user's runtime state is unchanged. The Python substitution loop's "(skip) ... already replaced" branch makes repeated runs visibly diff-clean.
- ✅ **One-file skill (`SKILL.md`):** no metadata folder. Step 1 uses Metadata API runtime retrieve; Step 2 uses an internal Visualforce a4j POST (no metadata file required); Step 3 uses pure CLI (`sf project deploy start` against the existing `diy-embeddedservice/` repo source + `sf apex run` against the existing `scripts/apex/activateMessagingChannel.apex`); Step 4 uses Metadata API runtime retrieve + edit-in-place + redeploy of the `CustomSite` for the ESW_ESA Site that Step 3 provisioned; Step 5 is the only Playwright-MCP step — it computes the Setup URL from a Tooling SOQL lookup of `EmbeddedServiceConfig.DeveloperName='ESA_Web_Deployment'`, drives the browser to log in and click the Publish button, then leaves; Step 6 reads the repo's flow XML, substitutes 4 stale IDs with current org values from SOQL lookups, and redeploys via Metadata API (Salesforce auto-handles the version transition).
- ❌ **Do NOT verify Step 5's publish state.** The Setup UI publishes asynchronously and there is no public API to query the result. The user has explicitly scoped Step 5 as "click Publish then leave it." Do not poll the page, re-fetch, or call an API in an attempt to confirm — there is none.
- ❌ **Do NOT hardcode the EmbeddedServiceConfig Id in Step 5.** The Id is org-specific (15/18-char Salesforce ID where the 4–6th chars encode the org's pod). Always look it up at runtime via Tooling SOQL. The verified-test Id `04Ibm000000siP3EAI` is for OrgRetailTest35 only and will not work on any other org.

---

## Example Usage

### Example 1 — Step 1 only

**User:** "Enable Messaging Channel on OrgRetailTest35"

**Skill:**
1. Retrieves current `LiveMessageSettings` from the org → `enableLiveMessage = false`
2. In-place edits `/c/tmp/dsaew-step1/settings/LiveMessage.settings-meta.xml` → `enableLiveMessage = true`
3. Deploys via `sf project deploy start --source-dir /c/tmp/dsaew-step1/settings` → `state: Changed`
4. Re-retrieves to verify → `enableLiveMessage = true` ✅
5. Cleans up `/c/tmp/dsaew-step1*` directories
6. Reports the deploy id, the state transition, and verified post-deploy value

### Example 2 — Step 2 (Register Site Domain)

**User:** "Register the Salesforce Site domain on OrgRetailTest35"

**Skill:**
1. Frontdoor-authenticates: `curl /secur/frontdoor.jsp?sid=<token>` → cookie jar at `/c/tmp/dsaew-step2/cookies.txt`
2. Fetches `/udd/Site/customSubdomain.apexp` → page HTML at `/c/tmp/dsaew-step2/page.html`
3. Pre-check: page contains `"Register My Salesforce Site Domain"` → `STATE=NotRegistered`, proceed
4. Extracts the four `com.salesforce.visualforce.ViewState*` fields from the HTML
5. Builds form-urlencoded body (`AJAXREQUEST=_viewRoot`, `termsCB=on`, `registerDomain=...`, ViewState fields) → `/c/tmp/dsaew-step2/postbody.txt`
6. POSTs to `/udd/Site/customSubdomain.apexp` → response is `Ajax-Response: redirect, Location: /0DM/o` ✅
7. Re-fetches the page → registration form is gone (page bounces to `/0DM/o`) ✅
8. Final cleanup deletes `/c/tmp/dsaew-step2/` (token-leakage protection — runs on success AND failure paths)
9. Reports `Pre-state: NotRegistered, Post-state: Domain registered`

### Example 3 — Step 3 (Install Embedded Service Package + Activate Messaging Channel)

**User:** "Install the embedded service package on OrgRetailTest35"

**Skill:**
1. `sf project deploy start -d diy-embeddedservice --target-org OrgRetailTest35 --json` → 30 components Created (`EmbeddedServiceConfig`, `MessagingChannel`, `Flow`, `CustomSite`, `DigitalExperienceBundle`, `Network`, `Queue`, etc.), 0 failures
2. `sf apex run -f scripts/apex/activateMessagingChannel.apex --target-org OrgRetailTest35` → `Compiled successfully. Executed successfully.` (1 SOQL, 1 DML)
3. Verifies via `SELECT IsActive FROM MessagingChannel WHERE DeveloperName='ESA_Channel'` → `IsActive: true` ✅
4. Reports the deploy id, component count, and verified `ESA_Channel.IsActive = true`
5. Step 3 creates no on-disk artefacts — Final cleanup is still run as a backstop in case earlier steps were also part of the same skill invocation

### Example 4 — Step 4 (Trusted Domains for Inline Frames)

**User:** "Add the Experience Cloud Sites Domain to the embedded service iframe whitelist on OrgRetailTest35"

**Skill:**
1. Locates the ESW_ESA Site provisioned by Step 3 → `Name='ESW_ESA_Web_Deployment_<timestamp>'`, `urlPathPrefix` ending `vforcesi`
2. Computes My Domain prefix from `instanceUrl` → e.g. `storm-359e620867b1f4`
3. Computes the single target host: `<prefix>.my.site.com` (Experience Cloud Sites Domain)
4. `sf project retrieve start --metadata "CustomSite:<NAME>"` → `/c/tmp/dsaew-step4/sites/<NAME>.site-meta.xml`
5. Reads existing `<siteIframeWhiteListUrls>` blocks:
   - **Already exactly `[target]`** → `state: NoChange`, skip deploy, jump to verify
   - **Anything else** (empty / different / extra entries) → strips ALL existing blocks, writes one canonical `<siteIframeWhiteListUrls><url>{target}</url></siteIframeWhiteListUrls>`, deploys via `sf project deploy start --source-dir`
6. Verifies via `SELECT Url FROM SiteIframeWhiteListUrl WHERE SiteId='<id>'` → exactly one entry, equal to target ✅
7. Per-step cleanup deletes `/c/tmp/dsaew-step4/`
8. Reports the deploy id, pre-state entries, and the post-deploy single-entry whitelist

**Real-world deploy id reference (OrgRetailTest35, 2026-06-12):** `0Afbm00000VsJ8gCAF` — simplified the iframe whitelist on `ESW_ESA_Web_Deployment_1768908454395` from 2 entries (`storm-...my.site.com` + `storm-...my.salesforce.com`) down to exactly 1 entry (`storm-...my.site.com`). The earlier 3-entry deploy id `0Afbm00000VsO57CAF` represents an older variant that included Salesforce Sites Domain and My Domain — those were dropped because only the Experience Cloud Sites Domain is needed for the DIYStorefront embedding scenario.

### Example 5 — Step 5 (Publish ESA Web Deployment)

**User:** "Publish the ESA Web Deployment on OrgRetailTest35"

**Skill:**
1. Tooling SOQL: `SELECT Id FROM EmbeddedServiceConfig WHERE DeveloperName='ESA_Web_Deployment'` → `04Ibm000000siP3EAI`
2. Computes Publish URL: `https://storm-359e620867b1f4.my.salesforce.com/lightning/setup/EmbeddedServiceDeployments/04Ibm000000siP3EAI/view`
3. `mcp.browser_navigate(url=...)` — Salesforce redirects to `/?ec=302&startURL=...` (login wall)
4. Snapshot finds Username + Password textboxes → `mcp.browser_type` fills `storm.359e620867b1f4@salesforce.com` + `orgfarm1234`
5. `mcp.browser_click` on Log In → page lands on `/lightning/setup/EmbeddedServiceDeployments/04Ibm000000siP3EAI/view`
6. `mcp.browser_wait_for(text="Publish", time=15)` → page renders
7. `mcp.browser_click` on the Publish button (accessible name: "Publish button to complete changes after editing a deployment.") OR fallback `mcp.browser_evaluate` with the JS finder — verified `clicked: true, label: "Publish"`
8. Leaves the page — no verification (per scope: "click Publish then leave it"). The Salesforce-side publish runs asynchronously.
9. `mcp.browser_close()` to release the MCP browser session

**Real-world reference (OrgRetailTest35, 2026-06-12):** EmbeddedServiceConfig Id `04Ibm000000siP3EAI`. Login user `storm.359e620867b1f4@salesforce.com`. Publish click confirmed via `browser_evaluate` returning `{ clicked: true, label: "Publish" }`.

### Example 6 — Step 6 (Create a New Version of the Omni-Channel Flow)

**User:** "Refresh the routing flow so the stale IDs from the source-org repo XML get replaced with this org's actual IDs"

**Skill:**
1. SOQL lookups against the current org:
   - `SELECT Id FROM ServiceChannel WHERE DeveloperName='sfdc_livemessage'` → `0N9bm000003I46gCAC`
   - `SELECT Id FROM Group WHERE Type='Queue' AND DeveloperName='Messaging_Queue'` → `00Gbm00000Kg1llEAB`
   - `SELECT Id FROM BotDefinition WHERE MasterLabel='DIY Assistant'` → `0Xxbm000002DEqQCAW`
2. Stages `diy-embeddedservice/.../Route_Conversations_to_Agentforce_Service_Agents.flow-meta.xml` to `/c/tmp/dsaew-step6/flows/`
3. Python substitutes the 4 stale values: `serviceChannelId`, `queueId`, `copilotId` (each replaced with the SOQL result) + `<stringValue>DIY Service Agent</stringValue>` → `<stringValue>DIY Assistant</stringValue>`
4. `sf project deploy start --source-dir /c/tmp/dsaew-step6/flows --json` → `Status: Succeeded`. Salesforce auto-deactivates v1 (sets `Status: Obsolete`) and auto-activates v2 (sets `Status: Active`)
5. Verifies via Tooling SOQL → v2 is `Active`, all 4 fields match the corrected values ✅
6. Per-step cleanup deletes `/c/tmp/dsaew-step6/`
7. Reports the deploy id, version transition, and the 4 refreshed values

**Real-world deploy id reference (OrgRetailTest35, 2026-06-12):** `0Afbm00000VsXA1CAN` — went from `v1 (Active, with 4 stale source-org IDs)` → `v1 (Obsolete) + v2 (Active, with the 4 corrected current-org IDs)`. Single `sf project deploy start` call replaced the entire 6-click manual sequence (deactivate → re-pick service channel → re-pick agent → re-pick queue → save as new version → activate).

---

## Failure scenarios (and where the strict rule applies)

| Failure | Sub-step | Action |
|---|---|---|
| `sf org display` returns "no such org" | (precondition) | STOP. Tell user to run `sf org login web -a <alias>`. |
| **Step 1** ||
| Step 1.1 retrieve returns `Failed` or empty file | 1.1 | STOP. Surface CLI output. Likely the org doesn't expose `Settings:LiveMessage`. |
| Pre-deploy state is neither `true` nor `false` (e.g. file malformed) | 1.1 | STOP. Surface the file contents. |
| `sed` edit fails or grep verification doesn't show `true` | 1.2 | STOP. Surface the file. |
| Deploy returns `status: Failed` | 1.2 | STOP. Surface `componentFailures[].problem`. |
| Post-deploy verify still shows `false` | 1.3 | STOP. Surface re-retrieved file. |
| **Step 2** ||
| `frontdoor.jsp` returns login form (cookie jar empty) | 2.0 | STOP. CLI session expired — user must run `sf org login web -a <alias>` and retry. |
| `customSubdomain.apexp` page fetch returns non-200 or empty body | 2.0 | STOP. Surface page content + HTTP code. Likely a setup-domain redirect issue. |
| Required ViewState fields missing in retrieved page HTML | 2.1 | STOP. Salesforce changed the page structure. Surface the page HTML for human inspection. |
| POST response is NOT `Ajax-Response: redirect → /0DM/o` | 2.1 | STOP. Surface the response body. Either ToU acceptance failed or the form contract changed. |
| Verify probe still finds the registration form after POST | 2.2 | STOP. Surface the post-POST page HTML. The POST silently failed despite returning success-shaped XML. |
| **Step 3** ||
| `sf project deploy start -d diy-embeddedservice` returns `Failed` | 3.1 | STOP. Surface `componentFailures[].problem`. Common causes: missing `LiveMessageSettings.enableLiveMessage = true` (Step 1 not done) or unregistered Sites domain (Step 2 not done). |
| `sf apex run` reports compile error or `Execute Anonymous error` | 3.2 | STOP. Surface the apex log. Most likely cause: Step 3.1 didn't complete, so `MessagingChannel.ESA_Channel` doesn't exist. |
| Verify shows `IsActive=False` after Apex run | 3.3 | STOP. Surface SOQL response. Apex DML committed but `IsActive` didn't flip — investigate validation rules / org permissions. |
| **Step 4** ||
| No active ESW_ESA Site with `urlPathPrefix` ending `vforcesi` found | 4.1 | STOP. Step 3 (deploy `diy-embeddedservice`) hasn't completed or its CustomSite was renamed. |
| `sf project retrieve` produces no Site XML file | 4.3 | STOP. Surface CLI output. The ESW_ESA Site name from 4.1 didn't match a deployable CustomSite member. |
| `<siteType>` anchor not found in retrieved XML | 4.4 | STOP. Salesforce changed the CustomSite schema or the retrieved file is empty. Surface `$SITE_FILE`. |
| Deploy fails with `Enter a valid URL or URI` | 4.4 | STOP. The skill wrote a `<url>` value Salesforce rejects. Verify all entries are bare hosts (no scheme, no path). Surface the offending `<url>` line. |
| Deploy fails for any other reason | 4.4 | STOP. Surface `componentFailures[].problem`. |
| Post-deploy SOQL verify shows the target URL absent OR more than 1 entry remains | 4.5 | STOP. Surface the SOQL response and the deployed `$SITE_FILE` for diff. Either the deploy didn't apply (deferred-deploy artefact) or the rewriter's strip-all regex missed an existing block (anchor mismatch in the regex). |
| **Step 5** ||
| Tooling SOQL returns 0 records for `EmbeddedServiceConfig.DeveloperName='ESA_Web_Deployment'` | 5.1 | STOP. Step 3 (deploy `diy-embeddedservice`) hasn't completed — it provisions the EmbeddedServiceConfig. |
| Browser navigate fails / page never loads / login redirect loops | 5.3 | STOP. Surface the page URL + console errors. Most likely cause: bad USERNAME/PASSWORD, MFA prompt, or org IP restriction. The skill cannot bypass these — user must resolve manually. |
| Snapshot does not contain "Publish" text after 20s wait | 5.3 | STOP. The deployment detail page never rendered. Verify the URL by opening it manually. The most likely cause is the Id from 5.1 was wrong (different org, stale Id). |
| `browser_evaluate` fallback returns `clicked: false` | 5.3 | STOP. The Publish button is not on the page (already published? deactivated deployment?). Surface a screenshot for human inspection. |
| **Step 6** ||
| One or more of the 3 SOQL ID lookups returns 0 records | 6.1 | STOP. The current org doesn't have the prerequisite entity. Most likely Step 3 (deploy `diy-embeddedservice`) hasn't completed — it provisions `ServiceChannel(LiveMessage)`, `Group(Messaging_Queue)`, and `BotDefinition(DIY Assistant)`. Surface the missing entity name. |
| Python substitution prints `(skip) ...` for ALL 4 values on first run | 6.2 | This is fine ONLY if the deploy below proceeds and v+1 is created — that means the repo XML was already pre-corrected by an earlier run. If the substitution skipped because the repo file's stale IDs are different from what's documented here, the skill's hardcoded "stale value" list is out of date. STOP and surface the file. |
| Deploy returns `INVALID_CROSS_REFERENCE_KEY` on `serviceChannelId` / `queueId` / `copilotId` | 6.3 | STOP. The lookup in 6.1 returned a stale value or the entity was deleted between 6.1 and 6.3. Re-run 6.1. |
| Deploy returns `Failed` for any other reason | 6.3 | STOP. Surface `componentFailures[].problem`. |
| Verify shows v_new is `Inactive` instead of `Active` | 6.4 | STOP. Salesforce did not auto-activate the new version. The previous version may have been Inactive (rare in our installer chain). Manually PATCH `Flow.Status='Active'` via Tooling API on the new version's Id, then re-run 6.4. |
| Verify shows v_new is Active but one of the 4 fields doesn't match | 6.4 | STOP. Surface the diff. Salesforce accepted the deploy but a field didn't apply — likely an org-level validation rule on the flow input parameter. |

---

## Scope (6 steps total — fixed)

The skill scope is fixed at 6 steps. Anything not on this list is **deliberately out of scope** and must NOT be added without an explicit instruction from the user.

| Step | Status | Pattern |
|---|---|---|
| 1. Enable Messaging Channel | ✅ Implemented | Metadata API runtime retrieve + edit-in-place + deploy of `LiveMessageSettings` |
| 2. Register Site Domain | ✅ Implemented | Visualforce a4j POST against the internal `/udd/Site/customSubdomain.apexp` Setup endpoint |
| 3. Install Embedded Service Package + Activate Messaging Channel | ✅ Implemented | Pure CLI: `sf project deploy start -d diy-embeddedservice` + `sf apex run -f scripts/apex/activateMessagingChannel.apex` |
| 4. Trusted Domains for Inline Frames | ✅ Implemented | Metadata API runtime retrieve + Python rewriter (canonical single Experience Cloud Sites Domain entry, host-only) + redeploy `CustomSite` |
| 5. Publish ESA Web Deployment | ✅ Implemented (Playwright MCP — only browser step in skill) | Tooling SOQL on `EmbeddedServiceConfig.DeveloperName='ESA_Web_Deployment'` to get the Id, then `browser_navigate` to `/lightning/setup/EmbeddedServiceDeployments/<Id>/view`, log in if redirected, click the page's Publish button (accessible name `"Publish button to complete changes after editing a deployment."`, fallback `evaluate(document.querySelectorAll('button').find(label === 'Publish'))`), leave. No public API surfaces this — the Setup UI button calls a private Aura action and there is no documented Metadata / Tooling / Connect REST endpoint to query the publish state, so the skill does not verify the result. |
| 6. Create a New Version of the Omni-Channel Flow | ✅ Implemented | SOQL lookup of current org IDs (`ServiceChannel`/`Group`/`BotDefinition`) + Python substitution of repo's stale source-org IDs + Metadata API redeploy of the flow XML. Salesforce auto-handles the version transition (old→Obsolete + new→Active). |

**Out of scope (NOT in this skill):**

- ❌ CORS Configuration — adding entries to `CorsWhitelistOrigin` (external website URL, `*.my.salesforce-scrt.com`, CloudFront image host).
- ❌ Trusted URL / CSP Configuration — adding entries to `CspTrustedSite` (external website URL with `frame-src`, CloudFront images host with `img-src + style-src`).

These are intentionally NOT part of this skill. The user has scoped this skill to exactly the 6 steps above. If a future user asks to add CORS or CSP automation, that is a **separate skill**.

No shipped metadata templates anywhere in this skill — every step retrieves what it needs from the org at runtime, edits in place, and redeploys.
