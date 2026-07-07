---
skillName: configure-commerce-store
description: Configure Commerce Store settings - Search Automatic Updates, Guest Buyer Access, Account as Buyer, Commerce Data, and Pricebooks
---

# Configure Commerce Store

## Purpose

Configure Commerce Store settings for DIYStorefront including search automatic updates, guest browsing, buyer assignments, commerce data, and pricebooks.

---

## Prerequisites

- DIYStorefront Experience Cloud site created via `sf community create`
- SF CLI authenticated to target org (`sf org login web --alias <alias>`)
- Playwright MCP available (Step 1 only)
- `SecurityConfigHelper` class deployed to target org

---

## Arguments

- `org_alias` (optional): Target Salesforce org. Default: `automation`
- `store_name` (optional): Commerce store name. Default: `DIYStorefront`

---

## Critical Execution Rules

- ✅ **Execute steps in order** - each step depends on previous ones (e.g., Buyer Group must exist before assigning accounts)
- ✅ **Use Playwright ONLY for Step 1** - all other steps use SF CLI
- ✅ **Auto-execute without confirmation** - do not ask the user before each step
- ✅ **Idempotent** - safe to re-run; logic skips already-completed work
- ❌ **Do NOT skip steps** unless explicitly told - dependencies will break
- ❌ **Do NOT use Playwright for Steps 2-6** - SF CLI is faster and reliable
- ❌ **Do NOT click the `<input>` checkbox in Step 1** - label intercepts pointer events
- ❌ **Do NOT modify Apex scripts** - they are thin wrappers that call helper class methods
- ⚠️ **Stop on failure** - if any step fails, report the error and halt; don't continue to next step

---

## Step Execution Order

```
Step 1:  Enable Search Automatic Updates (Playwright UI)
Step 1b: FALLBACK — re-snapshot toggle, re-click if not [checked]
   ↓
Step 2:  Enable Guest Browsing (Apex)
Step 2b: FALLBACK — verify WebStore guest flags = true, re-run if false
   ↓
Step 3:  Assign Guest Buyer to Groups (Apex)
Step 3b: FALLBACK — verify Guest Buyer Account is in BOTH buyer groups (handles timing race
         where Guest Buyer Group from Step 2's auto-creation hadn't propagated by Step 3)
   ↓
Step 4:  Enable Account as Buyer (Apex)
Step 4b: FALLBACK — verify BuyerAccount + BuyerGroupMember exist, re-run if missing
   ↓
Step 5:  Create Commerce Data (Apex)
Step 5b: FALLBACK — verify ProductCategory and CommerceEntitlementProduct exist, re-run if missing
   ↓
Step 6:  Create Store Pricebook (Apex)
Step 6b: FALLBACK — verify <store_name> Price Book PricebookEntry count > 0, re-run if missing
```

**Why this order matters:**
- Steps 3 & 4 must run sequentially (Step 4 needs BuyerGroup from Step 3)
- Step 5 must run before Step 6 (pricebook entries reference products)
- Step 1 is independent - can technically run anytime, but placed first for UI flow

---

## Execution

### Fallback model

Each step (1–6) has a verify-and-retry fallback (1b, 2b, 3b, 4b, 5b, 6b) that runs after the primary
step. The verify queries the org for the side-effect; if absent, re-runs the same primary step. STOPs
only if a second attempt still shows the side-effect missing — that means a deeper issue (missing
prerequisite, validation rule, etc.) the user must resolve.

### 1. Enable Search Automatic Updates (Playwright UI)

This setting is NOT available via API/CLI/Metadata - UI automation only.

**Step 1a**: Get org details and WebStore ID
```bash
sf org display --target-org <org_alias> --json
sf apex run --target-org <org_alias> -e "List<WebStore> s = [SELECT Id FROM WebStore WHERE Name = '<store_name>' LIMIT 1]; if(!s.isEmpty()) System.debug('STORE_ID:' + s[0].Id);"
```

