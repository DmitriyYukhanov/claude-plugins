---
name: collaborative-loop
model: opus
description: Sequential drive/validate/act collaboration between Claude and Codex. Claude analyzes, Codex validates each finding, both models must agree before action. Use when you want iterative improvement with bilateral consensus.
---

# Collaborative Loop: Sequential Drive / Validate / Act

## Overview

Sequential pair-programming loop between Claude and Codex CLI. Claude PRODUCES an analysis with numbered findings, Codex VALIDATES each finding individually (CONFIRM/REJECT), Claude RE-EVALUATES the validation decisions, and only findings where both models agree proceed to implementation. After fixes, Codex reviews the changes and the loop repeats until clean.

**Core principle:** Claude never acts on its own unvalidated output. Every finding passes through bilateral consensus before implementation.

## Trigger Phrases

"collaborate with codex", "have codex review my changes", "drive and review loop", "iterative improvement", "produce-validate-act", "collaborative loop"

## Invocation

```
collaborative-loop [--max-rounds N] [--type code|plan|architecture|design] [target files...]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `--max-rounds` | `3` | Maximum fix-review iteration rounds |
| `--type` | (auto-detected) | Artifact type override |
| target files | (branch diff) | Specific files to analyze |

## Step 1: Preflight

Read `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md` and execute the preflight check.

Invoke `/codex:setup` via the Skill tool. Two failure modes:

1. **Command not recognized** (plugin not installed) — print install instructions from prerequisites and ABORT. Do not continue to Step 2.
2. **Setup reports failure** (CLI missing, auth expired) — report the specific error from `/codex:setup` and ABORT.

On success, proceed to Step 2.

### Liveness Check

After `/codex:setup` succeeds, verify the Codex broker can actually complete work (not just accept connections). Run a trivial Codex task:

```bash
node "${CLAUDE_PLUGIN_ROOT}/../codex/scripts/codex-companion.mjs" task --fresh "Reply with OK"
```

If this hangs for >60 seconds or returns empty output, the runtime's connection is dead (likely WebSocket TTL expired — see "WebSocket Connection Limit" in prerequisites.md). Recovery:

1. Ask the user to close all Codex instances and restart the Codex app/CLI
2. Re-run `/codex:setup` — the companion will establish a fresh connection
3. Repeat the liveness check

Only proceed to Step 2 after the liveness check passes.

### Runtime Failure Policy

The collaborative loop requires BOTH collaborators. If Codex fails at any point during the workflow (script error, empty output):

1. Do NOT fall back to a Claude subagent as reviewer -- self-review defeats the purpose
2. Attempt Direct CLI Fallback (see prerequisites.md) before stopping — construct a self-contained prompt with all context inlined and run via `codex exec`
3. Only STOP the loop if both companion and CLI fallback fail
4. Report the failure clearly with the exact error and suggest remediation (re-run `/codex:setup`, check auth, check OpenAI API status)

### Hang Detection

Codex tasks can legitimately run for 30+ minutes on complex analyses. Do NOT use a hard timeout. Use companion task status to assess health — **never PID-based checks on Windows** (see "Task Health Verification" in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md`).

**Tier 1 — Task health check (within 60 seconds of dispatch):**

After dispatching a Codex task, verify it is making progress within 60 seconds using the companion's task status. If the companion reports the task as `failed` or the runtime pipe is gone, follow the Auto-Retry Protocol in prerequisites.md.

**Tier 2 — Starting-stuck detection (5-minute threshold):**

If the task phase stays `starting` for >5 minutes without advancing to `running` or showing any log entries, run Diagnostic Escalation from prerequisites.md. This catches dead connections (WebSocket limit, 403 errors) quickly.

**Tier 3 — Response-generation awareness (critical):**

After tool calls go quiet, Codex is composing its response. Max wait: **15 minutes** of silence (reduced from prior guidance — session data shows silence >10 min is almost always a dead task, not slow generation). After 15 minutes, escalate to Direct CLI Fallback. See "Response-Generation Awareness" in prerequisites.md.

