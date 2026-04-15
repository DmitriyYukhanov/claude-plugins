---
name: cross-review
model: opus
description: Parallel dual review between Claude and Codex. Both models review independently, findings are cross-validated and resolved by evidence, with only genuinely inconclusive disagreements surfaced for user decision. Use for reviewing existing work with independent perspectives.
---

# Cross-Review: Parallel Dual Review

## Overview

Parallel review workflow between Claude and Codex CLI. Both models review the same artifact **simultaneously and independently**, then findings go through a three-stage resolution pipeline: initial triage → cross-validation (each model verifies the other's findings) → evidence-based research (documentation/code inspection for remaining disputes). Only genuinely inconclusive disagreements reach the user. Repeats until clean or max rounds reached.

**Core principle:** Two independent perspectives are stronger than one. Neither model sees the other's review until triage. Disagreements are resolved by **evidence first** (cross-validation, then documentation/code research) — the user is only asked to decide when evidence is genuinely inconclusive.

## Trigger Phrases

"cross-review", "dual review", "multi-model review", "get a second opinion", "validate with another model", "review with codex", "parallel review"

## Invocation

```
cross-review [--max-rounds N] [--type code|plan|architecture|design] [target files...]
```

| Argument | Default | Description |
|----------|---------|-------------|
| `--max-rounds` | `3` | Maximum review-fix iteration rounds |
| `--type` | (auto-detected) | Artifact type override |
| target files | (branch diff) | Specific files to review |

## Step 1: Preflight

Read `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md` and execute the preflight check.

Invoke `/codex:setup` via the Skill tool. Two failure modes:

1. **Command not recognized** (plugin not installed) -- print install instructions from prerequisites and ABORT. Do not continue to Step 2.
2. **Setup reports failure** (CLI missing, auth expired) -- report the specific error from `/codex:setup` and ABORT.

On success, proceed to Step 2.

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
3. If zero files in diff: ask the user what to review (this is the ONLY case where clarification is allowed)

### Classify Artifact Type

Follow the rules in `artifact-detection.md`.

### Gather Context for Non-Code Artifacts

For **design**, **plan**, and **architecture** artifacts, reviewers need codebase context to validate claims made in the spec. Code artifacts get this naturally from `git diff`, but specs reference source files that reviewers must read.

1. Scan the target spec for referenced file paths, function names, class names, and modules
2. Read the referenced source files (use an Explore agent for large blast radii, direct Read for 1-3 files)
3. Include key source context in the Codex prompt (`<codebase_context>` block) and pass file paths to Claude agents
4. This step pays for itself — reviewers without source context produce vague findings; reviewers WITH context catch concrete issues like wrong call-site counts and missing files in blast radius

### Initialize State

```
ROUND = 0
MAX_ROUNDS = <from args or 3>
ARTIFACT_TYPE = <detected>
TARGET_FILES = <resolved list>
BASE_BRANCH = <detected>
```

## Step 3: Parallel Review

**CRITICAL: Launch Claude agents and Codex simultaneously. Do NOT wait for one before starting the other.** Both review independently; cross-validation happens in Step 5.

### Claude Side (Background Agents)

Spawn focused review agents using the Agent tool. Each agent reviews through its domain lens using focus areas from `${CLAUDE_PLUGIN_ROOT}/skills/shared/review-domains.md`.

**Domain agents by artifact type:** Select agents and focus areas from `review-domains.md` for the detected artifact type. Do not use code-focused agents for design specs or vice versa.

**Scoping:**
- Use agent teams when scope is large (5+ files or complex multi-component changes)
- Use individual agents with `run_in_background: true` for smaller reviews (1-4 files)
- Each agent receives the target file paths and reviews through its domain lens
- On rounds N > 1, Claude agents scope to only changed files (use `git diff` to identify delta from previous round)

**Agent prompt pattern:**

```
You are a <domain> reviewer. Review these files: <file list>.
This is Round N of a cross-review. <If N > 1: Focus only on changes since last round.>

Use focus areas from the review-domains reference for <artifact type>.

Structure findings as:
- [severity] [category] file:line -- description
  Fix: concrete suggested fix

Severity levels: critical > high > medium > minor
Be specific: reference file paths, line numbers, and concrete examples.
```

### Codex Side (Simultaneously)

Launch Codex **in the same turn** as Claude agents. Do not wait for Claude.

**Pre-dispatch: fresh setup.** Before dispatching, re-invoke `/codex:setup` to verify the runtime is alive. Read the "Fresh Setup Before Dispatch" section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md`. Do NOT reuse the preflight result from Step 1 — the runtime endpoint may have changed. **After setup confirms success, proceed immediately to dispatch in the same turn. Do not stop, summarize setup status, or wait for user acknowledgment — the user said "cross-review", not "set up and ask me before continuing".**

**For code artifacts:**
- Invoke `/codex:review --base <ref> --background` via the Skill tool
- `/codex:review` reviews the entire branch diff, not specific files -- this is by design
- Do NOT combine `--base` with a prompt -- they are mutually exclusive in Codex CLI

**For non-code artifacts:**
- Invoke `/codex:rescue --fresh --background` via the Skill tool with a review prompt
- Compose the prompt using `gpt-5-4-prompting` patterns with XML-tagged blocks
- Include focus areas from `${CLAUDE_PLUGIN_ROOT}/skills/shared/review-domains.md` for the detected artifact type
- Include `${CLAUDE_PLUGIN_ROOT}/skills/shared/verdict-format.md` as `<structured_output_contract>`
- Non-code prompts can be scoped to specific files by including them in the prompt

**Post-dispatch: health check.** Within 60 seconds of dispatch, verify the task is making progress using the companion's task status (see "Task Health Verification" in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md`). **Do NOT use PID-based checks on Windows** — the CLI launcher exits immediately while the actual work happens in the runtime server.