**Step 1b**: Navigate via Playwright using frontdoor URL
```
{instanceUrl}/secur/frontdoor.jsp?sid={accessToken}&retURL=/lightning/n/standard-CommerceStores?target=search%26channelId={STORE_ID}
```

**Step 1c**: Wait for `"Automatic Updates"` text to appear

**Step 1d**: Check toggle state via `browser_snapshot` with `target: '[data-automation="autoIndexToggle"]'`
- If `[checked]` → Skip click (idempotent)
- If not checked → Proceed to click

**Step 1e**: Click toggle with `target: label.slds-checkbox_toggle`

**Step 1f**: Verify with `browser_snapshot` - confirm `[checked]` is present

### 1b. Verify Search Automatic Updates is enabled (FALLBACK)

The Step 1f snapshot is the in-page check. As an out-of-band fallback (e.g. snapshot was lost / re-render mid-click),
re-snapshot the toggle:

```text
mcp.browser_snapshot(target = '[data-automation="autoIndexToggle"]')
```

Expected: snapshot shows `[checked]`.

**Fallback (only if not `[checked]`)** — re-click the toggle exactly as in Step 1e:
```text
mcp.browser_click(target = 'label.slds-checkbox_toggle')
```
Re-snapshot. If still not checked after the retry, STOP — likely a permission issue on the user.

### 2. Enable Guest Browsing
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/enableGuestBrowsing.apex --target-org <org_alias>"
```

### 2b. Verify Guest Browsing flags are set (FALLBACK)

**Verify** — query WebStore for the two stable fields:
```powershell
sf data query -q "SELECT Id, Name, OptionsGuestBrowsingEnabled, OptionsGuestCheckoutEnabled FROM WebStore WHERE Name = '<store_name>'" -o <org_alias>
```

Expected: both `OptionsGuestBrowsingEnabled = true` AND `OptionsGuestCheckoutEnabled = true`.

**Then verify the three LWR-specific toggles** — Cart access (LWR), Preserve guest carts (LWR),
and Checkout access (LWR). The underlying WebStore field for "Cart access" / "Preserve guest carts"
has shifted across releases (e.g. `OptionsAllowGuestAddToCartEnabled` vs `OptionsAddToCartGuestEnabled`,
`OptionsPreserveCartEnabled` vs `OptionsPreserveCartGuestUserEnabled`), so don't hard-code the field
name in a SOQL query — let `SecurityConfigHelper.printGuestBrowsingStatus` (re-run from Step 2) tell
you which field it actually wrote and to what value. The log lines look like:

```
- Guest Browsing: true
- Guest Checkout (LWR): true
- Cart access (LWR): true   [field: OptionsAllowGuestAddToCartEnabled]
- Preserve guest carts (LWR): true   [field: OptionsPreserveCartEnabled]
```

Required: every line above must read `true`. The `[field: NONE_FOUND]` marker means this org's
WebStore SObject doesn't expose a candidate field for that toggle — treat that as a soft-pass for
that specific toggle (it can't be set programmatically here) and continue.

**Fallback (only if any of the four toggles is false, ignoring `NONE_FOUND`)** — re-run Step 2:
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/enableGuestBrowsing.apex --target-org <org_alias>"
```
Re-read the four lines from the apex log. If any of `Guest Browsing`, `Guest Checkout (LWR)`,
`Cart access (LWR)`, or `Preserve guest carts (LWR)` is still `false` after the retry, STOP —
likely a Commerce Cloud feature flag is not enabled on the org (check `Commerce.settings-meta.xml`
deploy from the experience-cloud-setup skill) or a validation rule is blocking the WebStore update.

