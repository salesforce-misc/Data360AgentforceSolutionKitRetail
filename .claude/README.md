# Claude Code Skills: Data360 Retail Solution Kit - Fully Automated Installation

**100% automated installation** of Salesforce Data Cloud 360 Retail Solution Kit using Claude Code with 15 specialized skills.

## Overview

This project provides complete end-to-end automation for installing the Data360 Retail Solution Kit into any Salesforce org with Data Cloud. All 15 installation steps are fully automated using browser automation (Playwright), REST APIs, and Salesforce CLI.

**Total Installation Time:** ~45-60 minutes (fully automated, no manual intervention)

---

## ⚙️ One-time machine prep (the installer auto-runs this for you)

The Data360 installer drives Salesforce UI through the **Playwright Claude Code plugin** (from the `claude-plugins-official` marketplace). It must be installed on your laptop **before** the installer can run.

**Officially supported on macOS, Windows, and Linux** (per Claude Code's [system requirements](https://code.claude.com/docs/en/setup#system-requirements)).

### How it works — zero touches in the happy path

When you say `install Data360 retail`, the installer's Step 0.0 preflight does this in the first second:

```
1. Is the Playwright plugin installed?
   ├─ YES → continue silently to mode selection ✅
   └─ NO  → auto-run setup script
            (setup.sh on macOS / Linux, setup.bat on Windows)
            │
            ├─ Script SUCCESS → "Plugin installed. Run
            │                    /reload-plugins inside Claude Code,
            │                    then re-run install Data360 retail." ✅
            │                    User runs /reload-plugins → installer
            │                    resumes
            │
            └─ Script FAILS  → show the manual /plugin steps below
                               so the user can install it themselves
```

The auto-run path covers the vast majority of users — no terminal opening, no commands to copy, no decisions. Just one slash command + one retype.

### What the setup script does

```bash
1. Verify `claude` CLI is on PATH (exit with install link if missing)
2. Verify Node.js 18+ is installed (Microsoft Playwright MCP requirement)
3. Register claude-plugins-official marketplace if not already added
4. claude plugin install playwright@claude-plugins-official
5. Print "Run /reload-plugins inside Claude Code" reminder
```

The script is idempotent — re-running it after the plugin is already installed prints a friendly "no action needed" message instead of failing.

### Manual install (only if the auto-install fails)

If the installer's auto-run fails — for example because the `claude` CLI is not on PATH, Node.js is missing, or the marketplace is unreachable — install the plugin yourself directly inside Claude Code. Same steps on macOS, Windows, AND Linux:

1. In Claude Code's chat input, type and press Enter:
   ```
   /plugin
   ```
2. A plugin marketplace browser opens. Select:
   ```
   claude-plugins-official
   ```
3. Find and select:
   ```
   playwright
   ```
4. Click **Install** and wait for the confirmation.
5. Reload Claude Code's plugin index (universal command — works on every surface and OS):
   ```
   /reload-plugins
   ```
6. Re-run:
   ```
   install Data360 retail
   ```

That's the universal procedure — works in every Claude Code surface (VS Code extension, CLI, Desktop, Web) on every supported OS (macOS, Windows, Linux).

### How to verify the plugin is installed correctly (optional)

Open a terminal — PowerShell on Windows, Terminal on Mac — and run:

```
claude plugin list
```

You should see:

```
❯ playwright@claude-plugins-official
    Scope: user
    Status: ✔ enabled
```

If that line is present, the Data360 installer's Step 0.0 preflight will pass silently.

---

### Why the plugin (and not `claude mcp add playwright`)?

The Data360 skills hard-code tool calls under the plugin prefix `mcp__plugin_playwright_playwright__*`. Installing the bare MCP server via `claude mcp add playwright npx @playwright/mcp@latest` exposes Playwright tools under a different prefix (`mcp__playwright__*`) that the skills do NOT call. So the bare MCP server would let the preflight "pass" but the skills would still fail at runtime. **The plugin is the only distribution that exposes the prefix the skills actually call.**

---

## ⚠️ Known limitation: Corporate-managed Macs with Chrome MDM policy

If your Mac is managed by corporate IT and Chrome has the `DeveloperToolsAvailability: DeveloperToolsDisallowed` enterprise policy enforced, **the `/intelligent-context` skill cannot fully automate** without manual intervention.

### How to tell you're affected

When `/intelligent-context` (Step 6 of Mode 2) runs, you see one of these errors in the agent output:

```
DevTools remote debugging is disallowed by the system admin.
Browser is already in use for /Users/.../ms-playwright-mcp/mcp-chrome-...
TimeoutError: async initializeServer: Timeout 180000ms exceeded.
```

### Why it happens (three combined factors)

1. **Salesforce IC UI flow** — Intelligent Context requires the file upload + "Edit Configuration" + Publish to happen through the UI to create a valid `contentLensSession`. Pure-API alternatives return `UNKNOWN_EXCEPTION`.
2. **Playwright drives UI via Chrome DevTools Protocol (CDP)** — the only way to automate the browser.
3. **Corporate Chrome MDM policy** — blocks CDP at the OS level, so Playwright's `--remote-debugging-pipe` is rejected by Chrome itself.

The Anthropic Playwright plugin hardcodes system Chrome and ignores `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` and `--browser chromium`. So pointing it to Playwright's bundled Chromium (which would sidestep the policy) is not currently possible at the plugin level.

### What the skill now does about it

The `/intelligent-context` skill detects this failure pattern and, instead of looping or printing a cryptic stack trace, surfaces a clear 5-step manual completion procedure:

1. Open the IC Builder URL in your normal browser
2. Click "Upload Files" and select the PDF
3. Wait for the file to register
4. Click "Edit Configuration" → leave smart defaults → click "Publish"
5. Wait for status: READY

After the user completes both lenses (DIY Bathroom + Building a Deck) manually, they tell the agent to continue. **Steps 7–21 are API-driven and run automatically** — no further browser automation is needed.

### Permanent fix (requires IT action)

Ask your IT / Security team to grant an Exception In Policy (EIP) for `DeveloperToolsAvailability` on your Mac. Once EIP is in place, the IC skill runs end-to-end without manual intervention.

### Honest caveats

- This limitation **only affects** the `/intelligent-context` skill (Step 6). All other 20 skills in Mode 2 are API-driven or use minimal browser automation that doesn't require DevTools.
- The bug is **not in the Data360 installer code** — it's a combination of Salesforce platform behavior, the Playwright MCP plugin, and your corporate Chrome policy. We've made the failure mode graceful, but we cannot bypass the policy.
- On Windows and non-managed Macs, this fallback **does not trigger** and the install runs fully automated.

---

## Installation Skills (15 Steps)

| # | Skill Name | Purpose | Method | Duration |
|---|------------|---------|--------|----------|
| 1 | `feature-enablement` | Enable Data Cloud, Einstein, Agentforce | Playwright | 3-5 min |
| 2 | `base-metadata-deploy` | Deploy base metadata (diy-base) | Salesforce CLI | 2-3 min |
| 3 | `datakit-metadata-deploy` | Deploy Data Kit metadata (612 components) | Salesforce CLI | 5-10 min |
| 4 | `datakit-api-deploy` | Activate Data Kit via Connect API | REST API | 25-35 min |
| 5 | `agentforce-data-library` | Create 3 Agentforce Data Libraries | REST API | 2-3 min |
| 6 | `intelligent-context` | Create 2 Intelligent Context configs | Playwright | 5-8 min |
| 7 | `create-individual-retrievers` | Create 2 Individual Retrievers | REST API | 1-2 min |
| 8 | `agent-setup-configuration` | Configure DIY Home Improvement Agent | Playwright | 3-5 min |
| 9 | `prompt-template-add-retriever` | Add retrievers to prompt template | Playwright | 2-3 min |
| 10 | `assign-permission-to-app` | Assign DIY Store Front App permission | Salesforce CLI | 1-2 min |
| 11 | `datastream-file-upload` | Upload 4 CSV files to Data Streams | Playwright | 3-5 min |
| 12 | `copy-field-sync` | Sync 5 copy fields for Contact | Playwright | 2-3 min |
| 13 | `data-cloud-related-list` | Add Customer Affinities related list | Playwright | 2-3 min |
| 14 | `refresh-data-streams` | Refresh 12 Data Streams | Playwright | 6-12 min |
| 15 | `refresh-data-cloud-components` | Refresh 5 Data Cloud components | Playwright | 3-5 min |

---

## Prerequisites

### Required Software
- **Salesforce CLI** (`sf` command) - v2.0 or higher
- **Git** (for cloning repository)
- **Python 3** (for JSON parsing in scripts)
- **Claude Code** (VS Code extension or CLI)

### Required Access
- **Salesforce org** with Data Cloud license
- **System Administrator** profile or equivalent permissions
- **Org authentication** via `sf org login web -a <org-alias>`
- **Permissions:** 
  - Manage Data Cloud
  - View Setup and Configuration
  - Modify All Data (for agent configuration)

### Repository Structure
```
Data360AgentforceSolutionKitRetail/
├── .claude/
│   ├── skills/                    # 15 automation skills
│   ├── settings.json              # Pre-configured permissions
│   └── README.md                  # This file
├── diy-base/                      # Base metadata
├── diy-datacloud/                 # 612 Data Kit components
├── diy-pd-pack/                   # Agent package
├── DIY Documents/                 # CSV and PDF files
└── sfdx-project.json
```

---

## Quick Start

### Option 1: One Command Installation (Recommended)

From the repository root in Claude Code:

```
Install the complete Data360 Retail Solution Kit into MyRetailOrg
```

Claude will execute all 14 steps automatically.

### Option 2: Step-by-Step Execution

Run each skill individually:

```
Step 1: /feature-enablement MyRetailOrg
Step 2: /base-metadata-deploy MyRetailOrg
Step 3: /datakit-metadata-deploy MyRetailOrg
Step 4: /datakit-api-deploy MyRetailOrg
Step 5: /agentforce-data-library MyRetailOrg
Step 6: /intelligent-context MyRetailOrg
Step 7: /create-individual-retrievers MyRetailOrg
Step 8: /agent-setup-configuration MyRetailOrg
Step 9: /prompt-template-add-retriever MyRetailOrg
Step 10: /assign-permission-to-app MyRetailOrg
Step 11: /datastream-file-upload MyRetailOrg
Step 12: /copy-field-sync MyRetailOrg
Step 13: /data-cloud-related-list MyRetailOrg
Step 14: /refresh-data-streams MyRetailOrg
Step 15: /refresh-data-cloud-components MyRetailOrg
```

---

## Skill Details

### Step 1: Feature Enablement (`feature-enablement`)
**Method:** Playwright browser automation

**What it does:**
- Provisions Data Cloud (if not already enabled)
- Enables Einstein features
- Enables Agentforce features
- Modifies permission sets for DIY agent access

**Technology:** MCP Playwright tools, no JavaScript generation

---

### Step 2: Base Metadata Deploy (`base-metadata-deploy`)
**Method:** Salesforce CLI

**What it does:**
- Deploys diy-base metadata (objects, fields, layouts)
- Assigns permission sets
- Activates Price Books
- Imports sample data (accounts, contacts, products)
- Executes Apex scripts

**Command:** `sf project deploy start`

---

### Step 3: Data Kit Metadata Deploy (`datakit-metadata-deploy`)
**Method:** Salesforce CLI

**What it does:**
- Cleans KeyQualifier fields automatically
- Filters managed DLO objects
- Deploys 612 metadata components:
  - DataPackageKitDefinitions
  - DataPackageKitObjects
  - dataSourceBundleDefinitions
  - DLO objects (Data Lake Objects)

**Command:** `sf project deploy start`

---

### Step 4: Data Kit API Deploy (`datakit-api-deploy`)
**Method:** Connect REST API

**What it does:**
- Triggers Data Kit installation via API
- Activates 31 Data Kit components
- Returns Job ID for monitoring
- Async mode (runs in background)

**Endpoint:** `/services/data/v63.0/ssot/data-kits/Data360RetailDIYDataKit`

---

### Step 5: Agentforce Data Library (`agentforce-data-library`)
**Method:** Einstein REST API

**What it does:**
- Creates 3 Agentforce Data Libraries (ADL):
  - ADL_DIYBathroomLibr (Bathroom_Remodelling_Instructions.pdf)
  - ADL_DiyBuildingADec (Building_a_Deck_Instructions.pdf)
  - ADL_DiySeasonal (DIY_Seasonal.csv)
- Uses Einstein API for PDF and CSV ingestion

**Endpoint:** `/einstein/ai-library/v1/data-libraries`

---

### Step 6: Intelligent Context (`intelligent-context`)
**Method:** Playwright browser automation

**What it does:**
- Creates 2 Intelligent Context configurations:
  1. DIY Bathroom (with PDF upload)
  2. Building a Deck (with PDF upload)
- Configures smart defaults
- Sets up LLM-based parsing
- Publishes to UDMOs

**Technology:** MCP Playwright tools with file upload

---

### Step 7: Individual Retrievers (`create-individual-retrievers`)
**Method:** Connect REST API

**What it does:**
- Creates 2 Individual Retrievers:
  1. DIY_Bathroom Retriever
  2. Building_a_Deck Retriever
- Configures 7 chunk fields with relationships
- Auto-discovers search indexes
- Activates retrievers

**Endpoint:** `/services/data/v63.0/ssot/machine-learning/retrievers`

---

### Step 8: Agent Setup (`agent-setup-configuration`)
**Method:** Playwright browser automation

**What it does:**
- Configures "DIY Home Improvement Agent"
- Adds retrievers to agent
- Enables agent
- Publishes agent

**Technology:** MCP Playwright tools

---

### Step 9: Prompt Template Retriever (`prompt-template-add-retriever`)
**Method:** Playwright browser automation

**What it does:**
- Adds retrievers to prompt template
- Configures grounding sources
- Saves configuration

**Technology:** MCP Playwright tools

---

### Step 10: Assign Permission to App (`assign-permission-to-app`)
**Method:** Salesforce CLI

**What it does:**
- Creates DIY_Store_Front_App_Access permission set
- Grants the DIY Store Front App SetupEntityAccess
- Assigns the permission set to the running user

**Technology:** Salesforce CLI Apex run (no browser automation)

---

### Step 11: Data Stream File Upload (`datastream-file-upload`)
**Method:** Playwright browser automation

**What it does:**
- Uploads 4 CSV files to Data Streams:
  - DIY_Seasonal.csv
  - Promotion.csv
  - Promotion_Product.csv
  - Asset_Warranty.csv
- Creates Data Stream for each file
- Selects All Records
- Saves and activates

**Technology:** MCP Playwright tools with file upload

---

### Step 12: Copy Field Sync (`copy-field-sync`)
**Method:** Playwright browser automation

**What it does:**
- Syncs 5 copy fields for Contact object:
  - Average Order Value Lifetime
  - Average Purchase Value
  - Customer Lifespan
  - Customer Lifetime Value
  - Unified Contact Profile Information

**Technology:** MCP Playwright tools

---

### Step 13: Data Cloud Related List (`data-cloud-related-list`)
**Method:** Playwright browser automation

**What it does:**
- Adds "Customer Affinities" related list to Account page layout
- Configures Data Cloud Related List component
- Filters to show top 5 affinities

**Technology:** MCP Playwright tools

---

### Step 14: Refresh Data Streams (`refresh-data-streams`)
**Method:** Playwright browser automation

**What it does:**
- Refreshes 12 Data Streams sequentially:
  - Account_Home, Contact_Home, Product2_Home
  - Pricebook2_Home, PricebookEntry_Home
  - Asset_Home, AssetWarranty_Home
  - Order_Home, OrderItem_Home
  - Promotion_Home, PromotionProduct_Home
  - ServiceAppointment_Home
- Selects Full Refresh for each
- Waits for Success status

**Technology:** MCP Playwright tools

---

### Step 15: Refresh Data Cloud Components (`refresh-data-cloud-components`)
**Method:** Playwright browser automation

**What it does:**
- Refreshes 5 Data Cloud components:
  - Calculated Insights (3)
  - Identity Resolutions (2)
- Waits for Success status

**Technology:** MCP Playwright tools

---

## Automation Technology Stack

| Technology | Purpose | Skills Using |
|------------|---------|--------------|
| **Playwright (MCP)** | Browser automation | 9 skills (Steps 1, 6, 8, 11-14) |
| **Salesforce CLI** | Metadata + permission deployment | 3 skills (Steps 2, 3, 10) |
| **Connect REST API** | Data Kit activation, retrievers | 2 skills (Steps 4, 7) |
| **Einstein REST API** | Agentforce Data Libraries | 1 skill (Step 5) |

**Key Benefits:**
- ✅ No JavaScript code generation
- ✅ MCP Playwright tools for browser automation
- ✅ Native REST APIs for backend operations
- ✅ Salesforce CLI for metadata deployment
- ✅ All permissions pre-configured in `.claude/settings.json`

---

## Configuration

### Permissions (`.claude/settings.json`)

All required permissions are pre-configured:

```json
{
  "permissions": {
    "allow": [
      "mcp__plugin_playwright_playwright__*",
      "Bash:sf *",
      "Bash:curl *",
      "Bash:python*",
      "Bash:test *",
      "Bash:ls *",
      "Bash:grep *",
      "Bash:cat *"
    ],
    "deny": [
      "Bash:sf org delete*",
      "Bash:rm -rf*"
    ]
  }
}
```

**No permission prompts during installation** - all commands pre-approved.

---

## Troubleshooting

### Common Issues

| Error | Solution |
|-------|----------|
| Org not authenticated | Run `sf org login web -a <org-alias>` |
| Repository structure missing | Clone from GitHub: `git clone https://github.com/salesforce-misc/Data360AgentforceSolutionKitRetail.git` |
| Data Cloud not enabled | Run Step 1: `/feature-enablement` |
| Playwright tools not loaded | Restart Claude Code, tools will auto-load |
| Data Stream refresh timeout | Some Data Streams take 60+ seconds - wait for Success status |
| Search index not ready | Wait 5-10 minutes after Step 9 before Step 10 |

### Automated Verification After Installation

All verification is performed automatically by the installation skills via SOQL queries and API status checks. No manual verification is required.

---

## Important Notes

### Execution Guidelines
- ✅ **Always use org alias** - never hardcode org names
- ✅ **Run steps sequentially** - some steps depend on previous ones
- ✅ **Wait for completion** - especially Steps 4, 9, 11, 12
- ✅ **Use frontdoor URL with access token** - bypasses authentication prompts
- ✅ **Check logs** - detailed execution logs in `.playwright-mcp/`

### Step Dependencies
- Step 4 requires Step 3 (metadata must be deployed first)
- Step 10 requires Step 9 (search indexes must be ready)
- Step 13 requires Step 10 (retrievers must exist)
- Step 14 requires Step 13 (agent must be configured)

### Best Practices
- ✅ Use a **sandbox org** for first installation
- ✅ Ensure **Data Cloud is provisioned** before starting
- ✅ Have **System Administrator** permissions
- ✅ Run during **low-usage hours** (deployments are faster)
- ✅ Keep **browser visible** during Playwright automation

---

## Success Criteria

Installation is successful when:

✅ All 14 skills complete without errors  
✅ Data Kit shows "Active" in Setup  
✅ All Data Streams show "Success" status  
✅ 2 Intelligent Contexts published  
✅ 2 Individual Retrievers active  
✅ DIY Home Improvement Agent enabled  
✅ Agent responds to test queries  

---

## Support & Documentation

- **GitHub Repository:** https://github.com/salesforce-misc/Data360AgentforceSolutionKitRetail
- **Data Cloud Documentation:** https://help.salesforce.com/s/articleView?id=sf.c360_a.htm
- **Agentforce Documentation:** https://help.salesforce.com/s/articleView?id=sf.agentforce.htm

---

**Tested With:**
- Salesforce CLI: v2.0+
- API Version: v63.0+
- Claude Code: 2026
- Playwright MCP: Latest

**Last Updated:** May 2026