**Poll and retrieve:**
- Poll job status via `/codex:status` (Skill tool)
- If `/codex:status` fails via Skill tool (e.g., `disable-model-invocation` error), fall back to querying the Codex companion's task status via Bash commands directly
- Retrieve output via `/codex:result` (Skill tool) when complete
- **Starting-stuck detection:** if the task phase stays `starting` for >5 minutes with no log entries, run Diagnostic Escalation from prerequisites.md
- **Response generation awareness:** after tool calls go quiet, the task is likely composing its response — this can take 10-30 minutes for complex reviews. Do NOT cancel. See "Response-Generation Awareness" in prerequisites.md.

### Codex Job Failure Handling

If Codex background job fails (auth expired, CLI error, timeout, dead task):

1. Follow the Auto-Retry Protocol in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md` — run diagnostics, then retry (max 2 retries)
2. If diagnostics reveal a connection issue (WebSocket limit, 403, etc.): report the specific error and remediation to the user. **Do NOT retry against a dead connection.** Wait for user to fix and confirm.
3. If all retries fail: **STOP and report.** Do NOT proceed with Claude-only findings.

**Both models are required.** The entire value of cross-review is independent perspectives from two different models. Claude reviewing its own output provides no cross-validation signal. If Codex cannot complete, the review must be retried after fixing the underlying issue — never degraded to single-model.

### Fast-Path: Zero Findings

If both reviewers produced zero findings, skip directly to Step 9 (Exit) with "all clean" status. Do not run triage, cross-validation, or evidence research on empty results.

## Step 4: Initial Triage

Claude compares the two independent reviews to find agreements, unique findings, and disagreements.

### Matching Process

For each unique finding across both reviews:

1. **Match findings** -- identify when both reviewers found the same issue (even if worded differently or categorized under different domains)
2. **Evaluate unique findings** -- when only one reviewer found an issue, note it as single-source
3. **Detect disagreements** -- flag cases where reviewers conflict on severity, fix approach, or whether something is an issue at all
4. **Classify** -- apply the initial classification table:

| Situation | Initial Classification |
|-----------|----------------------|
| Both agree (same issue, same or similar fix) | **agreed** |
| Only one side found it | **single-source** |
| Disagreement (severity, fix approach, or validity) | **disagreement** |
| Both rate as minor + no concrete action | **informational** |

### Triage Presentation (Internal)

Present the cross-model agreement matrix as a table for internal tracking. This table is NOT shown to the user yet — it feeds Step 5.

```
| # | Severity | Finding | Claude Agent 1 | Claude Agent 2 | Codex |
|---|----------|---------|----------------|----------------|-------|
| 1 | critical | Missing files in blast radius | critical | critical | major |
| 2 | high     | Call site count wrong | high | minor | major |
| 3 | —        | (Claude-only finding) | high | medium | — |
```

This format makes it immediately visible which findings are agreed, single-source, or disputed. Use `—` for reviewers that didn't find the issue. After classification, proceed **immediately** to Step 5 — do not stop or wait for user acknowledgment between triage and cross-validation.

### Fast-Path: Full Agreement

If triage yields only **agreed** and **informational** items (no single-source findings, no disagreements), skip Steps 5-6 entirely. Promote all agreed items to **auto-fixable** and go directly to Step 7 (Present).

## Step 5: Cross-Validation

**Purpose:** Verify single-source findings and attempt to resolve disagreements before involving the user. Each model's findings are verified by the other. Agreed and informational items from Step 4 pass through unchanged — only single-source and disagreement items are cross-validated.

### Launch Cross-Validation in Parallel

1. **Claude verifies Codex findings** — spawn a background Agent that:
   - Receives all Codex-only (single-source) findings and Codex's side of each disagreement
   - Reads the actual code/spec/docs referenced in each finding
   - For each finding: CONFIRM (with evidence from code) or REJECT (with counter-evidence)
   - May also REFINE (agree with the issue but disagree on severity/fix)

2. **Codex verifies Claude findings** — invoke `/codex:rescue --fresh --background` with:
   - All Claude-only (single-source) findings and Claude's side of each disagreement
   - Include `${CLAUDE_PLUGIN_ROOT}/skills/shared/validation-format.md` as `<structured_output_contract>`
   - Ask Codex to CONFIRM, REJECT, or REFINE each finding with evidence

Both run simultaneously — do NOT wait for one before launching the other.

### Process Cross-Validation Results

After both complete, reclassify each finding:

| Cross-Validation Result | New Classification |
|------------------------|-------------------|
| Single-source finding confirmed by other model | **auto-fixable** |
| Single-source finding refined by other model | **auto-fixable** (use refined severity/fix) |
| Single-source finding rejected by other model | **disagreement** (escalate) |
| Original disagreement — cross-validation resolved it | **auto-fixable** (use agreed fix) |
| Original disagreement — cross-validation refined it | **auto-fixable** (use refined fix) |
| Original disagreement — cross-validation did NOT resolve it | **disagreement** (escalate) |

Agreed and informational items from Step 4 carry forward unchanged (agreed → auto-fixable).

If zero disagreements remain after cross-validation, skip Step 6 and go directly to Step 7 (Present).

## Step 6: Evidence-Based Dispute Resolution

**Purpose:** Resolve remaining disagreements through documentation and code evidence before asking the user. Many disagreements stem from one model having incorrect assumptions about a framework, API, or codebase convention — evidence can settle these without user involvement.

### For Each Remaining Disagreement

1. **Identify the factual claim** — extract the specific assertion each model makes (e.g., "path points to unityLibrary" vs "path points to launcher")

2. **Research the claim** using available tools (prefer higher-quality sources, fall back as needed):
   - **Exa MCP** (`mcp__exa__web_search_exa`, `mcp__exa__web_fetch_exa`) — best for doc search and fetching; fall back to built-in `WebSearch`/`WebFetch` if Exa is not installed
   - **Context7 MCP** (`resolve-library-id` → `query-docs`) — best for framework/library docs; fall back to web search + fetch if not installed
   - **Code inspection** — read the actual files, check existing patterns in the codebase (always available)
   - Use whichever tools are available. The research step must not fail because a specific MCP server is missing.

3. **Evaluate evidence:**
   - If evidence **conclusively** supports one model's claim → classify as **resolved-by-evidence** (apply the evidenced fix)
   - If evidence is **ambiguous or insufficient** → remains a **disagreement** for user decision
   - If evidence **disproves both** models → flag as new finding with correct information

### Research Prompt Pattern

For each disagreement, search for the specific factual claim, not the general topic:
- Bad: "Unity Android manifest" (too broad)
- Good: "Unity IPostGenerateGradleAndroidProject path parameter unityLibrary vs launcher" (specific claim)

### Parallelism

Research multiple disagreements in parallel when they are independent. Use background agents or parallel tool calls.

### Output

After research, each disagreement is either:
- **resolved-by-evidence** — cite the source (doc URL, code file:line, API reference)
- **needs-decision** — evidence was inconclusive, present both sides + research findings to user

## Step 7: Present Results to User

Present findings in priority order. This step now only shows items that survived cross-validation AND evidence-based resolution.

### 1. Needs-Decision Items (First)

Only shown if evidence-based resolution could not settle the disagreement:

```
## Needs Decision

