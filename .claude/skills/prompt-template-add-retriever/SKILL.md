---
name: prompt-template-add-retriever
description: "Automate adding Einstein retrievers to AI prompt templates using Salesforce CLI. Queries org for retriever API names via REST API, updates prompt template XML files with correct retriever references, increments version numbers, and deploys to org. NO browser automation, CLI-only workflow. Use when user wants to add retrievers to prompt templates, update prompt templates with retrievers, or configure AI prompt template retrievers."
---

# prompt-template-add-retriever

## Purpose

Automate the process of adding Einstein retrievers to AI prompt templates using Salesforce CLI commands.

**✅ CLI-ONLY SOLUTION**

This skill automates the complete retriever configuration process for prompt templates. It queries the org for actual retriever API names, updates XML files with correct references, increments version numbers, and deploys the changes.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT generate Playwright scripts
- ❌ Do NOT use browser automation
- ✅ Use Salesforce CLI commands ONLY
- ✅ **Execute ALL commands sequentially** - wait for each to complete before proceeding
- ✅ **Query org for retriever API names** - never hardcode retriever names
- 📸 **Screenshot Policy**: N/A - This is a CLI-only skill with no browser automation

**Complete Workflow (substitute → deploy → rollback):**
1. Query org for retriever API names via REST API
2. Match retrievers by label name (Building_a_Deck, DIY_Bathroom, File_DiySeasonal)
3. Read current prompt template files and extract version numbers
4. Update Bathroom_Remodeling_Prompt with DIY_Bathroom retriever (substitute placeholder)
5. Update storageCabinetDetails with DIY_Bathroom retriever (substitute placeholder)
6. Update seasonalPlantRecomendation with File_DiySeasonal retriever (substitute placeholder)
7. Update Building_Deck_Prompt with Building_a_Deck retriever (substitute placeholder)
8. Deploy all 4 templates + Flow:Fetch_Seasonal_Products to org
9. **🚨 ROLLBACK to placeholders ONLY IF deploy succeeded** — restore the literal placeholder strings, revert version numbers, re-comment the templateDataProviders blocks. Keeps repo org-agnostic and idempotent.

**🚨 PLACEHOLDER PATTERN (org-agnostic repo):**

The repo files ship with placeholder strings, NOT real retriever IDs. Each run:
- Substitutes placeholder → real retriever name (org-specific 1Cx_* parent name)
- Deploys to org
- ON SUCCESS: rolls back the file edits to restore placeholders
- ON FAILURE: leaves files dirty so the user can debug what was about to deploy

This means:
- The repo never has org-specific IDs committed
- Re-running the skill always finds `DIY_BATHROOM_RETRIEVER` etc. — Edit tool's `old_string` always matches
- Different orgs (sandbox, prod) all start from the same placeholder baseline

**Placeholders in the repo:**
| File | Placeholder string(s) |
|---|---|
| Bathroom_Remodeling_Prompt | `DIY_BATHROOM_RETRIEVER` (3 occurrences in `<content>`) |
| storageCabinetDetails | `DIY_BATHROOM_RETRIEVER` (1 occurrence) |
| seasonalPlantRecomendation | `DIY_SEASONAL_RETRIEVER` (1 occurrence) |
| Building_Deck_Prompt | `DIY_BUILDING_RETRIEVER` (1 occurrence) |

The `<templateDataProviders>` block ships COMMENTED OUT in all 4 templates with stale retriever IDs inside the comment. The skill uncomments + replaces during substitution, then re-comments + restores stale IDs during rollback.

**🚨 KNOWN ISSUES (verified June 2026):**

1. **There are FOUR templates to update, not three** — `Building_Deck_Prompt` (mapped to the `Building_a_Deck Retriever`) is the FOURTH. Without it, the Building_a_Deck retriever sits unused. Original skill listed only 3 templates; that's incomplete.

2. **Retriever placeholder strings in `<content>`** — templates ship with placeholders like `DIY_BATHROOM_RETRIEVER`, `DIY_BUILDING_RETRIEVER`, `DIY_SEASONAL_RETRIEVER` embedded in the prompt body. Replace each occurrence with `{!$EinsteinSearch:<retriever_parent_name>.results}` (use `replace_all: true` since they appear multiple times in some templates).

3. **`templateDataProviders` block ships COMMENTED OUT** (`<!-- ... -->`). Step 4–7 must REMOVE the comment markers AND swap the old retriever name with the new one. Forgetting to remove `<!--` / `-->` leaves the retriever unwired even though the version was bumped.

