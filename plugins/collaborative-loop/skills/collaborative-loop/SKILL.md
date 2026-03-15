---
name: collaborative-loop
model: opus
description: This skill should be used when the user wants sequential AI-to-AI collaboration where one model drives and another validates iteratively. Applies when the user wants to "collaborate with codex", "have codex review my changes", "drive and review loop", "iterate with another model", "collaborative loop", "sequential review", "AI pair programming", or wants one model to build on another's feedback in a back-and-forth cycle. Orchestrates produce-validate-act cycles between Claude and Codex CLI until consensus (APPROVED verdict) or escalation.
---

# Collaborative Loop: Sequential Claude x Codex CLI

## Overview

Pair-programming loop between Claude and Codex CLI. The driver PRODUCES an artifact (analysis, review, code, plan) → the reviewer VALIDATES the driver's output before any action is taken → the driver ACTS only on validated findings → the reviewer evaluates the action → repeat until clean.

**Key principle: the driver never acts on its own unvalidated output.** Every analysis is validated by the other model before implementation. This prevents false-positive fixes and wasted iterations.

## Prerequisites

- Codex CLI installed: `npm install -g @openai/codex`
- Codex authenticated: `codex auth login`
- Config at `~/.codex/config.toml` with model and approval mode:

```toml
# ~/.codex/config.toml (example — adjust model to your available version)
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
```

### Platform Notes

- **MINGW/MSYS (Git Bash on Windows):** Codex runs via WSL. The preflight check verifies WSL is available and codex is installed inside it. All codex invocations are transparently routed through `wsl --cd <path> -- codex`.
- **WSL:** Codex runs directly. Just needs `codex` in PATH.
- **Linux/macOS:** Codex runs directly.

## Checklist

Execute each of these steps sequentially, completing one before moving to the next:

1. **Preflight check** — verify codex is reachable before any work begins; ABORT if not
2. **Parse arguments and detect context** — set DRIVER/REVIEWER roles, detect artifact type, identify target files
3. **Driver PRODUCES initial artifact** — analysis, review, draft, or code (NO fixes, NO implementation of own findings)
4. **Reviewer VALIDATES driver's output** — confirm/reject each finding, add missed findings
5. **Merge validated findings** — combine confirmed + new findings; check if action is needed
6. **Driver ACTS on validated findings only** — implement fixes or refinements
7. **Reviewer evaluates action with structured verdict** — standard review of what the driver changed
8. **Parse verdict and check exit conditions** — APPROVED? MINOR_ISSUES? stall? max rounds?
9. **Mediator escalation (if stalled)** — present stalled items, get user guidance
10. **Present results summary** — final state, resolved issues, remaining items
11. **Clean up intermediate files** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" docs/plans/collaborative-loop` (mandatory)

## Core Workflow