[1] [high] [security] src/auth.ts:42
    Claude: SQL injection via string concatenation. Fix: use parameterized query.
    Codex: Not exploitable -- input is validated upstream at line 30.
    Research: [summary of what evidence was found and why it was inconclusive]
    -> Please decide: fix or dismiss?
```

Wait for user decisions on each item before proceeding.

### 2. Auto-Fixable Items (Second)

Includes items agreed by both models AND items resolved by cross-validation/evidence:

```
## Auto-Fixable (confirm to proceed)

[3] [high] [correctness] src/handler.ts:87 -- Missing null check (both agree)
    Fix: Add guard clause before accessing .data property

[4] [medium] [test-coverage] src/auth.ts -- No tests for login flow (Claude found, Codex confirmed)
    Fix: Add unit tests for success and failure paths
```

### 3. Resolved by Evidence (Third)

Items where disagreements were settled by documentation/code research:

```
## Resolved by Evidence

[5] [critical] [technical] spec:40 -- manifest path correctness
    Claude claimed: path points to wrong module (launcher needed)
    Codex claimed: path is correct (unityLibrary has activity declarations)
    Evidence: Unity API docs confirm path = unityLibrary module. Codex is correct.
    -> Applied Codex's recommendation. No user action needed.
```

### 4. Informational Items (Last)

```
## Informational