4. **`seasonalPlantRecomendation` has TWO `<templateDataProviders>` blocks** — one EinsteinSearch (commented out, must be uncommented + updated) and one `flow://Fetch_Seasonal_Products` (active, MUST be preserved). Don't delete the Flow block.

5. **Flow `Fetch_Seasonal_Products` MUST be co-deployed with seasonalPlantRecomendation** — otherwise deploy fails with `Failure to create template ... Caused by: ... Fetch_Seasonal_Products is not accessible`. Always include `Flow:Fetch_Seasonal_Products` in the deploy command. Symptom in error output: 3/4 components succeed, only seasonal fails.

6. **Retriever names captured in Step 10 (Individual Retrievers) use PARENT name (1Cx prefix)**, not the configuration name (1Cy prefix). The parent name is the top-level `name` field on the retriever envelope; the configuration version `name` is inside `activeConfiguration.name`. Use the PARENT for both `invocable://getEinsteinRetrieverResults/<NAME>` and `EinsteinSearch:<NAME>` references.

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username
- `template_directory` (optional): Path to prompt templates directory. Defaults to "diy-pd-pack/main/default/genAiPromptTemplates"

---

## Preconditions

Before running:

- Salesforce CLI authenticated with target org
- User has System Administrator profile or equivalent permissions
- Einstein retrievers must exist in the org:
  - **Building_a_Deck Retriever**
  - **DIY_Bathroom Retriever**
  - **File_DiySeasonal**
- Prompt template files exist in the specified directory:
  - Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml
  - storageCabinetDetails.genAiPromptTemplate-meta.xml
  - seasonalPlantRecomendation.genAiPromptTemplate-meta.xml
- SF CLI project structure is valid (sfdx-project.json exists)
- The Data360 repository is already cloned locally and Claude Code is launched from its root (no git clone needed)

---

## Workflow

**CRITICAL EXECUTION RULES:**

1. ✅ **ALWAYS execute commands sequentially** - wait for each to complete
2. ✅ **Query org for retriever API names first** - never hardcode names
3. ✅ **Extract version numbers** before updating files
4. ✅ **Use Edit tool** to update XML (never Write tool on existing files)
5. ✅ **Increment version numbers** for all templates
6. ✅ **Wait for deployment** to complete before reporting success

**Step Execution Order:**
```
Step 0: Verify repository and template files exist
   ↓
Step 1: Query org for retriever API names via REST API
   ↓
Step 2: Parse retriever API names by label
   ↓
Step 3: Read current prompt template files
   ↓
Step 4: Update Bathroom_Remodeling_Prompt template (DIY_Bathroom retriever)
   ↓
Step 5: Update storageCabinetDetails template (DIY_Bathroom retriever)
   ↓
Step 6: Update seasonalPlantRecomendation template (File_DiySeasonal retriever)
        - PRESERVE the existing flow://Fetch_Seasonal_Products block
   ↓
Step 6.5: Update Building_Deck_Prompt template (Building_a_Deck retriever)  ← MANDATORY
   ↓
Step 7: Deploy all 4 templates + Flow:Fetch_Seasonal_Products to org
   ↓
Step 7.5: 🚨 ROLLBACK to placeholders (ONLY on deploy success)
          - Restore placeholder strings (DIY_BATHROOM_RETRIEVER, etc.)
          - Revert version numbers (_12 → _11, _10 → _9, etc.)
          - Re-comment the templateDataProviders blocks with stale IDs
          - On deploy FAILURE: skip rollback, leave files dirty for debugging
   ↓
Step 8: Generate final completion report
```

---

### Step 0 — Verify repository and template files exist

**CRITICAL: Check all required files before starting**

Check if template directory exists:

```bash
ls "{template_directory}"
```

Verify all three template files exist:

```bash
ls "{template_directory}/Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml"
ls "{template_directory}/storageCabinetDetails.genAiPromptTemplate-meta.xml"
ls "{template_directory}/seasonalPlantRecomendation.genAiPromptTemplate-meta.xml"
```

**If any file is missing:**
- Report error: "Required template file not found: [file_path]"
- List available files in the directory
- Stop execution

**If all files exist:**
- Report: "✅ All required template files verified"
- Continue to Step 1

---

### Step 1 — Query org for retriever API names via REST API

**CRITICAL: Get actual retriever API names from org**

Query the org for all retrievers using SF CLI data query:

```bash
sf data query --query "SELECT Id, Name, DeveloperName, Label FROM EinsteinSearchRetriever WHERE IsActive = true" --target-org {org_alias} --json
```

Or use REST API endpoint directly:

```bash
sf org display --target-org {org_alias} --json
```

Extract instance URL from output, then:

```bash
curl --header "Authorization: Bearer $(sf org display --target-org {org_alias} --json | jq -r '.result.accessToken')" \
"$(sf org display --target-org {org_alias} --json | jq -r '.result.instanceUrl')/services/data/v62.0/ssot/machine-learning/retrievers"
```

**Expected JSON response structure:**
```json
{
  "retrievers": [
    {
      "id": "...",
      "name": "Building_a_Deck_Retriever_V2_1...",
      "label": "Building_a_Deck Retriever",
      ...
    },
    {
      "id": "...",
      "name": "DIY_Bathroom_Retriever_V2_1...",
      "label": "DIY_Bathroom Retriever",
      ...
    },
    {
      "id": "...",
      "name": "File_DiySeasonal_...",
      "label": "File_DiySeasonal",
      ...
    }
  ]
}
```

**If API call fails:**
- Report error: "❌ Could not query retrievers from org"
- Check org authentication: `sf org display -o {org_alias}`
- Suggest: `sf org login web -a {org_alias}`
- Stop execution

**If API call succeeds:**
- Capture full JSON output for parsing
- Continue to Step 2

---

### Step 2 — Parse retriever API names by label

**CRITICAL: Extract API names for each retriever by matching label**

Parse the JSON response to extract API names (DeveloperName or name field) for:

**Retriever 1: Building_a_Deck Retriever**
- Search for: `"label": "Building_a_Deck Retriever"`
- Extract: `name` field value
- Store in variable: `building_deck_retriever_api_name`

**Retriever 2: DIY_Bathroom Retriever**
- Search for: `"label": "DIY_Bathroom Retriever"`
- Extract: `name` field value
- Store in variable: `diy_bathroom_retriever_api_name`

**Retriever 3: File_DiySeasonal**
- Search for: `"label": "File_DiySeasonal"`
- Extract: `name` field value
- Store in variable: `file_seasonal_retriever_api_name`

**If any retriever not found:**
- Report error: "❌ Required retriever not found: [label_name]"
- List all available retrievers from JSON response
- Suggest creating missing retrievers first
- Stop execution

**If all retrievers found:**
- Report: "✅ Retrieved API names:"
  - Building_a_Deck: {building_deck_retriever_api_name}
  - DIY_Bathroom: {diy_bathroom_retriever_api_name}
  - File_DiySeasonal: {file_seasonal_retriever_api_name}
- Continue to Step 3

---

### Step 3 — Read current prompt template files

**Read all three template files to extract current version numbers:**

**File 1: Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml**

```
Tool: Read
file_path: {template_directory}/Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml
```

Extract version numbers from:
- `<activeVersionIdentifier>..._[version]</activeVersionIdentifier>`
- `<versionIdentifier>..._[version]</versionIdentifier>`

Store: `bathroom_current_version`

**File 2: storageCabinetDetails.genAiPromptTemplate-meta.xml**

```
Tool: Read
file_path: {template_directory}/storageCabinetDetails.genAiPromptTemplate-meta.xml
```

Extract version numbers from same tags.

Store: `storage_current_version`

**File 3: seasonalPlantRecomendation.genAiPromptTemplate-meta.xml**

```
Tool: Read
file_path: {template_directory}/seasonalPlantRecomendation.genAiPromptTemplate-meta.xml
```

Extract version numbers from same tags.

Store: `seasonal_current_version`

**If version number cannot be extracted:**
- Report error: "❌ Cannot parse version number from: [filename]"
- Show current activeVersionIdentifier value
- Stop execution

**If all versions extracted successfully:**
- Report: "✅ Current versions:"
  - Bathroom_Remodeling_Prompt: _{bathroom_current_version}
  - storageCabinetDetails: _{storage_current_version}
  - seasonalPlantRecomendation: _{seasonal_current_version}
- Continue to Step 4

---

### Step 4 — Update Bathroom_Remodeling_Prompt template

**File path:** `{template_directory}/Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml`

**CRITICAL: This template uses DIY_Bathroom Retriever**

**Operation 1: Increment version identifiers**

Find the current version number pattern (e.g., `_11`) and increment it (e.g., `_12`).

