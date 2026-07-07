---
name: setup-commerce-site
description: Setup Experience Cloud Commerce Store (LWR) site and activate it. Auto-executes site creation, monitors job status, and activates - no user interaction or confirmation needed.
---

# setup-commerce-site

## Purpose

Create and activate an Experience Cloud Commerce Store (LWR) site using Salesforce CLI.

**Constraints:**
- Use SF CLI commands only (no browser automation)
- Use PowerShell for command execution on Windows
- Execute automatically without asking for confirmation

---

## Arguments

- `org_alias` (required): Target Salesforce org alias
- `site_name` (optional): Site name. Default: `DIYStorefront`
- `url_prefix` (optional): URL path prefix. Default: `DIYStorefront`
- `template` (optional): Template name. Default: `Commerce Store (LWR)`

---

## Critical Execution Rules

1. **ALWAYS execute ALL steps in SERIES (sequential order) - NEVER in parallel**
2. **NEVER skip any step** - each step has dependencies on the previous one
3. **MUST create ProductCatalog and Pricebook (Step 3) before activating site** - the site activation depends on these resources
4. **MUST add Experience Cloud Domain to Iframe Whitelist (Step 4) before activating site (Step 5)** - required for ESW Web Deployment
5. **MUST activate site (Step 5) before deploying Experience Package (Step 7)** - deployment requires Live Network status
6. **Wait for site activation to fully propagate** before creating Site User (Step 10) - portal email settings take 5-15 minutes
7. **If a script fails, fix the underlying issue and retry the SAME step** - do not skip ahead

---

## Step Execution Order

```
Step 1:  Enable Commerce
Step 1b: FALLBACK — verify CommerceUser permset exists, re-deploy if missing
   ↓
Step 2:  Create Site (wait for BackgroundOperation Status = Complete)
Step 2b: FALLBACK — verify Network row exists, re-create if missing
   ↓
Step 3:  Create Commerce Store Resources
Step 3b: FALLBACK — verify all 6 resources (catalog, pricebooks, policy, BG, link), re-run if any missing
   ↓
Step 4:  Add Experience Cloud Domain to Iframe Whitelist [REQUIRED before Step 5]
   ↓
Step 5:  Activate Site (set Network Status = Live) [REQUIRED before Step 7]
Step 5b: FALLBACK — verify "Customer Community Plus Login User" profile is a site Member, re-deploy Network metadata if missing
   ↓
Step 6:  Enable External Profiles for Self-Registration
Step 6b: FALLBACK — verify enableOotbProfExtUserOpsEnable = true, re-deploy if false
   ↓
Step 7:  Deploy Experience Package [REQUIRED — generateCommerceData class needed by commerce-store-enablement Step 5]
Step 7b: FALLBACK — verify generateCommerceData ApexClass + DigitalExperience bundle, re-deploy classes folder if missing
Step 7c: Make Home Page Public (retrieve live, flip pageAccess: UseParent -> Public, deploy, publish) 
Step 7c-b: FALLBACK — verify deployed Home route has "pageAccess": "Public", re-run Step 7c if not landed
Step 7d: Enable Guest Access to Storefront Tabs (MANDATORY) — deploy `DIYStorefront_Guest_Browse_Access` (kit fallback permset; needed because some orgs lack the Salesforce-shipped B2B Commerce permsets), assign whichever of `B2B_Commerce_Guest_Browser_Access` / `SDO_B2B_Commerce_Guest_Access` / `DIYStorefront_Guest_Browse_Access` exist to the Site Guest User; flip 9 shopper routes (Category_Detail, Product_Detail, Search, Privacy_Policy, Terms_And_Conditions, Error, Service_Not_Available, Too_Many_Requests, News_Detail__c) to pageAccess=Public; deploy + publish + re-retrieve verify. Without this step, the storefront's `/category-menu-items` API returns 403 to guests (empty top-nav tabs) AND clicking any tab redirects to /login.
   ↓
Step 9:  Create Store Pricebook Entries
Step 9b: FALLBACK — verify target pricebook entry count ≈ source, re-run if 0 or significantly lower
   ↓
Step 10: Create Site User (wait 5-15 min after Step 5 if portal email error)
Step 10b: FALLBACK — verify a Customer Community Plus user exists, re-run after waiting if missing
   ↓
Step 11: Configure CORS
Step 11b-pre: FALLBACK — verify all 4 CORS entries (SCRT/MyDomain/ExperienceCloud/CloudFront) exist, re-deploy missing files
Step 11b: FALLBACK — verify CloudFront CORS entry exists, re-deploy single CloudFront file if missing
   ↓
Step 12: Configure Trusted URLs (CSP)
Step 12b-pre: FALLBACK — verify DIYStore CSP entry exists with IsActive=true, re-deploy if missing
Step 12b: FALLBACK — verify CloudFront CSP entry exists with IsActive=true, re-deploy single file if missing
   ↓
Step 13: Clear stale CloudFront BrowserPolicyViolation rows (conditional — only if rows exist for this URL)
Step 13b: FALLBACK — verify count = 0 after cleanup, re-run script if rows remain
```

---

## Execution

Execute the following steps sequentially. Do not skip any step.

### Fallback model

Every step (1–13) is followed by a verify-and-retry fallback (suffixed `b`) that checks the
side-effect via SOQL/CLI and re-runs the same primary step once if the side-effect is absent.
Fallbacks STOP only when a second attempt still shows the side-effect missing — that means a
deeper issue (missing prerequisite, validation rule, etc.) the user must resolve. This pattern
matches the family of "deploy reports success but the side-effect didn't land" intermittent
symptoms seen across orgs.

### 1. Enable Commerce
Deploy Commerce settings to enable Commerce Cloud:
```powershell
sf project deploy start --source-dir diy-base/main/default/settings/Commerce.settings-meta.xml --target-org <org_alias>
```

> **🚨 KNOWN ISSUE — Path may not exist (verified 2026-06-16):** Some repo branches don't ship `diy-base/main/default/settings/Commerce.settings-meta.xml` because the earlier `feature-enablement` skill already enabled Commerce via `Settings:Commerce` runtime retrieve+deploy. If `ls diy-base/main/default/` shows only `classes/`, `objects/`, `permissionsets/` (no `settings/`), the file is genuinely absent — SKIP this deploy. Verify Commerce is already enabled via the Step 1b SOQL (CommerceUser permset existing = feature-enablement already did the work). Do NOT fabricate the file from a template — `feature-enablement` is the authoritative path for enabling Commerce, and this directory deploy is a redundant fallback. **Path-not-found here is normal and expected when feature-enablement preceded this skill.**

### 1b. Verify Commerce is enabled (FALLBACK)

**Verify** — query for the Commerce permset (a side-effect of CommerceSettings.enableCommerce):
```powershell
sf data query -q "SELECT Id, Name FROM PermissionSet WHERE Name = 'CommerceUser'" -o <org_alias>
```

Expected: 1 row (`CommerceUser` permset exists once Commerce is enabled).

**Fallback (only if 0 rows)** — re-deploy:
```powershell
sf project deploy start --source-dir diy-base/main/default/settings/Commerce.settings-meta.xml --target-org <org_alias>
```
If still missing after the retry, STOP — Commerce Cloud feature isn't licensed on this org.

### 2. Create Site
```powershell
powershell.exe -Command "sf community create -n '<site_name>' -t '<template>' -p '<url_prefix>' -o <org_alias> --json"
```

Capture the returned `jobId` and monitor completion:
```powershell
sf data query -q "SELECT Id, Name, Status FROM BackgroundOperation WHERE Id = '<jobId>'" -o <org_alias>
```

