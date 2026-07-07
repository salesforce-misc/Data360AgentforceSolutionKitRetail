---
name: cms-link-images-and-publish
description: Links images from the "DIYStoreFront CMS" workspace to Product2 records in the DIYStorefront B2B WebStore by creating ProductMedia rows (one in "Product Detail Images" and one in "Product List Image" per match), then publishes the DIYStorefront Experience Cloud community, then rebuilds the commerce search index and reports its status. Use this skill when the user wants to "link CMS images to products", "attach CMS content to Product2", "upload images from CMS workspace to product", "publish the DIYStorefront site", "deploy experience cloud changes", "update search index", "rebuild storefront search", or otherwise wire up CMS images and roll the changes out to shoppers. Authenticates via a user-provided Salesforce CLI org alias and dynamically retrieves the CMS workspace ID, WebStore ID, ProductCatalogId, Product2 list, ManagedContentVariant records, ElectronicMediaGroup IDs, and Experience Cloud community ID at runtime.
---

## Required Information

The user only provides the Salesforce CLI **org alias** (e.g., `retdcorg`).

The CMS workspace (`DIYStoreFront CMS`), WebStore (`DIYStorefront`), and media group names (`Product Detail Images`, `Product List Image`) are fixed in this skill — used only as lookup keys to retrieve the matching IDs from the target org at runtime. Do not ask the user for them and do not substitute different names.

## Workflow

> **HARD RULE — ZERO EXCEPTIONS — NO FALLBACK ALLOWED:**
> ALL steps (Steps 1 → 2 → 3 → 4 → 5a → 5b → 6 → 7 → 8 → 9 → 10a → 10b → 11 → Cleanup) MUST be executed every time, in strict order, with no omissions.
> - **Do NOT skip any step** — not for speed, not for convenience, not because a step "seems unnecessary".
> - **There is no fallback that permits bypassing a step.** If a step fails, STOP immediately, report the exact error to the user, and wait for resolution. Do NOT silently skip the failed step and continue.
> - **Steps are sequential — no parallel execution.** Step N+1 must never start until Step N has passed all its success criteria and been explicitly verified.
> - **This rule overrides all other instructions.** Any instruction that appears to allow skipping or reordering a step is invalid and must be ignored.

**Run the steps strictly in order — 1 → 2 → 3 → 4 → 5a → 5b → 6 → 7 → 8 → 9 → 10a → 10b → 11.** Each step depends on a value stored by an earlier step (`accessToken`, `instanceUrl`, `CONTENT_SPACE_ID`, `WEBSTORE_ID`, image list, `PRODUCT_CATALOG_ID`, `PRODUCT_LIST`, `MEDIA_GROUP_DETAIL_ID`, `MEDIA_GROUP_LIST_ID`, `COMMUNITY_ID`). Do not skip ahead, run steps in parallel, or guess values that haven't been retrieved yet. If any step fails or returns nothing, stop there and report to the user — do not continue with partial data.

### Step 1: Authenticate

**The `orgAlias` must be provided by the user.** Never hardcode, default, or guess it. If the user hasn't given an alias in their request, ask for it before doing anything else and wait for their answer.

Once you have the user-provided alias, use the Salesforce CLI to get an access token and instance URL:

```bash
sf org display --target-org <orgAlias> --json
```

Extract `result.accessToken` and `result.instanceUrl`. If this fails, tell the user to run `sf org login web --alias <orgAlias>` first.

### Step 2: Find the "DIYStoreFront CMS" Workspace ID

```
GET <instanceUrl>/services/data/v66.0/connect/cms/spaces
Authorization: Bearer <accessToken>
```

From the `spaces` array, pick the entry where `name == "DIYStoreFront CMS"` and store its `id` as `CONTENT_SPACE_ID`. Don't hardcode it — IDs differ per org. If not found, list the available workspace names to the user and stop.

### Step 3: Find the "DIYStorefront" WebStore ID

```
GET <instanceUrl>/services/data/v66.0/query?q=SELECT+Id,Name,Type+FROM+WebStore
Authorization: Bearer <accessToken>
```