```
Tool: Edit
file_path: {template_directory}/Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml
old_string: <activeVersionIdentifier>Bathroom_Remodeling_Prompt_{bathroom_current_version}</activeVersionIdentifier>
new_string: <activeVersionIdentifier>Bathroom_Remodeling_Prompt_{bathroom_current_version + 1}</activeVersionIdentifier>
```

```
Tool: Edit
file_path: {template_directory}/Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml
old_string: <versionIdentifier>Bathroom_Remodeling_Prompt_{bathroom_current_version}</versionIdentifier>
new_string: <versionIdentifier>Bathroom_Remodeling_Prompt_{bathroom_current_version + 1}</versionIdentifier>
```

**Operation 2: Update retriever reference in content (if placeholder exists)**

Check if placeholder `DIY_BATHROOM_RETRIEVER` exists in the content. If yes:

```
Tool: Edit
file_path: {template_directory}/Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml
old_string: DIY_BATHROOM_RETRIEVER
new_string: {!$EinsteinSearch:{diy_bathroom_retriever_api_name}.results}
```

**Operation 3: Update templateDataProviders section**

Replace the entire `<templateDataProviders>` section with:

```xml
<templateDataProviders>
    <definition>invocable://getEinsteinRetrieverResults/{diy_bathroom_retriever_api_name}</definition>
    <label>DIY_Bathroom Retriever</label>
    <parameters>
        <definition>primitive://String</definition>
        <isRequired>true</isRequired>
        <parameterName>searchText</parameterName>
        <valueExpression>{!$Input:Question}{!$Input:Category}</valueExpression>
    </parameters>
    <parameters>
        <definition>primitive://List&lt;String&gt;</definition>
        <isRequired>false</isRequired>
        <parameterName>outputFieldNames</parameterName>
        <valueExpression>[&quot;Chunk&quot;]</valueExpression>
    </parameters>
    <referenceName>EinsteinSearch:{diy_bathroom_retriever_api_name}</referenceName>
</templateDataProviders>
```

**If Edit fails:**
- Report error: "❌ Failed to update Bathroom_Remodeling_Prompt template"
- Show current XML content
- Stop execution

**If Edit succeeds:**
- Report: "✅ Bathroom_Remodeling_Prompt updated: version _{bathroom_current_version} → _{bathroom_current_version + 1}"
- Report: "  Retriever: {diy_bathroom_retriever_api_name}"
- Continue to Step 5

---

### Step 5 — Update storageCabinetDetails template

**File path:** `{template_directory}/storageCabinetDetails.genAiPromptTemplate-meta.xml`

**CRITICAL: This template uses DIY_Bathroom Retriever**

**Operation 1: Increment version identifiers**

```
Tool: Edit
file_path: {template_directory}/storageCabinetDetails.genAiPromptTemplate-meta.xml
old_string: <activeVersionIdentifier>storageCabinetDetails_{storage_current_version}</activeVersionIdentifier>
new_string: <activeVersionIdentifier>storageCabinetDetails_{storage_current_version + 1}</activeVersionIdentifier>
```

```
Tool: Edit
file_path: {template_directory}/storageCabinetDetails.genAiPromptTemplate-meta.xml
old_string: <versionIdentifier>storageCabinetDetails_{storage_current_version}</versionIdentifier>
new_string: <versionIdentifier>storageCabinetDetails_{storage_current_version + 1}</versionIdentifier>
```

**Operation 2: Update retriever reference in content (if placeholder exists)**

Check if placeholder `DIY_BATHROOM_RETRIEVER` exists in the content. If yes:

```
Tool: Edit
file_path: {template_directory}/storageCabinetDetails.genAiPromptTemplate-meta.xml
old_string: DIY_BATHROOM_RETRIEVER
new_string: {!$EinsteinSearch:{diy_bathroom_retriever_api_name}.results}
```

**Operation 3: Update templateDataProviders section**

Replace the entire `<templateDataProviders>` section with:

```xml
<templateDataProviders>
    <definition>invocable://getEinsteinRetrieverResults/{diy_bathroom_retriever_api_name}</definition>
    <label>DIY_Bathroom Retriever</label>
    <parameters>
        <definition>primitive://String</definition>
        <isRequired>true</isRequired>
        <parameterName>searchText</parameterName>
        <valueExpression>{!$Input:Question}</valueExpression>
    </parameters>
    <parameters>
        <definition>primitive://List&lt;String&gt;</definition>
        <isRequired>false</isRequired>
        <parameterName>outputFieldNames</parameterName>
        <valueExpression>[&quot;Chunk&quot;]</valueExpression>
    </parameters>
    <referenceName>EinsteinSearch:{diy_bathroom_retriever_api_name}</referenceName>
</templateDataProviders>
```

