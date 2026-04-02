---
name: cross-review
model: opus
description: Parallel dual review between Claude and Codex. Both models review independently, findings are cross-validated and triaged, disagreements surfaced for user decision. Use for reviewing existing work with independent perspectives.
---

# Cross-Review: Parallel Dual Review

## Overview

Parallel review workflow between Claude and Codex CLI. Both models review the same artifact **simultaneously and independently**, findings are cross-validated and triaged into auto-fixable / needs-decision / informational buckets, and only approved fixes are applied. Disagreements are always surfaced for user mediation. Repeats until clean or max rounds reached.

**Core principle:** Two independent perspectives are stronger than one. Neither model sees the other's review until triage. Disagreements go to the user, never resolved silently.

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

## Step 3: Parallel Review

**CRITICAL: Launch Claude agents and Codex simultaneously. Do NOT wait for one before starting the other.** Both review independently; cross-validation happens in Step 4.

### Claude Side (Background Agents)

Spawn focused review agents using the Agent tool. Each agent reviews through its domain lens using focus areas from `${CLAUDE_PLUGIN_ROOT}/skills/shared/review-domains.md`.

**Domain agents:**

| Agent | Focus |
|-------|-------|
| `security-reviewer` | Auth, injection, validation, secrets, data exposure |
| `performance-reviewer` | Bottlenecks, N+1 queries, memory leaks, scalability |
| `correctness-reviewer` | Logic errors, edge cases, error handling, type safety |
| `test-coverage-reviewer` | Test gaps, missing edge cases, flaky test risks |
| `maintainability-reviewer` | Code clarity, patterns, coupling, naming, duplication |

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

**For code artifacts:**
- Invoke `/codex:review --base <ref> --background` via the Skill tool
- `/codex:review` reviews the entire branch diff, not specific files -- this is by design
- Do NOT combine `--base` with a prompt -- they are mutually exclusive in Codex CLI

**For non-code artifacts:**
- Invoke `/codex:rescue --background` via the Skill tool with a review prompt
- Compose the prompt using `gpt-5-4-prompting` patterns with XML-tagged blocks
- Include focus areas from `${CLAUDE_PLUGIN_ROOT}/skills/shared/review-domains.md` for the detected artifact type
- Include `${CLAUDE_PLUGIN_ROOT}/skills/shared/verdict-format.md` as `<structured_output_contract>`
- Non-code prompts can be scoped to specific files by including them in the prompt

**Poll and retrieve:**
- Poll job status via `/codex:status` (Skill tool)
- Retrieve output via `/codex:result` (Skill tool) when complete

### Codex Job Failure Handling

If Codex background job fails (auth expired, CLI error, timeout):

1. Report the failure to the user with the specific error
2. Proceed to triage with Claude-only findings but **warn that cross-validation is degraded**
3. Mark all Claude findings as single-source (no cross-validation possible)
4. If user wants full cross-review, they should fix Codex and re-run

This differs from collaborative-loop, which ABORTs entirely on Codex failure. Cross-review can degrade gracefully because Claude's findings still have value as independent review, even without cross-validation.

## Step 4: Triage Findings

Claude cross-validates findings from both sides. Compare the two independent reviews to find agreements, unique findings, and disagreements.

### Classification Rules

| Situation | Classification |
|-----------|---------------|
| Both agree (same issue, same or similar fix) | **auto-fixable** (if fix is unambiguous) |
| Only one side found it, Claude evaluates as real | **auto-fixable** |
| Only one side found it, uncertain | **needs-decision** |
| Disagreement (severity, fix approach, or validity) | **needs-decision** |
| Both rate as minor + no concrete action | **informational** |

### Cross-Validation Process

For each unique finding across both reviews:

1. **Match findings** -- identify when both reviewers found the same issue (even if worded differently or categorized under different domains)
2. **Evaluate unique findings** -- when only one reviewer found an issue, Claude independently assesses whether it is genuine
3. **Detect disagreements** -- flag cases where reviewers conflict on severity, fix approach, or whether something is an issue at all
4. **Classify** -- apply the classification table above

Hold triage results in conversation context.

## Step 5: Present Triage to User

Present findings in priority order:

### 1. Needs-Decision Items (First)

Show these first -- they block progress until the user decides:

```
## Needs Decision

[1] [high] [security] src/auth.ts:42
    Claude: SQL injection via string concatenation. Fix: use parameterized query.
    Codex: Not exploitable -- input is validated upstream at line 30.
    -> Please decide: fix or dismiss?

[2] [medium] [performance] lib/cache.ts:15
    Claude: Medium severity -- cache grows unbounded.
    Codex: High severity -- will cause OOM in production.
    -> Please decide on severity and fix approach.
```

Wait for user decisions on each item before proceeding.

### 2. Auto-Fixable Items (Second)

List for confirmation:

```
## Auto-Fixable (confirm to proceed)

[3] [high] [correctness] src/handler.ts:87 -- Missing null check (both reviewers agree)
    Fix: Add guard clause before accessing .data property

[4] [medium] [test-coverage] src/auth.ts -- No tests for login flow (Claude found, confirmed valid)
    Fix: Add unit tests for success and failure paths
```

### 3. Informational Items (Last)

Show as FYI, no action needed:

```
## Informational

[5] [minor] [maintainability] src/utils.ts:12 -- Variable name could be more descriptive
```

## Step 6: Apply Fixes and Re-Review

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

After fixes are applied, go back to Step 3 with these adjustments:

- **Claude side:** Scope agents to only changed files from this round (use `git diff` to identify delta)
- **Codex side for code:** `/codex:review` reviews the full branch diff (branch-scoped) -- it will see all branch changes, not just this round's fixes
- **Codex side for non-code:** `/codex:rescue` prompt can be scoped to specific changed files

Increment `ROUND` and repeat until exit conditions are met.

**File scoping constraint:** `/codex:review` and `/codex:adversarial-review` are branch-scoped. Codex will review all branch changes in re-reviews, not just the current round's files. Previously-fixed issues should not reappear, but Codex may surface new findings in unchanged code.

## Step 7: Exit and Summary

Exit when any of these conditions is met:
- All clean (no findings in latest round)
- Max rounds reached (default: 3)
- Unresolvable needs-decision items remain after user mediation

Present final state:

```
## Cross-Review Summary

Rounds completed: N
Exit reason: <all clean | max rounds reached | user stopped>

### Issues Found: X
### Issues Fixed: Y
### Issues Remaining: Z

### Resolved
- [1] [severity] [category] file:line -- fixed in round N

### Dismissed (user decision)
- [2] [severity] [category] file:line -- user dismissed: <reason>

### Remaining (if max rounds reached)
- [3] [severity] [category] file:line -- description
```

## Key Differences from Collaborative Loop

| Aspect | Cross-Review | Collaborative Loop |
|--------|-------------|-------------------|
| Execution model | **Parallel** -- both review at once | **Sequential** -- produce, validate, act |
| Primary goal | **Finding issues** in existing work | **Driving changes** iteratively |
| Disagreement handling | **User mediation** via triage | Automated bilateral consensus gate |
| Codex failure | Degrades gracefully (Claude-only) | ABORTs entirely |
| Best for | **Review of existing work** | **Iterative improvement** |
| Agent structure | Domain-specific reviewers | Single analysis pass |

Use cross-review when you want independent perspectives on existing work. Use collaborative-loop when you want iterative improvement driven by bilateral consensus.

## Common Mistakes

- **Do NOT resolve disagreements silently.** Any conflict between Claude and Codex findings MUST be surfaced to the user. Never auto-resolve in favor of either model.

- **Do NOT run Claude agents to completion before launching Codex.** Both must start simultaneously. Launch Codex first (Skill tool), then spawn Claude agents in the same turn.

- **Do NOT forget to poll `/codex:status` for background jobs.** Codex runs in the background -- you must check status and retrieve results before triage.

- **Do NOT skip triage and apply both reviews directly.** The two reviews may contain contradictions. Triage reconciles them and identifies disagreements.

- **Do NOT combine `--base` with a prompt in `/codex:review`.** They are mutually exclusive in Codex CLI. Use `--base` alone for code review; use `/codex:rescue` with a prompt for non-code.

- **Do NOT review same issues each round.** Focus on deltas/changed files for Claude agents. Codex code review is branch-scoped by design but previously-fixed issues should not reappear.

- **Do NOT skip user confirmation for auto-fixable items.** Present the triage and wait for user to confirm before applying fixes.

- **Do NOT use `/codex:adversarial-review` for this workflow.** It produces independent findings without cross-mapping. Use `/codex:review` for code and `/codex:rescue` with structured prompts for non-code.