**When a genuine failure is detected:**

1. Cancel the stalled task via `/codex:cancel` or the companion
2. Run Diagnostic Escalation from prerequisites.md — check for connection errors before blindly retrying
3. If diagnostics reveal a connection issue → report to user with specific remediation, do NOT retry
4. If no connection issue → re-run `/codex:setup` and retry (max 2 companion retries)
5. If companion retries fail → escalate to Direct CLI Fallback (see prerequisites.md). Construct a self-contained prompt with all context inlined and run via `codex exec`
6. If both companion and CLI fail, STOP the loop and report diagnostics:
   ```
   Codex failed via both companion (N retries) and direct CLI.
   Diagnostics: <specific findings from logs>
   Remediation: Check OpenAI API status, verify auth (codex auth login), check network.
   ```

## Step 2: Detect Context

Read `${CLAUDE_PLUGIN_ROOT}/skills/shared/artifact-detection.md` and follow the detection procedure.

### Parse Arguments

- `--max-rounds N` (default: 3)
- `--type code|plan|architecture|design` (default: auto-detect from files)
- Remaining positional arguments are target files

### Resolve Target Files

If no target files provided:

1. Detect base branch: check for `main`, then `master`, then `git remote show origin` default
2. Run `git diff <base>...HEAD --name-only` to find changed files
3. If zero files in diff: ask the user what to work on (this is the ONLY case where clarification is allowed)

### Classify Artifact Type

Follow the rules in `artifact-detection.md`:

| Signal | Type |
|--------|------|
| Source code extensions (`.ts`, `.py`, `.js`, `.go`, `.rs`, `.cs`, `.java`, etc.) | **code** |
| `*-plan*`, `*-tasks*`, `*implementation-plan*` | **plan** |
| `*-architecture*`, `*-spec*` | **architecture** |
| Other `.md` in `docs/` or `plans/` | **design** |
| Mixed | default to **code** |

### Initialize State

```
ROUND = 0
MAX_ROUNDS = <from args or 3>
ARTIFACT_TYPE = <detected>
TARGET_FILES = <resolved list>
BASE_BRANCH = <detected>
```

## Step 3: Claude PRODUCES Analysis

Claude analyzes target files and produces numbered findings with severity. **No implementation yet** -- analysis only. Do not modify any files.

### Skill Discovery (Code Artifacts)

For code artifacts, search available skills for the best match:
- Search for: `coder`, `code-review`, `feature-dev`
- Priority: project-specific skills first (e.g., `unity-coder`, `python-coder`) then general-purpose
- If a matching skill is found, invoke it for analysis guidance
- If no skill found, perform direct structured analysis

### Non-Code Artifacts

For plan, architecture, and design artifacts, perform structured analysis against focus areas from `${CLAUDE_PLUGIN_ROOT}/skills/shared/review-domains.md`. Read the file and use the focus areas for the detected artifact type.

### Output Format

Produce numbered findings, globally ordered by severity:

```
[1] [critical] [security] src/auth/login.ts:42 -- SQL injection via unsanitized input
    Suggested fix: Use parameterized query instead of string concatenation

[2] [high] [correctness] src/api/handler.ts:87 -- Missing null check on response.data
    Suggested fix: Add guard clause before accessing .data property

[3] [medium] [performance] lib/cache.ts:15 -- Cache has no TTL, grows unbounded
    Suggested fix: Add maxAge option to cache constructor
```

Every finding must:
- Have a sequential number `[N]`
- Include severity: `critical`, `high`, `medium`, or `minor`
- Include category (e.g., security, correctness, performance, test-coverage)
- Reference specific `file:line`
- Provide a concrete suggested fix

Hold findings in conversation context. Do not write intermediate files.

## Step 4: Codex VALIDATES

