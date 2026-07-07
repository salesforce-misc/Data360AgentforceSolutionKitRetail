---
name: configure-experience-site-images
description: "Configure ALL Experience Cloud site branding (Site Logo + Background/Left/Right Banner Images + Embedded Messaging chat icon) in ONE retrieve + ONE deploy + ONE publish. Stripping any stale chat-icon placements anywhere outside the canonical layout footer is part of the same single-deploy operation. Use when the user wants to: 'configure site images', 'set site logo', 'update banner images', 'place embedded messaging icon in storefront footer', 'add chat icon to storefront footer', 'remove duplicate chat icons', 'embed service agent on storefront', 'publish storefront with chat icon'."
---

# configure-experience-site-images

## Purpose

Configure every piece of site branding in a single round-trip: Site Logo (header + footer), Background Banner, Left/Right Banner sections, and the Embedded Messaging chat icon — all retrieved once, edited together, deployed together, and the community is published exactly once at the end.

**Why one retrieve / one deploy / one publish:** earlier versions of this skill ran three independent retrieve→edit→deploy→publish cycles (logo, banners, chat icon). Each publish had its own cache-propagation window, and when Step 4's chat-icon publish landed before Step 3's banner publish had fully propagated, the storefront would show stale logo/banner state OR a missing chat icon depending on which cache won. Folding everything into one cycle makes the change atomic from the live site's perspective.

The chat-icon work uses a **remove-first-then-add** pattern: stale chat-icon component placements anywhere outside the canonical layout footer (typically baked into `sfdc_cms__view/home/content.json` from a source org with foreign `scrtUrl`/`siteEndpoint` values) are surgically stripped first, then the icon is inserted into the layout footer if not already present. The icon goes into the **layout footer once** — `commerceLayout` is the theme layout that wraps the storefront, so the footer it defines renders below every page.

---

## Prerequisites

- Site exists (created via `setup-commerce-site` skill)
- Experience package deployed (`diy-pd-experience-optional`)
- SF CLI authenticated to target org (`sf org login web --alias <alias>`)
- Python 3 on PATH (the consolidated script is Python; no PowerShell required)
- Images uploaded **and Published** in the **DIYStoreFront CMS Workspace** (or whatever workspace `cms-workspace-setup` provisioned). The script accepts the canonical names AND common spaced/extension variants — see `CMS_NAME_VARIANTS` in [scripts/python/configure_site_branding.py](../../../scripts/python/configure_site_branding.py):
  - `DIYStoreLogo` (also accepts: `DIYStore Logo`, `DIYStore_Logo`, `DIYStoreLogo.jpeg`, `DIYStore Logo.jpeg`) - Site Logo (header & footer)
  - `DIYStoreBanner` (also accepts: `DIYStore Banner`, `DIYStore_Banner`, `DIYStoreBanner.png`, `DIYStoreBanner.jpeg`) - Main Background Image
  - `DIYStoreBanner2` (also accepts: `DIYStore Banner2`, `DIYStore_Banner2`, `DIYStoreBanner2.jpeg`, `DIYStoreBanner2.png`) - Right Background Image
  - `DIYStoreBanner3` (also accepts: `DIYStore Banner3`, `DIYStore_Banner3`, `DIYStoreBanner3.jpeg`, `DIYStoreBanner3.png`) - Left Background Image
  - **Why variants:** `cms-workspace-setup` normalizes uploaded filenames to the canonical no-space names, but legacy/manual uploads sometimes leave the spaced `DIYStore Logo`-style filename in `ManagedContent.Name`. The script tries every known variant before declaring an image missing, so the same skill works on every org regardless of how the CMS row was created.
