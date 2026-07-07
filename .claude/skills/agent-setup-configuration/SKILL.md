---
name: agent-setup-configuration
description: "Automate complete Agent deployment workflow for Data360 Retail Solution Kit using Salesforce CLI. Creates agent user via Apex, updates bot-meta.xml, deploys agents package, assigns permission sets, and activates agent. NO browser automation, CLI-only workflow. Use when user wants to setup agents, configure agents, deploy DIY_Employee_Agent, or activate Agentforce agents."
---

# agent-setup-configuration

## Purpose

Automate complete Agent deployment workflow for Data360 Retail Solution Kit using Salesforce CLI commands.

**✅ CLI-ONLY SOLUTION**

This skill automates the complete agent setup process without any browser automation. It uses Salesforce CLI commands exclusively to create agent users, update configuration files, deploy packages, and activate agents.

**Critical Constraints:**
- ❌ Do NOT generate JavaScript files
- ❌ Do NOT generate Playwright scripts
- ❌ Do NOT use browser automation
- ❌ **Do NOT skip agent activation (Steps 8 + 9) under any circumstance** — both agents MUST be activated. The skill is not "complete" until `sf agent activate` reports success for BOTH `DIY_Employee_Agent` AND `DIY_Service_Agent`.
- ❌ **Do NOT skip permission-set assignment (Step 7)** — `RetailDIYStorePS` MUST be on the freshly-created agent user before agent activation. Without it, the bot run-as user has no object access and the agent breaks at first conversation. Verify the assignment after the assign call; if missing, re-run.
- ❌ **Do NOT skip Step 7.5 SetupEntityAccess binding (Employee Agent only)** — `DIY_Employee_Agent` is `<type>InternalCopilot</type>` and does NOT support `<botUser>`. Profile and permset access is controlled by the Setup UI's **"Profiles with Agent Access"** + **"Permission Sets with Agent Access"** tabs at `/lightning/setup/EinsteinCopilot/<DIY_Employee_Agent_botId>/edit`. Both tabs are views over the **`SetupEntityAccess`** SObject — writable via Apex DML. Step 7.5 inserts 2 rows (System Administrator profile-shadow permset + RetailDIYStorePS, each bound to DIY_Employee_Agent only) and verifies the SOQL count. If a binding is missing, the Employee Agent appears active in Setup but **no user can launch it** because the launching user's profile/permset is not in the access list.
- ❌ **Do NOT bind DIY_Service_Agent via SetupEntityAccess in Step 7.5.** The Service Agent is `<type>ExternalCopilot</type>`. It runs as the user named in `<botUser>` (set in Step 4), and SetupEntityAccess rows on it have no runtime effect for Embedded Messaging conversations. The Service Agent's RetailDIYStorePS assignment lives on the bot user (Step 7), NOT on the bot definition.
- ❌ **Do NOT treat "BotDefinition exists in SOQL" as proof of activation.** A `BotDefinition` row created by the metadata deploy can sit `Inactive` indefinitely; only `sf agent activate` flips it.
- ✅ Use Salesforce CLI commands ONLY
- ✅ **Execute ALL commands sequentially** - wait for each to complete before proceeding
- ✅ **STOP immediately if Step 1 fails** - user creation and XML update are critical
- 📸 **Screenshot Policy**: N/A - This is a CLI-only skill with no browser automation

**Complete Workflow (substitute → deploy → rollback):**
1. Create Agent User via Apex script
2. Parse email from output
3. Update Service Agent bot-meta.xml with agent user email — substitute `AGENT_USER_EMAIL` placeholder (Employee Agent does NOT need this)
4. Deploy Agents package (diy-pd-pack)
5. Assign Permission Set to default user
6. Activate Employee Agent (DIY_Employee_Agent)
7. Activate Service Agent (DIY_Service_Agent)
8. **🚨 ROLLBACK bot-meta.xml to `AGENT_USER_EMAIL` placeholder** (ONLY on deploy success) — keeps repo org-agnostic and idempotent

**🚨 PLACEHOLDER PATTERN (org-agnostic repo):**

`DIY_Service_Agent.bot-meta.xml` ships with `<botUser>AGENT_USER_EMAIL</botUser>` — a literal placeholder string, NOT a real email. Each run:
- Substitutes `AGENT_USER_EMAIL` → real agent user email (e.g. `eagent1780504659747@example.com`)
- Deploys to org
- ON SUCCESS: rolls back the file to restore `AGENT_USER_EMAIL` placeholder
- ON FAILURE: leaves the file dirty so the user can debug what was about to deploy

This means:
- The repo never has org-specific emails committed
- Re-running the skill always finds `AGENT_USER_EMAIL` — Edit tool's `old_string` always matches
- Different orgs (sandbox, prod) all start from the same placeholder baseline

---

## Arguments

- `org_alias` (required): Target Salesforce org alias or username
- `repo_path` (optional): Path to the cloned Data360 repo root. Defaults to "." (current working directory — assumes Claude Code is launched from the repo root)

---

## Preconditions

Before running:

- Salesforce CLI authenticated with target org
- User has System Administrator profile or equivalent permissions
- The Data360 repository is already cloned locally and Claude Code is launched from its root (no git clone needed)
- Apex script exists at `scripts/apex/createAgentUser.apex`
- Service Agent bot meta file exists at `diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml`
- **Note:** Only DIY_Service_Agent.bot-meta.xml needs botUser update. DIY_Employee_Agent does not require botUser configuration.

---

## Workflow

**CRITICAL EXECUTION RULES:**