```dot
digraph collaborative_loop {
    rankdir=TB;
    node [shape=box];

    "Preflight: check-codex.sh" -> "Parse args + detect context" [label="OK"];
    "Preflight: check-codex.sh" -> "ABORT: codex not reachable" [label="FAIL"];

    "Parse args + detect context" -> "DRIVER: produce artifact (NO action)";

    subgraph cluster_initial {
        label="Initial Phase (once)";
        style=dashed;
        "DRIVER: produce artifact (NO action)" -> "Save loop-analysis.md";
        "Save loop-analysis.md" -> "REVIEWER: validate driver output";
        "REVIEWER: validate driver output" -> "Save loop-validation.md";
        "Save loop-validation.md" -> "Merge: confirmed + new findings";
    }

    "Merge: confirmed + new findings" -> "No actionable findings?" [label=""];
    "No actionable findings?" -> "Present results (clean)" [label="yes"];
    "No actionable findings?" -> "DRIVER: act on validated findings" [label="no"];

    subgraph cluster_fix_loop {
        label="Fix-Review Loop (repeats)";
        style=dashed;
        "DRIVER: act on validated findings" -> "Save loop-drive-round-N.md";
        "Save loop-drive-round-N.md" -> "REVIEWER: evaluate action + verdict";
        "REVIEWER: evaluate action + verdict" -> "Save loop-review-round-N.md";
    }

    "Save loop-review-round-N.md" -> "Parse verdict (STATUS line)";
    "Parse verdict (STATUS line)" -> "Present results" [label="APPROVED"];
    "Parse verdict (STATUS line)" -> "Log minor → Present results" [label="MINOR_ISSUES"];
    "Parse verdict (STATUS line)" -> "Check exit conditions" [label="CHANGES_REQUESTED"];

    "Check exit conditions" -> "Mediator escalation" [label="stall detected"];
    "Check exit conditions" -> "Present results" [label="max rounds"];
    "Check exit conditions" -> "Feed review → DRIVER (Step 6)" [label="continue"];

    "Feed review → DRIVER (Step 6)" -> "DRIVER: act on validated findings";
    "Mediator escalation" -> "User decides";
    "User decides" -> "Feed guidance → DRIVER (Step 6)" [label="continue"];
    "User decides" -> "Present results" [label="abort"];
    "Feed guidance → DRIVER (Step 6)" -> "DRIVER: act on validated findings";

    "Present results (clean)" -> "cleanup-loop.sh";
    "Log minor → Present results" -> "cleanup-loop.sh";
    "Present results" -> "cleanup-loop.sh";
}
```

## Step 1: Preflight Check

**Run this BEFORE any other work.** If the check fails, ABORT immediately — do not parse arguments, detect context, or start any loop work.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-codex.sh"
```

The script detects the environment and validates codex reachability:

| Environment | Detection | How codex runs |
|-------------|-----------|----------------|
| **MINGW/MSYS** | `uname -s` starts with `MINGW` or `MSYS` | Via WSL: `wsl --cd <wsl_path> -- codex` |
| **WSL** | `WSL_DISTRO_NAME` is set or `/proc/version` contains "Microsoft" | Directly: `codex` |
| **Native** | Everything else (Linux, macOS) | Directly: `codex` |

**On success:** prints `OK: ...` to stderr and `CODEX_ENV=<env>` to stdout. Proceed to Step 2.
**On failure:** prints `FAIL: ...` with install instructions. **STOP HERE** — tell the user what's missing and how to fix it. Do not continue.

The shell scripts (`run-codex-drive.sh`, `run-codex-review.sh`, `run-codex-validate.sh`) source this script internally and use `codex_run` instead of bare `codex`, so WSL path translation is handled transparently.

## Step 2: Parse Arguments and Detect Context

### Argument Parsing

Parse the user's invocation. Defaults in parentheses:

| Argument | Default | Description |
|----------|---------|-------------|
| `--driver` | `claude` | Who drives: `claude` or `codex` |
| `--max-rounds` | `5` | Maximum fix-review iteration rounds |
| `--task` | (from user message; inferred from branch name + commits if bare) | Task description for the driver |
| target files | (current branch diff) | Specific files to work on |

### Default Mode (No Arguments) — MANDATORY

**When invoked without arguments, you MUST apply all defaults from the table above and start immediately. NEVER ask clarifying questions — infer and proceed.** Use ALL files from the branch diff regardless of count. Infer the task from branch name and commit messages (e.g., branch `story/151-parser-progress` → "Review and improve the parser progress calculation changes"; generic branch like `main` → "Review and improve the changed files").

If no target files specified:
1. Detect base branch: check for `main`, then `master`
2. Run `git diff <base>...HEAD --name-only` to find changed files
3. If no changes found (zero files in diff), this is the ONLY case where you may ask the user what to work on

### Artifact Type Detection

Examine the target file(s) to classify:

| Signal | Artifact Type |
|--------|---------------|
| `*-plan*.md`, `*implementation-plan*`, `*-tasks*` | **plan** |
| `*-design*.md`, `*-architecture*`, `*-spec*` | **architecture** |
| `*.cs`, `*.ts`, `*.py`, `*.js`, `*.go`, `*.rs`, `*.java` (source files) | **code** |
| Other `*.md` in `docs/` or `plans/` | **design** |

Mixed artifacts (e.g., code + docs) → prioritize **code**.

Set `ARTIFACT_TYPE`, `DRIVER` (claude|codex), `REVIEWER` (the other), `MAX_ROUNDS`, and `TARGET_FILES`.

### Initialize State

```
ROUND = 0  (fix-review rounds start at 1; initial phase is round 0)
STALL_COUNT = 0
PREV_FINDINGS = []  (empty — tracked internally, not persisted to files)
```

Create output directory:
```bash
mkdir -p docs/plans/collaborative-loop
```

## Step 3: Driver PRODUCES Initial Artifact (NO Action)

**CRITICAL: The driver produces an analysis, review, or draft — but does NOT implement fixes or act on its own findings.** The output is a deliverable for the reviewer to validate, not a set of changes to the codebase.

### When Claude is Driver

**Skill Discovery:**
Search available skills for the best match based on `ARTIFACT_TYPE`:

| Artifact Type | Search Keywords |
|---------------|-----------------|
| **plan** | `writing-plans`, `executing-plans`, `plan` |
| **architecture** | `architect`, `architecture`, `brainstorming`, `design` |
| **code** | `coder`, `code-review`, `implementation`, `feature-dev` (prefer project-specific) |
| **design** | `brainstorming`, `writing-plans`, `design` |

Priority: project-specific skills first → general-purpose skills second → direct analysis if no skill found.

**For review tasks (code with existing changes):**
Invoke the discovered skill or perform the review directly. The output MUST be a structured analysis with findings — NOT code changes. Save findings to `docs/plans/collaborative-loop/loop-analysis.md`.

**For produce tasks (creating new code/plan/design):**
Invoke the discovered skill to produce the initial artifact. The artifact is the deliverable itself (code, plan, design doc). Save a summary of what was produced to `docs/plans/collaborative-loop/loop-analysis.md`.

Analysis file format:
```markdown
# Driver Analysis

