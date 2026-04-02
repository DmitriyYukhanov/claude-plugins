# Codex Collaboration Plugin — Refactor Design Spec

> Merges `collaborative-loop` (v1.4.0) and `cross-review` (v1.6.2) into a single
> `codex-collaboration` plugin that delegates all Codex interaction to the official
> [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc).
> Removes all WSL-specific code, bash scripts, and manual Codex orchestration.

## Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Plugin name | `codex-collaboration` | Clear dependency on codex plugin |
| Prompt strategy | Leverage `gpt-5-4-prompting` skill + inline domain focus tables | Aligns with codex plugin's prompt composition; no static template files |
| Missing codex plugin | Hard ABORT with install instructions | Cross-model collaboration requires two models; self-review defeats the purpose |
| Driver direction | Claude always drives | Claude is orchestrator with full context; Codex drives available via `/codex:rescue` directly |
| Adversarial review | Optional final confidence gate; NOT used for per-finding validation | Adversarial review produces its own findings, doesn't map back to Claude's analysis |
| Validation mechanism | `/codex:rescue` with explicit validation prompt for step 4 | Allows per-finding CONFIRM/REJECT contract that adversarial-review can't provide |
| Parallelism | Organic — each side decides internally | Claude uses subagents/teams when valuable; Codex uses `multi_agent = true`; no directory-group chunking formulas |
| Plugin structure | Approach B — shared domain knowledge layer | DRY focus areas, shorter skills, consistent review quality |
| plugin.json location | `.claude-plugin/plugin.json` only | Official Claude Code spec; root copy was custom convention causing sync issues |

## Plugin Structure

```
plugins/codex-collaboration/
├── .claude-plugin/
│   └── plugin.json
└── skills/
    ├── collaborative-loop/
    │   └── SKILL.md              # Sequential drive/validate/act cycles
    ├── cross-review/
    │   └── SKILL.md              # Parallel dual review with triage
    └── shared/
        ├── prerequisites.md       # Codex plugin install check + config
        ├── review-domains.md      # Focus areas per artifact type
        ├── artifact-detection.md  # How to classify target files
        ├── verdict-format.md      # Structured output format for reviews
        └── validation-format.md   # Per-finding CONFIRM/REJECT format for step 4
```

**No bash scripts. No WSL code. No prompt template files. Environment-agnostic.**

## Manifest

```json
{
  "name": "codex-collaboration",
  "version": "1.0.0",
  "description": "Cross-model collaboration between Claude and Codex — sequential drive/validate/act loops and parallel dual review with triage"
}
```

## Prerequisites (shared/prerequisites.md)

Both skills share the same preflight:

1. **Check codex plugin** — invoke `/codex:setup`. Two failure modes:
2. **Command not recognized** (plugin not installed) — print install instructions and ABORT:
   ```
   The codex-collaboration plugin requires the Codex plugin for Claude Code.

   Install it:
   1. /plugin marketplace add openai/codex-plugin-cc
   2. /plugin install codex@openai-codex
   3. /reload-plugins
   4. Run /codex:setup to verify Codex CLI authentication

   Then re-run this skill.
   ```
3. **Setup reports failure** (plugin installed but CLI missing or auth expired) — report the specific issue and ABORT:
   ```
   Codex plugin is installed but setup failed: <specific error from /codex:setup>

   Fix it:
   - CLI not found: npm install -g @openai/codex
   - Auth expired: codex auth login
   - Then re-run this skill.
   ```
4. **On success** — proceed.

Recommended Codex config (informational, not blocking):
```toml
# ~/.codex/config.toml
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
[features]
multi_agent = true
```

## Artifact Detection (shared/artifact-detection.md)

Detection order:

1. **Explicit flag** — `--type code|plan|architecture|design`
2. **File extension matching:**
   - Source code (`.ts`, `.py`, `.js`, `.jsx`, `.tsx`, `.go`, `.rs`, `.cs`, `.java`, `.rb`, `.cpp`, `.c`, `.h`) -> **code**
   - `*-plan*`, `*-tasks*`, `*implementation-plan*` -> **plan**
   - `*-architecture*`, `*-spec*` -> **architecture**
   - Other `.md` in `docs/` or `plans/` -> **design**
3. **Mixed targets** — default to **code**

Target files (when not provided):
- `git diff <base>...HEAD --name-only`
- Auto-detect base branch or fall back to `main`
- Bare invocation: ask user

## Review Domains (shared/review-domains.md)

Focus areas per artifact type, injected into `<task>` blocks via `gpt-5-4-prompting`:

### Code
- Correctness & edge cases
- Security vulnerabilities
- Performance bottlenecks
- Test coverage gaps
- Error handling completeness
- Consistency with surrounding code patterns
- Import/type correctness
- No debug code, TODOs, or placeholders