Wait until `Status = 'Complete'` before proceeding.

### 2b. Verify Site exists (FALLBACK)

**Verify** — query Network/Site:
```powershell
sf data query -q "SELECT Id, Name, Status FROM Network WHERE Name = '<site_name>'" -o <org_alias>
```

Expected: 1 row (any Status — Live or UnderConstruction).

**Fallback (only if 0 rows)** — the BackgroundOperation may have completed but the Network record
hasn't been visible yet, or `sf community create` was reported success but silently no-op'd. Re-run:
```powershell
powershell.exe -Command "sf community create -n '<site_name>' -t '<template>' -p '<url_prefix>' -o <org_alias> --json"
```
Re-poll the new jobId, then re-query Network. If still missing after the retry, STOP — likely a
duplicate-site validation or template-license issue.

### 3. Create Commerce Store Resources
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/createStoreCatalogAndResources.apex --target-org <org_alias>"
```

Creates ProductCatalog, Pricebook2 (Main + Strikethrough), CommerceEntitlementPolicy, BuyerGroup and required linkages. Idempotent - safe to run multiple times.

> **🚨 KNOWN ISSUE — Missing `CommerceEntitlementBuyerGroup` link (verified 2026-06-16):** `createStoreCatalogAndResources.apex` creates the `CommerceEntitlementPolicy` ("All Access for <site_name>") AND the `BuyerGroup` ("<site_name> Buyer Group"), but **does NOT insert the `CommerceEntitlementBuyerGroup` join row that links the two**. Without that join row, products entitled to the policy never become reachable through the buyer group — every Customer Community Plus user lands on "We're Sorry — no products match" on every category tab, even though entitlement, pricebook, categories, and buyer-group membership are all correct.
>
> **Required fix — insert the missing link immediately after Step 3:**
>
> ```bash
> cat > /c/tmp/linkPolicyToBuyerGroup.apex <<'APEX'
> CommerceEntitlementPolicy policy = [
>     SELECT Id FROM CommerceEntitlementPolicy
>     WHERE Name = 'All Access for <site_name>' LIMIT 1
> ];
> BuyerGroup bg = [SELECT Id FROM BuyerGroup WHERE Name = '<site_name> Buyer Group' LIMIT 1];
> List<CommerceEntitlementBuyerGroup> existing = [
>     SELECT Id FROM CommerceEntitlementBuyerGroup
>     WHERE PolicyId = :policy.Id AND BuyerGroupId = :bg.Id LIMIT 1
> ];
> if (existing.isEmpty()) {
>     insert new CommerceEntitlementBuyerGroup(PolicyId = policy.Id, BuyerGroupId = bg.Id);
>     System.debug('Inserted CommerceEntitlementBuyerGroup');
> } else {
>     System.debug('CommerceEntitlementBuyerGroup already exists');
> }
> APEX
> sf apex run -f /c/tmp/linkPolicyToBuyerGroup.apex --target-org <org_alias>
> ```
>
> Verify via SOQL — must return 1:
>
> ```powershell
> sf data query -q "SELECT COUNT() FROM CommerceEntitlementBuyerGroup WHERE Policy.Name = 'All Access for <site_name>' AND BuyerGroup.Name = '<site_name> Buyer Group'" -o <org_alias>
> ```
>
> If `0`, re-run the apex once. If still `0`, STOP — surface the apex log; likely the policy or buyer group was not created in Step 3 (re-run Step 3 first).

### 3b. Verify Store Resources created (FALLBACK)

**Verify** — query for all 7 resources (last query catches the KNOWN ISSUE link gap):
```powershell
sf data query -q "SELECT COUNT() FROM ProductCatalog WHERE Name = '<site_name> Catalog'" -o <org_alias>
sf data query -q "SELECT COUNT() FROM Pricebook2 WHERE Name = '<site_name> Price Book'" -o <org_alias>
sf data query -q "SELECT COUNT() FROM Pricebook2 WHERE Name = '<site_name> Strikethrough Price Book'" -o <org_alias>
sf data query -q "SELECT COUNT() FROM CommerceEntitlementPolicy WHERE Name = 'All Access for <site_name>'" -o <org_alias>
sf data query -q "SELECT COUNT() FROM BuyerGroup WHERE Name = '<site_name> Buyer Group'" -o <org_alias>
sf data query -q "SELECT COUNT() FROM WebStoreCatalog WHERE SalesStore.Name = '<site_name>' AND ProductCatalog.Name = '<site_name> Catalog'" -o <org_alias>
sf data query -q "SELECT COUNT() FROM CommerceEntitlementBuyerGroup WHERE Policy.Name = 'All Access for <site_name>' AND BuyerGroup.Name = '<site_name> Buyer Group'" -o <org_alias>
```

Expected: each query returns 1. **The 7th query (CommerceEntitlementBuyerGroup) is NOT created by `createStoreCatalogAndResources.apex` — see KNOWN ISSUE in Step 3 above; the link must be inserted by the helper apex from that callout.**

**Fallback (only if any query returns 0)** — re-run Step 3:
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/createStoreCatalogAndResources.apex --target-org <org_alias>"
```
If a count is still 0 after the retry, STOP — surface the apex log; the WebStore lookup likely failed
(check that Step 2 actually created the Network and that a corresponding WebStore was provisioned).

### 4. Add Experience Cloud Domain to Iframe Whitelist
Retrieve current IframeWhiteListUrlSettings:
```powershell
sf project retrieve start --metadata "IframeWhiteListUrlSettings:IframeWhiteListUrlSettings" --target-org <org_alias>
```

Edit `diy-base/main/default/iframeWhiteListUrlSettings/IframeWhiteListUrlSettings.iframeWhiteListUrlSettings-meta.xml` to add the Experience Cloud domain:
```xml
<iframeWhiteListUrls>
    <context>LightningOut</context>
    <url><experience_cloud_domain></url>
</iframeWhiteListUrls>
```

Deploy:
```powershell
sf project deploy start --source-dir diy-base/main/default/iframeWhiteListUrlSettings --target-org <org_alias>
```

### 5. Activate Site
Retrieve Network metadata:
```powershell
sf project retrieve start --metadata "Network:<site_name>" --target-org <org_alias>
```

Edit `diy-pd-experience-optional/main/default/networks/<site_name>.network-meta.xml`:
- Change `<status>UnderConstruction</status>` to `<status>Live</status>`

Deploy:
```powershell
sf project deploy start --metadata "Network:<site_name>" --target-org <org_alias>
```