## Task
<task description>

## Artifact Type
<code | plan | architecture | design>

## Target Files
- path/to/file1
- path/to/file2

## Findings

- [1] [severity: critical|high|medium|minor] [category] File:line — description
  - Suggested fix: <concrete fix>
- [2] [severity: ...] ...

## Summary
<1-2 sentence overall assessment>
```

### When Codex is Driver

**Do NOT use `run-codex-drive.sh` for the initial analysis** — its prompts are designed for the fix phase ("apply reviewer feedback", "make changes"), not analysis. Instead, construct an analysis prompt and run Codex directly.

Run as a **background bash process** (`run_in_background: true`). Source `check-codex.sh` first to get the `codex_run` function (required for WSL/MINGW environments):

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/check-codex.sh"

# Construct the prompt inline, tailored to the artifact type and task
# Load the artifact-specific review focus for domain context:
#   ${CLAUDE_PLUGIN_ROOT}/prompts/codex-review-${ARTIFACT_TYPE}.txt
# Include target files and task description
# Instruct: "Analyze only. Do NOT make any changes to the codebase."

cd /path/to/project
codex_run exec --full-auto "<analysis_prompt>" 2>&1 | tee docs/plans/collaborative-loop/loop-analysis.md
```

The analysis prompt must:
1. Instruct Codex to act as an analyst, NOT a fixer
2. Include the task description and target files
3. Explicitly state: "Do NOT modify any files. Produce a structured analysis with findings only."
4. Request output in the analysis file format (see above)

Wait for the background task to complete using TaskOutput. Then verify the output file exists and has content. If the file is empty or missing, reconstruct from TaskOutput (the script uses `tee`).

## Step 4: Reviewer VALIDATES Driver's Output

**For review tasks:** The reviewer's job is to validate the driver's FINDINGS — not to review the code independently. For each finding the driver reported, the reviewer verifies whether it's real, a false positive, or needs severity adjustment. The reviewer also identifies findings the driver missed.

