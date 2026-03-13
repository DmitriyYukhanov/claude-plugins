# Unified Review Mechanics: collaborative-loop + cross-review

## Problem Statement

Three issues identified from a collaborative-loop session:

1. **Cleanup bug:** `cleanup-loop.sh` only removes `loop-drive-round-*.md` and `loop-review-round-*.md`. Orchestrator-created scratch files (e.g., `round1-diff.txt`) are left behind.

2. **Review depth gap:** Cross-review spawns 3-5 specialized Claude agents in parallel (security, performance, test-coverage, etc.) + Codex. Collaborative-loop uses a single general-purpose Claude subagent. Much less review coverage.

3. **Prompt duplication:** Both plugins maintain nearly identical review prompts that have diverged in structure, creating drift risk and maintenance burden.

## Design

### 1. Cleanup Fix

**File:** `plugins/collaborative-loop/scripts/cleanup-loop.sh`

Replace specific glob pattern removal with a wildcard that removes all files in the output directory:

```bash
# Before (broken — misses orchestrator scratch files)
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 \( -name 'loop-drive-round-*.md' -o -name 'loop-review-round-*.md' \) 2>/dev/null | wc -l)
rm -f "$OUTPUT_DIR"/loop-drive-round-*.md \
      "$OUTPUT_DIR"/loop-review-round-*.md

# After (removes everything in the transient workspace)
FILE_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
rm -f "$OUTPUT_DIR"/*
```

Both the `FILE_COUNT` line and the `rm` line must be updated — the count should reflect all files being removed, not just the two specific patterns.

The output directory (`docs/plans/collaborative-loop/`) is a transient workspace. Target artifact files live elsewhere — nothing in the output dir should persist.

**SKILL.md addition** to Common Mistakes:
- "Creating scratch files in the output directory — only `loop-drive-round-N.md` and `loop-review-round-N.md` should exist there. The cleanup script removes all files in the directory."

### 2. Shared Review Prompts

**New directory:** `shared/prompts/review/`

Create 6 canonical prompt files by merging content from both plugins:

| Canonical File | Source | Notes |
|---------------|--------|-------|
| `review-base.txt` | Merge of cross-review's `codex-base.txt` + collab-loop's `codex-review-base.txt` | Combine cross-review's agent-spawning + severity-first structure with collab-loop's DRIVER/REVIEWER framing and delta-review instruction |
| `review-code.txt` | Collab-loop's `codex-review-code.txt` | Cross-review lacks a code-specific prompt |
| `review-plan.txt` | Cross-review's `codex-plan.txt` | Content identical across both |
| `review-architecture.txt` | Cross-review's `codex-architecture.txt` | Content identical across both |
| `review-design.txt` | Cross-review's `codex-design.txt` | Content identical across both |
| `verdict-format.txt` | Collab-loop's `verdict-format.txt` | Used by collab-loop for structured verdicts |

**Merged `review-base.txt` content** (combines both versions):

```
You are a senior engineer reviewing work produced by another AI model.
Your role is REVIEWER — evaluate quality, find issues, deliver a structured verdict.
Do not make changes yourself. Do not ask for clarification — make reasonable assumptions.

Before any tool call, identify ALL files you need to read.
Batch-read them in a single parallel request — never read sequentially
when parallelization is feasible.

Skip preamble, acknowledgments, and status updates.
Be terse and direct — optimize for information density.
Lead with the most severe findings first.

Spawn one agent per review focus area, wait for all of them, and
produce a single consolidated review.

Review focus areas:
1. Correctness — bugs, logic errors, off-by-one, race conditions, wrong behavior
2. Security — auth, injection, validation, secrets, data exposure
3. Performance — bottlenecks, N+1 queries, memory, scalability
4. Completeness — missing edge cases, unhandled errors, gaps in implementation
5. Maintainability — patterns, readability, coupling, naming
6. Consistency — adherence to conventions in surrounding code

Quality criteria:
- Internal consistency: no contradictions between sections or components
- Conventions: flag deviations from patterns established in surrounding work
- Risky shortcuts: speculative changes, untested assumptions, missing rationale
- Completeness: identify gaps where expected content or handling is absent

IMPORTANT: You are reviewing the DRIVER's output. Focus on whether their changes
are correct, complete, and improve the codebase. If reviewing a subsequent round,
only evaluate changes made since the last review — do not re-report fixed issues.

Structure findings GLOBALLY by severity, not grouped by area:

### Critical Issues (blocks progress)
- [category] File:line — description (for code; use section/heading for docs)

### High Issues (causes bugs or architectural problems)
- [category] File:line — description

### Medium Issues (quality, consistency)
- [category] File:line — description

### Minor Issues (nice to have)
- [category] File:line — description
```