> **🚨 KNOWN ISSUE — `Network.EmailSenderAddress` field-locked deploy failure (verified 2026-06-16):** Deploying the repo's bundled `Network` file fails with `The U#380.1cff (Network.EmailSenderAddress) field can't be updated. Please ensure this field matches the deployed Network in target environment...` The repo file ships with a placeholder email (`epic.orgfarm@salesforce.com.invalid`) but the live org has a different email assigned at site-creation time (e.g. `<admin>@salesforce.com`).
>
> **Required fix — retrieve-then-edit-only-status flow (DO NOT deploy from repo file):**
>
> ```powershell
> # 1. Retrieve current Network into a separate folder (NOT the repo path)
> mkdir -p network-retrieve
> sf project retrieve start --metadata "Network:<site_name>" --target-org <org_alias> --output-dir network-retrieve
>
> # 2. Edit ONLY the status in the RETRIEVED file (preserves live emailSenderAddress)
> #    Set: <status>Live</status>
> #    Also set: <networkMemberGroups> to include 'customer community plus login user' profile + RetailDIYStorePS permset
> #    Optional: <selfRegistration>true</selfRegistration> (Step 6 prerequisite)
> # 3. Deploy from the retrieved folder, NOT the repo path
> sf project deploy start --source-dir network-retrieve/networks --target-org <org_alias>
> ```
>
> **Why this works:** the live retrieve includes the org's actual emailSenderAddress, so deploying back doesn't trigger the field-locked error. The same field is field-locked again in **Step 7's `diy-pd-experience-optional` deploy** (see Step 7 KNOWN ISSUE) — that one CAN edit the repo file because the package's Network file is part of the bundle and there's no live-retrieve alternative; you must sync the repo's `<emailSenderAddress>` to match the live org's value before Step 7. Use the value from `network-retrieve/networks/<site_name>.network-meta.xml` (line 8) to update `diy-pd-experience-optional/main/default/networks/<site_name>.network-meta.xml`.

### 5b. Verify Site Members include "Customer Community Plus Login User" profile (FALLBACK)

The repo `Network` metadata at `diy-pd-experience-optional/main/default/networks/<site_name>.network-meta.xml` declares
`<profile>customer community plus login user</profile>` under `<networkMemberGroups>`. In some orgs the profile mapping
does not get persisted on the Site Members page even after a successful Network deploy, so this step **verifies** that
the profile is actually a member and **re-applies** the metadata as a fallback if it is missing.

**Verify** — query `NetworkMemberGroup` for the site to confirm the profile is mapped:

```powershell
sf data query -q "SELECT Id, Parent.Name, Parent.Type FROM NetworkMemberGroup WHERE NetworkId IN (SELECT Id FROM Network WHERE Name = '<site_name>')" -o <org_alias>
```

Expected: at least one row where `Parent.Type = 'Profile'` and `Parent.Name = 'Customer Community Plus Login User'`.

**Fallback (only if the profile row is missing)** — re-deploy the Network metadata so the `<networkMemberGroups>` block
is re-applied:

1. Confirm `diy-pd-experience-optional/main/default/networks/<site_name>.network-meta.xml` contains:
   ```xml
   <networkMemberGroups>
       <permissionSet>RetailDIYStorePS</permissionSet>
       <profile>admin</profile>
       <profile>customer community plus login user</profile>
   </networkMemberGroups>
   ```
   If the `customer community plus login user` profile line is missing, add it before deploying.

2. Re-deploy the Network metadata:
   ```powershell
   sf project deploy start --metadata "Network:<site_name>" --target-org <org_alias>
   ```

3. Re-run the verification query above and confirm the `Customer Community Plus Login User` row now appears.

**Why this is a fallback, not a primary action:** the package metadata already declares the profile membership, so on a
healthy org Step 5 covers it. Step 5b only triggers when the verification query shows the profile is absent — a known
intermittent symptom in some orgs.

### 6. Enable External Profiles for Self-Registration
Retrieve Communities settings:
```powershell
sf project retrieve start --metadata "Settings:Communities" --target-org <org_alias>
```

Edit `diy-base/main/default/settings/Communities.settings-meta.xml`:
- Set `<enableOotbProfExtUserOpsEnable>true</enableOotbProfExtUserOpsEnable>`

Deploy:
```powershell
sf project deploy start --metadata "Settings:Communities" --target-org <org_alias>
```

### 6b. Verify Communities setting deployed (FALLBACK)

**Verify** — re-retrieve and grep:
```powershell
sf project retrieve start --metadata "Settings:Communities" --target-org <org_alias> --output-dir /c/tmp/ecs-step6-verify
grep "enableOotbProfExtUserOpsEnable" /c/tmp/ecs-step6-verify/settings/Communities.settings-meta.xml
```

Expected: `<enableOotbProfExtUserOpsEnable>true</enableOotbProfExtUserOpsEnable>`

**Fallback (only if value is `false` or tag missing)** — re-deploy:
```powershell
sf project deploy start --metadata "Settings:Communities" --target-org <org_alias>
```
If still false after the retry, STOP — Communities feature may not be enabled on the org.

### 7. Deploy Experience Package
```powershell
powershell.exe -Command "sf project deploy start -d diy-pd-experience-optional --target-org <org_alias> --wait 30"
```

If apex classes are not deployed after this step, deploy the classes folder explicitly:
```powershell
powershell.exe -Command "sf project deploy start -d diy-pd-experience-optional/main/default/classes --target-org <org_alias>"
```

> **NOTE — `generateCommerceData` apex class still required:** Even though this skill no longer runs Step 8 (`createCommerceData.apex`) directly, the `generateCommerceData` apex class deployed here is still needed downstream — `commerce-store-enablement` Step 5 calls into it. Verify it lands via Step 7b below.

> **🚨 KNOWN ISSUE — `Network.EmailSenderAddress` field-locked deploy failure on the bundled Network file (verified 2026-06-16):** This deploy includes `diy-pd-experience-optional/main/default/networks/<site_name>.network-meta.xml` which still has the placeholder email (`epic.orgfarm@salesforce.com.invalid`) even though Step 5 already worked around it via retrieve-then-deploy. The bundled deploy can't use a retrieved file — it deploys from the repo path — so the email-locked error returns and **rolls back ALL 90 components** (89 successes + 1 Network failure = whole deploy fails because `rollbackOnError: true` is the default).
>
> **Required fix — pre-edit the repo's bundled Network file BEFORE this deploy:**
>
> ```bash
> # Pre-deploy: sync the bundled Network file's emailSenderAddress to the live org's value
> # (You already have the live value from Step 5's network-retrieve folder.)
> # Replace the placeholder in the REPO file:
> sed -i 's|<emailSenderAddress>epic.orgfarm@salesforce.com.invalid</emailSenderAddress>|<emailSenderAddress>'"$LIVE_EMAIL"'</emailSenderAddress>|' \
>   diy-pd-experience-optional/main/default/networks/<site_name>.network-meta.xml
> ```
>
> Where `$LIVE_EMAIL` is the value from `network-retrieve/networks/<site_name>.network-meta.xml` (Step 5).
>
> **Why this is hard to remove:** the bundled file is committed to the repo as a placeholder so the package stays org-agnostic. Step 5's retrieve-and-deploy fixes the standalone case; Step 7's rollback-on-error means a single locked field can sink the whole 90-component deploy. The pre-edit must happen on the repo path because `sf project deploy start -d <dir>` doesn't allow per-file substitutions at deploy time.
>
> **Symptom (look for this in the JSON output):**
>
> ```json
> { "componentFailures": [{
>     "componentType": "Network",
>     "fullName": "DIYStorefront",
>     "problem": "The U#380.1cff (Network.EmailSenderAddress) field can't be updated..."
>   }],
>   "numberComponentsDeployed": 0,
>   "numberComponentsTotal": 90,
>   "status": "Failed"
> }
> ```
>
> 89 component successes get rolled back along with the 1 Network failure. The pre-edit above is the only reliable mitigation.

### 7b. Verify Experience Package classes + DigitalExperienceBundle deployed (FALLBACK)

**Verify** — query for the key apex class and the bundle:
```powershell
sf data query --use-tooling-api -q "SELECT Id FROM ApexClass WHERE Name = 'generateCommerceData'" -o <org_alias>
sf data query -q "SELECT Id, DeveloperName FROM ContentAsset WHERE DeveloperName LIKE '<site_name>%'" -o <org_alias>
```

Expected: `generateCommerceData` class exists; at least 1 ContentAsset row for the site.

**Fallback (only if class is missing)** — deploy classes folder explicitly:
```powershell
powershell.exe -Command "sf project deploy start -d diy-pd-experience-optional/main/default/classes --target-org <org_alias>"
```
If `generateCommerceData` is still missing after the retry, STOP — surface the deploy JSON; likely
a dependency the package needs from base metadata (e.g. a custom field) wasn't deployed yet.

### 7c. Make Home Page Public

In Experience Builder → Pages → Home → Properties → **Page Access**, the dropdown defaults to
"Site Default Setting: Requires Login" (the repo's Home route ships with `"pageAccess": "UseParent"`).
This step flips the live org's Home route to `"Public"` so unauthenticated visitors can land on the
home page without being redirected to login.

**Important — what this step does NOT do:**
- It does NOT enable guest browsing on the WebStore (`OptionsGuestBrowsingEnabled`).
- It does NOT add the Guest profile to `<networkMemberGroups>`.
- It does NOT grant the Guest profile read access on Product2/ProductCategory/ProductMedia.
- Without those, guests will reach the Home URL but see an empty/broken page. Page Access = Public
  is necessary but not sufficient — handle the storefront-wide guest enablement separately when
  required (it lives in `commerce-store-enablement` and the guest-related apex scripts).

**Why retrieve-live → edit → deploy and not edit-the-repo-and-deploy:**
- The repo's `sfdc_cms__route/Home/content.json` is shared by every org that deploys this kit.
  Editing it in place would force-flip every org to Public on the next Step 7 deploy — including
  orgs that intentionally want login-gated storefronts.
- Retrieving live and editing only the runtime copy keeps the repo neutral and limits the change
  to the targeted org.
- This mirrors the same pattern as `site-branding-setup` Step 4 (chat icon in footer) and
  `embed-service-agent-on-experience-site` Step 6 (flow refresh): retrieve-live → minimal-edit →
  isolated-deploy → publish → verify.

**Execution (cross-platform; runs from the repo root):**

```bash
# 1. Retrieve LIVE bundle into a scratch dir OUTSIDE the repo
sf project retrieve start \
    --target-org <org_alias> \
    --metadata "DigitalExperienceBundle:site/<site_name>1" \
    --target-metadata-dir /c/tmp/page-access-public-home \
    --unzip