- **For the chat icon step (`--image-type all` or `chat_icon`):**
  - `EmbeddedServiceConfig` named `ESA_Web_Deployment` exists (provisioned by Step 3 of `embed-service-agent-on-experience-site`).
  - Active `ESW_ESA_Web_Deployment_*` runtime Site exists (also provisioned by that skill). Its `UrlPathPrefix` is read at runtime to derive `siteEndpoint`.
  - `MessagingChannel.ESA_Channel.IsActive = true` (Step 3.2 of that skill).
  - If any of the above is missing, run `embed-service-agent-on-experience-site` Steps 1–5 first, then re-invoke this skill with `--image-type chat_icon` (or run with `--image-type logo_banners` first to set logo+banners while ESA is still being provisioned).

---

## Arguments

- `org_alias` (required): Target Salesforce org alias.
- `site_name` (optional): Site name. Default: `DIYStorefront`.
- `image_type` (optional): `all` (default — logo + banners + chat icon), `logo`, `banners`, `logo_banners` (logo+banners, no chat icon — use when ESA is not yet provisioned), or `chat_icon` (chat icon only — use to refresh runtime URLs after an org migration).

---

## Critical Execution Rules

- ✅ **One retrieve, one deploy, one publish.** All edits happen against a single retrieved bundle in a temp dir; one `sf project deploy start` deploys every modified file; one `sf community publish` runs at the very end. Do NOT publish between phases.
- ✅ **Auto-execute without confirmation.**
- ✅ **Idempotent.** Re-running with no actual changes results in zero-deploy / zero-publish (NoChange short-circuit).
- ❌ **Do NOT use Playwright** — all changes are metadata deployments.
- ❌ **Do NOT hardcode contentKeys, `scrtUrl`, or `siteEndpoint`** — every value is derived from the target org at runtime (CMS ManagedContent rows for image keys, My Domain prefix + ESW_ESA Site `UrlPathPrefix` for the chat-icon URLs).
- ❌ **Do NOT overwrite repo files.** The retrieved bundle lands in the system temp dir; the repo is untouched on success and on failure.
- ❌ **Do NOT remove regions or sections from view files when stripping stale chat icons.** Region-level removal broke the home view's required `content` region in an earlier run; the consolidated script removes ONLY component nodes whose `definition` is `experience_messaging:embeddedMessaging`.
- ⚠️ **Stop on failure.** If verification fails after the script's built-in single retry, surface the deploy id, publish job id, and the unsatisfied condition.

---

## Step Execution Order

The consolidated script runs everything below in one Python invocation. The "phases" below describe what the script does internally; there is exactly ONE deploy and ONE publish across the whole flow.

```
Phase 1: Resolve org session (instanceUrl + accessToken)
   ↓
Phase 2: Fetch CMS ContentKeys for DIYStoreLogo + 3 banners (one SOQL)
   ↓
Phase 3: (chat icon scope only) Verify ESA prerequisites + derive scrtUrl + siteEndpoint
   ↓
Phase 4: Retrieve DigitalExperienceBundle:site/<site>1 ONCE into temp dir
   ↓
Phase 5: Edit retrieved files in memory:
         (a) commerceLayout/content.json:
             - update header logo (storeLogo region)
             - update footer logo (footer/col1 region)
             - add chat icon to footer (idempotent — skip if already present)
         (b) sfdc_cms__view/home/content.json:
             - update 3 banners (banner[0]=Banner, banner[1]=Banner3, banner[2]=Banner2)
         (c) every other content.json:
             - strip any stale chat-icon component placements (component-level only)
   ↓
Phase 6: ONE sf project deploy start with one --source-dir per modified component
   ↓
Phase 7: ONE sf community publish
   ↓
Phase 8: Verify (single re-retrieve, multiple checks):
         - logo contentKey appears >=2 times in commerceLayout
         - each banner contentKey appears >=1 time in home view
         - chat icon present in commerceLayout (footer)
         - no chat icon in any other content.json
   ↓
Phase 8b: FALLBACK — if any check fails, re-deploy + re-publish ONCE, re-verify
   ↓
Phase 9: Cleanup scratch on success; preserve on failure
```

---

## Image / Component Mapping