### Plan
- Requirement completeness (every requirement -> at least one task)
- DAG validity (no cycles in task ordering)
- Dependency correctness
- Realistic estimates given scope
- Task clarity and assumption identification

### Architecture
- Pattern consistency across components
- Separation of concerns / clear boundaries
- Scalability & bottleneck analysis
- Deployment constraints
- Coupling analysis
- Missing abstractions
- Trade-off rationale

### Design
- Requirements coverage
- Technical feasibility
- Scope creep detection
- Missing decisions / unresolved trade-offs
- Decision rationale with alternatives considered
- User impact (UX, performance, accessibility)

### Shared Across All Types
- Severity levels: Critical > High > Medium > Minor
- Findings format: `[severity] [category] file:line — description`
- Global ordering by severity (not grouped by area)
- Every finding must cite specific code/text

## Verdict Format (shared/verdict-format.md)

Structured output included in Codex prompts as `<structured_output_contract>`:

### Statuses

| Status | Meaning | Action |
|--------|---------|--------|
| `APPROVED` | No issues or all trivial | Stop, present summary |
| `MINOR_ISSUES` | Only minor/informational | Log findings, stop |
| `CHANGES_REQUESTED` | Actionable findings | Continue to next round |

### Output Structure

```markdown
## Status
APPROVED | MINOR_ISSUES | CHANGES_REQUESTED

## Findings
- [severity] [category] file:line — description
  Fix: concrete suggested fix
- ...

## Summary
Brief overall assessment (2-3 sentences)
```

### Parsing Rules
- Extract status from first non-empty line after `## Status`
- Parse findings as list items matching `[severity] [category] file:line`
- If output doesn't match format, treat as `CHANGES_REQUESTED` with full output as single finding

Aligns with codex plugin's `review-output.schema.json` for `/codex:review`. Provides markdown format for `/codex:rescue` responses.

## Validation Format (shared/validation-format.md)

Per-finding validation output used in collaborative-loop step 4. Distinct from the verdict format — this evaluates the driver's individual findings, not the overall state.

Included in Codex validation prompts as `<structured_output_contract>`:

```markdown
## Confirmed Findings
- [finding #] CONFIRM — evidence from code/spec

## Rejected Findings
- [finding #] REJECT — evidence why this is a false positive

## New Findings (Missed by Driver)
- [severity] [category] file:line — description

## Status
VALIDATED | PARTIALLY_VALIDATED | REJECTED

## Summary
Brief assessment (confirmed X, rejected Y, found Z new)
```

### Parsing Rules
- `VALIDATED` — majority confirmed, proceed with confirmed + new
- `PARTIALLY_VALIDATED` — some confirmed, some rejected, proceed with confirmed + new only
- `REJECTED` — majority rejected, escalate to user before proceeding

## Collaborative Loop Skill

Sequential drive/validate/act workflow. Claude drives, Codex validates and reviews.

**Invocation:** `collaborative-loop [--max-rounds N] [--type code|plan|architecture|design] [target files...]`

**Defaults:** `--max-rounds 3`

### Workflow

#### Step 1: Preflight
Read `shared/prerequisites.md`. Run `/codex:setup`. ABORT if plugin missing or setup fails.

#### Step 2: Detect Context
Read `shared/artifact-detection.md`. Classify targets, detect base branch.

#### Step 3: Claude PRODUCES Analysis
Claude analyzes target files and produces findings/proposed changes. **No implementation yet** — analysis only.
- For code: use appropriate project skills if available
- For non-code: structured analysis against focus areas from `shared/review-domains.md`

#### Step 4: Codex VALIDATES
Send Claude's analysis to Codex for independent per-finding verification via `/codex:rescue` with a validation prompt composed using `gpt-5-4-prompting` patterns:
- Include Claude's numbered findings in the prompt
- Include `shared/validation-format.md` as `<structured_output_contract>`
- Include `shared/review-domains.md` focus areas for the artifact type as context
- For code: include target file paths so Codex can read and verify against the actual code
- For non-code: include the artifact content

Codex independently verifies each finding: CONFIRM or REJECT with concrete evidence.

**Why not `/codex:adversarial-review`?** Adversarial review produces its own independent findings — it doesn't map back to Claude's analysis per-finding. The validation step requires per-finding CONFIRM/REJECT, which only a custom prompt via `/codex:rescue` can provide. `/codex:adversarial-review` can optionally be used as a final confidence gate after all rounds complete.

#### Step 4.5: Claude RE-EVALUATES Codex Validation
Claude reviews Codex's CONFIRM/REJECT decisions against the original analysis:

| Codex Says | Claude Agrees? | Action |
|------------|---------------|--------|
| CONFIRMED | Yes | **Proceed** — act on finding |
| CONFIRMED | No | **Flag for user** — disagreement |
| REJECTED | Yes | **Drop** — both agree not real |
| REJECTED | No | **Flag for user** — disagreement |