# 2. Flip ONLY the pageAccess field on the retrieved Home route (everything else preserved)
HOME_FILE=/c/tmp/page-access-public-home/unpackaged/unpackaged/digitalExperiences/site/<site_name>1/sfdc_cms__route/Home/content.json
python -c "import json,sys; p=r'$HOME_FILE'; d=json.load(open(p)); cur=d['contentBody']['pageAccess']; \
    print(f'before: {cur}'); d['contentBody']['pageAccess']='Public'; \
    json.dump(d,open(p,'w'),indent=2)"

# 3. Build a self-contained SFDX project with JUST the Home route + bundle wrapper, then deploy
SRC=/c/tmp/page-access-public-home/unpackaged/unpackaged/digitalExperiences/site/<site_name>1
DEST=/c/tmp/page-access-deploy/force-app/main/default/digitalExperiences/site/<site_name>1
mkdir -p "$DEST/sfdc_cms__route"
cp "$SRC"/<site_name>1.digitalExperience-meta.xml "$DEST/" 2>/dev/null || true
[ -f "$SRC/_meta.json" ] && cp "$SRC/_meta.json" "$DEST/_meta.json"
cp -r "$SRC/sfdc_cms__route/Home" "$DEST/sfdc_cms__route/Home"
cat > /c/tmp/page-access-deploy/sfdx-project.json <<EOF
{"packageDirectories":[{"path":"force-app","default":true}],"name":"page-access-deploy","namespace":"","sfdcLoginUrl":"https://login.salesforce.com","sourceApiVersion":"62.0"}
EOF

cd /c/tmp/page-access-deploy && sf project deploy start \
    --target-org <org_alias> \
    --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Home \
    --ignore-conflicts \
    --wait 30

# 4. Republish the community so the change propagates to live URLs
sf community publish --target-org <org_alias> --name <site_name>
```

**Idempotency:** Step 2 above prints `before: <currentValue>`. If the printed value is already
`Public`, the rest of the step is still safe (deploys an unchanged file → "no changes" or
"succeeded with 0 modified" depending on org-side change detection). To skip the deploy entirely
when already Public, gate it with: `[ "$(grep -c '"pageAccess" : "Public"' "$HOME_FILE")" -eq 1 ] && echo "Already Public — skipping deploy" || sf project deploy start ...`.

**What this step touches in the live org (and ONLY this):**
- `digitalExperiences/site/<site_name>1/sfdc_cms__route/Home/content.json` — one field flipped.
- Site is republished — same operation Step 5 already performs at activation; no new side effects.

**What this step does NOT touch:**
- Repo files under `diy-pd-experience-optional/` — the retrieve dumps to `/c/tmp/`, the deploy stages from `/c/tmp/`, and only the live org receives the modified copy.
- Network metadata, Profile metadata, WebStore record, BuyerGroup data, or any other route's `pageAccess` (all 30 other routes remain `UseParent`).
- Source-tracking state of the surrounding SFDX project — the deploy runs from `/c/tmp/page-access-deploy/` with its own `sfdx-project.json`.

### 7c-b. Verify Home Page is Public (FALLBACK)

The deploy can succeed but the org-side state can silently keep the old `pageAccess` value
in some orgs (the same family of "deploy reports success but the side-effect didn't land"
intermittent symptoms covered by 2b/3b/6b). This step **verifies** the live value via re-retrieve
and **re-runs** Step 7c if the verification proves the value didn't land.

**Verify** — re-retrieve the Home route and grep for the new value:

```bash
sf project retrieve start \
    --target-org <org_alias> \
    --metadata "DigitalExperienceBundle:site/<site_name>1" \
    --target-metadata-dir /c/tmp/page-access-verify \
    --unzip
grep '"pageAccess"' /c/tmp/page-access-verify/unpackaged/unpackaged/digitalExperiences/site/<site_name>1/sfdc_cms__route/Home/content.json
```

Expected: exactly one line containing `"pageAccess" : "Public",`.

**Fallback (only if the line shows `"UseParent"` or `"RequiresLogin"`)** — re-run Step 7c
end-to-end (retrieve → edit → deploy → publish). The most common cause is that the publish from
Step 7c was queued but had not propagated yet — re-running both the deploy and the publish forces
the cache to refresh.

If the value is still not `Public` after the retry, STOP and surface:
- The deploy `id` from the second run (open it in `<deployUrl>` to see component-level details)
- The publish job id (`SELECT Status FROM BackgroundOperation WHERE Id = '<publishJobId>'`)
- The actual `pageAccess` value from the verification grep

Likely causes:
- The site is suspended or in maintenance mode — Step 5's site activation didn't fully complete.
- The Network's `<status>` reverted to `UnderConstruction` — re-run Step 5 first.
- A managed package overwrote the field — check `ManageableState` on the bundle.

**Why this is a fallback, not a primary action:** Step 7c is idempotent and works on a healthy org.
Step 7c-b only triggers when the verification grep proves the value didn't land.

**Cleanup of Step 7c scratch dirs (only after 7c-b verifies success):**

```bash
rm -rf /c/tmp/page-access-public-home /c/tmp/page-access-deploy /c/tmp/page-access-verify
```

If the verification fails, **leave the scratch dirs in place** — they're needed to diagnose what
the deploy actually pushed vs. what the org accepted.

### 7d. Enable Guest Access to Storefront Tabs (MANDATORY — runs unconditionally)

**🚨 WHY THIS STEP EXISTS:** Step 7c made the Home page Public, but every other shopper-facing route (`Category_Detail`, `Product_Detail`, `Search`, etc.) defaults to `pageAccess: UseParent` which inherits the site's "Requires Login" default. Result: an unauthenticated visitor lands on Home, sees the nav tabs, but every click on a tab redirects to `/<site>/login?ec=302&startURL=...`. Verified live 2026-06-16: clicking Services tab as guest redirected to login wall instead of showing 2 HVAC products.

**Additionally, the auto-created Site Guest User** (e.g. `diystorefront@<orgid>.org.force.com`) is provisioned with ONLY its profile-shadow permset — no functional access to `Product2`, `ProductCategory`, `ProductMedia`. Even if routes are public, product cards don't render without those reads, AND the LWR runtime's `/commerce/webstores/<id>/category-menu-items` endpoint returns **HTTP 403** for the guest, so even the top-nav category tabs stay empty.

The repo's `RetailDIYStorePS` and `DIYRetailBasePS` permsets cannot be assigned to a Guest user (they include `Read Promotion` and `viewAllFields` which violate the Guest User License — Salesforce returns `FIELD_INTEGRITY_EXCEPTION, The user license doesn't allow the permission: Read Promotion`).