| Section | Source | Target |
|---------|--------|--------|
| Site Logo (Header) | CMS `DIYStoreLogo` | commerceLayout `storeLogo` region — `dxp_content_layout:siteLogo` |
| Site Logo (Footer) | CMS `DIYStoreLogo` | commerceLayout `footer` → `col1` region — `dxp_content_layout:siteLogo` |
| Background (Hero) | CMS `DIYStoreBanner` | home view first `dxp_content_layout:banner` |
| Left Section | CMS `DIYStoreBanner3` | home view second `dxp_content_layout:banner` (counterintuitive: left=Banner3) |
| Right Section | CMS `DIYStoreBanner2` | home view third `dxp_content_layout:banner` (counterintuitive: right=Banner2) |
| Embedded Messaging chat icon | Built-in LWR component `experience_messaging:embeddedMessaging` (no source under `lwc/`) | commerceLayout `footer` region — last child, wrapped in a new `community_layout:section` |

---

## Execution

### One command — consolidated retrieve + edit + deploy + publish + verify

```bash
python scripts/python/configure_site_branding.py \
    --org-alias <org_alias> \
    --site-name <site_name>
```

**Optional flags:**

- `--image-type all` (default): logo + banners + chat icon.
- `--image-type logo_banners`: logo + banners only — use when ESA is not yet provisioned.
- `--image-type chat_icon`: chat icon only — use to refresh `scrtUrl`/`siteEndpoint` after an org migration.
- `--image-type logo` / `--image-type banners`: scope to one image group.
- `--force-reinsert` (chat icon only): strip the existing chat-icon section from the footer before inserting a fresh one. Use to refresh runtime URLs.
- `--keep-scratch`: preserve scratch dir on success (debugging only).

**Recommended workflow (Mode 2 in the data360-retail-installer):**

1. Run with `--image-type logo_banners` early in the install flow — does NOT require ESA.
2. Run `embed-service-agent-on-experience-site` (skill 20) — provisions ESA.
3. Re-invoke this skill with `--image-type chat_icon` — single retrieve / single deploy / single publish updates only the icon.

If ESA is already provisioned before this skill runs (e.g. during a re-install), `--image-type all` (the default) does logo + banners + chat icon in one cycle.

### What the script verifies (Phase 8)

- **Logo:** `DIYStoreLogo` contentKey appears at least twice in `commerceLayout/content.json` (header + footer).
- **Banners:** each of the 3 banner contentKeys appears at least once in `sfdc_cms__view/home/content.json`.
- **Chat icon (when in scope):**
  - `"experience_messaging:embeddedMessaging"` literal is present in `commerceLayout/content.json`.
  - The component's `attributes.scrtUrl`, `attributes.siteEndpoint`, AND `attributes.deploymentName` all match the runtime values derived from the target org (My Domain prefix → `scrtUrl`; runtime ESW_ESA Site `UrlPathPrefix` → `siteEndpoint`; `deploymentName` must be `"ESA_Web_Deployment"`).
  - No other `content.json` in the bundle contains the chat icon literal — exactly one chat icon site-wide.

**Chat-icon edit policy is unconditional strip-then-add:** every run with chat-icon scope (default `--image-type all` or explicit `--image-type chat_icon`) ALWAYS removes every existing chat-icon component from the commerceLayout footer, then inserts a single fresh one pointing at the current org's `ESA_Web_Deployment`. There is no "skip if attrs already match" short-circuit — a stale icon from a source-org retrieve renders but never connects (foreign `scrtUrl`), and silent skips were the source of "icon shows but doesn't open" reports across orgs. Re-inserting unconditionally costs ~1 extra deploy round-trip per run and guarantees the live icon always points at the runtime ESA Web Deployment.

If any check fails, the script automatically retries the deploy + publish once (Phase 8b), then re-verifies. If verification still fails after the retry, exits with the deploy id, publish job id, and the list of unsatisfied conditions.

### Exit codes

- `0` — Success.
- `1` — Deploy / publish / verify failed (after the single retry).
- `2` — ESA prerequisites missing (only when `chat_icon` is in scope). Run `embed-service-agent-on-experience-site` Steps 1–5 first.
- `3` — A required CMS image is not found / not Published. Run `cms-workspace-setup` to upload + publish, then retry.