Only findings where **both models agree** proceed to action. Disagreements presented to user for mediation before continuing.

#### Step 5: Claude ACTS on Validated Findings
Filter to confirmed findings. Claude implements fixes.
- Use subagents when parallelism adds value (e.g., independent fixes across different modules)
- Rejected findings logged but not acted on

#### Step 6: Codex REVIEWS Changes
Send changes for review:
- **Code:** `/codex:review --base <ref>`
- **Non-code:** `/codex:rescue` with review prompt using `gpt-5-4-prompting` patterns and `shared/verdict-format.md`

Codex returns verdict. May use its own subagents internally (`multi_agent = true`).

#### Step 7: Evaluate & Loop
Parse verdict:
- `APPROVED` / `MINOR_ISSUES` -> present summary, done
- `CHANGES_REQUESTED` -> feed findings back to step 5, next round
- **Stall detection:** >50% of findings persist across 2 consecutive rounds -> stop, escalate to user
- **Max rounds reached** -> stop, present remaining issues

### Key Principles
- Claude never acts on its own unvalidated output (step 4 gate)
- Both models must agree before action (step 4.5 gate)
- No intermediate files — Claude holds state in conversation context
- No cleanup scripts needed
- Parallelism is organic: Claude subagents for independent fixes, Codex native subagents for large reviews

## Cross-Review Skill

Parallel dual review with triage. Both models review independently, then cross-validate.

**Invocation:** `cross-review [--max-rounds N] [--type code|plan|architecture|design] [target files...]`

**Defaults:** `--max-rounds 3`

### Workflow

#### Step 1: Preflight
Same as collaborative-loop.

#### Step 2: Detect Context
Same as collaborative-loop.

#### Step 3: Parallel Review
Launch simultaneously:

**Claude side:** Spawn focused review agents (security, performance, correctness, test coverage, maintainability). Use Agent tool — agent teams when scope is large, individual agents for smaller reviews. Each agent reviews through its domain lens using `shared/review-domains.md`.

**Codex side:** `/codex:review --base <ref> --background` for code, or `/codex:rescue --background` with review prompt via `gpt-5-4-prompting` for non-code.

Both sides run concurrently. Poll Codex job via `/codex:status`. When complete, retrieve output via `/codex:result`.

**Codex job failure handling:** If the Codex background job fails (auth expired, CLI error, timeout), report the failure to the user. Proceed to triage with Claude-only findings but warn that cross-validation is degraded — Codex findings will be empty for that round. If user wants full cross-review, they should fix Codex (e.g., re-run `/codex:setup`) and re-run.

**File scoping note:** `/codex:review` reviews the entire branch diff, not specific files. When re-reviewing in subsequent rounds, Codex will see all branch changes including prior rounds' fixes. This is acceptable — Codex should focus on new/changed code, and the prompt for `/codex:rescue` (non-code) can be scoped to specific files.

#### Step 4: Triage Findings
Claude cross-validates findings from both sides:

| Situation | Classification |
|-----------|---------------|
| Both agree (same issue) | **auto-fixable** (if fix is unambiguous) |
| Only one side found it, Claude evaluates as real | **auto-fixable** |
| Only one side found it, uncertain | **needs-decision** |
| Disagreement (severity, fix approach, or validity) | **needs-decision** |
| Both rate as minor + no concrete action | **informational** |

#### Step 5: Present Triage to User
Show needs-decision items first. User decides which to fix, which to dismiss. Auto-fixable items listed for confirmation.