**If Edit fails:**
- Report error: "❌ Failed to update storageCabinetDetails template"
- Show current XML content
- Stop execution

**If Edit succeeds:**
- Report: "✅ storageCabinetDetails updated: version _{storage_current_version} → _{storage_current_version + 1}"
- Report: "  Retriever: {diy_bathroom_retriever_api_name}"
- Continue to Step 6

---

### Step 6 — Update seasonalPlantRecomendation template

**File path:** `{template_directory}/seasonalPlantRecomendation.genAiPromptTemplate-meta.xml`

**CRITICAL: This template uses File_DiySeasonal Retriever (NOT DIY_Bathroom)**

**Operation 1: Increment version identifiers**

```
Tool: Edit
file_path: {template_directory}/seasonalPlantRecomendation.genAiPromptTemplate-meta.xml
old_string: <activeVersionIdentifier>seasonalPlantRecomendation_{seasonal_current_version}</activeVersionIdentifier>
new_string: <activeVersionIdentifier>seasonalPlantRecomendation_{seasonal_current_version + 1}</activeVersionIdentifier>
```

```
Tool: Edit
file_path: {template_directory}/seasonalPlantRecomendation.genAiPromptTemplate-meta.xml
old_string: <versionIdentifier>seasonalPlantRecomendation_{seasonal_current_version}</versionIdentifier>
new_string: <versionIdentifier>seasonalPlantRecomendation_{seasonal_current_version + 1}</versionIdentifier>
```

**Operation 2: Update retriever reference in content (if placeholder exists)**

Check if placeholder `DIY_SEASONAL_RETRIEVER` exists in the content. If yes:

```
Tool: Edit
file_path: {template_directory}/seasonalPlantRecomendation.genAiPromptTemplate-meta.xml
old_string: DIY_SEASONAL_RETRIEVER
new_string: {!$EinsteinSearch:{file_seasonal_retriever_api_name}.results}
```

**Operation 3: Update templateDataProviders section**

Replace the entire `<templateDataProviders>` section with:

```xml
<templateDataProviders>
    <definition>invocable://getEinsteinRetrieverResults/{file_seasonal_retriever_api_name}</definition>
    <description>File_ADL_Diy_Seasonal</description>
    <label>File_DiySeasonal</label>
    <parameters>
        <definition>primitive://String</definition>
        <isRequired>true</isRequired>
        <parameterName>searchText</parameterName>
        <valueExpression>{!$Input:Question}</valueExpression>
    </parameters>
    <parameters>
        <definition>primitive://List&lt;String&gt;</definition>
        <isRequired>false</isRequired>
        <parameterName>outputFieldNames</parameterName>
        <valueExpression>[&quot;Chunk&quot;]</valueExpression>
    </parameters>
    <referenceName>EinsteinSearch:{file_seasonal_retriever_api_name}</referenceName>
</templateDataProviders>
```

**If Edit fails:**
- Report error: "❌ Failed to update seasonalPlantRecomendation template"
- Show current XML content
- Stop execution

**If Edit succeeds:**
- Report: "✅ seasonalPlantRecomendation updated: version _{seasonal_current_version} → _{seasonal_current_version + 1}"
- Report: "  Retriever: {file_seasonal_retriever_api_name}"
- Continue to Step 7

---

### Step 6.5 — Update Building_Deck_Prompt template (MANDATORY — do NOT skip)

**File path:** `{template_directory}/Building_Deck_Prompt.genAiPromptTemplate-meta.xml`

**Retriever:** Building_a_Deck Retriever (parent name from Step 10 / from API query — uses `1Cx_*` prefix)

**Operation 1: Increment version identifiers (both `<activeVersionIdentifier>` and `<versionIdentifier>`)**

**Operation 2: Replace `DIY_BUILDING_RETRIEVER` placeholder in `<content>`** with `{!$EinsteinSearch:<building_a_deck_retriever_parent_name>.results}`. Use `replace_all: true` if multiple occurrences.

**Operation 3: Uncomment + update `<templateDataProviders>` block** — remove the `<!--` and `-->` markers, replace the old `Building_a_Deck_Retriever_1Cx_*` name with the freshly-created one in BOTH `<definition>invocable://getEinsteinRetrieverResults/<NAME></definition>` AND `<referenceName>EinsteinSearch:<NAME></referenceName>`.