Send Claude's numbered findings to Codex for per-finding validation. Codex independently evaluates each finding and returns CONFIRM or REJECT with evidence.

**Pre-dispatch: fresh setup.** Before dispatching, re-invoke `/codex:setup` to verify the runtime is alive. Read the "Fresh Setup Before Dispatch" section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md`. Do NOT reuse the preflight result from Step 1 — the runtime endpoint may have changed since preflight.

**IMPORTANT:** Use `/codex:rescue --fresh` via the Skill tool -- NOT `/codex:adversarial-review`. Adversarial review produces its own independent findings and does not map back per-finding. Only `/codex:rescue` with a custom prompt supports per-finding CONFIRM/REJECT. Always pass `--fresh` to prevent the codex plugin from prompting the user about resuming a previous thread.

**Monitor the task using the Hang Detection procedure from Step 1.** Verify task health within 60 seconds, watch for starting-stuck at 5 minutes. Remember: after tool calls go quiet, Codex is likely generating its response (10-30 minutes) — do NOT cancel. Poll status every 5 minutes, not every 2 minutes.

### Compose the Validation Prompt

Invoke the `gpt-5-4-prompting` skill patterns when composing the prompt. Structure the prompt with XML-tagged blocks:

**`<task>` block:**
```
Validate each of Claude's findings independently. For each finding, determine
whether it is a genuine issue (CONFIRM) or a false positive (REJECT). You must
provide evidence from the actual code or specification for each decision.
Also report any issues you find that Claude missed entirely.
```

**Include in the prompt:**
- Claude's numbered findings (the full list from Step 3)
- Focus areas from `${CLAUDE_PLUGIN_ROOT}/skills/shared/review-domains.md` for the detected artifact type
- `${CLAUDE_PLUGIN_ROOT}/skills/shared/validation-format.md` as `<structured_output_contract>`
- For code artifacts: include target file paths so Codex can read them directly
- For non-code artifacts: include the artifact content inline

### Expected Response

Codex returns per `validation-format.md`:

```
## Confirmed Findings
- [1] CONFIRM -- evidence from code/spec
- [3] CONFIRM -- evidence from code/spec

## Refined Findings
- [4] REFINE -- agree with issue but severity should be medium, not high: <reasoning>

## Rejected Findings
- [2] REJECT -- evidence why this is a false positive

## New Findings (Missed by Driver)
- [high] [error-handling] src/api/handler.ts:91 -- Unhandled promise rejection
  Suggested fix: Add try/catch wrapper

## Status
VALIDATED | PARTIALLY_VALIDATED | REJECTED