### 3. Assign Guest Buyer to Groups
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/assignGuestBuyerToGroups.apex --target-org <org_alias>"
```

### 3b. Verify Guest Buyer Account is assigned to BuyerGroups (FALLBACK)

Step 3 calls [SecurityConfigHelper.assignGuestBuyerToGroups](../../../diy-pd-pack/main/default/classes/SecurityConfigHelper.cls#L325).
That method queries `<store_name> Guest Buyer Profile` right after Step 2 enables guest browsing — but in
some orgs the auto-creation of that BuyerGroup (triggered by `OptionsGuestBrowsingEnabled = true` in
Step 2) has not finished propagating by the time Step 3 runs. When that happens, the helper logs
`❌ ERROR: <store_name> Guest Buyer Profile not found!` and **returns early without inserting the
`BuyerGroupMember` row**, so the Guest Buyer Account is never actually attached to either group.

This step **verifies** that the Guest Buyer Account is a member of the main Buyer Group, and **re-runs Step 3** as a fallback if the link is missing.

**Verify** — query `BuyerGroupMember` for the Guest Buyer Account:

```powershell
sf data query -q "SELECT Id, BuyerGroup.Name FROM BuyerGroupMember WHERE BuyerId IN (SELECT Id FROM GuestBuyerProfile WHERE Name = '<store_name> Guest Buyer Profile') AND BuyerGroup.Name = '<store_name> Buyer Group'" -o <org_alias>
```

Expected: **1 row** — one for `<store_name> Buyer Group`.

**Fallback (only if 0 rows)** — re-running Step 3 will insert the missing `BuyerGroupMember` row:

```powershell
powershell.exe -Command "sf apex run -f scripts/apex/assignGuestBuyerToGroups.apex --target-org <org_alias>"
```

Re-run the verification query above and confirm 1 row is returned.

**If the verification query still shows 0 rows after the retry**, STOP — the `DIYStorefront Buyer Group` is missing or the `GuestBuyerProfile` was not created. Re-run Step 2 to recreate guest access.

### 4. Enable Account as Buyer
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/enableAccountAsBuyer.apex --target-org <org_alias>"
```

> **🚨 KNOWN ISSUE — `BuyerAccount.BuyerStatus` defaults to `Pending` (verified 2026-06-16):** `enableAccountAsBuyer.apex` (and the Salesforce platform when it auto-creates BuyerAccounts during user creation) inserts the row with `IsActive=true` but **leaves `BuyerStatus = 'Pending'`**. Salesforce Commerce silently filters all products from the storefront for any buyer whose `BuyerStatus != 'Active'` — admins bypass the check (so `gaurav@…` sees everything), but Customer Community Plus users like Mark Smith hit "We're Sorry — no products match" on every category tab. The data layer (entitlement, pricebook, categories, buyer group membership) is fully correct; the buyer just cannot see anything until `BuyerStatus` flips to `Active`.
>
> **Required fix — flip ALL BuyerAccounts to Active immediately after Step 4:**
>
> ```bash
> cat > /c/tmp/activateAllBuyerAccounts.apex <<'APEX'
> // Activate every Pending BuyerAccount so storefront buyers can see entitled products.
> List<BuyerAccount> pending = [
>     SELECT Id, Buyer.Name, BuyerStatus, IsActive FROM BuyerAccount
>     WHERE BuyerStatus = 'Pending' OR IsActive = false
> ];
> if (pending.isEmpty()) {
>     System.debug('No pending/inactive BuyerAccounts — nothing to fix');
>     return;
> }
> for (BuyerAccount b : pending) {
>     b.BuyerStatus = 'Active';
>     b.IsActive = true;
> }
> update pending;
> System.debug('Activated ' + pending.size() + ' BuyerAccount(s)');
> APEX
> sf apex run -f /c/tmp/activateAllBuyerAccounts.apex --target-org <org_alias>
> ```
>
> Verify via SOQL — count must be 0:
>
> ```powershell
> sf data query -q "SELECT COUNT() FROM BuyerAccount WHERE BuyerStatus != 'Active' OR IsActive = false" -o <org_alias>
> ```
>
> If > 0, re-run the apex once. If still > 0, STOP — surface the apex log; likely a validation rule blocking the update.