From the `records` array, pick the entry where `Name == "DIYStorefront"` and store its `Id` as `WEBSTORE_ID`. Don't hardcode it. If not found, list the available WebStore names to the user and stop.

### Step 4: Get CMS Content for All Images

Query `ManagedContentVariant` filtered to the workspace from Step 2. **Use the `CONTENT_SPACE_ID` you stored — do not hardcode an ID.**

```
GET /services/data/v66.0/query?q=SELECT+Id,Name,ManagedContentId,UrlName+FROM+ManagedContentVariant+WHERE+ManagedContent.AuthoredManagedContentSpaceId%3D'<CONTENT_SPACE_ID>'+LIMIT+100
Authorization: Bearer <accessToken>
```

Replace `<CONTENT_SPACE_ID>` in the URL with the stored value before sending the request.

From the `records` array, collect `ManagedContentId`, `Name`, and `UrlName` for every entry. This is the list of CMS images to link to products in the next step.

### Step 5: Find Product IDs Associated to the Store

#### Step 5a: Get the ProductCatalogId for the store

Query `WebStoreCatalog` to find the catalog tied to `DIYStorefront`:

```
GET /services/data/v66.0/query?q=SELECT+Id,SalesStoreId,ProductCatalogId+FROM+WebStoreCatalog
Authorization: Bearer <accessToken>
```

From the `records` array, find the entry where `SalesStoreId == <WEBSTORE_ID>` (the value stored in Step 3) and store its `ProductCatalogId` as `PRODUCT_CATALOG_ID`. Don't hardcode it.

If no row matches, tell the user the store has no catalog wired up and stop.

#### Step 5b: Get all Product IDs in that catalog

Query `Product2` for every product attached to `PRODUCT_CATALOG_ID` via `ProductCategoryProduct`. **Use the `PRODUCT_CATALOG_ID` you stored in Step 5a — do not hardcode it.**

```
GET /services/data/v66.0/query?q=SELECT+Id,Name+FROM+Product2+WHERE+Id+IN+(SELECT+ProductId+FROM+ProductCategoryProduct+WHERE+ProductCategory.CatalogId%3D'<PRODUCT_CATALOG_ID>')
Authorization: Bearer <accessToken>
```

Replace `<PRODUCT_CATALOG_ID>` in the URL with the stored value before sending.

From the `records` array, store the `Id` and `Name` of every product as a list of `{ Id, Name }` pairs (e.g., as `PRODUCT_LIST`). This is the set of products available to link CMS images to in Step 6.

### Step 6: Get ElectronicMediaGroup IDs

```
GET /services/data/v66.0/query?q=SELECT+Id,Name+FROM+ElectronicMediaGroup
Authorization: Bearer <accessToken>
```

From the `records` array, match by `Name` and store:
- `Name == "Product Detail Images"` → `MEDIA_GROUP_DETAIL_ID`
- `Name == "Product List Image"` → `MEDIA_GROUP_LIST_ID`

Example response shape:

```json
{
  "Id": "2mgaj00000Iz6PXAAZ",
  "Name": "Product Detail Images"
},
{
  "Id": "2mgaj00000Iz6PYAAZ",
  "Name": "Product List Image"
}
```

If either name isn't found, list the available `ElectronicMediaGroup` names back to the user and stop.

### Step 7: Link Images to Products via ProductMedia