**For produce tasks:** The reviewer's job is to review the driver's ARTIFACT (code, plan, design). Use the standard verdict format (`verdict-format.txt`) instead of the validation format. The reviewer produces findings about the artifact — these become the validated findings for Step 5. Save the output to `loop-validation.md` with the same structure (confirmed = reviewer's own findings, rejected = empty, new = empty).

### When Claude is Reviewer

Launch a subagent. The prompt depends on the task type:

**For review tasks** (driver produced findings):
```
Agent tool with:
  - subagent_type: "general-purpose"
  - model: "opus"
  - run_in_background: false
  - prompt: |
      You are validating another AI model's analysis of a codebase.
      Your job is to independently verify each finding.

      ## Driver's Analysis
      <content of loop-analysis.md>

      ## Target Files
      <file list — provide paths so the subagent can read them>

      <validation-format.txt content>

      For EACH finding the driver reported:
      1. Read the relevant code
      2. Determine if the finding is valid
      3. CONFIRM or REJECT with concrete evidence

      Also identify any issues the driver MISSED.
      Produce your output following the validation format above exactly.
```

**For produce tasks** (driver produced an artifact):
```
Agent tool with:
  - subagent_type: "general-purpose"
  - model: "opus"
  - run_in_background: false
  - prompt: |
      You are reviewing an artifact produced by another AI model.
      Your job is to review the produced work for quality, correctness, and completeness.

      ## Driver's Output
      <content of loop-analysis.md>

      ## Target Files
      <file list — provide paths so the subagent can read them>

      <verdict-format.txt content>

      Review the artifact and produce a verdict following the format above exactly.
```

Save the subagent's output to `docs/plans/collaborative-loop/loop-validation.md`.

### When Codex is Reviewer

**For review tasks** — run the validation script as a **background bash process** (`run_in_background: true`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-validate.sh" <ARTIFACT_TYPE> docs/plans/collaborative-loop /path/to/project docs/plans/collaborative-loop/loop-analysis.md [base_branch] [target_files...]
```

**For produce tasks** — run the review script instead (the driver produced an artifact, not findings):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh" <ARTIFACT_TYPE> 1 docs/plans/collaborative-loop /path/to/project [base_branch|target_files...]
```

Wait for the background task to complete using TaskOutput. Then verify the output file exists and has content. If the file is empty or missing, reconstruct from TaskOutput (the script uses `tee`).

Then rename the output to the expected location: `cp docs/plans/collaborative-loop/loop-review-round-1.md docs/plans/collaborative-loop/loop-validation.md`

### Parse Validation Result

Read `docs/plans/collaborative-loop/loop-validation.md` and extract the `STATUS:` line:

**Review tasks** (validation format):
- `VALIDATED` → majority confirmed, proceed
- `PARTIALLY_VALIDATED` → some confirmed, some rejected, proceed with confirmed + new only
- `REJECTED` → majority rejected, escalate to user (see below)

**Produce tasks** (verdict format):
- `APPROVED` → artifact is good, skip to Step 10
- `MINOR_ISSUES` → log minor items, skip to Step 10
- `CHANGES_REQUESTED` → treat reviewer's findings as the validated findings for Step 5

Also extract confirmed/rejected/new findings counts.

**If STATUS is REJECTED** (review tasks only — majority of driver's findings rejected):
- Present the validation result to the user
- Ask: "The reviewer rejected most of the driver's findings. Should I (1) re-analyze with the driver, (2) proceed with confirmed + new findings only, or (3) abort?"
- Follow user's decision

## Step 5: Merge Validated Findings

Combine the validation result into an actionable list:

**For review tasks** (validation format with confirmed/rejected/new):
1. **Confirmed findings** — from driver's analysis, validated by reviewer (use reviewer's severity if adjusted)
2. **New findings** — issues the reviewer found that the driver missed
3. **Rejected findings** — logged but NOT acted upon

**For produce tasks** (verdict format with findings): all reviewer findings are actionable — treat them as confirmed findings

Save merged findings internally (not to a file — this is the orchestrator's working state).

### Check If Action Is Needed

- If no confirmed + new findings at medium severity or above → **skip to Step 10** (present results: clean)
- If only minor confirmed + new findings → **skip to Step 10** (present results with minor items logged)
- Otherwise → proceed to Step 6

## Step 6: Driver ACTS on Validated Findings

Set `ROUND = ROUND + 1`.

### When Claude is Driver

Read the validation file (`docs/plans/collaborative-loop/loop-validation.md`). Apply ONLY the confirmed and new findings:

- Address findings in severity order (critical → high → medium → minor)
- Use Edit tool for precise changes
- Do NOT fix rejected findings — they were false positives
- Do not refactor beyond what's needed to address findings
- Save summary to `docs/plans/collaborative-loop/loop-drive-round-{ROUND}.md`

**Round N > 1:** Read the latest review file (`docs/plans/collaborative-loop/loop-review-round-{ROUND-1}.md`) instead of the validation file. Apply each finding directly.

Drive round summary format:
```markdown
# Drive Round N

## Task
<"Apply validated findings" (round 1) or "Apply reviewer feedback from round N-1" (round N>1)>

## Changes Applied
- [finding ref] description of change

## Findings Declined (if any)
- [finding ref] reason (should only be rejected findings in round 1)

## Files Modified
- path/to/file1
- path/to/file2
```

### When Codex is Driver

Run the drive script as a **background bash process** (`run_in_background: true`):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-drive.sh" <ARTIFACT_TYPE> <ROUND> docs/plans/collaborative-loop /path/to/project <feedback_file> [target_files...]
```

- Round 1 (first fix round): `feedback_file` = `docs/plans/collaborative-loop/loop-validation.md`
- Round N > 1: `feedback_file` = `docs/plans/collaborative-loop/loop-review-round-{ROUND-1}.md`

**Round 1 caveat:** The validation file contains "Rejected Findings" which the driver must NOT act on. Before passing it to `run-codex-drive.sh`, prepend an instruction to the feedback: "IMPORTANT: Only apply findings marked as CONFIRMED or listed under 'New Findings'. Do NOT apply findings marked as REJECTED — they are false positives." Either modify the file before passing it, or construct the feedback inline.

Wait for the background task to complete using TaskOutput. Then verify the output file exists and has content.

## Step 7: Reviewer Evaluates Action with Structured Verdict

Now the reviewer evaluates what the driver actually changed — this is a standard review of the implementation, not a validation of analysis.

### When Claude is Reviewer

Launch a subagent to review the driver's changes:

```
Agent tool with:
  - subagent_type: "general-purpose"
  - model: "opus"
  - run_in_background: false  (sequential — we need the result before proceeding)
  - prompt: |
      You are reviewing changes made by the driver in a collaborative loop.
      This is Fix Round N.

      ## Task Context
      <original task description>

      ## Driver's Changes
      <content of loop-drive-round-N.md or git diff summary>

      ## Target Files
      <file list>

      ## Validated Findings Being Addressed
      <confirmed + new findings from loop-validation.md>

      <If Round N > 1:>
      ## Previous Review (Round N-1)
      <content of loop-review-round-{N-1}.md>
      Only evaluate NEW changes. Do not re-report issues that were fixed.
      </If>

      <verdict-format.txt content>

      Review the driver's work and produce a verdict following the format above exactly.
      Focus on whether the driver correctly addressed the validated findings.
```

Save the subagent's output to `docs/plans/collaborative-loop/loop-review-round-{ROUND}.md`.

### When Codex is Reviewer

Run the review script as a **background bash process** (`run_in_background: true`):

**For code artifacts:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh" code <ROUND> docs/plans/collaborative-loop /path/to/project <base_branch>
```

**For non-code artifacts:**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-codex-review.sh" <plan|architecture|design> <ROUND> docs/plans/collaborative-loop /path/to/project [target_files...]
```

Wait for the background task to complete using TaskOutput. Verify the output file:
- Read `docs/plans/collaborative-loop/loop-review-round-{ROUND}.md`
- Confirm it contains `STATUS:` line and structured findings
- If file is truncated/empty, reconstruct from TaskOutput (the script uses `tee`)

**For code round 1:** The script uses `codex review --base` which has its own output format (no verdict template). Parse the output to extract findings and synthesize a verdict:
- If no critical/high/medium findings → `STATUS: APPROVED`
- If only minor findings → `STATUS: MINOR_ISSUES`
- Otherwise → `STATUS: CHANGES_REQUESTED`

Rewrite the review file with proper verdict format if needed.

## Step 8: Parse Verdict and Check Exit Conditions

### Verdict Parsing

Scan the review file for the `STATUS:` line:

```
grep -i "^STATUS:" docs/plans/collaborative-loop/loop-review-round-N.md
```

Extract the verdict:
- `APPROVED` → Step 10 (present results)
- `MINOR_ISSUES` → log the minor items, then Step 10 (present results)
- `CHANGES_REQUESTED` → continue to exit condition checks
- Missing or malformed → treat as `CHANGES_REQUESTED`

### Stall Detection

Extract current round's findings (file:line + description tuples). Compare with `PREV_FINDINGS`:
- Count findings that persist (same file, same issue — fuzzy match on description)
- If > 50% of findings persist from the previous round, increment `STALL_COUNT`
- If `STALL_COUNT >= 2` → mediator escalation (Step 9)

Update `PREV_FINDINGS` with current round's findings.

### Exit Condition Checks (in order)

1. **Stall detected** (`STALL_COUNT >= 2`) → Step 9 (mediator)
2. **Max rounds reached** (`ROUND >= MAX_ROUNDS`) → Step 10 with remaining issues
3. **Otherwise** → feed review to driver, back to Step 6 (which increments `ROUND`)

## Step 9: Mediator Escalation

When stall is detected (same findings persist across 2+ rounds despite fixes):

### Present to User

```markdown
## Mediator Needed — Collaboration Stalled

**Round:** N | **Stall count:** 2 | **Persistent findings:** X

The following issues have persisted across multiple fix-review cycles:

### Stalled Finding 1
- **Issue:** <description>
- **Driver's position:** <what driver did/argued>
- **Reviewer's position:** <what reviewer keeps flagging>
- **History:** Flagged round M, attempted fix round M+1, re-flagged round M+2

### Stalled Finding 2
...

**Options:**
1. **Accept driver's approach** — tell reviewer to stop flagging these items
2. **Side with reviewer** — provide specific guidance for how to fix
3. **Your own direction** — provide alternative approach
4. **Abort** — stop the loop, keep current state
```

### After User Decides

- If user provides guidance: feed it as **authoritative context** to the next driver round (non-negotiable — driver must follow)
- Tell the reviewer in the next round: "The following items were settled by the user and must NOT be re-flagged: <list>"
- Reset `STALL_COUNT` to 0
- Continue the loop

If user chooses abort → Step 10 (present results).

## Step 10: Present Results Summary

```markdown
## Collaborative Loop Complete

**Driver:** <claude|codex> | **Reviewer:** <claude|codex>
**Rounds:** N (initial + N fix rounds) | **Max rounds:** M
**Exit reason:** <approved | minor issues only | no actionable findings | max rounds | stall → user decision | abort>

### Validation Summary (Initial Phase)
- Driver findings: X
- Confirmed by reviewer: Y
- Rejected (false positives prevented): Z
- New findings added by reviewer: W

### Final Verdict
<last reviewer verdict>

### Resolved Issues (across all rounds)
- Round 1: <issues fixed>
- Round 2: <issues fixed>
- ...

### Remaining Issues (if any)
<unresolved findings from last review>

### User Decisions Made (if any)
<mediator outcomes>
```

## Step 11: Clean Up Intermediate Files (MANDATORY)

Run the cleanup script — this is MANDATORY regardless of exit reason:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" docs/plans/collaborative-loop
```

**Do NOT delete** the target artifact files that were worked on — only the loop round files.
**Do NOT skip this step** — leaving intermediate files is a known failure mode.

## Iteration Rules

- **Max 5 rounds** default (fix-review rounds only; initial produce-validate phase is separate) — override with `--max-rounds`
- **Sequential, not parallel** — driver completes before reviewer starts, reviewer completes before next driver round
- **Initial phase produces 2 files:** `loop-analysis.md`, `loop-validation.md`
- **Each fix round produces 2 files:** `loop-drive-round-N.md`, `loop-review-round-N.md`
- **All intermediate files are deleted** after the loop completes (Step 11 — mandatory)
- **Driver never acts on unvalidated output** — the initial analysis MUST be validated before any fixes begin
- **Context is minimal** — each agent receives only the latest review or validation, not full history
- **Stall detection compares adjacent fix rounds** — findings that persist across 2+ rounds trigger mediator
- **User guidance is authoritative** — once the user decides on a stalled item, it's settled
- **Verdict format is enforced** — if Codex doesn't use it (e.g., `codex review --base`), synthesize one from the output

## Common Mistakes

- **Driver fixing its own unvalidated findings** — this is the #1 error the redesign prevents. The driver MUST wait for validation before acting. Never skip Step 4
- **Treating validation as a standard review** — for review tasks, validation (Step 4) examines the driver's FINDINGS (use validation-format.txt), not the code directly. For produce tasks, validation is a standard review of the ARTIFACT (use verdict-format.txt). Standard review (Step 7) always examines the driver's CHANGES
- **Skipping the preflight check** — always run `check-codex.sh` before any loop work. If codex is not reachable, the loop will fail mid-flight with cryptic errors. Fail fast, not mid-round
- **Running driver and reviewer in parallel** — this is a SEQUENTIAL loop; driver must finish before reviewer starts. The whole point is that the reviewer evaluates the driver's actual output
- **Passing full round history to agents** — each agent gets ONLY the most recent review or validation file. The orchestrator tracks state internally
- **Not detecting stall** — if you don't track findings across rounds, the loop can spin forever on the same issues
- **Silently resolving stalled items** — stall resolution requires user input; never auto-resolve
- **Using skill discovery on fix rounds** — after the initial phase, Claude driver should apply feedback directly with Edit tool, not re-invoke skills
- **Leaving intermediate files** — always run `cleanup-loop.sh` regardless of exit reason
- **Running Codex scripts without `run_in_background`** — Codex commands can take minutes; always run as background tasks and wait via TaskOutput
- **Passing both `--base` and a prompt to `codex review`** — they are mutually exclusive in Codex CLI; the review script handles this correctly
- **Not verifying Codex output files** — always read the output file after TaskOutput completes; reconstruct from TaskOutput if file is empty/truncated (script uses `tee`)
- **Treating MINOR_ISSUES as CHANGES_REQUESTED** — MINOR_ISSUES means the loop should stop; log the items but don't iterate further
- **Ignoring user's --driver flag** — if user specifies `--driver codex`, Codex drives and Claude reviews; don't override
- **Feeding user mediator guidance as a suggestion** — user decisions are authoritative and non-negotiable for both driver and reviewer
- **Responding to late background task notifications** — if a Codex background task completion arrives after the workflow has finished, do NOT generate a user-facing response; silently acknowledge it
- **Asking clarifying questions when invoked without arguments** — the skill has sensible defaults for everything; when invoked bare, use them all and start immediately. Never ask about task, driver, files, or rounds — infer and proceed
- **Acting on rejected findings** — when the reviewer rejects a driver finding, the driver MUST skip it. Rejected findings are false positives that would introduce regressions if "fixed". When Codex is driver, the validation file is passed as raw feedback — prepend an instruction to skip REJECTED findings, since the drive script's base prompt says "apply ALL findings"
- **Using bare `codex` instead of `codex_run` on MINGW** — on Windows Git Bash, codex runs via WSL. Always source `check-codex.sh` and use `codex_run` instead of bare `codex` when running commands inline (the plugin scripts handle this automatically)
- **Forgetting to synthesize verdict for `codex review --base` output** — round 1 code review with Codex uses `codex review` which has its own format; you must parse it and produce a verdict