If you skip this step, the Building_a_Deck retriever created in Step 10 sits unused.

---

### Step 7 — Deploy all 4 templates + Flow to org

**🚨 CRITICAL: Co-deploy `Flow:Fetch_Seasonal_Products` — without it, seasonalPlantRecomendation deployment FAILS with `Fetch_Seasonal_Products is not accessible`.**

Use `--metadata` flags (do NOT use `--source-dir` of the genAiPromptTemplates folder, because the Flow lives outside that folder):

```bash
sf project deploy start \
  --metadata "GenAiPromptTemplate:Bathroom_Remodeling_Prompt" \
  --metadata "GenAiPromptTemplate:storageCabinetDetails" \
  --metadata "GenAiPromptTemplate:seasonalPlantRecomendation" \
  --metadata "GenAiPromptTemplate:Building_Deck_Prompt" \
  --metadata "Flow:Fetch_Seasonal_Products" \
  --target-org {org_alias} \
  --wait 10
```

Wait for deployment to complete (1-2 minutes).

**Expected output:**
```
Status: Succeeded
Components: 5/5 (100%)
Deploy ID: 0Af...
```

**If deployment fails with "Fetch_Seasonal_Products is not accessible":**
- The Flow was NOT included in the deploy. Re-run with the `Flow:Fetch_Seasonal_Products` metadata included.
- Check that the flow file exists locally: `ls diy-pd-pack/main/default/flows/Fetch_Seasonal_Products.flow-meta.xml`

**If deployment fails for any other reason:**
- Report full error message
- Check XML validity
- Stop execution

**If deployment succeeds:**
- Report: "✅ All 4 prompt templates + Flow deployed successfully"
- Report Deploy ID for reference
- Continue to Step 7.5 (ROLLBACK — mandatory)

---

### Step 7.5 — Rollback to placeholders (ONLY on deploy success)

**🚨 THIS STEP IS MANDATORY ON DEPLOY SUCCESS — DO NOT SKIP.**

The repo must remain org-agnostic. After confirming the deploy succeeded, reverse every Edit operation from Steps 4-6.5 so the files return to their placeholder state. This makes future runs idempotent.

**Precondition:** Deploy in Step 7 reported `Status: Succeeded`. If deploy failed, skip this step entirely — leave the files dirty so the user can inspect what was about to deploy.

**For each of the 4 template files, reverse the 3 Edit operations:**

**A. Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml:**

```
Tool: Edit (replace_all: true)
old_string: {!$EinsteinSearch:<diy_bathroom_retriever_parent_name>.results}
new_string: DIY_BATHROOM_RETRIEVER
```

```
Tool: Edit
old_string: <activeVersionIdentifier>...=_{new_version}</activeVersionIdentifier>
new_string: <activeVersionIdentifier>...=_{original_version}</activeVersionIdentifier>
```

```
Tool: Edit
old_string: <versionIdentifier>...=_{new_version}</versionIdentifier>
new_string: <versionIdentifier>...=_{original_version}</versionIdentifier>
```

```
Tool: Edit
old_string: <ACTIVE templateDataProviders block with new retriever name>
new_string: <ORIGINAL commented-out block with stale retriever name>
```

The "stale retriever name" is whatever was in the file BEFORE Step 4 ran. Read the file's git history or pre-run snapshot to know the original. If unknown, use these defaults from the canonical repo state:
- Bathroom_Remodeling_Prompt: `DIY_Bathroom_Retriever_1Cx_96b30e02021` (commented)
- storageCabinetDetails: `DIY_Bathroom_Retriever_1Cx_96b30e02021` (commented)
- seasonalPlantRecomendation: `File_ADL_Diy_Seasonal_1Cx_96ba4896ddb` (commented)
- Building_Deck_Prompt: `Building_a_Deck_Retriever_1Cx_96bc9aaf8da` (commented)

**B. Repeat for storageCabinetDetails, seasonalPlantRecomendation, Building_Deck_Prompt.**

For seasonalPlantRecomendation: re-comment ONLY the EinsteinSearch templateDataProviders block. The `flow://Fetch_Seasonal_Products` block must remain active (uncommented).

**C. Verify all placeholders are restored:**

```bash
echo "=== Placeholder verification ==="
for f in Bathroom_Remodeling_Prompt storageCabinetDetails seasonalPlantRecomendation Building_Deck_Prompt; do
  grep -E "(activeVersionIdentifier|RETRIEVER|EinsteinSearch:|<!--)" "diy-pd-pack/main/default/genAiPromptTemplates/$f.genAiPromptTemplate-meta.xml" | head -3
done
```