## Summary
Brief assessment (confirmed X, refined Y, rejected Z, found W new)
```

## Step 4.5: Claude RE-EVALUATES Codex Validation

Claude reviews Codex's CONFIRM/REJECT decisions against the original analysis. This is the bilateral consensus gate.

### Decision Matrix

| Codex Says | Claude Agrees? | Action |
|------------|---------------|--------|
| CONFIRMED | Yes | **Proceed** -- act on this finding in Step 5 |
| CONFIRMED | No | **Flag for user** -- present disagreement, ask for mediation |
| REFINED | Yes | **Proceed** -- act with Codex's adjusted severity/fix |
| REFINED | No | **Flag for user** -- present disagreement on the refinement |
| REJECTED | Yes | **Drop** -- both agree this is not a real issue |
| REJECTED | No | **Flag for user** -- present disagreement, ask for mediation |

### Process

1. For each CONFIRMED finding: Claude reviews whether the confirmation is sound. If Claude still agrees the finding is real, mark as **proceed**. If Claude now thinks Codex's confirmation was based on a misunderstanding, mark as **flag**.

2. For each REFINED finding: Claude reviews the adjusted severity/fix. If Claude agrees with the refinement, mark as **proceed** (using Codex's adjusted severity/fix). If Claude disagrees with the refinement, mark as **flag**.

3. For each REJECTED finding: Claude reviews whether the rejection is justified. If Claude agrees the finding was a false positive, mark as **drop**. If Claude still believes the finding is valid despite Codex's rejection, mark as **flag**.

4. For new findings from Codex: Claude evaluates each. If Claude agrees it is a real issue, mark as **proceed**. If Claude disagrees, mark as **flag**.

4. **Flagged disagreements:** Present ALL flagged items to the user with both models' reasoning. Wait for user mediation before continuing. The user may:
   - Confirm the finding (add to proceed list)
   - Reject the finding (add to drop list)
   - Modify the finding and confirm

5. Only findings marked **proceed** (including user-mediated ones) advance to Step 5.

**Never silently resolve disagreements.** The entire point of bilateral consensus is that ambiguous cases get human judgment.

## Step 5: Claude ACTS on Validated Findings

Filter to confirmed-and-agreed findings only. Claude implements the fixes.

### Implementation Strategy

- Apply fixes in order of severity (critical first)
- For each fix, make the minimum change that addresses the finding
- Use subagents (Agent tool with `run_in_background: true`) when parallelism adds value -- specifically when fixes are independent and span different modules/files
- When fixes are interdependent or touch the same file, apply sequentially

### Rejected Findings

Log dropped findings for the summary but do not act on them:
```
Dropped (both models agreed not real):
- [2] [high] [correctness] src/api/handler.ts:87 -- reason for drop
```

## Step 6: Codex REVIEWS Changes

After Claude implements fixes, Codex reviews the resulting changes.

**Pre-dispatch: fresh setup.** Before dispatching, re-invoke `/codex:setup` to verify the runtime is alive. Same rationale as Step 4 — the runtime endpoint may have changed during Claude's implementation work in Step 5.

### For Code Artifacts

Invoke `/codex:review --base <ref>` via the Skill tool, where `<ref>` is the commit or ref before Step 5's changes. This uses the codex plugin's native review capability.

### For Non-Code Artifacts

Invoke `/codex:rescue --fresh` via the Skill tool with a review prompt. Compose the prompt using `gpt-5-4-prompting` patterns:

- `<task>`: Review the changes made to these artifacts. Evaluate whether the fixes correctly address the validated findings without introducing new issues.
- Include the modified artifact content
- Include `${CLAUDE_PLUGIN_ROOT}/skills/shared/verdict-format.md` as `<structured_output_contract>`

### Expected Response

Codex returns per `verdict-format.md`:

```
## Status
APPROVED | MINOR_ISSUES | CHANGES_REQUESTED

## Findings
- [severity] [category] file:line -- description
  Fix: concrete suggested fix

## Summary
Brief overall assessment
```

## Step 7: Evaluate and Loop

Parse the verdict status from Codex's response.

### Exit Conditions

**`APPROVED`** -- All issues resolved. Present final summary and stop.

**`MINOR_ISSUES`** -- Only minor/informational findings remain. Log them in the summary and stop.

**`CHANGES_REQUESTED`** -- Actionable findings remain. Continue to next round:

1. Increment `ROUND`
2. Check stall detection (see below)
3. Check max rounds (see below)
4. If neither triggered: feed Codex's findings back to Step 5 (skip Steps 3-4.5 since Codex's review findings are already validated by Codex)

### Stall Detection

Track findings across rounds. If more than 50% of findings persist (same file:line, same category) across 2 consecutive rounds:

1. Stop the loop
2. Present the stalled findings to the user with context:
   ```
   Stall detected: X of Y findings persisted across rounds N and N+1.
   These findings may require architectural changes or manual intervention:
   - [finding details]
   - [finding details]
   Please advise: continue with modified approach, or stop here?
   ```
3. Wait for user guidance before continuing or stopping

### Max Rounds Reached

When `ROUND >= MAX_ROUNDS`:

1. Stop the loop
2. Present remaining unresolved findings:
   ```
   Max rounds (N) reached. Remaining issues:
   - [finding details]
   - [finding details]
   ```
3. Do not continue automatically

### Final Summary

Present at the end of every loop run (whether clean exit, stall, or max rounds):

```
## Collaborative Loop Summary