### 4b. Verify Account is a Buyer + in Buyer Group + Status=Active (FALLBACK)

**Verify** — query BuyerAccount and BuyerGroupMember for the account name the script enables. **Both `IsActive = true` AND `BuyerStatus = 'Active'` must be true** — see KNOWN ISSUE above:

```powershell
sf data query -q "SELECT Id, Name, IsActive, BuyerStatus FROM BuyerAccount WHERE Buyer.Name = 'Mark Smith'" -o <org_alias>
sf data query -q "SELECT Id, BuyerGroup.Name FROM BuyerGroupMember WHERE Buyer.Name = 'Mark Smith' AND BuyerGroup.Name = '<store_name> Buyer Group'" -o <org_alias>
```

Expected: both queries return ≥ 1 row, BuyerAccount with **`IsActive = true` AND `BuyerStatus = 'Active'`**.

**Fallback (only if either is empty)** — re-run Step 4:
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/enableAccountAsBuyer.apex --target-org <org_alias>"
```
**If `BuyerStatus = 'Pending'` after the retry**, run the activate-all apex from the KNOWN ISSUE block above — `enableAccountAsBuyer.apex` itself does NOT set `BuyerStatus`.

If still missing after the retry, STOP — the `Mark Smith` Account does not exist (sample data import failed)
or the `<store_name> Buyer Group` was deleted (run Step 3 again).

### 5. Create Commerce Data
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/createCommerceData.apex --target-org <org_alias>"
```

### 5b. Verify ProductCategory + EntitlementProducts created (FALLBACK)

**Verify** — query the catalog's categories and entitlement products:
```powershell
sf data query -q "SELECT Id, Name FROM ProductCategory WHERE Catalog.Name = '<store_name> Catalog'" -o <org_alias>
sf data query -q "SELECT COUNT() FROM CommerceEntitlementProduct WHERE Policy.Name = 'All Access for <store_name>'" -o <org_alias>
```

Expected: at least 1 ProductCategory row AND CommerceEntitlementProduct count > 0.

**Fallback (only if either is empty)** — re-run Step 5:
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/createCommerceData.apex --target-org <org_alias>"
```
If still empty after the retry, STOP — likely the ProductCatalog or CommerceEntitlementPolicy from Step 3
of `experience-cloud-setup` doesn't exist (re-run that step's createStoreCatalogAndResources.apex).

### 6. Create Store Pricebook
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/storePricebookCreation.apex --target-org <org_alias>"
```

> **🚨 KNOWN ISSUE — Duplicate-key error on re-run after experience-cloud-setup (verified 2026-06-16):** The same script `scripts/apex/storePricebookCreation.apex` is also called from `experience-cloud-setup` Step 9. If `experience-cloud-setup` ran successfully right before this skill, the 85 PricebookEntries are already present in `<store_name> Price Book` and re-running the script throws `System.DmlException: Insert failed. First exception on row 0; first error: FIELD_INTEGRITY_EXCEPTION, This price definition already exists in this price book: []` because line 164's `insert newEntries` rejects existing PricebookEntry+Product2 pairs.
>
> **This is NOT a real failure** — it just means Step 6 of this skill is redundant when experience-cloud-setup already ran. **Treat the duplicate-key error as success-equivalent** if a quick verification confirms the pricebook is already populated:
>
> ```bash
> # Verify pricebook is already populated — duplicate-key on re-run is benign
> sf data query --target-org <org_alias> -q "SELECT COUNT() FROM PricebookEntry WHERE Pricebook2.Name = '<store_name> Price Book' AND IsActive = true"
> ```
>
> Expected: count > 0 (typically 85 active entries matching `DIYStore Custom Price Book` source). If count is 0, the duplicate-key error is masking a real problem — surface the apex log. If count matches the source, skip the apex re-run and proceed to the next step.
>
> **Why the script doesn't guard against this:** `storePricebookCreation.apex` doesn't pre-query existing entries before insert. Adding a `WHERE NOT IN` filter would make it idempotent, but the historical script was authored under the assumption it'd run exactly once. The verification-after-error pattern above is the no-code-change workaround.