1. ✅ **ALWAYS execute commands sequentially** - wait for each to complete
2. ✅ **STOP if Step 1-6 fails** - user creation and XML update are critical
3. ✅ **Parse Apex output** to extract agent user email
4. ✅ **Use Edit tool** to update XML (never Write tool on existing files)
5. ✅ **Verify XML update** before proceeding to deployment
6. ✅ **Wait for deployment** to complete before next step

**Step Execution Order:**
```
Step 0: Verify repository and files exist
   ↓
Step 0.5: Detect stale repo state (warn loudly if rollback failed in prior run)
   ↓
Step 1: Execute Apex script to create Agent User
   ↓
Step 2: Parse Agent User email from output (use `Created user:` marker, NOT first email)
   ↓
Step 3: Read Service Agent bot-meta.xml file (NOT Employee Agent)
   ↓
Step 4: Update Service Agent botUser tag with new email
   ↓
Step 5: Verify the Service Agent update
   ↓
Step 6: Deploy Agents Package (diy-pd-pack)
   ↓
Step 7: Assign Permission Set (RetailDIYStorePS) to agent user
   ↓
Step 7.5: Bind System Administrator profile + RetailDIYStorePS to
          DIY_Employee_Agent ONLY via Apex DML on SetupEntityAccess.
          Inserts 2 rows. Idempotent — skips already-existing rows.
          Verifies SOQL count = 2 before continuing. Hard-stops on mismatch.
          DIY_Service_Agent is excluded — its access is via <botUser>
          (Step 4), not via SetupEntityAccess.
   ↓
Step 8: Activate Employee Agent (DIY_Employee_Agent)
   ↓
Step 9: Activate Service Agent (DIY_Service_Agent)
   ↓
Step 9.5: 🚨 ROLLBACK bot-meta.xml to AGENT_USER_EMAIL placeholder
          (ONLY if Step 6 deploy succeeded — leave dirty on failure)
   ↓
Step 10: Generate final completion report
```

---

### Step 0 — Verify repository and files exist

**CRITICAL: Check all required files before starting**

Check if repository exists:

```bash
ls "{repo_path}"
```

Verify Apex script exists:

```bash
ls "{repo_path}/scripts/apex/createAgentUser.apex"
```

Verify bot meta XML file exists:

```bash
ls "{repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml"
```

**If any file is missing:**
- Report error: "Required file not found: [file_path]"
- List available files in the directory
- Stop execution

**If all files exist:**
- Report: "✅ All required files verified"
- Continue to Step 0.5 (canonical-state check)

---

### Step 0.5 — Detect stale repo state (warn loudly if rollback failed in a prior run)

**Why:** the repo's `DIY_Service_Agent.bot-meta.xml` is supposed to ship with the literal placeholder `<botUser>AGENT_USER_EMAIL</botUser>`. After Step 9.5, every successful run restores that placeholder. If a prior run's deploy succeeded but Step 9.5 was skipped (script aborted, rollback errored, manual interrupt, etc.), the file will still contain a real-looking org-specific email when this skill starts. The skill's Step 4 fallback handles it correctly — but the warning is buried, and silent accumulation of stale state across runs is a real risk.

**Loud check at the top of Step 0.5:**

```bash
if grep -q "<botUser>AGENT_USER_EMAIL</botUser>" "{repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml"; then
  echo "✅ Repo in canonical placeholder state — proceeding normally."
else
  CURRENT=$(grep -oE '<botUser>[^<]*</botUser>' "{repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml")
  echo ""
  echo "⚠️ ============================================================"
  echo "⚠️  REPO NOT IN CANONICAL PLACEHOLDER STATE — RECOVERY MODE"
  echo "⚠️ ============================================================"
  echo "⚠️  DIY_Service_Agent.bot-meta.xml currently contains:"
  echo "⚠️    $CURRENT"
  echo "⚠️"
  echo "⚠️  Expected: <botUser>AGENT_USER_EMAIL</botUser>"
  echo "⚠️"
  echo "⚠️  This means a prior run's Step 9.5 rollback did NOT execute."
  echo "⚠️  Possible causes:"
  echo "⚠️    - Prior run's deploy succeeded but rollback was skipped/aborted"
  echo "⚠️    - The repo was manually edited"
  echo "⚠️    - A prior run's deploy FAILED and the file was intentionally left dirty for debugging"
  echo "⚠️"
  echo "⚠️  Step 4 will substitute the current value with the new email"
  echo "⚠️  (fallback path) and proceed. Step 9.5 WILL fire on success and"
  echo "⚠️  restore the placeholder."
  echo "⚠️ ============================================================"
fi
```

**Do NOT abort on stale state** — the fallback in Step 4 handles it correctly. The warning's purpose is to make the recovery visible so the user can confirm the file isn't accumulating drift across runs.

**Continue to Step 1 regardless of canonical/stale outcome.**

---

### Step 1 — Execute Apex script to create Agent User

**CRITICAL: This step MUST succeed or entire workflow fails**

Run the Apex script to create agent user:

```bash
sf apex run -f "{repo_path}/scripts/apex/createAgentUser.apex" -o {org_alias}
```

**Expected output format examples:**
```
USER_DEBUG|User created: agent@example.com
```

Or:
```
User Email: agent@example.com
```

Or:
```
Created agent user: agent@example.com
```

**If command fails:**
- Report full error message from SF CLI
- Check org authentication: `sf org display -o {org_alias}`
- Suggest: `sf org login web -a {org_alias}`
- Stop execution

**If command succeeds:**
- Capture full output for parsing
- Continue to Step 2

---

### Step 2 — Parse Agent User email from output

**🚨 CRITICAL: Extract email address from the Apex `Created user:` DEBUG marker — NOT "first email pattern in output".**