[6] [minor] [maintainability] src/utils.ts:12 -- Variable name could be more descriptive
```

## Step 8: Apply Fixes and Re-Review

After user confirms auto-fixable items and resolves needs-decision items, apply approved fixes.

### Skill Discovery

Search available skills for the best match based on artifact type:

| Artifact Type | Search Keywords | Priority |
|---------------|----------------|----------|
| Code | `coder`, `code-review`, `implementation`, `feature-dev` | Project-specific first |
| Plan | `writing-plans`, `executing-plans`, `plan` | General-purpose |
| Architecture | `architect`, `architecture`, `brainstorming`, `design` | General-purpose |
| Design | `brainstorming`, `writing-plans`, `design` | General-purpose |

**Selection priority:**
1. Project-specific skills (e.g., `unity-coder`, `python-coder`)
2. General-purpose skills (e.g., `writing-plans`, `brainstorming`)
3. Fallback: if no matching skill, apply fixes directly with Edit tool

### Apply Fixes

- Use subagents (Agent tool with `run_in_background: true`) for independent fixes that span different files
- Apply sequentially when fixes are interdependent or touch the same file
- Invoke discovered skill for guidance when available

### Re-Review

After fixes are applied, go back to Step 3 (Parallel Review) with these adjustments:

- **Claude side:** Scope agents to only changed files from this round (use `git diff` to identify delta)
- **Codex side for code:** `/codex:review` reviews the full branch diff (branch-scoped) -- it will see all branch changes, not just this round's fixes
- **Codex side for non-code:** `/codex:rescue --fresh` prompt can be scoped to specific changed files

Increment `ROUND` and repeat until exit conditions are met.

**File scoping constraint:** `/codex:review` and `/codex:adversarial-review` are branch-scoped. Codex will review all branch changes in re-reviews, not just the current round's files. Previously-fixed issues should not reappear, but Codex may surface new findings in unchanged code.

## Step 9: Exit and Summary

Exit when any of these conditions is met:
- All clean (no findings in latest round)
- Max rounds reached (default: 3)
- Unresolvable needs-decision items remain after user mediation

Present final state:

```
## Cross-Review Summary