**Symlink structure:**

```
plugins/cross-review/prompts/
  codex-base.txt           → ../../../shared/prompts/review/review-base.txt
  codex-plan.txt           → ../../../shared/prompts/review/review-plan.txt
  codex-architecture.txt   → ../../../shared/prompts/review/review-architecture.txt
  codex-design.txt         → ../../../shared/prompts/review/review-design.txt

plugins/collaborative-loop/prompts/
  codex-review-base.txt    → ../../../shared/prompts/review/review-base.txt
  codex-review-code.txt    → ../../../shared/prompts/review/review-code.txt
  codex-review-plan.txt    → ../../../shared/prompts/review/review-plan.txt
  codex-review-architecture.txt → ../../../shared/prompts/review/review-architecture.txt
  codex-review-design.txt  → ../../../shared/prompts/review/review-design.txt
  verdict-format.txt       → ../../../shared/prompts/review/verdict-format.txt
```

Both plugins keep existing filenames so their `run-codex-review.sh` scripts require no changes.

### 3. Claude Agent Team for Collaborative-Loop Review

**File:** `plugins/collaborative-loop/skills/collaborative-loop/SKILL.md` — Step 4 "When Claude is Reviewer"

Replace single subagent with specialized agent team (matching cross-review's approach):

**Always spawn (core reviewers):**
1. `security-reviewer` — auth, injection, validation, secrets, data exposure
2. `performance-reviewer` — bottlenecks, N+1 queries, memory, scalability
3. `test-reviewer` — test coverage gaps, edge cases, flaky test risks

**Conditionally spawn (up to 5 total):**
4. `architect-reviewer` — if artifact involves multi-component or structural changes
5. `requirements-reviewer` — if artifact type is plan or spec

All agents spawn with `run_in_background: true` (parallel within the team).

**Agent prompt template:**
```
You are a {focus area} reviewer in a collaborative loop.
This is Round N.

## Task Context
{original task description}

## Driver's Changes
{content of loop-drive-round-N.md or git diff summary}

## Target Files
{file list}

{If Round N > 1:}
## Previous Review (Round N-1)
{content of loop-review-round-{N-1}.md}
Only evaluate NEW changes. Do not re-report issues that were fixed.
{/If}

Focus exclusively on {focus area}: {focus area description}

Structure findings as:
### Critical Issues (blocks progress)
### High Issues (causes bugs or architectural problems)
### Medium Issues (quality, consistency)
### Minor Issues (nice to have)

Be specific: reference file paths, line numbers, concrete examples.
Every finding MUST have a suggested fix.
```

**Consolidation rules:**
After all agents complete, consolidate into a single `loop-review-round-N.md`:

1. Collect all findings from all agents
2. Deduplicate: if two agents flag the same file:line with the same issue, keep one
3. When agents disagree on severity for the same issue, use the higher severity
4. Format as verdict (STATUS + findings + summary) per `verdict-format.txt`
5. Determine STATUS:
   - No findings → `APPROVED`
   - Only minor findings → `MINOR_ISSUES`
   - Any medium+ finding → `CHANGES_REQUESTED`

**When Codex is reviewer:** No change — stays as single background `run-codex-review.sh` process.

### 4. Version Bumps

| Plugin | Current | New | Reason |
|--------|---------|-----|--------|
| collaborative-loop | 1.1.1 | 1.2.0 | MINOR — new feature (agent team review) + bug fix (cleanup) |
| cross-review | 1.6.1 | 1.6.2 | PATCH — prompts moved to symlinks, no behavioral change |

Both `plugin.json`, `.claude-plugin/plugin.json`, and `.claude-plugin/marketplace.json` must be updated.

### 5. CLAUDE.md Update

Rename "Current shared scripts" to "Current shared resources" and add:

```
- `shared/prompts/review/` — Canonical review prompts (base, code, plan, architecture, design, verdict-format) used by: collaborative-loop, cross-review
```

### 6. Collaborative-loop Drive Prompts

The drive prompts (`codex-drive-base.txt`, `codex-drive-code.txt`, etc.) stay in `plugins/collaborative-loop/prompts/` — only collaborative-loop uses them. They are NOT shared since cross-review does not drive.

## Files Changed

| File | Action |
|------|--------|
| `shared/prompts/review/review-base.txt` | CREATE — merged canonical prompt |
| `shared/prompts/review/review-code.txt` | CREATE — from collab-loop |
| `shared/prompts/review/review-plan.txt` | CREATE — from cross-review |
| `shared/prompts/review/review-architecture.txt` | CREATE — from cross-review |
| `shared/prompts/review/review-design.txt` | CREATE — from cross-review |
| `shared/prompts/review/verdict-format.txt` | CREATE — from collab-loop |
| `plugins/cross-review/prompts/codex-base.txt` | REPLACE with symlink |
| `plugins/cross-review/prompts/codex-plan.txt` | REPLACE with symlink |
| `plugins/cross-review/prompts/codex-architecture.txt` | REPLACE with symlink |
| `plugins/cross-review/prompts/codex-design.txt` | REPLACE with symlink |
| `plugins/collaborative-loop/prompts/codex-review-base.txt` | REPLACE with symlink |
| `plugins/collaborative-loop/prompts/codex-review-code.txt` | REPLACE with symlink |
| `plugins/collaborative-loop/prompts/codex-review-plan.txt` | REPLACE with symlink |
| `plugins/collaborative-loop/prompts/codex-review-architecture.txt` | REPLACE with symlink |
| `plugins/collaborative-loop/prompts/codex-review-design.txt` | REPLACE with symlink |
| `plugins/collaborative-loop/prompts/verdict-format.txt` | REPLACE with symlink |
| `plugins/collaborative-loop/scripts/cleanup-loop.sh` | EDIT — wildcard cleanup |
| `plugins/collaborative-loop/skills/collaborative-loop/SKILL.md` | EDIT — agent team review + cleanup instruction |
| `plugins/collaborative-loop/plugin.json` | EDIT — 1.1.1 → 1.2.0 |
| `plugins/collaborative-loop/.claude-plugin/plugin.json` | EDIT — 1.1.1 → 1.2.0 |
| `plugins/cross-review/plugin.json` | EDIT — 1.6.1 → 1.6.2 |
| `plugins/cross-review/.claude-plugin/plugin.json` | EDIT — 1.6.1 → 1.6.2 |
| `.claude-plugin/marketplace.json` | EDIT — both version bumps |
| `CLAUDE.md` | EDIT — shared resources documentation |

## Out of Scope

- Cross-review SKILL.md changes (not needed — symlinks are transparent)
- Cross-review `run-codex-review.sh` changes (reads prompts by filename, symlinks work)
- Collaborative-loop `run-codex-review.sh` changes (same reason)
- Collaborative-loop drive prompts (not shared — cross-review doesn't drive)