### 6b. Verify PricebookEntries copied (FALLBACK)

**Verify** — count entries on the new store pricebook:
```powershell
sf data query -q "SELECT COUNT() FROM PricebookEntry WHERE Pricebook2.Name = '<store_name> Price Book' AND IsActive = true" -o <org_alias>
sf data query -q "SELECT COUNT() FROM PricebookEntry WHERE Pricebook2.Name = 'DIYStore Custom Price Book' AND IsActive = true" -o <org_alias>
```

Expected: the `<store_name> Price Book` count should equal (or be close to) the `DIYStore Custom Price Book` count.

**Fallback (only if `<store_name> Price Book` count is 0 or significantly lower)** — re-run Step 6:
```powershell
powershell.exe -Command "sf apex run -f scripts/apex/storePricebookCreation.apex --target-org <org_alias>"
```
If still empty after the retry, STOP — the source `DIYStore Custom Price Book` is missing (sample
data import failed) or has no active entries.

---

## Element Selectors (Step 1)

| Element | CSS Selector | Use For |
|---------|--------------|---------|
| Toggle (click) | `label.slds-checkbox_toggle` | Clicks |
| Toggle (state) | `[data-automation="autoIndexToggle"]` | Verification |

⚠️ Do NOT click the `<input>` checkbox - the label intercepts pointer events.

---

## Files Used

- `scripts/apex/enableGuestBrowsing.apex` → calls `SecurityConfigHelper.printGuestBrowsingStatus()`
- `scripts/apex/assignGuestBuyerToGroups.apex` → calls `SecurityConfigHelper.assignGuestBuyerToGroups()`
- `scripts/apex/enableAccountAsBuyer.apex` → calls `SecurityConfigHelper.enableAccountAsBuyer()`
- `scripts/apex/createCommerceData.apex` → calls `generateCommerceData.createCommercePolicy()`
- `scripts/apex/storePricebookCreation.apex` → calls `generateCommerceData.insertionPricebookStore()`
- `diy-pd-pack/main/default/classes/SecurityConfigHelper.cls`
- `diy-pd-experience-optional/main/default/classes/generateCommerceData.cls`

---

## Notes

- All steps are idempotent - safe to run multiple times
- Step 1 uses Playwright (no API available)
- Steps 2-6 use Apex scripts that delegate to helper class methods

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If any apex step fails, **do NOT clean up** — leave artifacts for debugging.
- Fix the underlying issue, retry, then run cleanup once Steps 1–6 all succeed.

**Files this skill creates and must delete:**

```bash
rm -f /c/tmp/egb.out
rm -f /c/tmp/agb.out
rm -f /c/tmp/agb2.out
rm -f /c/tmp/eab.out
rm -f /c/tmp/ega.out
rm -f /c/tmp/ccd2.out
rm -f /c/tmp/spc2.out
rm -f check_buyer_groups.soql
```

**Folders this skill creates via Playwright (Step 1) and must delete:**

```bash
cmd.exe //c "rmdir /S /Q .playwright-mcp" 2>/dev/null || rm -rf .playwright-mcp
```

**Verification (must show no leftovers):**

```bash
ls /c/tmp/egb.out /c/tmp/agb.out /c/tmp/agb2.out /c/tmp/eab.out /c/tmp/ega.out /c/tmp/ccd2.out /c/tmp/spc2.out 2>&1 | grep -v "cannot access"
ls *.soql 2>&1 | grep -v "cannot access"
ls -d .playwright-mcp 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete items listed above. Do NOT delete `scripts/apex/enableGuestAccessOneShot.apex` — it's a repo helper that the canonical `enableGuestBrowsing.apex` (Step 2) depends on for actually creating the Guest Buyer Group.
- ❌ Skipping this step is not allowed once Steps 1–6 all succeed.