Expected output: each file shows the placeholder string (`DIY_BATHROOM_RETRIEVER`, etc.) and the original version number.

If verification fails for any file, report: `❌ Rollback verification failed for {filename} — manual cleanup required` and continue to Step 8 with a warning. The org has the deployed version regardless; only the local repo state is dirty.

If verification passes:
- Report: "✅ Rollback complete — all 4 templates restored to placeholder state"
- Continue to Step 8

---

---

### Step 8 — Generate final completion report

Generate comprehensive completion report:

```text
✅ Prompt Template Retrievers Updated and Deployed!

Org: {org_alias}
Instance: {instanceUrl}

═══════════════════════════════════════════════════

📋 Templates Updated:

1. ✅ Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml
   Version: _{bathroom_current_version} → _{bathroom_current_version + 1}
   Retriever: DIY_Bathroom Retriever
   API Name: {diy_bathroom_retriever_api_name}
   Status: Deployed
   
2. ✅ storageCabinetDetails.genAiPromptTemplate-meta.xml
   Version: _{storage_current_version} → _{storage_current_version + 1}
   Retriever: DIY_Bathroom Retriever
   API Name: {diy_bathroom_retriever_api_name}
   Status: Deployed
   
3. ✅ seasonalPlantRecomendation.genAiPromptTemplate-meta.xml
   Version: _{seasonal_current_version} → _{seasonal_current_version + 1}
   Retriever: File_DiySeasonal
   API Name: {file_seasonal_retriever_api_name}
   Status: Deployed

═══════════════════════════════════════════════════

🔗 Verify Prompt Templates:

1. Navigate to: Setup → Einstein Search → Prompt Templates
2. Verify new versions appear for all three templates
3. Check retriever connections are correct
4. Test templates with sample queries

═══════════════════════════════════════════════════

📊 Deployment Details:

Deploy ID: {deploy_id}
Deployed Components: 9
Status: Success

═══════════════════════════════════════════════════

✅ All prompt templates updated with retrievers successfully!

Next: Test prompt templates in Agentforce Agent configuration.
```

---

## Important Rules

**CRITICAL - Execution Sequence:**
- 🚨 **ALWAYS execute commands sequentially** - wait for each to complete
- 🚨 **Query org for retriever API names first** - never hardcode
- 🚨 **Wait for deployment to complete** before reporting success
- 🚨 **Do NOT run commands in parallel** - must be sequential

**CRITICAL - Retriever Mapping:**
- ✅ **Bathroom_Remodeling_Prompt** uses DIY_Bathroom Retriever
- ✅ **storageCabinetDetails** uses DIY_Bathroom Retriever
- ✅ **seasonalPlantRecomendation** uses File_DiySeasonal Retriever
- ✅ **Always query org** for actual API names - never hardcode

**CRITICAL - Version Management:**
- ✅ **Always read current version** before updating
- ✅ **Increment both** activeVersionIdentifier and versionIdentifier
- ✅ **Version numbers must match** between both tags

**CRITICAL - XML Editing:**
- ✅ **Always use Edit tool** to update existing XML (never Write)
- ✅ **Preserve XML formatting** and indentation
- ✅ **Update all three references**: content placeholder, definition, referenceName
- ✅ **Verify XML is valid** after each edit

**CRITICAL - CLI Commands:**
- ✅ **ONLY use Salesforce CLI** - no browser automation
- ✅ **Change to repo directory** before deploy commands
- ✅ **Wait for API responses** before parsing
- ✅ **Capture command output** for error reporting

**General Rules:**
- NEVER generate JavaScript files
- NEVER write automation scripts to disk
- NEVER hardcode retriever API names - always query org
- NEVER skip version increment
- NEVER deploy without verifying all edits succeeded
- ALWAYS report errors with full context
- ALWAYS provide actionable error messages
- Estimated time: 2-5 minutes for complete workflow

---

## Example Usage

### Example 1: Basic template update

**User:** "Add retrievers to prompt templates in <YOUR_ORG_ALIAS>"

**Skill:**
1. Verifies template files exist
2. Queries org for retrievers via REST API: `/services/data/v62.0/ssot/machine-learning/retrievers`
3. Parses API names:
   - DIY_Bathroom Retriever → `DIY_Bathroom_Retriever_V2_1Cx_t6f8670d786`
   - File_DiySeasonal → `File_DiySeasonal_Retriever_V2_1Cx_abc123`