---

## Why this is one script and not three steps

Earlier versions split the work into three separate steps (logo via PowerShell, banners via PowerShell, chat icon via Python), each with its own retrieve + deploy + publish. That introduced three failure modes that we kept observing on different orgs:

1. **Cache-propagation races between publishes.** Step 2's publish would still be propagating when Step 3 re-retrieved the bundle, so Step 3 sometimes operated on a pre-Step-2 snapshot, then Step 3's publish would clobber Step 2's logo update.
2. **PowerShell scripts that don't ship in every branch.** `scripts/powershell/` is absent in some checkouts; the agent was forced to improvise a Python walker on every run, with subtly different selector logic each time.
3. **Three publishes meant three opportunities for cache cores to disagree.** End-users saw "logo updated but banner stale," "logo + banner correct but no chat icon," etc. — different on every org.

The consolidated script fixes all three: one retrieve produces a consistent snapshot, one deploy applies every change atomically, one publish triggers a single cache invalidation, and the verify-then-retry-once-then-fail policy gives us a deterministic outcome.

---

## Files Used

- `scripts/python/configure_site_branding.py` - Consolidated retrieve / edit / deploy / publish / verify entrypoint (the only script this skill invokes)
- `digitalExperiences/site/<SiteName>1/sfdc_cms__themeLayout/commerceLayout/content.json` (read + edited via temp-dir retrieve; **repo file untouched**)
- `digitalExperiences/site/<SiteName>1/sfdc_cms__view/home/content.json` (read + edited via temp-dir retrieve; **repo file untouched**)
- **Runtime-only paths under the system temp dir:**
  - `<system_temp>/diy-site-branding/work/...` — retrieved-then-edited working copy
  - `<system_temp>/diy-site-branding/sfdx-deploy-<random>/...` — self-contained SFDX project for the partial deploy
  - `<system_temp>/diy-site-branding/verify/...` and `verify-retry/...` — re-retrieve(s) for verification

---

## Notes

- contentKeys are unique per org — always fetched dynamically at runtime (no hardcoding).
- Images must be **Published** in CMS Workspace (not just Draft) — exit code `3` covers the unpublished case.
- `scrtUrl` and `siteEndpoint` are derived from the target org at runtime — never read from the repo, so an org migration never bakes in stale URLs.
- The script never writes to `diy-pd-experience-optional/` or any other repo path; the retrieve uses `--target-metadata-dir` outside the repo so source-tracking can't interfere.
- Hard refresh Experience Builder (Ctrl+Shift+R) to see changes after a successful publish.

---

## Cleanup

The script auto-cleans its scratch dir under `<system_temp>/diy-site-branding/` on success. On failure it preserves the scratch for inspection. Pass `--keep-scratch` to preserve on success too (debugging only).

Manual cross-platform cleanup (only needed if the script was killed mid-run or `--keep-scratch` was passed):

```bash
python -c "import shutil, tempfile, pathlib; shutil.rmtree(pathlib.Path(tempfile.gettempdir()) / 'diy-site-branding', ignore_errors=True)"
```

**Failure-handling rule:** if the script exits non-zero, do NOT clean up — leave the scratch dir for debugging. Fix the underlying issue, re-run the skill, then the next successful run cleans up automatically.

**Rules:**
- ✅ Do NOT delete: `scripts/python/configure_site_branding.py` (repo source — the entrypoint), `Experience Cloud/*.png` (repo source — branding image originals), `scripts/apex/getCMSImageContentKey.apex` (repo source — referenced by `cms-workspace-setup`), `diy-pd-experience-optional/**` (repo source — the script retrieves into the system temp dir, never writes here), `diy-embeddedservice/**` (repo source consumed by the prerequisite ESA skill).
- ✅ The script makes ZERO repo edits. There is no "rollback contentKeys to placeholder" step — earlier versions of this skill needed one because the PowerShell scripts wrote into the repo. The consolidated script does not.