#### Step 6: Apply Fixes & Re-Review
Claude fixes approved items using subagents for independent fixes. Discover best available skill for the artifact type, then apply fixes. Re-review: go to step 3. For Claude side, scope review agents to only the changed files. For Codex side, `/codex:review` will re-review the full branch diff (it's branch-scoped); for non-code, `/codex:rescue` can be scoped to changed files via prompt. Max rounds (default 3).

**Skill discovery** — search available skills for the best match:

| Artifact Type | Search Keywords | Priority |
|---------------|----------------|----------|
| Code | `coder`, `code-review`, `implementation`, `feature-dev` | Project-specific first |
| Plan | `writing-plans`, `executing-plans`, `plan` | General-purpose |
| Architecture | `architect`, `architecture`, `brainstorming`, `design` | General-purpose |
| Design | `brainstorming`, `writing-plans`, `design` | General-purpose |

Fallback: if no matching skill found, apply fixes directly with Edit tool. For trivial fixes (typos, missing imports), skip skill discovery entirely.

**File scoping constraint:** `/codex:review` and `/codex:adversarial-review` are branch-scoped (they review the entire branch diff), not file-scoped. When re-reviewing after fixes, Codex will still review all branch changes, not just the files changed in this round. For non-code artifacts, `/codex:rescue` can be scoped to specific files via the prompt.

#### Step 7: Exit & Summary
When clean or max rounds reached, present final state.

### Key Differences from Collaborative Loop
- **Parallel** (both review at once) vs **sequential** (produce -> validate -> act)
- Focus on **finding issues** vs **driving changes**
- Triage with **user mediation** vs automated consensus gate
- Better for **review of existing work**; collaborative-loop better for **iterative improvement**

## Codex Plugin Commands Mapping

How our skills map to codex plugin features:

| Our Usage | Codex Plugin Command | Notes |
|-----------|---------------------|-------|
| Preflight check | `/codex:setup` | Validates CLI install + auth |
| Code review | `/codex:review --base <ref>` | Native structured review |
| Per-finding validation | `/codex:rescue` with validation prompt | Custom prompt enables CONFIRM/REJECT per finding (step 4) |
| Adversarial confidence gate | `/codex:adversarial-review --base <ref>` | Optional final gate after all rounds; challenge-focused |
| Non-code review/task | `/codex:rescue <prompt>` | Task delegation with custom prompt |
| Background execution | `--background` flag on review/rescue | For parallel execution in cross-review |
| Job status check | `/codex:status` | Monitor background jobs |
| Job result retrieval | `/codex:result` | Fetch completed background job output |
| Prompt composition | `gpt-5-4-prompting` skill (from codex plugin) | XML-tagged blocks, recipes, anti-patterns |

## Skill Trigger Descriptions

**collaborative-loop:**
- "collaborate with codex", "have codex review my changes"
- "drive and review loop", "iterative improvement"
- "produce-validate-act", "collaborative loop"

**cross-review:**
- "cross-review", "dual review", "multi-model review"
- "get a second opinion", "validate with another model"
- "review with codex", "parallel review"

## Removed

### Files Deleted
- `plugins/collaborative-loop/` (entire directory)
- `plugins/cross-review/` (entire directory)
- `shared/scripts/check-codex.sh`
- `shared/scripts/` (if empty after deletion)

### Capabilities Removed
- `--driver codex` flag (Codex as driver)
- WSL/MINGW environment detection and path translation
- Directory-group chunking formulas
- File-based intermediate state (`loop-analysis.md`, `loop-validation.md`, `loop-drive-round-*.md`, etc.)
- Bash script orchestration
- Static `.txt` prompt template files

## Repo-Wide Plugin Structure Cleanup

Align all plugins with official Claude Code plugin spec.

### Root plugin.json Removal

| Plugin | Action |
|--------|--------|
| `agent-teams` | No change (already correct — only `.claude-plugin/plugin.json`) |
| `implementation-prd` | Delete root `plugin.json` |
| `lsp-setup` | Delete root `plugin.json` |
| `python-dev` | Delete root `plugin.json`; update `.claude-plugin/plugin.json` to v1.2.0 |
| `typescript-dev` | Delete root `plugin.json`; update `.claude-plugin/plugin.json` to v1.2.0 |
| `unity-dev` | Delete root `plugin.json`; update `.claude-plugin/plugin.json` to v1.6.0 |

### Pre-Commit Hook Update
- Remove check for root `plugin.json`
- Check only `.claude-plugin/plugin.json` vs marketplace.json
- Remove "both must match" logic

### CLAUDE.md Update
Replace dual-manifest requirement with:
```
1. `plugins/<name>/.claude-plugin/plugin.json` — manifest (the only location Claude Code reads)
```

### New Plugin Checklist Update
The current CLAUDE.md checklist has:
1. `plugins/<name>/plugin.json` — root manifest
2. `plugins/<name>/.claude-plugin/plugin.json` — identical copy

After this change:
- **Remove item 1** (root `plugin.json` — no longer needed)
- **Keep item 2, renumber to 1** (`.claude-plugin/plugin.json` — this is the only manifest Claude Code reads)
- Update wording to remove "identical copy" since it's now the sole location

## marketplace.json Changes

Remove:
- `collaborative-loop` entry (v1.4.0)
- `cross-review` entry (v1.6.2)

Add entry to the `plugins` array (matching existing entry format):
```json
{
  "name": "codex-collaboration",
  "description": "Cross-model collaboration between Claude and Codex — sequential drive/validate/act loops and parallel dual review with triage",
  "version": "1.0.0",
  "author": {
    "name": "Dmitry Yuhanov"
  },
  "source": "./plugins/codex-collaboration",
  "category": "workflow",
  "homepage": "https://github.com/DmitriyYukhanov/claude-plugins"
}
```

## README.md Changes

Remove:
- "Collaborative Loop" plugin section
- "Cross-Review" plugin section

Add (in alphabetical position) "Codex Collaboration" section:
- What it does (two workflows)
- Dependency on codex plugin with install link
- Brief description of each skill
- When to use which
- Install command