The Apex script's actual output contains MULTIPLE emails, most of which are NOT the agent user:

```
Execute Anonymous:  * @author            : ChangeMeIn@UserSettingsUnder.SFDoc        ← apex docstring boilerplate (WRONG)
Execute Anonymous:  * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc        ← apex docstring boilerplate (WRONG)
10:00:44.233|USER_INFO|[EXTERNAL]|005Hn00000JCBgL|storm.556c4752411403@salesforce.com ← executing user, NOT the new agent (WRONG)
10:00:52.810 (8824069353)|USER_DEBUG|[93]|DEBUG|Created user: eagent1781100044645@example.com  ← THE REAL ONE
```

A naive "first email" extraction returns `ChangeMeIn@UserSettingsUnder.SFDoc` — a placeholder docstring address. The bot-meta.xml deploy will succeed (XML validation doesn't validate emails), but the agent will break at runtime because `botUser` resolves to a non-existent user.

**Correct extraction — match on the `Created user:` marker:**

```bash
AGENT_USER_EMAIL=$(grep -oE 'Created user: [a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$APEX_OUTPUT_FILE" \
  | head -1 \
  | awk '{print $NF}')
echo "Extracted agent_user_email=$AGENT_USER_EMAIL"
```

The `awk '{print $NF}'` strips the `Created user: ` prefix and leaves just the email. The `head -1` defends against multiple matches if the Apex script ever logs the line twice.

**Apex script contract (createAgentUser.apex MUST emit this marker):**

The Apex script writes:
```apex
System.debug('Created user: ' + newUser.Email);
```

which Salesforce's debug log renders as:
```
HH:MM:SS.SSS (...)|USER_DEBUG|[N]|DEBUG|Created user: <email>
```

If the Apex script ever changes the marker text, this regex must change with it. The marker is the contract.

**Fallback markers (less reliable — only if `Created user:` produces no match):**

```bash
# Fallback 1: bare "User Email: <email>" (some older versions of the script use this)
[ -z "$AGENT_USER_EMAIL" ] && AGENT_USER_EMAIL=$(grep -oE 'User Email: [a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$APEX_OUTPUT_FILE" | head -1 | awk '{print $NF}')

# Fallback 2: "Created agent user:"
[ -z "$AGENT_USER_EMAIL" ] && AGENT_USER_EMAIL=$(grep -oE 'Created agent user: [a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "$APEX_OUTPUT_FILE" | head -1 | awk '{print $NF}')
```

**🛑 NEVER use a bare email regex against the full apex output.** It will match `ChangeMeIn@UserSettingsUnder.SFDoc` (docstring) or the executing user's email — both wrong.

**If no email found from any marker:**
- Report error: "❌ Could not extract user email from Apex output via `Created user:` marker"
- Show the full Apex output for debugging
- Verify `scripts/apex/createAgentUser.apex` emits a `System.debug('Created user: ' + newUser.Email);` line
- Stop execution (do NOT proceed with a guessed email)

**If email found:**
- Validate it isn't a known false-positive: reject if it matches `ChangeMeIn@UserSettingsUnder.SFDoc` or contains `salesforce.com` (the executing admin's email — agent users always use synthetic `@example.com` or `@orgfarm.salesforce.com` style addresses)
- Store email in variable: `AGENT_USER_EMAIL`
- Report: "✅ Agent User created: {AGENT_USER_EMAIL}"
- Continue to Step 3

---

### Step 3 — Read Service Agent bot-meta.xml file

**Read the Service Agent XML configuration:**

**IMPORTANT:** Only DIY_Service_Agent requires botUser configuration. DIY_Employee_Agent does NOT need botUser update.

```
Tool: Read
file_path: {repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml
```

Check if `<botUser>` tag exists in the XML.

**Expected XML structure:**
```xml
<Bot xmlns="http://soap.sforce.com/2006/04/metadata">
    ...
    <botUser></botUser>
    ...
</Bot>
```

Or:
```xml
<Bot xmlns="http://soap.sforce.com/2006/04/metadata">
    ...
    <botUser>old@example.com</botUser>
    ...
</Bot>
```

**If file cannot be read:**
- Report error: "❌ Cannot read bot-meta.xml"
- Check file path and permissions
- Stop execution

**If file read successfully:**
- Store XML content for editing
- Continue to Step 4

---

### Step 4 — Update Service Agent botUser tag with new email

**CRITICAL: Use Edit tool to update XML (never Write tool)**

**IMPORTANT:** This step only updates DIY_Service_Agent.bot-meta.xml. DIY_Employee_Agent does NOT require botUser configuration.

**Canonical case (placeholder pattern — repo state):**

The repo file ships with `<botUser>AGENT_USER_EMAIL</botUser>`. Substitute the placeholder with the real email:

```
Tool: Edit
file_path: {repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml
old_string: <botUser>AGENT_USER_EMAIL</botUser>
new_string: <botUser>{agent_user_email}</botUser>
```

**Fallback cases (only if `AGENT_USER_EMAIL` placeholder is missing):**

If a previous run failed mid-flow without rollback, the file may contain a stale email or be empty. Read the file first to detect:

- If contains `<botUser></botUser>` → empty tag, replace with `<botUser>{agent_user_email}</botUser>`
- If contains `<botUser>old@example.com</botUser>` → stale email from a prior run, replace with `<botUser>{agent_user_email}</botUser>`
- If `<botUser>` tag is missing entirely → insert after `</botVersions>`

In all fallback cases, log a warning: `⚠️ Repo file was not in canonical placeholder state — previous run may have failed without rollback`.

**If Edit fails:**
- Report error: "❌ Failed to update bot-meta.xml"
- Show current content of `<botUser>` tag
- Stop execution

