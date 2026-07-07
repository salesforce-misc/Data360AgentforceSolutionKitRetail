# CLAUDE.md — Data360 Retail Installation rules

These rules apply to every conversation in this repo, including when a user invokes a single skill directly (`/intelligent-context`, `/refresh-data-streams`, etc.) outside the orchestrator agent. They do not modify any skill — skills continue to work exactly as written.

## Auto-launch the installer when the user asks to install

When the user says any of these in this repo (or anything semantically equivalent), invoke the `data360-retail-installer` agent immediately — do not run individual skills directly:

- "install Data360", "deploy Data360", "set up Data360"
- "install retail data kit", "deploy retail solution kit"
- "install D360", "set up the kit", "run the installer"

The orchestrator agent owns the full sequence. The agent's Step 0 will ask the user to pick Mode 1 (15 skills) or Mode 2 (21 skills) once, then auto-chain the rest. Do not pre-empt that prompt and do not invoke skills outside the agent.

## Canonical skill sequences

The authoritative Mode 1 (15 skills) and Mode 2 (21 skills) sequences live in [.claude/agents/data360-retail-installer/AGENT.md](.claude/agents/data360-retail-installer/AGENT.md) lines 52-96. Always treat that file as the source of truth — do not reorder, substitute, skip, or invent skills.

## Mandatory announce line (this is also the verification signal)

Before invoking ANY Data360 skill (whether via the agent or directly), the FIRST line of output MUST be:

```
Mode <N>, Step <X>: /<next-skill> (after Step <X-1>: /<previous-skill>)
```

No preamble, no other text before this line. This is non-negotiable — it is how the user (and any future tester) verifies the rules are loaded. If this line ever fails to appear before a skill invocation, the rules are not active and the next skill pick may be wrong; the run must stop.

## Sequence rules

Before invoking ANY Data360 skill:

1. **Confirm the install mode.** If the user has not stated Mode 1 or Mode 2, ask once. Do not guess.
2. **Read AGENT.md lines 52-96** to load the canonical sequence for the chosen mode.
3. **Identify the current position** by matching the just-completed skill (or the user's "start from X" / "continue" reference) against the sequence. If you cannot match it unambiguously, stop and ask which step to resume from. Do not guess.
4. **Pick the next skill from the sequence** — never substitute, reorder, or skip.
5. **Print the announce line first** (see section above).
6. **Inside the skill, run every numbered step in the skill's own SKILL.md.** Do not skip, merge, reorder, or "optimize" steps even if a step looks redundant or already done — the skill's own pre-checks will short-circuit safely when applicable.

## Failure handling (no fallback, no silent skip, no auto-decision)

When a skill or a step inside a skill fails:

1. **Stop immediately at the failure point.** Do not invoke the next skill. Do not advance to the next step inside the same skill. Do not retry on your own beyond what the skill itself defines.
2. **Attempt only the skill's own documented retry/recovery in place** (token refresh, transient HTTP retry, etc.). Do not invent new recovery logic, do not change selectors, do not patch the skill mid-run.
3. **If that recovery does not resolve it, STOP and surface the error to the user with full details:**
   - Which skill failed (name + its position in the Mode 1 / Mode 2 sequence)
   - Which numbered step *inside that skill* failed (read from the skill's own SKILL.md)
   - The exact error message / stack trace / API response returned
   - What was completed successfully before the failure
   - What is still pending
4. **Ask the user explicitly — these exact options, in this order:**

   ```
   Failure at Skill <S> ("/<skill-name>"), Step <T>.

   How should I proceed?
     (a) retry the SAME step (Step <T> of /<skill-name>)
     (b) skip Step <T> and continue with the NEXT step inside /<skill-name>
     (c) skip the rest of /<skill-name> and continue with the NEXT skill in the sequence (Skill <S+1>: /<next-skill>)
     (d) stop the install entirely and let me investigate
   ```

5. **Wait for the user's explicit reply.** Do NOT pick a default. Do NOT auto-retry. Do NOT auto-advance. The user's choice is the only thing that resumes execution.
6. **Resume from where the user directs** — never restart from Step 1, never silently skip ahead, never re-run already-completed skills.

## Bash permission popups

Bash auto-approval is already configured in [.claude/settings.json](.claude/settings.json) (`Bash(*)` allow + a deny list for destructive commands). Skills invoke Bash freely without prompting. If a popup ever appears, it means the command matches the deny list — investigate before approving manually.
