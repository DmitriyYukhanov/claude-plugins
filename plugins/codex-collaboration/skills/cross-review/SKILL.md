---
name: cross-review
model: opus
description: Parallel dual review between Claude and Codex. Both models review independently. Findings confirmed by reviewer agreement, cross-validation, or evidence research are auto-applied each round; only genuinely inconclusive disagreements surface for user decision. Use for reviewing existing work with independent perspectives.
---

# Cross-Review: Parallel Dual Review

## Overview

Parallel review workflow between Claude and Codex CLI. Both models review the same artifact **simultaneously and independently**, then findings go through a three-stage resolution pipeline: initial triage → cross-validation (each model verifies the other's findings) → evidence-based research (documentation/code inspection for remaining disputes). Only genuinely inconclusive disagreements reach the user. Repeats until clean or max rounds reached. Auto-apply is the default; the user is consulted only for needs-decision items where evidence couldn't break a tie.

**Core principle:** Two independent perspectives are stronger than one. Neither model sees the other's review until triage. Disagreements are resolved by **evidence first** (cross-validation, then documentation/code research) — the user is only asked to decide when evidence is genuinely inconclusive. Confirmed findings are applied automatically; the user is consulted only for genuinely inconclusive disagreements.

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

**Argument validation.** If `--max-rounds < 1` is passed, abort with the message `--max-rounds must be ≥ 1`. Do not silently coerce.

```
ROUND = 1
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

**Pre-dispatch: fresh setup.** Before dispatching, re-invoke `/codex:setup` to verify the runtime is alive. Read the "Fresh Setup Before Dispatch" section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md`. Do NOT reuse the preflight result from Step 1 — the runtime endpoint may have changed. After setup confirms success, proceed immediately to dispatch in the same turn — do not stop or summarize setup status mid-workflow.

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

**Post-dispatch: health check.** Within 60 seconds of dispatch, verify the task is making progress using `/codex:status` (Skill tool) — see "Task Health Verification" in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md`. **Do NOT use PID-based checks on Windows** — the CLI launcher exits immediately while the actual work happens in the runtime server.

**Poll and retrieve.** Codex background jobs do not auto-notify. After dispatch:

1. One health check at 60 s (`progressPreview` non-empty, `elapsed` advancing).
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/cross-review/wait-for-codex.{sh,ps1} <job-id>` via the Bash tool with `run_in_background: true`. Helper exits 0 on `done`, 1 on `failed`/`cancelled`, 2 on 15-min timeout. Read `internals.md#codex-monitoring` for invocation details.
3. Subagent gap: when `/codex:rescue --background` runs inside an Agent tool call, the subagent's completion notification reflects only the dispatch — always run wait-for-codex yourself.
4. Starting-stuck (>5 min in `starting` with no log entries) → Diagnostic Escalation in `prerequisites.md`.
5. Retrieve via `/codex:result <job-id>` once wait-for-codex exits 0. If `/codex:result` or `/codex:status` errors, see the "Retrieving Codex Output" section below.

### Codex Job Failure Handling

If Codex background job fails (auth expired, CLI error, timeout, dead task):

1. Follow the Auto-Retry Protocol in `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md` — run diagnostics, then retry (max 2 companion retries)
2. If diagnostics reveal a connection issue (WebSocket limit, 403, etc.): skip remaining companion retries and go directly to Direct CLI Fallback
3. If companion retries are exhausted: **escalate to Direct CLI Fallback** (see prerequisites.md). Construct a self-contained prompt with all context inlined and run via `codex exec`
4. If both companion and CLI fail: **STOP and report.** Do NOT proceed with Claude-only findings for the initial review (Step 3).

### Skill-gate Rejection (Distinct from Runtime Failure)

If the user denies the `/codex:rescue` or `/codex:review` Skill invocation at the permission prompt, no job was dispatched — the Auto-Retry Protocol does NOT apply (retrying against the same permission prompt is futile and looks like a bypass attempt). Instead:

1. Report to the user that Codex review is required for cross-review (both models needed)
2. Offer Direct CLI Fallback (`codex exec`) as an alternative that doesn't route through the Skill gate
3. Wait for the user's explicit choice before dispatching via CLI — denial at the Skill gate is the user exercising control, not a runtime fault

User denial ≠ runtime failure. Treat them as two distinct paths.

**Both models are required for the initial review.** The entire value of cross-review is independent perspectives from two different models. Claude reviewing its own output provides no cross-validation signal.

**Exception — cross-validation (Step 5) can degrade gracefully.** If the initial review (Step 3) succeeded from both models but Codex fails during cross-validation, the skill MAY continue with partial cross-validation (see Step 5 for details). The initial review already provides independent perspectives; cross-validation adds rigor but its failure doesn't void the initial findings.

### Retrieving Codex Output

- Retrieve output via `/codex:result` (Skill tool) when complete
- If `/codex:result` fails with `disable-model-invocation` error, fall back to the companion script — but resolve its path at runtime (it lives in the **codex** plugin's cache, not codex-collaboration's). See the "Skill-tool Fallback" section in `prerequisites.md` for the cross-platform discovery commands. Do NOT use `${CLAUDE_PLUGIN_ROOT}/../codex/scripts/...` — that assumes a sibling layout that is wrong when the two plugins come from different marketplaces.
- If `/codex:status` fails via Skill tool, apply the same fallback approach

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

If triage yields only **agreed** and **informational** items, skip Steps 5–6. Promote agreed items to auto-fixable, run Step 8 auto-apply, then Step 7 (post-apply presentation).

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

### Codex Cross-Validation Failure (Graceful Degradation)

If Codex fails during cross-validation (companion retries exhausted + CLI fallback failed), but the initial review (Step 3) completed successfully from both models:

1. **Claude cross-validation of Codex findings** — should already be complete (runs as a background Agent, independent of Codex)
2. **Codex cross-validation of Claude findings** — failed. For these unverified findings:
   - **Code-level verification:** Claude can verify its own single-source findings by direct code/spec inspection. Read the actual source files, check the claims, confirm or reject each finding based on evidence. This is NOT self-review (Claude isn't reviewing its own analysis quality) — it's verifying factual claims against source code.
   - Mark findings verified by code inspection as **needs-decision (code-verified)** — never auto-applied. Read `internals.md#code-verified-policy`.
   - Mark findings that cannot be verified by code inspection as **needs-decision (unverified)** — never auto-applied; surface with the "Codex couldn't cross-validate" note.
3. **Present results** with clear labeling: agreed items, cross-validated items, code-verified items (with note), and unverified items

Code inspection still runs — it sets the right confidence label (code-verified vs unverified). Both labels are needs-decision under autonomy; bilateral consensus is the auto-apply invariant.

### Process Cross-Validation Results

After both complete (or after graceful degradation), reclassify each finding:

| Cross-Validation Result | New Classification |
|------------------------|-------------------|
| Single-source finding confirmed by other model | **auto-fixable** |
| Single-source finding refined by other model | **auto-fixable** (use refined severity/fix) |
| Single-source finding rejected by other model | **disagreement** (escalate) |
| Original disagreement — cross-validation resolved it | **auto-fixable** (use agreed fix) |
| Original disagreement — cross-validation refined it | **auto-fixable** (use refined fix) |
| Original disagreement — cross-validation did NOT resolve it | **disagreement** (escalate) |

Agreed and informational items from Step 4 carry forward unchanged (agreed → auto-fixable).

If zero disagreements remain after cross-validation, skip Step 6 and run Step 8 auto-apply, then Step 7 (post-apply presentation).

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

Present findings in priority order. Step 8 auto-apply has already run for the round's auto-fixable items by the time Step 7 fires; this section presents what was applied and what still needs the user's decision.

### 1. Needs-Decision (blocking, batched)

Only shown if cross-validation or evidence-based resolution did not settle the issue, or if a code-verified finding is pending bilateral consensus. Skip the entire subsection if zero needs-decision items.

```
## Needs Decision

[1] [high] [security] src/auth.ts:42
    Claude: SQL injection via string concatenation. Fix: use parameterized query.
    Codex: Not exploitable -- input is validated upstream at line 30.
    Research: [summary of what evidence was found and why it was inconclusive]
    -> Please decide: fix or dismiss?
```

Wait once for the user's batched response covering all needs-decision items. Verbs: `fix`, `dismiss`, `fix with changes: <edits>`, `stop`. Read `internals.md#needs-decision` for parsing rules and verb precedence (`stop` overrides everything).

**Resolution order** (after parsing the batched reply):

1. **`stop` precedence.** If ANY item is `stop`, exit the run immediately — do not drop, do not apply, do not re-review. Emit summary with `Exit reason: user stopped` and list pending items. Read `internals.md#needs-decision`.
2. Drop dismissed items + their deferred-overlap auto-fixes (Step 8 step 5).
3. Apply remaining `fix` / `fix with changes` items + their deferred overlaps as a single post-Step-7 pass. Run the standard Step 8 mechanics in order on this pass: step 2 (capture pass journal — required so `revert` has a rollback target), step 3 (dirty-tree gate on any file not yet gate-cleared), step 4 (pre-apply re-probe), step 5 (overlap detection — already done; deferred items inherit it), step 6 (apply), step 7 (partial-apply failure handling). Same rules as the pre-Step-7 pass.
4. Record dismissed items under "Dismissed (user decision)".
5. Otherwise (no `stop`): proceed to re-review.

### 2. Applied This Round (informational, non-blocking)

Lists fixes that have already been applied this round under the auto-apply eligibility rules. Bucket includes `agreed` + `cross-validated` items only. Mutually exclusive with "Resolved by Evidence" — evidence-resolved fixes appear in that section instead.

```
## Applied This Round

[3] [high] [correctness] src/handler.ts:87 -- Missing null check (both agree) — added guard clause before accessing .data property
[4] [medium] [test-coverage] src/auth.ts -- No tests for login flow (Claude found, Codex confirmed) — added unit tests for success and failure paths
```

### 3. Resolved by Evidence (informational, non-blocking)

Items where Step 6 evidence research settled a disagreement. Bucket carries `evidence-resolved` provenance only.

```
## Resolved by Evidence

[5] [critical] [technical] spec:40 -- manifest path correctness
    Claude claimed: path points to wrong module (launcher needed)
    Codex claimed: path is correct (unityLibrary has activity declarations)
    Evidence: Unity API docs confirm path = unityLibrary module. Codex is correct.
    -> Applied Codex's recommendation. No user action needed.
```

### 4. Informational (non-blocking)

```
## Informational

[6] [minor] [maintainability] src/utils.ts:12 -- Variable name could be more descriptive
```

## Step 8: Apply Fixes and Re-Review

Auto-fixable items apply at the end of the resolution pipeline, before Step 7 presents results. Needs-decision items, if any, apply after the user's batched response per Step 7 step 1's resolution order. Step 8 has two invocation points per round — pre-Step-7 (auto-fixable) and post-Step-7 (needs-decision-resolved + deferred overlaps) — and both run through the same mechanics below.

**Auto-apply mechanics.** Read `internals.md#auto-apply-mechanics` for the full algorithm.

1. **Lazy run-level baseline (per path).** Before first edit to a path within the run: capture `existedAtFirstTouch`, `wasUntrackedAtFirstTouch` (`git status --porcelain` shows `?? `), `hadPreExistingChanges` (`git diff --quiet HEAD` exit code), `snapshotContents` (full contents, or `null` if absent, or `"deferred"` for large files with `snapshotPathOnDisk` set). Read `internals.md#baseline-map-schema` for the full schema and rollback partitions.
2. **Pass journal (per apply pass).** At the start of each apply pass, capture `{path, contentsAtPassStart}` for every file the pass plans to edit. Used by partial-apply `revert` (read `internals.md#partial-apply-state`).
3. **Dirty-tree gate (per never-gate-cleared file).** For each apply pass, compute `delta` = files this pass will edit AND not yet gate-cleared in this run. Run `${CLAUDE_PLUGIN_ROOT}/scripts/cross-review/dirty-tree-probe.{sh,ps1} <delta-files>`. If any JSON line has `dirty=true`, `untracked=true`, or `wouldCreate=true`, prompt the user with the dirty-tree gate response enum (read `internals.md#dirty-tree-gate-response`). On `proceed`, mark every file in `delta` as gate-cleared for the rest of the run.
4. **Pre-apply re-probe.** Re-run dirty-tree-probe on the same `delta` immediately before the apply pass. If state changed since the gate fired, re-present the gate.
5. **Overlap detection.** Read `internals.md#overlap-footprint` for the rules. Overlap with a needs-decision item → defer to the post-Step-7 pass.
6. **Apply (with provenance).** Use Skill Discovery / subagent dispatch (existing). Update baseline map on first touch. Tag items by provenance (`agreed` | `cross-validated` | `evidence-resolved`).
7. **Partial-apply failure.** First failure stops the pass. Read `internals.md#partial-apply-state` for the state machine; surface the prompt and resolve. (`revert` operates on the pass journal — earlier rounds' fixes are NOT touched.)
8. **No commits.** Working-tree only.

**Round bookkeeping.** Increment `ROUND` at the end of each round, BEFORE the next parallel-review dispatch (the existing `Increment \`ROUND\`` instruction in this Step moves there). Combined with `ROUND = 1` init in Step 2, the progress message "Round N complete" always emits a non-zero N.

**Progress message.** After auto-apply, emit one line per the branch table. Read `internals.md#progress-update-branch-table` for the conditions and exact wording. Suppress when X = Y = 0 (Step 9 stable-round handles it).

**`--max-rounds 0` decline path.** Step 2's argument validation already rejects `--max-rounds < 1` at parse time. The dirty-tree decline path (gate response `stop`) is the only "exit without applying" route at runtime.

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

Exit when any of these is met:
- **All clean** — zero findings of any kind.
- **Stable round** — zero auto-fixable AND zero needs-decision (informational allowed).
- **Max rounds reached** — `ROUND` = `MAX_ROUNDS` and round produced ≥1 finding.
- **User stopped** — user replied `stop` to a needs-decision or partial-apply prompt.
- **Dirty-tree decline** — user replied `stop` to the dirty-tree gate; no fixes applied; baseline map discarded.

Present final state:

```
## Cross-Review Summary

Rounds completed: N (M included cross-validation)
Exit reason: <all clean | stable round | max rounds reached | user stopped | dirty-tree decline>

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

### Skipped (apply failed)
- [N] [severity] [category] file:line -- description (apply failed: <error>)
```

## Rollback (if needed)

Auto-applied edits are in the working tree (uncommitted). The baseline map partitions touched files into four subsets — apply the matching restore command per subset. Avoid bare `git restore .` — it discards every uncommitted change in the tree.

- **Tracked, no pre-existing changes:** `git restore -- <file>` (safe; reverts only cross-review's edit).
- **Tracked, pre-existing changes:** `git restore --patch -- <file>` (interactive; pick the cross-review hunks). For non-interactive contexts: `git stash`, `git checkout HEAD -- <file>`, then re-apply your prior work from the stash.
- **Pre-existing untracked (existedAtFirstTouch=true, wasUntrackedAtFirstTouch=true):** restore from the baseline `snapshotContents` (or copy from `snapshotPathOnDisk` for size-guard-deferred entries) — `git restore` does NOT work on untracked files. The summary embeds a per-file restore command (e.g., `cp <snapshotPathOnDisk> <file>` or a heredoc with the inline contents).
- **Newly created (existedAtFirstTouch=false):** delete (`rm <file>` / `Remove-Item <file>`); `git restore` cannot revert files absent at HEAD.

(The summary lists each subset with the actual file paths from the baseline map. For files where `snapshotContents="deferred"`, the baseline copy lives in the per-run scratch directory — see `internals.md#baseline-map-schema`.)

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

- **Do NOT forget to retrieve Codex background job output before triage.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/cross-review/wait-for-codex.{sh,ps1}` after dispatch — terminal phases are `done` / `failed` / `cancelled` (NOT `completed`). The Monitor tool watches log lines, not phase transitions; it cannot replace the helper script.

- **Do NOT cancel a task after tool calls go quiet** — it is generating its response (10-30 min). See "Response-Generation Awareness" in prerequisites.md.

- **Do NOT use PID-based liveness checks on Windows** — use `/codex:status` (Skill tool). See "Task Health Verification" in prerequisites.md.

- **Do NOT proceed with Claude-only findings if Codex fails during initial review (Step 3).** Both models are required for the initial review. Try Direct CLI Fallback before stopping. For cross-validation (Step 5), graceful degradation with code-level verification is acceptable.

- **Do NOT skip triage and apply both reviews directly.** The two reviews may contain contradictions. Triage reconciles them and identifies disagreements.

- **Do NOT combine `--base` with a prompt in `/codex:review`.** They are mutually exclusive in Codex CLI. Use `--base` alone for code review; use `/codex:rescue` with a prompt for non-code.

- **Do NOT review same issues each round.** Focus on deltas/changed files for Claude agents. Codex code review is branch-scoped by design but previously-fixed issues should not reappear.

- **Do NOT block on auto-fixable items.** Apply them at the end of the resolution pipeline (after Step 6). User involvement is limited to needs-decision items, the one-time-per-delta dirty-tree gate, and the partial-apply failure prompt.

- **Do NOT use `/codex:adversarial-review` for this workflow.** It produces independent findings without cross-mapping. Use `/codex:review` for code and `/codex:rescue` with structured prompts for non-code.

- **Do NOT escalate disagreements to the user before cross-validation and research.** The usage pattern is: triage → cross-validate → research evidence → only then ask the user. Premature escalation wastes the user's time on questions that documentation can answer.

- **Do NOT reuse stale preflight state for Codex dispatch.** The runtime endpoint (named pipe) can change between Step 1 preflight and Step 3 dispatch. Always re-run `/codex:setup` immediately before dispatching Codex. A 5-second setup call prevents 10+ minutes of debugging zombie tasks.

- **Do NOT wait 30+ minutes for a silent task hoping it's "generating."** The flat threshold is 15 minutes of no new tool calls — past that, escalate to Direct CLI Fallback immediately. Session data shows tasks silent for 10-15 minutes are almost always dead, not generating.

- **Do NOT give up when companion retries fail.** Always try Direct CLI Fallback (`codex exec`) before stopping. The companion has a known reliability issue on Windows (pipe crashes, no response timeout). Direct CLI creates fresh connections and consistently succeeds when the companion doesn't.