Rounds completed: N
Findings resolved: X
Findings dropped (consensus reject): Y
Findings remaining: Z

### Resolved
- [1] [severity] [category] file:line -- fixed in round N

### Dropped
- [2] [severity] [category] file:line -- both models agreed not real

### Remaining (if any)
- [5] [severity] [category] file:line -- description
```

## Key Principles

1. **Claude never acts on unvalidated output.** Step 3 produces analysis; Step 4 validates it; Step 4.5 requires bilateral agreement. Only then does Step 5 implement.

2. **Both models must agree before action.** The Step 4.5 decision matrix ensures that disagreements are surfaced to the user, never silently resolved.

3. **No intermediate files.** Claude holds all state (findings, validations, round tracking) in conversation context. No temp files to manage or clean up.

4. **No self-review fallback.** If Codex fails at any point, STOP. Do not substitute Claude reviewing its own work -- that defeats the purpose of bilateral validation.

5. **Parallelism is organic.** Claude uses Agent tool subagents when fixes are independent. Codex uses `multi_agent = true` internally when the prompt includes parallelism instructions. Neither is forced.

6. **Disagreements go to the user.** When Claude and Codex disagree on a finding's validity, the user mediates. No model overrides the other.

## Common Mistakes

- **Do NOT use `/codex:adversarial-review` for validation.** It produces its own independent findings instead of CONFIRM/REJECT on Claude's findings. Only `/codex:rescue` with a custom prompt provides per-finding validation.

- **Do NOT act on unvalidated output.** Claude's Step 3 analysis is a proposal, not a mandate. Every finding must pass through Steps 4 and 4.5 before implementation.

- **Do NOT fall back to Claude-only if Codex fails.** Self-review provides no additional signal. Stop the loop and report the failure.

- **Do NOT silently resolve disagreements.** If Claude and Codex disagree on a finding, present both perspectives to the user. Never auto-resolve in favor of either model.

- **Do NOT forget `gpt-5-4-prompting` patterns.** When composing any prompt for Codex (Steps 4, 6), invoke the `gpt-5-4-prompting` skill to use proper XML-tagged block structure. Codex performs significantly better with structured prompts.

- **Do NOT skip Step 4.5.** The re-evaluation gate is what distinguishes this from a simple "send to Codex and trust the result" workflow. Claude's independent review of Codex's decisions catches validation errors.

- **Do NOT poll Codex status rapidly.** Check status every 5 minutes, not every few seconds. 50+ bash commands polling status wastes context and provides no value.

- **Do NOT use hard timeouts for Codex tasks.** Complex validations legitimately take 15-30 minutes. A hard timeout would kill healthy tasks. Use the Hang Detection procedure from Step 1.

- **Do NOT cancel a task after tool calls go quiet** — it may be generating its response. But do NOT wait more than **15 minutes** of silence either — escalate to Direct CLI Fallback. See "Response-Generation Awareness" in prerequisites.md.

- **Do NOT use PID-based liveness checks on Windows** — use companion task status. See "Task Health Verification" in prerequisites.md.

- **Do NOT reuse stale preflight state for Codex dispatch.** The runtime endpoint (named pipe) can change between Step 1 preflight and Steps 4/6 dispatch. Always re-run `/codex:setup` immediately before dispatching Codex. A 5-second setup call prevents 10+ minutes of debugging zombie tasks.

- **Do NOT poll Codex status with repeated bash commands.** Use the Monitor tool to wait for completion. One manual health check at 60 seconds, then Monitor events. Excessive polling wastes context for no value.

- **Do NOT give up when companion retries fail.** Always try Direct CLI Fallback (`codex exec`) before stopping. The companion has a known reliability issue on Windows — direct CLI creates fresh connections and consistently succeeds.