**If Edit succeeds:**
- Report: "✅ Service Agent bot configuration updated with Agent User: {agent_user_email}"
- Note: "DIY_Employee_Agent does not require botUser configuration"
- Continue to Step 5

---

### Step 5 — Verify the Service Agent update

**CRITICAL: Verify Service Agent XML was updated correctly before proceeding**

Read the updated Service Agent file to confirm:

```
Tool: Read
file_path: {repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml
```

Search for the updated line: `<botUser>{agent_user_email}</botUser>`

**If found:**
- Report: "✅ Verification successful - Service Agent botUser tag contains: {agent_user_email}"
- Report: "ℹ️ Note: Employee Agent does not require botUser configuration"
- Continue to Step 6

**If not found:**
- Report error: "❌ Verification failed - Service Agent botUser tag not updated correctly"
- Show current XML content
- Stop execution

---

### Step 6 — Deploy Agents Package

**CRITICAL: Only proceed if Steps 0-5 completed successfully**

Navigate to repository directory and deploy diy-pd-pack:

```bash
cd "{repo_path}" && sf project deploy start -d diy-pd-pack -o {org_alias}
```

Wait for deployment to complete (may take several minutes).

**Expected output:**
```
Deploy ID: 0Af...
Deploy Status: Succeeded
```

**Common errors and solutions:**

**Error 1: FlexiPage Customer_Affinities error**
```
Error: Could not find related list [Customer_Affinities1__r] for entity [Account]
```

Solution:
- This occurs when Data Cloud Related List doesn't exist on Account object
- Comment out Customer_Affinities component in `diy-pd-pack/main/default/flexipages/Retail_Account_Record_page.flexipage-meta.xml` (around line 80)
- Retry deployment
- Note: Data Cloud Related List will be created automatically in Step 8 (data-cloud-related-list skill)

**Error 2: Other deployment failures**
- Report full error message
- Check if botUser XML was updated correctly
- Verify org has required permissions
- Stop execution (do not proceed to next steps)

**If deployment succeeds:**
- Report: "✅ Agents package deployed successfully"
- Report Deploy ID for reference
- Continue to Step 7

---

### Step 7 — Assign RetailDIYStorePS Permission Set to the Agent User (MANDATORY)

**🚨 CRITICAL — DO NOT SKIP. Without this permset on the agent user, both bots will fail at first conversation with object-access errors. The CLI's `sf org assign permset` defaults to the running CLI user (a System Administrator), NOT the freshly-created agent user, so use the targeted Apex assignment below.**

Run an Apex block that:
1. Looks up the agent User by the email captured in Step 2.
2. Looks up the `RetailDIYStorePS` PermissionSet.
3. Inserts a `PermissionSetAssignment` if and only if one doesn't already exist for that pair.

The `createAgentUser.apex` script in some repo branches already assigns `RetailDIYStorePS` as part of user creation. The block below is idempotent — if the assignment is already present, it logs and exits cleanly. Run it unconditionally; never skip this step on the assumption "the apex already did it."

```bash
cat > /c/tmp/assignPermsetToAgentUser.apex <<APEX
String agentEmail = '{agent_user_email}';
User u = [SELECT Id, Username, Email FROM User WHERE Email = :agentEmail LIMIT 1];
PermissionSet ps = [SELECT Id, Name FROM PermissionSet WHERE Name = 'RetailDIYStorePS' LIMIT 1];
List<PermissionSetAssignment> existing = [SELECT Id FROM PermissionSetAssignment
                                          WHERE AssigneeId = :u.Id AND PermissionSetId = :ps.Id LIMIT 1];
if (existing.isEmpty()) {
    insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    System.debug('Assigned RetailDIYStorePS to ' + u.Username);
} else {
    System.debug('RetailDIYStorePS already assigned to ' + u.Username);
}
APEX

sf apex run -f /c/tmp/assignPermsetToAgentUser.apex --target-org {org_alias}
```

**Expected debug line:** either `Assigned RetailDIYStorePS to <username>` (first run) or `RetailDIYStorePS already assigned to <username>` (re-run).

**Hard verification — before proceeding to Step 8:**

```bash
sf data query --target-org {org_alias} \
  -q "SELECT COUNT() FROM PermissionSetAssignment WHERE Assignee.Email = '{agent_user_email}' AND PermissionSet.Name = 'RetailDIYStorePS'"
```

Expected: **`totalSize: 1`**. If `0`:
- Re-run the Apex block once.
- Re-query.
- If still `0`, **STOP** — surface the apex log. Do NOT proceed to Step 8 (agents activated without this permset will appear "active" in Setup but break the moment a user talks to them).

**Cleanup of the temp Apex file:**

```bash
rm -f /c/tmp/assignPermsetToAgentUser.apex
```

Continue to Step 8 only after verification confirms the assignment.

---

### Step 7.5 — Bind System Administrator profile + RetailDIYStorePS to DIY_Employee_Agent ONLY (MANDATORY — runs BEFORE activation)

**🚨 SCOPE — this step targets ONLY `DIY_Employee_Agent`. The Service Agent (`DIY_Service_Agent`) is excluded.**

| Agent | How it gets access | Where it's configured |
|---|---|---|
| `DIY_Service_Agent` (`type=ExternalCopilot`) | Via `<botUser>` in bot-meta.xml | **Step 4** — set in `DIY_Service_Agent.bot-meta.xml` to point at the agent user. Service agents run as the bot user; profile/permset bindings on the bot itself are not used. |
| `DIY_Employee_Agent` (`type=InternalCopilot`) | Via `SetupEntityAccess` rows binding (Profile-shadow PS + RetailDIYStorePS) → BotDefinition | **THIS STEP (7.5)** — Apex DML inserts 2 rows. The Employee Agent runs as the launching user, so launching users need their profile or permset on the agent's access list. |