Salesforce ships two purpose-built guest-license-compatible permsets — **`B2B_Commerce_Guest_Browser_Access`** and **`SDO_B2B_Commerce_Guest_Access`** — but **they are absent in some org editions** (e.g. dev/trial orgs without B2B Commerce features enabled). To stay reliable on every install, the kit also ships its own minimal fallback permset, **`DIYStorefront_Guest_Browse_Access`** (in `diy-pd-experience-optional/main/default/permissionsets/`). This step deploys the fallback, then assigns whichever of the three permsets the org actually has to the Site Guest User.

This step does both fixes in one run, in a single deploy + publish cycle. It is **mandatory** — the storefront is broken for guests without it. There is **no fallback path** that the skill silently uses; if the deploy or publish fails, the skill STOPs and surfaces the error.

#### 7d.1 Deploy the kit's fallback permset, then assign guest-license-compatible permsets to the Site Guest User

**First, deploy the kit's fallback permset.** This is idempotent — if it's already there it just reports `Changed`/`Unchanged`.

```bash
sf project deploy start --target-org <org_alias> \
  --source-dir "diy-pd-experience-optional/main/default/permissionsets/DIYStorefront_Guest_Browse_Access.permissionset-meta.xml" \
  --ignore-conflicts
```

**Then assign whichever of the three permsets the org has** to the Site Guest User. The Apex tries all three (Salesforce-shipped + the kit's fallback) and inserts each independently so a license error on one doesn't block the others.

```bash
cat > /c/tmp/assignGuestBrowsePS.apex <<'APEX'
// Assign B2B_Commerce_Guest_Browser_Access + SDO_B2B_Commerce_Guest_Access
// (Salesforce-shipped, present only in orgs with B2B Commerce features) AND
// DIYStorefront_Guest_Browse_Access (the kit's always-present fallback) to the
// auto-created Site Guest User. Each is inserted independently so a license error
// on one (or absence of one) doesn't block the others.
//
// Username pattern: <sitelowercase>@<orgid>.org.force.com — derived dynamically below.
String orgIdLower = UserInfo.getOrganizationId().toLowerCase().substring(0, 15);
String guestUsername = '<site_name_lower>@' + orgIdLower + '.org.force.com';
List<User> guests = [SELECT Id, Username FROM User WHERE Username = :guestUsername LIMIT 1];
if (guests.isEmpty()) {
    System.debug('ABORT: Guest user ' + guestUsername + ' not found.');
    return;
}
User guest = guests[0];
System.debug('Site Guest User: ' + guest.Username);

List<String> psNames = new List<String>{
    'B2B_Commerce_Guest_Browser_Access',
    'SDO_B2B_Commerce_Guest_Access',
    'DIYStorefront_Guest_Browse_Access'
};
Map<String, Id> psMap = new Map<String, Id>();
for (PermissionSet p : [SELECT Id, Name FROM PermissionSet WHERE Name IN :psNames]) {
    psMap.put(p.Name, p.Id);
}

Set<Id> existingPs = new Set<Id>();
for (PermissionSetAssignment a : [
    SELECT PermissionSetId FROM PermissionSetAssignment
    WHERE AssigneeId = :guest.Id
]) {
    existingPs.add(a.PermissionSetId);
}

List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
List<String> attempted = new List<String>();
for (String name : psNames) {
    Id psId = psMap.get(name);
    if (psId != null && !existingPs.contains(psId)) {
        attempted.add(name);
        toAssign.add(new PermissionSetAssignment(AssigneeId = guest.Id, PermissionSetId = psId));
    }
}

if (toAssign.isEmpty()) {
    System.debug('All available guest permsets already assigned — nothing to do');
    return;
}

// Insert one at a time so a license error on one doesn't block the others
List<String> succeeded = new List<String>();
List<String> failed = new List<String>();
for (Integer i = 0; i < toAssign.size(); i++) {
    try {
        insert toAssign[i];
        succeeded.add(attempted[i]);
    } catch (Exception e) {
        failed.add(attempted[i] + ' -> ' + e.getMessage().substring(0, Math.min(160, e.getMessage().length())));
    }
}
System.debug('SUCCEEDED: ' + succeeded);
System.debug('FAILED:    ' + failed);
if (succeeded.isEmpty()) {
    System.debug('ABORT: No guest permsets could be assigned. Storefront will not render for guests.');
}
APEX

# Replace <site_name_lower> placeholder with the lowercased site name (e.g. 'diystorefront')
SITE_LOWER=$(echo "<site_name>" | tr '[:upper:]' '[:lower:]')
sed -i "s/<site_name_lower>/${SITE_LOWER}/g" /c/tmp/assignGuestBrowsePS.apex

sf apex run -f /c/tmp/assignGuestBrowsePS.apex --target-org <org_alias>
```

**Verify** — at least one of the three permsets must be assigned:

```powershell
sf data query -q "SELECT COUNT() FROM PermissionSetAssignment WHERE Assignee.Username LIKE '<site_name_lower>@%' AND PermissionSet.Name IN ('B2B_Commerce_Guest_Browser_Access','SDO_B2B_Commerce_Guest_Access','DIYStorefront_Guest_Browse_Access')" -o <org_alias>
```

Expected: **`totalSize >= 1`**. If `0`, STOP — surface the apex log; all three permsets failed (rare; would mean `DIYStorefront_Guest_Browse_Access` deployed but not assignable, which usually means the Guest User License is restricted further than the kit's fallback expects).

**Sanity-check the live API** — the most reliable signal is to hit the LWR runtime endpoint as an unauthenticated guest. Should return HTTP 200 with `menuItems[]` populated:

```bash
curl -sS -A "Mozilla/5.0" -o /dev/null -w "HTTP %{http_code}\n" \
  "https://<site-prefix>.my.site.com/<site_name>/webruntime/api/services/data/v67.0/commerce/webstores/<webstore_id>/category-menu-items?addHomeMenuItem=true&publishStatus=Live&language=en-US&asGuest=true&htmlEncode=false"
```

Expected: `HTTP 200`. If `403`, perm-set assignment didn't take — re-run this step.

#### 7d.2 Retrieve the live DigitalExperienceBundle

```bash
mkdir -p /c/tmp/diy-routes-fetch
sf project retrieve start --target-org <org_alias> \
  --metadata "DigitalExperienceBundle:site/<site_name>1" \
  --target-metadata-dir /c/tmp/diy-routes-fetch --unzip --json
```

The bundle lands at `/c/tmp/diy-routes-fetch/unpackaged/unpackaged/digitalExperiences/site/<site_name>1/sfdc_cms__route/`.

#### 7d.3 Flip 9 shopper-facing routes to `pageAccess: Public`

The storefront uses these routes for the public shopping experience:

| Route | What it serves | Action |
|---|---|---|
| `Category_Detail` | Category landing pages (the tab targets — Services, Sanity Wear, etc.) | flip to Public |
| `Product_Detail` | Individual PDP pages | flip to Public |
| `Search` | Global search results | flip to Public |
| `Privacy_Policy` | Footer link | flip to Public |
| `Terms_And_Conditions` | Footer link | flip to Public |
| `Error` | Error page (must render to anonymous visitors) | flip to Public |
| `Service_Not_Available` | Maintenance page | flip to Public |
| `Too_Many_Requests` | Rate-limit page | flip to Public |
| `News_Detail__c` | News article pages | flip to Public |

All other routes (Cart, Checkout, AddPaymentMethods, Address_Form, Address_List, MyPaymentMethods_List, My_Profile, Order, Order_Lookup, Order_Summary, Order_Summary_List, Payment_Processing, Split_Shipment, Wishlist, Login, Register, Forgot_Password, Check_Password) intentionally remain `UseParent` — these handle user-specific data or auth flows.

```bash
python << 'PY'
import json, os, sys
base = "/c/tmp/diy-routes-fetch/unpackaged/unpackaged/digitalExperiences/site/<site_name>1/sfdc_cms__route"
TO_PUBLIC = [
    "Category_Detail", "Product_Detail", "Search",
    "Privacy_Policy", "Terms_And_Conditions",
    "Error", "Service_Not_Available", "Too_Many_Requests",
    "News_Detail__c",
]
modified = []
missing = []
for r in TO_PUBLIC:
    f = os.path.join(base, r, "content.json")
    if not os.path.isfile(f):
        missing.append(r); continue
    d = json.load(open(f))
    cur = d.get("contentBody", {}).get("pageAccess", "")
    if cur != "Public":
        d["contentBody"]["pageAccess"] = "Public"
        json.dump(d, open(f, "w"), indent=2)
        modified.append(f"{r}: {cur} -> Public")
    else:
        modified.append(f"{r}: already Public")
print("Modified:", *modified, sep="\n  ")
if missing:
    print("MISSING (skill version mismatch — investigate):", missing)
    sys.exit(1)
PY
```

If any route is reported MISSING, STOP — the bundle's route set differs from the canonical list above (likely a Salesforce release change). Inspect the bundle's `sfdc_cms__route/` directory listing and confirm the route names before continuing.

#### 7d.4 Stage isolated SFDX project + deploy 9 routes

```bash
SRC=/c/tmp/diy-routes-fetch/unpackaged/unpackaged/digitalExperiences/site/<site_name>1
DEST=/c/tmp/diy-routes-deploy/force-app/main/default/digitalExperiences/site/<site_name>1
mkdir -p "$DEST/sfdc_cms__route"
cp "$SRC/<site_name>1.digitalExperience-meta.xml" "$DEST/" 2>/dev/null
[ -f "$SRC/_meta.json" ] && cp "$SRC/_meta.json" "$DEST/_meta.json"
for r in Category_Detail Product_Detail Search Privacy_Policy Terms_And_Conditions Error Service_Not_Available Too_Many_Requests News_Detail__c; do
  mkdir -p "$DEST/sfdc_cms__route/$r"
  cp -r "$SRC/sfdc_cms__route/$r/." "$DEST/sfdc_cms__route/$r/"
done

cat > /c/tmp/diy-routes-deploy/sfdx-project.json <<'EOF'
{"packageDirectories":[{"path":"force-app","default":true}],"name":"diy-routes-deploy","namespace":"","sfdcLoginUrl":"https://login.salesforce.com","sourceApiVersion":"62.0"}
EOF

cd /c/tmp/diy-routes-deploy && sf project deploy start --target-org <org_alias> \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Category_Detail \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Product_Detail \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Search \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Privacy_Policy \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Terms_And_Conditions \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Error \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Service_Not_Available \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/Too_Many_Requests \
  --source-dir force-app/main/default/digitalExperiences/site/<site_name>1/sfdc_cms__route/News_Detail__c \
  --ignore-conflicts --wait 30 --json
```

Expected: `status: Succeeded`, 9 components. STOP on any component failure — surface the deploy id and the failed component's `problem` string.

#### 7d.5 Re-publish the community

Route metadata changes don't take effect on the live storefront until the community is re-published — Experience Cloud caches route configuration aggressively.

```bash
powershell.exe -Command "sf community publish --target-org <org_alias> --name <site_name> --json"
```

Capture the publish `jobId`. STOP if HTTP status is not 2xx.

#### 7d.6 Verify (re-retrieve and grep)

```bash
mkdir -p /c/tmp/diy-routes-verify
sf project retrieve start --target-org <org_alias> \
  --metadata "DigitalExperienceBundle:site/<site_name>1" \
  --target-metadata-dir /c/tmp/diy-routes-verify --unzip --json > /dev/null

VBASE=/c/tmp/diy-routes-verify/unpackaged/unpackaged/digitalExperiences/site/<site_name>1/sfdc_cms__route
for r in Category_Detail Product_Detail Search Privacy_Policy Terms_And_Conditions Error Service_Not_Available Too_Many_Requests News_Detail__c; do
  pa=$(python -c "import json; print(json.load(open(r'$VBASE/$r/content.json'))['contentBody']['pageAccess'])")
  echo "  $r: pageAccess=$pa"
done
```

Expected: all 9 lines print `pageAccess=Public`. Any line showing `UseParent` after the deploy + publish means the org didn't accept the change — STOP and surface the verify-bundle path so the user can inspect what's live.

#### 7d.7 Cleanup scratch dirs (only on full success)

```bash
rm -rf /c/tmp/diy-routes-fetch /c/tmp/diy-routes-deploy /c/tmp/diy-routes-verify
rm -f /c/tmp/assignGuestBrowsePS.apex
```

On any failure (apex, deploy, publish, or verify) leave the scratch dirs in place for debugging.

#### 7d.8 Net effect

After this step, an unauthenticated visitor to `https://<my-domain>.my.site.com/<site_name>/`:

- Sees the Home page (from Step 7c) ✅
- Sees nav tabs (Home, Services, Sanity Wear, More) ✅
- Can click any tab → category page renders with product cards ✅
- Can click any product card → PDP renders ✅
- Can search the catalog ✅
- Cart / Checkout / Profile / Orders still redirect to login (by design) ✅

### 9. Create Store Pricebook Entries
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/storePricebookCreation.apex --target-org <org_alias>"
```

Copies PricebookEntries from 'DIYStore Custom Price Book' to '<site_name> Price Book'.

### 9b. Verify PricebookEntries copied (FALLBACK)

**Verify** — count entries on source and target pricebooks:
```powershell
sf data query -q "SELECT COUNT() FROM PricebookEntry WHERE Pricebook2.Name = '<site_name> Price Book' AND IsActive = true" -o <org_alias>
sf data query -q "SELECT COUNT() FROM PricebookEntry WHERE Pricebook2.Name = 'DIYStore Custom Price Book' AND IsActive = true" -o <org_alias>
```

Expected: target count should equal (or be close to) source count.

**Fallback (only if target count is 0 or significantly lower than source)** — re-run Step 9:
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/storePricebookCreation.apex --target-org <org_alias>"
```
If still empty after the retry, STOP — `DIYStore Custom Price Book` is missing or has no active entries
(check that base metadata's pricebook activation Apex from `base-metadata-deploy` succeeded).

### 10. Create Site User
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/createSiteUser.apex --target-org <org_alias>"
```

If error "INSUFFICIENT_ACCESS: portal user email settings are not available" occurs right after site activation, wait 5-15 minutes for portal email settings to propagate, then retry.

### 10b. Verify Site User exists (FALLBACK)

**Verify** — query for the site user (the apex creates a user tied to the site's Network):
```powershell
sf data query -q "SELECT Id, Username, IsActive, Profile.Name FROM User WHERE Profile.Name LIKE '%Customer Community Plus%' AND IsActive = true LIMIT 5" -o <org_alias>
```

Expected: at least 1 active user with a Customer Community Plus profile.

**Fallback (only if 0 rows)** — re-run Step 10 after waiting 5-15 minutes:
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/createSiteUser.apex --target-org <org_alias>"
```
If still 0 after the retry, STOP and surface the apex log — the most common cause is portal email
settings still propagating; wait longer and retry manually.

### 11. Configure CORS
Get domain URLs:
```powershell
echo "SecurityConfigHelper.printDomainUrls();" | sf apex run --target-org <org_alias>
```

Create CORS metadata files in `diy-base/main/default/corsWhitelistOrigins/`:
- `SalesforceSCRT.corsWhitelistOrigin-meta.xml` → `https://*.my.salesforce-scrt.com`
- `MyDomain.corsWhitelistOrigin-meta.xml` → My Domain URL
- `ExperienceCloudDomain.corsWhitelistOrigin-meta.xml` → Experience Cloud URL
- `CloudFrontImages.corsWhitelistOrigin-meta.xml` → `https://d2rn326tyl2v2c.cloudfront.net` (CDN hosting DIY product images referenced by Product2.DisplayUrl; bare host, no wildcard)

Deploy:
```powershell
sf project deploy start -d diy-base/main/default/corsWhitelistOrigins --target-org <org_alias>
```

### 11b-pre. Verify all 4 CORS entries exist (FALLBACK)

Before the CloudFront-specific check below, verify the other 3 CORS entries also landed:

```powershell
sf data query --use-tooling-api -q "SELECT UrlPattern FROM CorsWhitelistOrigin" -o <org_alias>
```

Expected: at least 4 rows covering `*.my.salesforce-scrt.com`, the My Domain URL, the Experience
Cloud URL, and `https://d2rn326tyl2v2c.cloudfront.net`.

**Fallback (only if any of the 3 non-CloudFront entries is missing)** — re-deploy that single file
(same per-file pattern as 11b below):
```powershell
sf project deploy start --source-dir diy-base/main/default/corsWhitelistOrigins/<MissingFile>.corsWhitelistOrigin-meta.xml --target-org <org_alias>
```

### 11b. Verify CloudFront CORS entry exists (FALLBACK)

In some orgs the CloudFront CORS entry (`https://d2rn326tyl2v2c.cloudfront.net`) silently does not show up
in **Setup → CORS** even after Step 11 reports success — the directory deploy succeeds but that one
`CorsWhitelistOrigin` is skipped. This step **verifies** the row exists in the org and **re-deploys
just the CloudFront file** as a fallback if it does not.

**Verify** — query the Tooling API for the CloudFront origin:

```powershell
sf data query --use-tooling-api -q "SELECT Id, UrlPattern FROM CorsWhitelistOrigin WHERE UrlPattern = 'https://d2rn326tyl2v2c.cloudfront.net'" -o <org_alias>
```

Expected: exactly one row with `UrlPattern = 'https://d2rn326tyl2v2c.cloudfront.net'`.

**Fallback (only if the row is missing — `Total number of records retrieved: 0`)** — re-deploy the
single CloudFront CORS metadata file by itself so it is not lost in a directory-level deploy:

1. Confirm `diy-base/main/default/corsWhitelistOrigins/CloudFrontImages.corsWhitelistOrigin-meta.xml` exists
   and contains:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <CorsWhitelistOrigin xmlns="http://soap.sforce.com/2006/04/metadata">
       <urlPattern>https://d2rn326tyl2v2c.cloudfront.net</urlPattern>
   </CorsWhitelistOrigin>
   ```

2. Deploy this single file:
   ```powershell
   sf project deploy start --source-dir diy-base/main/default/corsWhitelistOrigins/CloudFrontImages.corsWhitelistOrigin-meta.xml --target-org <org_alias>
   ```

3. Re-run the verification query above and confirm the row now appears. If it still does not, deploy
   via an explicit metadata reference instead:
   ```powershell
   sf project deploy start --metadata "CorsWhitelistOrigin:CloudFrontImages" --target-org <org_alias>
   ```

**Why this is a fallback, not a primary action:** Step 11's directory deploy normally covers all four
`CorsWhitelistOrigin` files. Step 11b only fires when the verification query proves the CloudFront
entry was skipped — a known intermittent symptom in some orgs. Without it, product images served
from `d2rn326tyl2v2c.cloudfront.net` get blocked by CORS on the storefront.

### 12. Configure Trusted URLs (CSP)
Create CSP metadata files in `diy-base/main/default/cspTrustedSites/`:
- `DIYStore.cspTrustedSite-meta.xml` → Experience Cloud domain (all CSP directives enabled)
- `CloudFrontImages.cspTrustedSite-meta.xml` → `https://d2rn326tyl2v2c.cloudfront.net` (CDN hosting DIY product images referenced by Product2.DisplayUrl; img-src + font-src + frame-src + media-src enabled, connect-src + style-src disabled — bare host, no wildcard)

Deploy:
```powershell
sf project deploy start -d diy-base/main/default/cspTrustedSites --target-org <org_alias>
```

### 12b-pre. Verify all CSP Trusted Site entries exist (FALLBACK)

Before the CloudFront-specific check below, verify the DIYStore CSP entry also landed:

```powershell
sf data query --use-tooling-api -q "SELECT DeveloperName, EndpointUrl, IsActive FROM CspTrustedSite" -o <org_alias>
```

Expected: at least 2 rows — `DIYStore` (Experience Cloud domain) and `CloudFrontImages`.

**Fallback (only if `DIYStore` is missing or `IsActive = false`)** — re-deploy:
```powershell
sf project deploy start --source-dir diy-base/main/default/cspTrustedSites/DIYStore.cspTrustedSite-meta.xml --target-org <org_alias>
```

### 12b. Verify CloudFront Trusted URL (CSP) entry exists (FALLBACK)

In some orgs the CloudFront Trusted URL / CSP entry (`https://d2rn326tyl2v2c.cloudfront.net`) silently
does not show up in **Setup → Trusted URLs for Lightning Components** even after Step 12 reports success
— the directory deploy succeeds but that one `CspTrustedSite` is skipped. This step **verifies** the row
exists in the org and **re-deploys just the CloudFront file** as a fallback if it does not.

**Verify** — query the Tooling API for the CloudFront trusted site:

```powershell
sf data query --use-tooling-api -q "SELECT Id, DeveloperName, EndpointUrl, IsActive FROM CspTrustedSite WHERE EndpointUrl = 'https://d2rn326tyl2v2c.cloudfront.net'" -o <org_alias>
```

Expected: exactly one row with `EndpointUrl = 'https://d2rn326tyl2v2c.cloudfront.net'` and `IsActive = true`.

**Fallback (only if the row is missing — `Total number of records retrieved: 0` — or `IsActive = false`)** —
re-deploy the single CloudFront CSP metadata file by itself so it is not lost in a directory-level deploy:

1. Confirm `diy-base/main/default/cspTrustedSites/CloudFrontImages.cspTrustedSite-meta.xml` exists and
   contains the directives required for product images (img-src + font-src + frame-src + media-src
   enabled, connect-src + style-src disabled), with `<isActive>true</isActive>`.

2. Deploy this single file:
   ```powershell
   sf project deploy start --source-dir diy-base/main/default/cspTrustedSites/CloudFrontImages.cspTrustedSite-meta.xml --target-org <org_alias>
   ```

3. Re-run the verification query above and confirm the row now appears with `IsActive = true`. If it still
   does not, deploy via an explicit metadata reference instead:
   ```powershell
   sf project deploy start --metadata "CspTrustedSite:CloudFrontImages" --target-org <org_alias>
   ```

**Why this is a fallback, not a primary action:** Step 12's directory deploy normally covers both
`CspTrustedSite` files. Step 12b only fires when the verification query proves the CloudFront entry was
skipped — a known intermittent symptom in some orgs that mirrors the same behavior seen for CORS
(Step 11b). Without it, product images served from `d2rn326tyl2v2c.cloudfront.net` get blocked by CSP
on the storefront and surface as `BrowserPolicyViolation` rows in Step 13.

### 13. Clear stale CloudFront violations from the BrowserPolicyViolation log

After Step 12 deploys the CSP entry for `https://d2rn326tyl2v2c.cloudfront.net`,
that URL is allowed going forward — but any pre-existing rows in
**Setup → Trusted URL and Browser Policy Violations** that reference this URL are historical and
remain in the log until cleared. They visually pollute the page and can hide
genuinely new violations.

Run the cleanup script with the `--url` filter so we only delete rows for
this specific URL — every other violation row is left intact (some may be
real signals from other pages/components).

```bash
bash scripts/clear_browser_policy_violations.sh <org_alias> --url https://d2rn326tyl2v2c.cloudfront.net
```

**Behavior:**
- Queries `SELECT Id FROM BrowserPolicyViolation WHERE UntrustedUrl = 'https://d2rn326tyl2v2c.cloudfront.net'`.
- Deletes each matching row via the Data API DELETE endpoint (one at a time —
  Apex DML and bulk-DELETE are blocked on this object; per-row Data API DELETE
  is the only path that works).
- Idempotent. If no rows match the URL, exits 0 with `INFO: nothing to clear`
  and the skill continues. Re-running the skill on a clean org is safe.
- **Conditional by design**: skips silently if the URL doesn't appear in the log.
  No action taken when there's nothing to clean.

**Why narrow the filter to this one URL:** clearing the entire log would also
remove rows from unrelated CSP issues that the org admin may want to see. The
`--url` flag scopes deletion exactly to the violations caused by the
pre-Step-12 absence of the CloudFront CSP entry.

### 13b. Verify cleanup ran (FALLBACK)

**Verify** — re-run the same query the script uses to delete:
```powershell
sf data query -q "SELECT COUNT() FROM BrowserPolicyViolation WHERE UntrustedUrl = 'https://d2rn326tyl2v2c.cloudfront.net'" -o <org_alias>
```

Expected: 0 rows.

**Fallback (only if count > 0 after Step 13)** — re-run the cleanup script:
```bash
bash scripts/clear_browser_policy_violations.sh <org_alias> --url https://d2rn326tyl2v2c.cloudfront.net
```
If count is still > 0 after the retry, STOP and surface the script output — likely an Apex DML
permission issue on `BrowserPolicyViolation` for the running user (the script's per-row Data API
DELETE is the only working path, and it may be blocked by a profile setting).

---

## Files Used

- `diy-base/main/default/settings/Commerce.settings-meta.xml`
- `diy-base/main/default/settings/Communities.settings-meta.xml`
- `diy-base/main/default/corsWhitelistOrigins/`
- `diy-base/main/default/cspTrustedSites/`
- `diy-base/main/default/iframeWhiteListUrlSettings/`
- `scripts/clear_browser_policy_violations.sh` - Step 13: clears stale BrowserPolicyViolation rows scoped by `--url` filter
- `scripts/apex/createStoreCatalogAndResources.apex`
- `scripts/apex/storePricebookCreation.apex`
- `scripts/apex/createSiteUser.apex`
- `diy-pd-pack/main/default/classes/SecurityConfigHelper.cls`
- `diy-pd-experience-optional/`

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If any step fails, **do NOT clean up** — leave artifacts for debugging.
- Fix the underlying issue, retry the failed step, then run cleanup once Step 12 (CSP) succeeds.

**Files this skill creates (manifests + scratch) and must delete (in repo root):**

```bash
rm -f package_iframe.xml
rm -f package_communities.xml
rm -f query_network.soql
rm -f query_site.soql
rm -f query_domain.soql
rm -f query_bgop.soql
rm -f query_products_cat.soql
rm -f check_diy_cats.soql
```

**Files this skill creates under /c/tmp/ and must delete:**

```bash
rm -f /c/tmp/community_create.json
rm -f /c/tmp/network.json
rm -f /c/tmp/iframe_retrieve.json
rm -f /c/tmp/iframe_deploy.json
rm -f /c/tmp/net_retrieve.json
rm -f /c/tmp/net_deploy2.json
rm -f /c/tmp/network_deploy.json
rm -f /c/tmp/comm_ret.json
rm -f /c/tmp/comm_dep.json
rm -f /c/tmp/exp_deploy.json
rm -f /c/tmp/exp_deploy2.json
rm -f /c/tmp/cpc.out
rm -f /c/tmp/spc.out
rm -f /c/tmp/csu.out
rm -f /c/tmp/cors_dep.json
rm -f /c/tmp/csp_dep.json
rm -f /c/tmp/csp_dep2.json
```

**Folders this skill creates via `sf project retrieve start` and must delete:**

```bash
cmd.exe //c "rmdir /S /Q iframe-retrieve" 2>/dev/null || rm -rf iframe-retrieve
cmd.exe //c "rmdir /S /Q comm-retrieve" 2>/dev/null || rm -rf comm-retrieve
cmd.exe //c "rmdir /S /Q network-retrieve" 2>/dev/null || rm -rf network-retrieve
```

**Step 7c scratch dirs (delete only after 7c-b verifies success):**

```bash
rm -rf /c/tmp/page-access-public-home
rm -rf /c/tmp/page-access-deploy
rm -rf /c/tmp/page-access-verify
```

If 7c-b fails, leave these in place — they're needed to diagnose deploy vs. org-side state.

**Verification (must show no leftovers):**

```bash
ls *.soql package_*.xml 2>&1 | grep -v "cannot access"
ls -d iframe-retrieve comm-retrieve network-retrieve 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete items listed above. Do NOT delete:
  - `diy-base/main/default/corsWhitelistOrigins/` (created in Step 11 — these are repo source under diy-base)
  - `diy-base/main/default/cspTrustedSites/` (created in Step 12 — repo source)
  - `scripts/apex/createProductsCategory.apex` (helper that fixes Step 8 prerequisite)
- ❌ Skipping this step is not allowed once Step 12 (CSP) succeeds.