Rounds completed: N (M included cross-validation)
Exit reason: <all clean | max rounds reached | user stopped>

Issues Found: X (across all reviewers)
Issues Fixed: Y
Issues Resolved by Evidence: Z
Issues Remaining: W

### Resolved
- [1] [severity] [category] file:line -- fixed in round N

### Resolved by Evidence
- [2] [severity] [category] file:line -- <source>: <brief explanation>

### Dismissed (user decision)
- [3] [severity] [category] file:line -- user dismissed: <reason>

### Remaining (if max rounds reached)
- [4] [severity] [category] file:line -- description
```

## Key Differences from Collaborative Loop

| Aspect | Cross-Review | Collaborative Loop |
|--------|-------------|-------------------|
| Execution model | **Parallel** -- both review at once | **Sequential** -- produce, validate, act |
| Primary goal | **Finding issues** in existing work | **Driving changes** iteratively |
| Disagreement handling | **Evidence-first** (cross-validate → research → user only if inconclusive) | Automated bilateral consensus gate |
| Codex failure | ABORTs (both models required) | ABORTs entirely |
| Best for | **Review of existing work** | **Iterative improvement** |
| Agent structure | Domain-specific reviewers | Single analysis pass |

Both skills require Codex — neither falls back to Claude-only mode. Use cross-review when you want independent perspectives on existing work. Use collaborative-loop when you want iterative improvement driven by bilateral consensus.

## Common Mistakes

- **Do NOT resolve disagreements by opinion.** Never silently pick one model's view over the other. Disagreements must be resolved by **evidence** (cross-validation + research) or escalated to the user. "Claude thinks X" is not evidence — documentation, code inspection, and API references are.

- **Do NOT run Claude agents to completion before launching Codex.** Both must start simultaneously. Launch Codex first (Skill tool), then spawn Claude agents in the same turn.

- **Do NOT forget to poll `/codex:status` for background jobs.** Codex runs in the background -- you must check status and retrieve results before triage. Poll every 5 minutes, not every 2 minutes — frequent polling wastes context.

- **Do NOT cancel a task after tool calls go quiet** — it is generating its response (10-30 min). See "Response-Generation Awareness" in prerequisites.md.

- **Do NOT use PID-based liveness checks on Windows** — use companion task status. See "Task Health Verification" in prerequisites.md.

- **Do NOT proceed with Claude-only findings if Codex fails.** Both models are required. STOP and report the failure with diagnostics.

- **Do NOT skip triage and apply both reviews directly.** The two reviews may contain contradictions. Triage reconciles them and identifies disagreements.

- **Do NOT combine `--base` with a prompt in `/codex:review`.** They are mutually exclusive in Codex CLI. Use `--base` alone for code review; use `/codex:rescue` with a prompt for non-code.

- **Do NOT review same issues each round.** Focus on deltas/changed files for Claude agents. Codex code review is branch-scoped by design but previously-fixed issues should not reappear.

- **Do NOT skip user confirmation for auto-fixable items.** Present the triage and wait for user to confirm before applying fixes.

- **Do NOT use `/codex:adversarial-review` for this workflow.** It produces independent findings without cross-mapping. Use `/codex:review` for code and `/codex:rescue` with structured prompts for non-code.

- **Do NOT escalate disagreements to the user before cross-validation and research.** The usage pattern is: triage → cross-validate → research evidence → only then ask the user. Premature escalation wastes the user's time on questions that documentation can answer.

- **Do NOT reuse stale preflight state for Codex dispatch.** The runtime endpoint (named pipe) can change between Step 1 preflight and Step 3 dispatch. Always re-run `/codex:setup` immediately before dispatching Codex. A 5-second setup call prevents 10+ minutes of debugging zombie tasks.