**Why the Service Agent is intentionally NOT bound here:** the Service Agent has a `<botUser>` (set in Step 4 to e.g. `eagent1781609906384@example.com`). When a customer chats with it via Embedded Messaging, the bot runs as the bot user — there is no per-customer profile in play. Adding `SetupEntityAccess` rows for the Service Agent would have no effect on its runtime behavior; its access is governed entirely by the bot user's own permsets (Step 7 already assigns RetailDIYStorePS to that user).

**Why the Employee Agent needs SetupEntityAccess:** `DIY_Employee_Agent` is `<type>InternalCopilot</type>` with `agentType: AgentforceEmployeeAgent`. It does NOT support `<botUser>` (Salesforce returns: *"The bot type InternalCopilot doesn't support the Bot User setting"* — verified 2026-06-16 deploy `0Afg7000006AjRpCAK`). Instead, the Setup UI at `/lightning/setup/EinsteinCopilot/<botId>/edit` → **Agent Access** tab exposes:

- **"Profiles with Agent Access"** — which profiles can launch the agent
- **"Permission Sets with Agent Access"** — which permsets can launch the agent

**Both tabs are views over the same physical table: `SetupEntityAccess` (writable via Apex DML).** Each row binds one Profile (via its profile-shadow PermissionSet) OR one PermissionSet to one Bot via:
- `ParentId` = PermissionSet Id (a profile-shadow permset for profile bindings, OR a regular PermissionSet for permset bindings)
- `SetupEntityId` = `BotDefinition.Id` (e.g. `0Xxg7000000jfLZCAY` for Employee Agent)
- `SetupEntityType` = auto-derived to `'BotDefinition'` (DO NOT set this field — it's read-only and Apex insert fails with `Field is not writeable: SetupEntityAccess.SetupEntityType` if you try)

**This step writes those rows directly via Apex DML.** It does NOT depend on Salesforce's auto-bind-during-deploy behavior, which is org-version-dependent and unreliable. Verified working 2026-06-16: 2 rows inserted via Apex (System Administrator profile-shadow permset + RetailDIYStorePS), both immediately visible in the Setup UI.

**Apex script template — bind ONLY the Employee Agent (2 rows):**

```bash
cat > /c/tmp/bindEmployeeAgentAccess.apex <<'APEX'
// Bind System Administrator profile + RetailDIYStorePS to DIY_Employee_Agent ONLY.
// Writes to SetupEntityAccess — the table behind the Setup UI's
// "Profiles with Agent Access" + "Permission Sets with Agent Access" tabs.
//
// DIY_Service_Agent is intentionally excluded — its access is via <botUser> in
// bot-meta.xml (Step 4), not via SetupEntityAccess. Adding rows for the Service
// Agent here would have no runtime effect.

// Resolve the System Administrator profile's shadow PermissionSet.
// Salesforce stores per-profile permset rows in PermissionSet with IsOwnedByProfile=true.
Profile sysAdmin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
PermissionSet adminShadowPS = [
    SELECT Id, Name FROM PermissionSet
    WHERE ProfileId = :sysAdmin.Id AND IsOwnedByProfile = true LIMIT 1
];
System.debug('System Admin shadow permset: ' + adminShadowPS.Id + ' (' + adminShadowPS.Name + ')');

// Resolve RetailDIYStorePS
PermissionSet retailPS = [SELECT Id FROM PermissionSet WHERE Name = 'RetailDIYStorePS' LIMIT 1];
System.debug('RetailDIYStorePS: ' + retailPS.Id);

// Resolve DIY_Employee_Agent BotDefinition
BotDefinition employeeBot = [
    SELECT Id, DeveloperName FROM BotDefinition
    WHERE DeveloperName = 'DIY_Employee_Agent' LIMIT 1
];
Id employeeBotId = employeeBot.Id;
System.debug('DIY_Employee_Agent BotId: ' + employeeBotId);

// Pre-query existing SetupEntityAccess rows (idempotency)
List<SetupEntityAccess> existing = [
    SELECT Id, ParentId FROM SetupEntityAccess
    WHERE SetupEntityId = :employeeBotId AND SetupEntityType = 'BotDefinition'
];
Set<Id> existingParents = new Set<Id>();
for (SetupEntityAccess s : existing) existingParents.add(s.ParentId);

// Build the desired 2-row binding set:
//   (System Admin shadow PS, Employee Bot)
//   (RetailDIYStorePS,       Employee Bot)
List<SetupEntityAccess> toInsert = new List<SetupEntityAccess>();
for (Id parentId : new List<Id>{adminShadowPS.Id, retailPS.Id}) {
    if (!existingParents.contains(parentId)) {
        // CRITICAL: do NOT set SetupEntityType — it is read-only and auto-derived from SetupEntityId prefix.
        // Including it causes: "Field is not writeable: SetupEntityAccess.SetupEntityType"
        toInsert.add(new SetupEntityAccess(ParentId = parentId, SetupEntityId = employeeBotId));
    }
}

if (toInsert.isEmpty()) {
    System.debug('Both Employee Agent bindings already present — no DML needed');
} else {
    insert toInsert;
    System.debug('Inserted ' + toInsert.size() + ' SetupEntityAccess rows for DIY_Employee_Agent');
    for (SetupEntityAccess s : toInsert) {
        System.debug('  Bound ParentId=' + s.ParentId + '  to BotId=' + s.SetupEntityId);
    }
}
APEX

sf apex run -f /c/tmp/bindEmployeeAgentAccess.apex --target-org {org_alias}
```

**Hard verification — before proceeding to Step 8:**

```bash
sf data query --target-org {org_alias} -q "SELECT COUNT() FROM SetupEntityAccess WHERE SetupEntityType = 'BotDefinition' AND SetupEntityId IN (SELECT Id FROM BotDefinition WHERE DeveloperName = 'DIY_Employee_Agent')"
```

Expected: **`totalSize: 2`** (Employee Agent × 2 bindings: System Admin shadow permset + RetailDIYStorePS).

If `< 2` after the Apex run, re-run the Apex once. If still `< 2`, STOP and surface:

- The Apex log
- The current SOQL count
- A row-by-row dump of what IS present:
  ```bash
  sf data query --target-org {org_alias} \
    -q "SELECT Parent.Name, Parent.Label, SetupEntityId FROM SetupEntityAccess WHERE SetupEntityType = 'BotDefinition' AND SetupEntityId IN (SELECT Id FROM BotDefinition WHERE DeveloperName = 'DIY_Employee_Agent')"
  ```

**Cleanup of the temp Apex file:**

```bash
rm -f /c/tmp/bindEmployeeAgentAccess.apex
```

Continue to Step 8 only after the SOQL count returns 2.

**Why this works:** `SetupEntityAccess` is the underlying table for ALL "Permission Set Group" / Profile permset / agent-access bindings in Setup UI. It accepts Apex DML on `INSERT` (and `DELETE` to remove bindings). The `Field is not writeable: SetupEntityAccess.SetupEntityType` error is the only gotcha — leave that field out and Salesforce derives it from the SetupEntityId's 3-character prefix (`0Xx` → `BotDefinition`).

**Why we use the profile-shadow permset and not the Profile directly:** the Setup UI's "Profiles with Agent Access" tab actually doesn't bind Profiles — it binds the **profile-shadow PermissionSet** that Salesforce auto-creates for every Profile. These rows have `IsOwnedByProfile = true` and `Name = 'X00<encoded_profile_id>...'`. The `RetailDIYStorePS` (a regular permset) and the System Admin shadow permset are both ParentIds on `SetupEntityAccess` — they're distinguished only by which tab the UI puts them in based on `IsOwnedByProfile`.

---

### Step 8 — Activate Employee Agent (DIY_Employee_Agent) — MANDATORY

**🚨 BOTH AGENTS MUST BE ACTIVATED. This step CANNOT be skipped, marked as "non-critical", or treated as optional.** A `BotDefinition` created by the metadata deploy is `Inactive` by default; without `sf agent activate`, the App Launcher entry exists but the agent never runs.

```bash
sf agent activate --api-name DIY_Employee_Agent --target-org {org_alias}
```

**Expected output (verbatim):** `Agent DIY_Employee_Agent activated.`

**Retry policy:**
- On failure containing `"still being provisioned"` / `"BotDefinition not found"` / `"Bot is not yet ready"` → wait 30s, retry. Up to **5 attempts** total (older guidance said 3 — bumping to 5 because deploy-to-activate provisioning lag has been observed at >2 minutes on fresh orgs).
- On any other failure → STOP and surface the CLI output. Do NOT continue to Step 9 — both agents must succeed together as a unit.

**Hard verification:**

```bash
sf data query --target-org {org_alias} \
  -q "SELECT Id, MasterLabel, DeveloperName FROM BotVersion WHERE BotDefinition.DeveloperName = 'DIY_Employee_Agent' AND Status = 'Active'"
```

Expected: **`totalSize: 1`**. If `0`, the CLI's success message lied about activation (rare but observed) — re-run `sf agent activate` once and re-verify. If still `0`, STOP and surface the SOQL response.

Continue to Step 9 only after verification shows an Active BotVersion.

---

### Step 9 — Activate Service Agent (DIY_Service_Agent) — MANDATORY

**🚨 SAME RULE AS STEP 8 — DO NOT SKIP, DO NOT TREAT AS OPTIONAL.** The Service Agent is the one wired to the Embedded Messaging chat icon on the storefront — without it, every chat session opens to a non-functional bot.

```bash
sf agent activate --api-name DIY_Service_Agent --target-org {org_alias}
```

**Expected output (verbatim):** `Agent DIY_Service_Agent activated.`

**Retry policy:** identical to Step 8 — up to 5 attempts, 30s between retries, on `"provisioning"` / `"not yet ready"` / `"BotDefinition not found"` errors.

**Hard verification:**

```bash
sf data query --target-org {org_alias} \
  -q "SELECT Id, MasterLabel, DeveloperName FROM BotVersion WHERE BotDefinition.DeveloperName = 'DIY_Service_Agent' AND Status = 'Active'"
```

Expected: **`totalSize: 1`**. If `0`, re-run activation once and re-verify. If still `0`, STOP and surface the SOQL response — the Service Agent is a hard dependency for the storefront chat icon and the install is incomplete without it.

Continue to Step 9.5 (rollback) only after BOTH Step 8 AND Step 9 verifications confirm Active BotVersions.

---

### Step 9.5 — Rollback bot-meta.xml to AGENT_USER_EMAIL placeholder

**🚨 THIS STEP IS MANDATORY ON DEPLOY SUCCESS — DO NOT SKIP.**

The repo must remain org-agnostic. After Step 6's deploy succeeded and the agents activated, restore the placeholder so the next run (this org or another org) starts clean.

**Precondition:** Step 6 deploy reported `Status: Succeeded`. If deploy failed, skip this step entirely — leave the file dirty so the user can inspect what was about to deploy. Agent activation failures (Steps 8-9) DO NOT block rollback because the agents may activate later automatically; the deploy is the load-bearing operation.

**Reverse the substitution from Step 4:**

```
Tool: Edit
file_path: {repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml
old_string: <botUser>{agent_user_email}</botUser>
new_string: <botUser>AGENT_USER_EMAIL</botUser>
```

Where `{agent_user_email}` is the email captured in Step 2.

**Verify rollback:**

```bash
grep -E "<botUser>" {repo_path}/diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml
```

Expected output: `<botUser>AGENT_USER_EMAIL</botUser>`

**If verification fails:**
- Report: `❌ Rollback verification failed for DIY_Service_Agent.bot-meta.xml — manual cleanup required`
- The org has the deployed configuration regardless; only the local repo state is dirty
- Continue to Step 10 with a warning

**If verification passes:**
- Report: "✅ Rollback complete — DIY_Service_Agent.bot-meta.xml restored to AGENT_USER_EMAIL placeholder"
- Continue to Step 10

---

### Step 10 — Generate Final Completion Report

Generate comprehensive completion report:

```text
✅ Agent Setup and Configuration Completed!

Org: {org_alias}
Repository: {repo_path}

═══════════════════════════════════════════════════

📋 Execution Results:

1. ✅ Agent User Created
   Email: {agent_user_email}
   
2. ✅ Bot Configuration Updated
   File: DIY_Service_Agent.bot-meta.xml
   botUser: {agent_user_email}
   
3. ✅ Agents Package Deployed
   Package: diy-pd-pack
   Deploy ID: {deploy_id}
   Status: Succeeded
   
4. ✅ Permission Set Assigned to Agent User
   Permission Set: RetailDIYStorePS
   Assigned To: {agent_user_email}

5. ✅ DIY_Employee_Agent Access Bindings (SetupEntityAccess)
   - Profile: System Administrator (via shadow permset)
   - Permission Set: RetailDIYStorePS
   Note: DIY_Service_Agent uses <botUser> (Step 4) instead of SetupEntityAccess

6. ✅ Employee Agent Activation
   Agent: DIY_Employee_Agent
   Status: {status}
   
7. ✅ Service Agent Activation
   Agent: DIY_Service_Agent
   Status: {status}

═══════════════════════════════════════════════════

🔗 Verify Agent Setup:

1. Navigate to: Setup → Agents
2. Find: DIY_Employee_Agent and DIY_Service_Agent
3. Verify Status: Both show "Active"
4. Test both agents' functionality

═══════════════════════════════════════════════════

📝 Next Steps (Optional):

If you want to commit the configuration change to git:

cd "{repo_path}"
git add diy-pd-pack/main/default/bots/DIY_Service_Agent/DIY_Service_Agent.bot-meta.xml
git commit -m "Configure agent user: {agent_user_email}"
git push

═══════════════════════════════════════════════════

✅ Agent setup workflow completed successfully!
```

---

## Important Rules

**CRITICAL - Execution Sequence:**
- 🚨 **ALWAYS execute commands sequentially** - wait for each to complete
- 🚨 **STOP immediately if Steps 0-5 fail** - user creation and XML update are critical
- 🚨 **Wait for deployment to complete** before proceeding to next step
- 🚨 **Do NOT run commands in parallel** - must be sequential

**CRITICAL - File Handling:**
- ✅ **Always verify files exist** before reading/editing
- ✅ **Use Edit tool** to update existing XML (never Write)
- ✅ **Verify XML update** after editing (Step 5)
- ✅ **Use absolute file paths** for all operations

**CRITICAL - Error Handling:**
- ✅ **Parse Apex output** to extract email address
- ✅ **Stop if email not found** in Apex output
- ✅ **Stop if XML update fails** or verification fails
- ✅ **Stop if deployment fails** - do not proceed to permission set
- ❌ **Permission-set assignment (Step 7) is NOT optional** — STOP if assignment fails AND the SOQL verification shows 0 rows. The previous "continue if permset fails (non-critical)" rule is REMOVED. An agent without `RetailDIYStorePS` on its run-as user will appear active but fail at first conversation.
- ❌ **Agent activation (Steps 8 + 9) is NOT optional** — both bots MUST end with an Active BotVersion verified via SOQL. The previous "continue if activation fails" rule is REMOVED.
- ✅ **Retry agent activation up to 5 times** (bumped from 3) if provisioning errors occur. If still failing, STOP — do not declare success.

**CRITICAL - CLI Commands:**
- ✅ **ONLY use Salesforce CLI** - no browser automation
- ✅ **Change to repo directory** before deploy commands
- ✅ **Report clear status** messages at each step
- ✅ **Capture command output** for error reporting

**General Rules:**
- NEVER generate JavaScript files
- NEVER write automation scripts to disk
- NEVER overwrite XML with Write tool (use Edit only)
- NEVER skip XML verification step (Step 5)
- NEVER proceed to deployment if email extraction fails
- NEVER proceed to permission set if deployment fails
- NEVER suggest manual completion of any step - automate everything
- ALWAYS report errors with full context
- ALWAYS provide actionable error messages
- Estimated time: 5-10 minutes for complete workflow

---

## Example Usage

### Example 1: Basic agent setup

**User:** "Setup agents in <YOUR_ORG_ALIAS>"

**Skill:**
1. Verifies repository exists
2. Verifies Apex script exists
3. Verifies bot-meta.xml exists
4. Executes: `sf apex run -f scripts/apex/createAgentUser.apex -o <YOUR_ORG_ALIAS>`
5. Parses output → Extracts email: `diy.agent@example.com`
6. Reads bot-meta.xml
7. Updates `<botUser>` tag with `diy.agent@example.com`
8. Verifies update
9. Deploys: `cd repo && sf project deploy start -d diy-pd-pack -o <YOUR_ORG_ALIAS>`
10. Assigns permset: `sf org assign permset -n RetailDIYStorePS -o <YOUR_ORG_ALIAS>`
11. Activates Employee Agent: `sf agent activate --api-name DIY_Employee_Agent -o <YOUR_ORG_ALIAS>`
12. Activates Service Agent: `sf agent activate --api-name DIY_Service_Agent -o <YOUR_ORG_ALIAS>`
13. Reports completion

---

### Example 2: Error handling - Apex script not found

**User:** "Setup agents in TestOrg"

**Skill:** [Checks for Apex script]

**Error:** `Apex script not found: scripts/apex/createAgentUser.apex`

**Skill:**
```text
❌ Apex Script Not Found

Org: TestOrg

Required File: scripts/apex/createAgentUser.apex

Available files in scripts/apex/:
- createSampleData.apex
- assignPermissionSets.apex

Suggested Fix:
1. Verify repository is cloned correctly
2. Check if createAgentUser.apex exists in the repo
3. Pull latest changes: git pull origin main
4. Retry skill execution

Cannot proceed without Apex script.
```

---

### Example 3: Error handling - Deployment failed

**User:** "Setup agents in ProdOrg"

**Skill:** [Creates user, updates XML, starts deployment]

**Error:** `Deploy failed: Could not find related list [Customer_Affinities1__r] for entity [Account]`

**Skill:**
```text
❌ Deployment Failed

Org: ProdOrg

Error: FlexiPage Customer_Affinities issue
Could not find related list [Customer_Affinities1__r] for entity [Account]

This occurs when Data Cloud Related List doesn't exist on Account object.

Automatic Fix:
1. Comment out Customer_Affinities component in:
   diy-pd-pack/main/default/flexipages/Retail_Account_Record_page.flexipage-meta.xml
   (around line 80)
2. Retry deployment automatically
3. Data Cloud Related List will be created in Step 8 (data-cloud-related-list skill)
```

---

## Success Criteria

Agent setup is successful when **ALL** of these are true (no exceptions, no "non-critical" carve-outs):

✅ Repository and required files verified
✅ Apex script executed successfully
✅ Agent user email extracted from output (via the `Created user:` marker)
✅ bot-meta.xml file read successfully
✅ botUser tag updated with new email
✅ XML update verified
✅ Agents package deployed successfully
✅ **`RetailDIYStorePS` PermissionSetAssignment exists on the agent user** — verified via SOQL `SELECT COUNT() FROM PermissionSetAssignment WHERE Assignee.Email = '<email>' AND PermissionSet.Name = 'RetailDIYStorePS'` returning 1
✅ **2 SetupEntityAccess rows exist** binding (System Administrator profile-shadow permset + RetailDIYStorePS) to DIY_Employee_Agent — verified via SOQL `SELECT COUNT() FROM SetupEntityAccess WHERE SetupEntityType = 'BotDefinition' AND SetupEntityId IN (SELECT Id FROM BotDefinition WHERE DeveloperName = 'DIY_Employee_Agent')` returning 2. (DIY_Service_Agent is intentionally excluded — its access is via `<botUser>` in bot-meta.xml, not SetupEntityAccess.)
✅ **`DIY_Employee_Agent` has an Active BotVersion** — verified via SOQL `SELECT Id FROM BotVersion WHERE BotDefinition.DeveloperName = 'DIY_Employee_Agent' AND Status = 'Active'` returning ≥ 1
✅ **`DIY_Service_Agent` has an Active BotVersion** — verified via SOQL `SELECT Id FROM BotVersion WHERE BotDefinition.DeveloperName = 'DIY_Service_Agent' AND Status = 'Active'` returning ≥ 1
✅ bot-meta.xml rolled back to placeholder (Step 9.5)
✅ Comprehensive completion report provided

**If ANY of the three SOQL verifications above returns 0 rows, the skill MUST report failure — even if the CLI commands all reported success.** Salesforce's `sf agent activate` command and `sf org assign permset` have both been observed to report success while the side effect didn't land; the SOQL verification is the only reliable signal.

---

## Notes

- Agent activation via CLI is retried up to 3 times if provisioning errors occur
- Permission set assignment is optional - skill continues if it fails
- XML update must succeed - deployment will fail without correct botUser
- Deployment can take 5-10 minutes depending on org size
- Both DIY_Employee_Agent and DIY_Service_Agent use the same agent user account

---

## Cleanup temp artifacts (MANDATORY before next skill)

Before declaring this skill complete, delete every temporary file/folder created during the run.

**Failure handling rule:**
- If a step fails (deploy, permset, activation), **do NOT clean up** — leave artifacts for debugging.
- Fix the underlying issue, retry the failed step, then run cleanup once both agents are activated.
- The Step 9.5 rollback (`<botUser>AGENT_USER_EMAIL</botUser>`) is a separate concern — that's repo state, not temp files. It still runs as defined in Step 9.5.

**Files this skill creates and must delete:**

```bash
rm -f /c/tmp/createAgentUser.out
rm -f /c/tmp/diy_pd_deploy.json
```

**Verification (must report no remaining agent-setup scratch):**

```bash
ls /c/tmp/createAgentUser.out /c/tmp/diy_pd_deploy.json 2>&1 | grep -v "cannot access"
```

**Rules:**
- ✅ Only delete the files listed above. Do NOT delete `scripts/apex/createAgentUser.apex` or any repo source.
- ✅ Step 9.5 (bot-meta.xml rollback to placeholder) is unrelated to this cleanup and must still run.
- ❌ Skipping this step is not allowed once both agents are activated.