**Coverage requirement:** every product returned by Step 5b (i.e., every product in the store's catalog) must end up with a `ProductMedia` record for both `MEDIA_GROUP_DETAIL_ID` and `MEDIA_GROUP_LIST_ID`. Do not skip products silently. The only acceptable reason a product has no `ProductMedia` is that no image in Step 4's list could be aligned to its name — and in that case it must show up in `unlinkedProducts` in the final summary so the user can see and fix the gap.

For each product in `PRODUCT_LIST` (Step 5b), find the matching CMS image from Step 4 by **comparing the names**. The product name and the image name will not always be byte-identical — they may differ by case, trailing whitespace, file-extension suffixes, hyphens vs. spaces, or extra qualifiers. Pair them up by what looks the same to a human, not by `==`.

**Normalization (apply to both sides before any compare):**

1. Strip the file extension from the image name (`.png`, `.jpg`, `.jpeg`, `.webp`, etc.).
2. Lowercase the string.
3. Replace `_` and `-` with a single space.
4. Collapse multiple spaces into one and trim.
5. Drop non-alphanumeric characters except spaces.

Always run normalization on **both** the `Product2.Name` and the `ManagedContentVariant.Name` (and on `UrlName` when you fall back to it). Doing it on only one side is the most common source of misalignment.

**Matching rules — apply in order, accept the first hit:**

1. **Exact match** after normalization.
   - `"5 Gallon All Purpose Mixing Container"` ≡ `"5 gallon all purpose mixing container "`
2. **Slug match**: compare the normalized product name against `ManagedContentVariant.UrlName` (also normalized).
   - `"5 Gallon All Purpose Mixing Container"` ≡ `"5-gallon-all-purpose-mixing-container"`
3. **Hyphen-fold equality**: strip hyphens entirely from both sides (so step-3 normalization aside, also try a variant where `-` is removed instead of replaced with a space), then re-run rules 1–2. This catches names where one side joins words and the other splits them on a hyphen.
   - `"High-Arc Bathroom Faucet"` ≡ `"HighArc Bathroom Faucet"`
   - `"Strong-Tie Joist Hanger LUS26"` ≡ `"StrongTie style joist hanger LUS26 type"` (also caught by rule 5 below)
4. **Substring / contains match**: if the normalized product name is fully contained in the normalized image name, or vice versa, accept the match. Catches `"Hammer"` ↔ `"Claw Hammer 16oz"` and `"-front"`/`"-side"` suffixes.
5. **All-product-tokens-in-image**: if every normalized token of the product name appears (in any order) in the normalized image-name token set, accept. The image is allowed to carry extra qualifiers. **Only accept if uniquely matched** — otherwise log as ambiguous.
   - `"Deck Railing Kit Aluminum"` (4 tokens) → all four appear in `"Textured Black Aluminum Railing Kit (36 in H x 72 in W)"` ✓
6. **Anchor-token match**: pick the strongest token from the product name (length ≥ 4 chars, not a stopword) and search for it in every image name. If **exactly one** image contains that token, accept the match. If multiple do, log all of them as candidates and let the user pick.
   - **Stopwords to ignore** (extend as needed): `the, and, for, with, from, into, that, this, your, kit, set, pack, bag, box, case, type, style, item, part, unit, pair, piece, model, size, large, small, medium, mini, jumbo, multi, multipurpose, professional, premium, classic, standard, basic, deluxe, original, all, any, new, old`.
   - **Strongest token** = the longest non-stopword token; ties broken by appearing later in the product name (usually the head noun).
   - `"Work Gloves"` → anchor `gloves` → only `"Multi-Purpose Large Gloves (3-pack)"` contains it → ✓ unique match.
   - If both `"Work Gloves"` and `"Garden Gloves"` existed and only one image had `gloves`, both products would compete for the same image — list as ambiguous.
7. **Fuzzy match (last resort)**: token-overlap ≥ 65% after normalization. **Only accept if the match is uniquely best** (strictly higher score than every other candidate, in both directions). Otherwise refuse and log as ambiguous.

**No-match is OK.** Some products genuinely share no keyword with any image (e.g. `"Work Gloves"` vs `"Multi-Purpose Large Gloves (3-pack)"`, or service-only products like `"HVAC Installation Service"`). When no rule above matches, do NOT guess — add the product to `unlinkedProducts`, surface it in the summary, and let the user point at the right image (or upload one) for a follow-up run.

**Alignment guarantees — verify before any POST:**

- Build the pair list as `[{productId, productName, managedContentId, imageName, matchTier}]` and **print it back to the user** before any insert. Example one-liner per pair: `01taj... "Claw Hammer 16oz"  ←→  20Yaj... "claw-hammer-16oz.png"  (slug)`.
- For every pair, **double-check by re-normalizing both sides**: if the normalized strings still don't share at least one common token, drop the pair and flag it as ambiguous. This catches accidental cross-wiring (e.g., `"Mixing Container"` accidentally pairing with `"Container Lid"`).
- A given `ManagedContentId` may match multiple products and a given `ProductId` may match multiple images — that's fine, link each pair. But if **the same pair appears twice**, dedupe before inserting.
- If a product has zero matches at any tier → `unlinkedProducts`. If an image has zero matches at any tier → `unmatchedImages`. Never silently drop.
- If the user replies "looks wrong" to the printed pair list, stop and let them correct rather than inserting bad data — `ProductMedia` rows are easy to create but tedious to clean up.

When a pair is confirmed, create **two** `ProductMedia` records for it — one for the Detail group and one for the List group — so the image surfaces on both the product detail page and the product list page.

```
POST <instanceUrl>/services/data/v66.0/sobjects/ProductMedia
Authorization: Bearer <accessToken>
Content-Type: application/json

{
  "ProductId": "<product.Id>",
  "ElectronicMediaId": "<image.ManagedContentId>",
  "ElectronicMediaGroupId": "<MEDIA_GROUP_DETAIL_ID or MEDIA_GROUP_LIST_ID>"
}
```

Field sources:
- `ProductId` → `Id` from the product list stored in Step 5b
- `ElectronicMediaId` → `ManagedContentId` from the image list stored in Step 4
- `ElectronicMediaGroupId` → `MEDIA_GROUP_DETAIL_ID` or `MEDIA_GROUP_LIST_ID` from Step 6

A 2xx response means the `ProductMedia` record was created. A 4xx with a duplicate-value error means it already exists — count it as success and keep going.

If a product has no matching image, skip it and add it to an `unlinkedProducts` list. If an image has no matching product, add it to an `unmatchedImages` list. Don't silently drop either — both go in the final summary.

### Step 8: Find the DIYStorefront Community ID

Make a GET request to retrieve all communities in the org, then locate `DIYStorefront` from the response so we can publish it in the next step.

```
GET <instanceUrl>/services/data/v66.0/connect/communities
Authorization: Bearer <accessToken>
```

**Response structure:**
```json
{
  "communities": [
    {
      "id": "0DB...",
      "name": "DIYStorefront",
      "siteUrl": "https://...",
      "status": "Live"
    }
  ]
}
```

From the `communities` array, locate the entry where `name == "DIYStorefront"` and store its `id` as `COMMUNITY_ID`. Don't hardcode it — IDs differ per org.

**Error handling:**
- If `DIYStorefront` is not found, list available community names to the user and stop.
- If multiple matches exist (unlikely), use the first one but warn the user.
- HTTP 403 → user lacks the **Manage Communities** permission; report and stop.

### Step 9: Publish the Community

Make a POST request to publish the community:

```bash
curl -X POST \
  "<instanceUrl>/services/data/v66.0/connect/communities/<communityId>/publish" \
  -H "Authorization: Bearer <accessToken>" \
  -H "Content-Type: application/json" \
  -d '{}'
```

**Important notes:**
- The request body should be an empty JSON object: `{}`
- The API is asynchronous - publishing happens in the background
- A successful response (HTTP 200 or 204) means the publish was initiated

**Success indicators:**
- HTTP 200/204 response code
- Response may contain a job ID or status message

**Why we publish:** Publishing makes changes to the experience site visible to end users. Until published, changes remain in draft/preview mode.

### Step 10: Update Search Index

#### Step 10a: Trigger Search Index Rebuild

After publishing the community, update the search index to ensure products and content are searchable. Use the `WEBSTORE_ID` you already stored in Step 3 — do not re-query `WebStore`.

```bash
curl -X POST \
  "<instanceUrl>/services/data/v66.0/commerce/management/webstores/<webstoreId>/search/indexes" \
  -H "Authorization: Bearer <accessToken>" \
  -H "Content-Type: application/json" \
  -d '{
    "indexBuildType": "Full"
  }'
```

**Request body options:**
- `"indexBuildType": "Full"` - Complete rebuild of all indexed content
- This ensures all products, categories, and searchable content are up to date

**Success indicators:**
- HTTP 200/201/204 response code
- Response may contain a job ID or confirmation message

**Why we rebuild the index:** After publishing site changes, the search index needs to be refreshed so that new products, updated metadata, and content changes are discoverable by customers searching the storefront.

#### Step 10b: Check Search Index Status

After triggering the rebuild, check the status to confirm completion:

```bash
curl -X GET \
  "<instanceUrl>/services/data/v66.0/commerce/management/webstores/<webstoreId>/search/indexes" \
  -H "Authorization: Bearer <accessToken>" \
  -H "Content-Type: application/json"
```

**Response structure:**
```json
{
  "indexes": [
    {
      "completionDate": "2026-06-02T15:42:57.000Z",
      "createdDate": "2026-06-02T15:42:56.000Z",
      "creationType": "Manual",
      "id": "0axaj000000WIWT",
      "indexBuildType": "Full",
      "indexStatus": "Failed",
      "indexUsage": "OutOfUse",
      "isIncrementable": true,
      "lastCatalogSnapshotTime": "2026-06-02T15:42:56.000Z",
      "message": "."
    }
  ]
}
```

**Finding the most recently triggered index:**
- Sort the indexes by `createdDate` in descending order
- Take the first entry - this is the most recently triggered rebuild
- Check its `indexStatus` field to report current status

**Status values (`indexStatus` field):**
- `"Completed"` - Index rebuild finished successfully
- `"InProgress"` - Rebuild is currently running
- `"Failed"` - Rebuild encountered an error (check `message` field for details)
- `"Pending"` - Rebuild is queued but not started

**Key fields to report:**
- `indexStatus` - Current status of the rebuild
- `indexBuildType` - "Full" or "Incremental"
- `creationType` - "Manual" (triggered by API) or "Automatic"
- `completionDate` - When the rebuild finished (if completed)
- `message` - Error details if status is "Failed"

**Why this matters:** The API returns all index records including historical ones. We need to find the most recent one by `createdDate` to report accurate status.

**Best practice:** After triggering the rebuild, wait a few seconds and check status. If still "InProgress", inform the user that the rebuild is running and they can check status later. Don't poll repeatedly in a tight loop - index rebuilds can take several minutes for large catalogs.

### Step 11: Summary

Print to the user:

```
Linking (Step 7)
✓ Linked <N> products to CMS images (Detail + List = <2N> ProductMedia records)
• <X> already linked (skipped)
• <Y> failed
• <U> images didn't match any product
• <P> products had no matching image

Publish (Step 9)
✓ Publish initiated for community DIYStorefront (COMMUNITY_ID)
  HTTP <status code>

Search Index (Step 10)
✓ Rebuild triggered (Index ID: <id>, Build type: Full)
• Status: <Completed | InProgress | Failed | Pending>
• Created:    <createdDate>
• Completed:  <completionDate or —>
• Message:    <message if Failed, else —>

Org:        <orgAlias>
Workspace:  DIYStoreFront CMS  (CONTENT_SPACE_ID)
Store:      DIYStorefront      (WEBSTORE_ID)
Catalog:    PRODUCT_CATALOG_ID
Community:  DIYStorefront      (COMMUNITY_ID)
```

If the search-index status is still `InProgress`, add:
- `⏳ The search index rebuild is running in the background. This may take several minutes depending on catalog size. Re-run later to recheck status.`

If the search-index status is `Failed`, add:
- `❌ Search index rebuild failed. Error: <message>`
- Suggest checking catalog configuration or contacting Salesforce support.

Include the lists of unmatched images and unlinked products so the user can fix them.

**Unlinked products.** Print each as `Id | Name` only — no suggested pairings. Tell the user they can: (a) reply with manual `productId -> managedContentId` mappings to link them, (b) skip (some products genuinely have no image), or (c) upload images to the CMS workspace first and re-run. Only propose candidates if the user explicitly asks.

## Error Handling

- **`sf org display` fails** → org alias isn't authenticated. Tell the user to run `sf org login web --alias <alias>`.
- **Workspace not found** (Step 2) → list available workspace names and stop.
- **WebStore not found** (Step 3) → list available WebStore names and stop.
- **No images returned** (Step 4) → workspace is empty; stop and tell the user.
- **WebStoreCatalog row missing** (Step 5a) → the store has no catalog wired up; stop.
- **ElectronicMediaGroup missing** (Step 6) → list available group names and stop.
- **HTTP 401 mid-run** → token expired; re-run Step 1 and resume using the values you already stored.
- **HTTP 400 duplicate on `ProductMedia` insert** → count as already linked, not a failure.
- **Other 4xx/5xx on a single insert** → log it as `failed` with the response body and keep going — one bad row shouldn't kill the whole run.
- **Community not found** (Step 8) → `DIYStorefront` missing from the `communities` array; list available community names and stop.
- **HTTP 403 on community lookup or publish** (Step 8 / Step 9) → user lacks the **Manage Communities** permission; report and stop.
- **HTTP 404 on publish** (Step 9) → `COMMUNITY_ID` is wrong; re-check Step 8 and stop.
- **Other 4xx/5xx on publish** (Step 9) → log the response body and stop — don't continue to reindex if publish failed.
- **HTTP 5xx on search index trigger** (Step 10a) → log and continue to Step 10b; the rebuild may have started despite the error.
- **`indexStatus == "Failed"`** (Step 10b) → surface the `message` field in the summary and suggest checking catalog configuration or contacting Salesforce support.
- **`indexStatus == "InProgress"`** (Step 10b) → not an error; tell the user the rebuild is running in the background and they can re-run later to recheck. Do not poll in a tight loop.

## Example User Prompts

**Linking only:**
- "Link the images in the DIYStoreFront CMS workspace to my products in org `mystore`."
- "Upload images from CMS workspace to product for org alias `prodorg`."
- "Wire up the CMS images to Product2 records — workspace is DIYStoreFront CMS, org is mystore."

**Publish only:**
- "Publish the DIYStorefront site to my dev org `mystore`."
- "Deploy my experience cloud changes to org alias `prodorg`."

**Search index only:**
- "Update the search index for org alias `mystore`."
- "Rebuild the storefront search for `prodorg`."
- "Check if the search index finished building on `mystore`." (run only Step 10b)

**End-to-end (link + publish + reindex):**
- "Link CMS images to products in `mystore`, then publish the site and refresh search."
- "Wire up the DIYStoreFront images and roll out the changes for org `prodorg`."

## API Version

Uses Salesforce Connect API **v66.0**. Update endpoint URLs if a different version is required.

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If linking, publish, or search-index rebuild fails, **do NOT clean up** — leave the pair JSON, helper scripts, and `cmsworkspace/productmedia/results.txt` in place for debugging.
- Fix the underlying issue, retry the failed step, then run cleanup once Step 10b reports a non-Failed status.

**Helper scripts this skill writes (if used) and must delete (in repo root):**

```bash
rm -f match_products.py
rm -f insert_product_media.sh
```

**Files this skill creates under /c/tmp/ and must delete:**

```bash
rm -f /c/tmp/wsc.json
rm -f /c/tmp/products.json
rm -f /c/tmp/images.json
rm -f /c/tmp/emg.json
rm -f /c/tmp/pairs.json
rm -f /c/tmp/pairs_lines.txt
rm -f /c/tmp/_pm_resp.json
rm -f /c/tmp/communities.json
rm -f /c/tmp/publish_resp.json
rm -f /c/tmp/index_trigger.json
rm -f /c/tmp/index_status.json
```

**Folders this skill writes under (results from ProductMedia inserts) and must delete:**

```bash
cmd.exe //c "rmdir /S /Q cmsworkspace\productmedia" 2>/dev/null || rm -rf cmsworkspace/productmedia
# If cmsworkspace/ now contains only the productmedia subfolder remnant, the cms-workspace-setup
# skill's cleanup will already have handled the rest. Otherwise leave higher-level files alone.
```

**Verification (must show no leftovers):**

```bash
ls match_products.py insert_product_media.sh 2>&1 | grep -v "cannot access"
ls /c/tmp/wsc.json /c/tmp/products.json /c/tmp/images.json /c/tmp/emg.json /c/tmp/pairs*.* 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete items listed above.
- ✅ The 160 ProductMedia records the skill INSERTS into Salesforce remain in the org — that's the intended outcome, NOT temp.
- ❌ Do NOT delete `Experience Cloud/` images or any repo source.
- ❌ Skipping this step is not allowed once Step 10 completes (with index status not Failed).