4. Reads current versions:
   - Bathroom_Remodeling_Prompt: _11
   - storageCabinetDetails: _9
   - seasonalPlantRecomendation: _2
5. Updates Bathroom_Remodeling_Prompt: version _11 → _12, adds DIY_Bathroom retriever
6. Updates storageCabinetDetails: version _9 → _10, adds DIY_Bathroom retriever
7. Updates seasonalPlantRecomendation: version _2 → _3, adds File_DiySeasonal retriever
8. Deploys all templates: `sf project deploy start --source-dir ...`
9. Reports completion with Deploy ID

---

### Example 2: Error handling - Retriever not found

**User:** "Add retrievers to prompt templates in TestOrg"

**Skill:** [Queries retrievers via API]

**Error:** `Required retriever not found: DIY_Bathroom Retriever`

**Skill:**
```text
❌ Required Retriever Not Found

Org: TestOrg

Missing Retriever: DIY_Bathroom Retriever

Available Retrievers:
- Product_Individual_Retriever_V2_1 (label: Product Individual)
- Another_Retriever_V1 (label: Another)

Suggested Fix:
1. Verify Einstein retrievers are created in Data Cloud
2. Check retriever labels match exactly:
   - "DIY_Bathroom Retriever"
   - "File_DiySeasonal"
3. Navigate to: Setup → Einstein Search → Retrievers
4. Create missing retrievers if needed
5. Retry skill execution

Cannot proceed without all required retrievers.
```

---

### Example 3: Error handling - Version parsing failed

**User:** "Add retrievers to prompt templates in ProdOrg"

**Skill:** [Reads template files]

**Error:** `Cannot parse version number from: Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml`

**Skill:**
```text
❌ Version Number Parsing Failed

Org: ProdOrg

File: Bathroom_Remodeling_Prompt.genAiPromptTemplate-meta.xml

Current activeVersionIdentifier:
<activeVersionIdentifier>Bathroom_Remodeling_Prompt</activeVersionIdentifier>

Expected Format:
<activeVersionIdentifier>Bathroom_Remodeling_Prompt_11</activeVersionIdentifier>

Suggested Fix:
1. Check if template file has version number suffix (_11, _12, etc.)
2. Auto-add version number if missing using Edit tool
3. Verify XML structure is valid
4. Retry skill execution

Cannot proceed without valid version numbers.
```

---

## Success Criteria

Prompt template update is successful when:

✅ Repository and template files verified
✅ REST API call to retrieve retrievers succeeded
✅ All three retriever API names extracted:
   - DIY_Bathroom Retriever
   - File_DiySeasonal
✅ Current version numbers extracted from all three templates
✅ Bathroom_Remodeling_Prompt updated with incremented version and DIY_Bathroom retriever
✅ storageCabinetDetails updated with incremented version and DIY_Bathroom retriever
✅ seasonalPlantRecomendation updated with incremented version and File_DiySeasonal retriever
✅ All templates deployed successfully to org
✅ Comprehensive completion report provided

---

## Notes

- Version numbers are automatically incremented for each template
- DIY_Bathroom Retriever is used by TWO templates (Bathroom_Remodeling_Prompt and storageCabinetDetails)
- File_DiySeasonal Retriever is used by ONE template (seasonalPlantRecomendation)
- Retriever API names are queried from org - never hardcoded
- Deployment includes 9 components total (3 templates × 3 metadata components each)
- Always verify deployment success before considering update complete
- Templates must have version numbers in format: `{TemplateName}_{version}`
- REST API endpoint requires Data Cloud provisioning to be complete

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If the deploy fails (Step 7), **do NOT clean up** — leave the modified template files dirty for inspection.
- Fix the underlying issue, retry the deploy, then perform Step 7.5 (rollback to placeholders) AND this cleanup.
- Step 7.5 (placeholder restore in repo) is a SEPARATE concern from this temp cleanup; both must run after a successful deploy.

**Files this skill creates and must delete:**

```bash
rm -f /c/tmp/prompt_deploy.json
```

**Verification (must report no remaining prompt-template scratch):**

```bash
ls /c/tmp/prompt_deploy.json 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete the files listed above. The 4 prompt-template XMLs and Flow are repo source — Step 7.5 handles their rollback.
- ❌ Skipping this step is not allowed once deploy succeeded and rollback is verified.
