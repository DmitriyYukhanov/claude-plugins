# Codex Collaboration Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge collaborative-loop and cross-review into a single codex-collaboration plugin that delegates to the official Codex plugin, remove all WSL/bash scripting, and clean up repo-wide plugin.json duplication.

**Architecture:** New plugin at `plugins/codex-collaboration/` with 2 skills (collaborative-loop, cross-review) sharing 5 reference files. All Codex interaction via `/codex:setup`, `/codex:review`, `/codex:rescue`, `/codex:adversarial-review` commands from the codex plugin. No bash scripts or environment-specific code.

**Tech Stack:** Markdown (SKILL.md files), JSON (plugin manifests), Bash (pre-commit hook)

**Spec:** `docs/superpowers/specs/2026-04-02-codex-collaboration-refactor-design.md`

---

### Task 1: Update Pre-Commit Hook

Update the hook first so it won't block later changes. Must reference `.claude-plugin/plugin.json` instead of root `plugin.json`.

**Files:**
- Modify: `.githooks/pre-commit`

- [ ] **Step 1: Update Check 1 — version bump detection**

Change the plugin.json path from root to `.claude-plugin/`:

In `.githooks/pre-commit`, find the `changed_plugins` loop (line ~26):
```bash
  if [[ "$file" =~ ^plugins/([^/]+)/ ]] && [[ "$file" != plugins/*/plugin.json ]]; then
```
Replace with:
```bash
  if [[ "$file" =~ ^plugins/([^/]+)/ ]] && [[ "$file" != plugins/*/.claude-plugin/plugin.json ]]; then
```

Then in the version check loop (line ~40-55), change all occurrences of:
```bash
    plugin_json="plugins/${plugin}/plugin.json"
```
to:
```bash
    plugin_json="plugins/${plugin}/.claude-plugin/plugin.json"
```

- [ ] **Step 2: Update Check 2 — marketplace sync**

In the sync check (line ~62):
```bash
for plugin_json in $(echo "$staged_files" | grep -E '^plugins/[^/]+/plugin\.json$' || true); do
  plugin_name=$(echo "$plugin_json" | sed 's|plugins/\([^/]*\)/plugin\.json|\1|')
```
Replace with:
```bash
for plugin_json in $(echo "$staged_files" | grep -E '^plugins/[^/]+/\.claude-plugin/plugin\.json$' || true); do
  plugin_name=$(echo "$plugin_json" | sed 's|plugins/\([^/]*\)/\.claude-plugin/plugin\.json|\1|')
```

- [ ] **Step 3: Update Check 3 — new plugin detection**

In the new plugin detection (line ~113-117):
```bash
  plugin_json="plugins/${plugin}/plugin.json"

  # Detect NEW plugins: plugin.json is staged AND didn't exist in HEAD
  if echo "$staged_files" | grep -qx "$plugin_json"; then
    if ! git show "HEAD:${plugin_json}" &>/dev/null; then
```
Replace with:
```bash
  plugin_json="plugins/${plugin}/.claude-plugin/plugin.json"

  # Detect NEW plugins: .claude-plugin/plugin.json is staged AND didn't exist in HEAD
  if echo "$staged_files" | grep -qx "$plugin_json"; then
    if ! git show "HEAD:${plugin_json}" &>/dev/null; then
```

- [ ] **Step 4: Update error message**

In the version bump error (line ~157-158):
```bash
    plugin_json="plugins/${plugin}/plugin.json"
    current=$(cat "$plugin_json" 2>/dev/null | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' || echo "unknown")
```
Replace with:
```bash
    plugin_json="plugins/${plugin}/.claude-plugin/plugin.json"
    current=$(cat "$plugin_json" 2>/dev/null | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | grep -o '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' || echo "unknown")
```

Also update the fix message (line ~167):
```bash
  echo "Fix: update \"version\" in the plugin's plugin.json, then re-stage and commit."
```
Replace with:
```bash
  echo "Fix: update \"version\" in the plugin's .claude-plugin/plugin.json, then re-stage and commit."
```

- [ ] **Step 5: Verify hook syntax**

Run: `bash -n .githooks/pre-commit`
Expected: no output (syntax valid)

---

### Task 2: Create Plugin Manifest

**Files:**
- Create: `plugins/codex-collaboration/.claude-plugin/plugin.json`

- [ ] **Step 1: Create directory and manifest**

```json
{
  "name": "codex-collaboration",
  "version": "1.0.0",
  "description": "Cross-model collaboration between Claude and Codex — sequential drive/validate/act loops and parallel dual review with triage"
}
```

- [ ] **Step 2: Verify JSON is valid**

Run: `python -c "import json; json.load(open('plugins/codex-collaboration/.claude-plugin/plugin.json'))"`
Expected: no error

---

### Task 3: Write Shared Reference Files

**Files:**
- Create: `plugins/codex-collaboration/skills/shared/prerequisites.md`
- Create: `plugins/codex-collaboration/skills/shared/artifact-detection.md`
- Create: `plugins/codex-collaboration/skills/shared/review-domains.md`
- Create: `plugins/codex-collaboration/skills/shared/verdict-format.md`
- Create: `plugins/codex-collaboration/skills/shared/validation-format.md`

- [ ] **Step 1: Write prerequisites.md**

Content — the preflight check logic and install instructions. Copy verbatim from spec section "Prerequisites (shared/prerequisites.md)" (lines 53-88). This is a reference file that SKILL.md files will instruct Claude to read.

- [ ] **Step 2: Write artifact-detection.md**

Content — detection order, file extension mapping, target file resolution. Copy from spec section "Artifact Detection" (lines 90-105).

- [ ] **Step 3: Write review-domains.md**

Content — focus areas per artifact type (code, plan, architecture, design) + shared formatting rules. Copy from spec section "Review Domains" (lines 107-149).

- [ ] **Step 4: Write verdict-format.md**

Content — status definitions, output structure, parsing rules. Copy from spec section "Verdict Format" (lines 151-183).

- [ ] **Step 5: Write validation-format.md**

Content — per-finding CONFIRM/REJECT format, status definitions, parsing rules. Copy from spec section "Validation Format" (lines 185-211).

- [ ] **Step 6: Verify all files exist**

Run: `ls -la plugins/codex-collaboration/skills/shared/`
Expected: 5 markdown files listed

---

### Task 4: Write Collaborative Loop SKILL.md

**Files:**
- Create: `plugins/codex-collaboration/skills/collaborative-loop/SKILL.md`

- [ ] **Step 1: Write the full SKILL.md**

Must include:
1. **Frontmatter** — name, model (opus), description, trigger phrases from spec line 370-373
2. **Overview** — sequential drive/validate/act, Claude drives, Codex validates
3. **Prerequisites section** — instruct Claude to read `${CLAUDE_PLUGIN_ROOT}/skills/shared/prerequisites.md` and execute the preflight
4. **Argument parsing** — `--max-rounds` (default 3), `--type`, target files
5. **Step 1: Preflight** — invoke `/codex:setup`, two failure modes
6. **Step 2: Detect Context** — read `shared/artifact-detection.md`, classify, detect base branch
7. **Step 3: Claude PRODUCES** — analysis only, no implementation. Use project skills if available. Output numbered findings with severity
8. **Step 4: Codex VALIDATES** — `/codex:rescue` with validation prompt. Include Claude's findings + `shared/validation-format.md` as output contract + `shared/review-domains.md` focus areas. Compose using `gpt-5-4-prompting` patterns
9. **Step 4.5: Claude RE-EVALUATES** — the bilateral consensus table (CONFIRMED+agree=proceed, etc). Disagreements flagged for user
10. **Step 5: Claude ACTS** — fix confirmed findings only. Subagents for parallel independent fixes
11. **Step 6: Codex REVIEWS** — `/codex:review --base <ref>` for code, `/codex:rescue` for non-code with `shared/verdict-format.md`
12. **Step 7: Evaluate & Loop** — parse verdict, stall detection (>50% persist for 2 rounds), max rounds
13. **Key Principles** — no self-review fallback, no intermediate files, organic parallelism
14. **Common Mistakes** — don't use `/codex:adversarial-review` for validation (produces own findings), don't act on unvalidated output, don't fall back to Claude-only

Target: ~250-300 lines. Concise but complete enough for an implementer with zero context.

- [ ] **Step 2: Verify frontmatter is valid YAML**

Run: `head -20 plugins/codex-collaboration/skills/collaborative-loop/SKILL.md`
Expected: valid `---` delimited frontmatter with name, model, description

---

### Task 5: Write Cross-Review SKILL.md

**Files:**
- Create: `plugins/codex-collaboration/skills/cross-review/SKILL.md`

- [ ] **Step 1: Write the full SKILL.md**

Must include:
1. **Frontmatter** — name, model (opus), description, trigger phrases from spec lines 375-378
2. **Overview** — parallel dual review, both models review independently, then triage
3. **Prerequisites section** — same pattern as collaborative-loop, read `shared/prerequisites.md`
4. **Argument parsing** — same flags as collaborative-loop
5. **Step 1: Preflight** — same as collaborative-loop
6. **Step 2: Detect Context** — same
7. **Step 3: Parallel Review** — Claude agents (security, performance, correctness, test, maintainability) + Codex (`/codex:review --background` or `/codex:rescue --background`). Poll via `/codex:status`, retrieve via `/codex:result`. Failure handling: proceed with Claude-only if Codex fails
8. **Step 4: Triage** — cross-validate: both agree = auto-fixable, disagreement = needs-decision, one-sided+uncertain = needs-decision
9. **Step 5: Present Triage** — needs-decision items first, user decides
10. **Step 6: Apply Fixes & Re-Review** — skill discovery table, file scoping constraint for Codex
11. **Step 7: Exit & Summary**
12. **Key Differences from Collaborative Loop** — parallel vs sequential, finding vs driving, user mediation vs consensus gate
13. **Common Mistakes** — don't resolve disagreements silently, don't forget `/codex:status` polling, file scoping

Target: ~200-250 lines.

- [ ] **Step 2: Verify frontmatter is valid YAML**

Run: `head -20 plugins/codex-collaboration/skills/cross-review/SKILL.md`
Expected: valid `---` delimited frontmatter

---

### Task 6: Update marketplace.json

**Files:**
- Modify: `.claude-plugin/marketplace.json`

- [ ] **Step 1: Remove collaborative-loop entry**

Delete the `collaborative-loop` object from the `plugins` array (current lines 76-85).

- [ ] **Step 2: Remove cross-review entry**

Delete the `cross-review` object from the `plugins` array (current lines 53-63).

- [ ] **Step 3: Add codex-collaboration entry**

Add to the `plugins` array (alphabetical position — after `agent-teams`, before `implementation-prd`):

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

- [ ] **Step 4: Verify JSON is valid**

Run: `python -c "import json; json.load(open('.claude-plugin/marketplace.json'))"`
Expected: no error

---

### Task 7: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update install commands**

Remove `cross-review` and `collaborative-loop` from the install list. Add `codex-collaboration` (alphabetical position):

```bash
/plugin install codex-collaboration
```

- [ ] **Step 2: Remove old plugin sections**

Delete the `### cross-review` section (lines 92-100) and `### collaborative-loop` section (lines 102-111).

- [ ] **Step 3: Add codex-collaboration section**

Insert after the `### agent-teams` section (alphabetical):

```markdown
### codex-collaboration

Cross-model collaboration between Claude and Codex with two workflows:

- **collaborative-loop** — Sequential drive/validate/act cycles. Claude analyzes, Codex validates each finding, both models must agree before any action is taken. Iterates until approved or max rounds.
- **cross-review** — Parallel dual review. Both Claude and Codex review independently, findings are cross-validated and triaged, disagreements surfaced for user decision.

**Requires** the [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc). Install it first:
1. `/plugin marketplace add openai/codex-plugin-cc`
2. `/plugin install codex@openai-codex`
3. `/codex:setup` to verify

[View skill documentation](./plugins/codex-collaboration/skills/collaborative-loop/SKILL.md)
```

---

### Task 8: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update Plugin Version Bumping section**

Change line 7:
```
When you modify ANY file inside `plugins/<name>/`, you MUST also bump the `"version"` in that plugin's `plugin.json` **and** update the matching version in `.claude-plugin/marketplace.json` before committing.
```
To:
```
When you modify ANY file inside `plugins/<name>/`, you MUST also bump the `"version"` in that plugin's `.claude-plugin/plugin.json` **and** update the matching version in `.claude-plugin/marketplace.json` before committing.
```

- [ ] **Step 2: Update New Plugin Checklist**

Replace lines 22-26:
```markdown
1. `plugins/<name>/plugin.json` — manifest with name, version, description
2. `plugins/<name>/.claude-plugin/plugin.json` — identical copy of the manifest
3. `.claude-plugin/marketplace.json` — add entry with matching version, description, author, source, category, homepage
4. `README.md` — add install command AND plugin description section (in alphabetical position among plugins)
```
With:
```markdown
1. `plugins/<name>/.claude-plugin/plugin.json` — manifest with name, version, description (the only location Claude Code reads)
2. `.claude-plugin/marketplace.json` — add entry with matching version, description, author, source, category, homepage
3. `README.md` — add install command AND plugin description section (in alphabetical position among plugins)
```

- [ ] **Step 3: Update enforcement note**

Change line 28:
```
A pre-commit hook enforces items 1-3. Item 4 (README) is also enforced
```
To:
```
A pre-commit hook enforces items 1-2. Item 3 (README) is also enforced
```

- [ ] **Step 4: Update Shared Scripts section**

Remove the shared scripts section (lines 37-44) entirely since `check-codex.sh` no longer exists and there are no other shared scripts. If other shared scripts exist, keep the section but remove the `check-codex.sh` bullet.

- [ ] **Step 5: Update Repository Structure**

In the structure tree (lines 48-69), remove:
```
    plugin.json          # Manifest with name, version, description
```
And update:
```
      plugin.json        # Copy of manifest (used by plugin loader)
```
To:
```
      plugin.json        # Plugin manifest (the only location Claude Code reads)
```

Also remove:
```
shared/
  scripts/               # Shared scripts symlinked from plugins
```

---

### Task 9: Delete Old Plugins and Shared Scripts

**Files:**
- Delete: `plugins/collaborative-loop/` (entire directory)
- Delete: `plugins/cross-review/` (entire directory)
- Delete: `shared/scripts/check-codex.sh`
- Delete: `shared/scripts/` (if empty)

- [ ] **Step 1: Delete collaborative-loop plugin**

Run: `rm -rf plugins/collaborative-loop`

- [ ] **Step 2: Delete cross-review plugin**

Run: `rm -rf plugins/cross-review`

- [ ] **Step 3: Delete shared scripts**

Run: `rm -f shared/scripts/check-codex.sh && rmdir shared/scripts 2>/dev/null; true`

- [ ] **Step 4: Verify deletions**

Run: `ls plugins/ && ls shared/ 2>/dev/null || echo "shared/ removed"`
Expected: `collaborative-loop` and `cross-review` not listed. `shared/scripts/` gone.

---

### Task 10: Clean Up Root plugin.json Across Existing Plugins

Remove root `plugin.json` from all plugins and fix version mismatches in `.claude-plugin/plugin.json`.

**Files:**
- Delete: `plugins/implementation-prd/plugin.json`
- Delete: `plugins/lsp-setup/plugin.json`
- Delete: `plugins/python-dev/plugin.json`
- Delete: `plugins/typescript-dev/plugin.json`
- Delete: `plugins/unity-dev/plugin.json`
- Modify: `plugins/python-dev/.claude-plugin/plugin.json` (version 1.1.0 -> 1.2.0)
- Modify: `plugins/typescript-dev/.claude-plugin/plugin.json` (version 1.1.0 -> 1.2.0)
- Modify: `plugins/unity-dev/.claude-plugin/plugin.json` (version 1.4.0 -> 1.6.0)

- [ ] **Step 1: Delete root plugin.json files**

Run:
```bash
rm -f plugins/implementation-prd/plugin.json plugins/lsp-setup/plugin.json plugins/python-dev/plugin.json plugins/typescript-dev/plugin.json plugins/unity-dev/plugin.json
```

- [ ] **Step 2: Fix python-dev version**

In `plugins/python-dev/.claude-plugin/plugin.json`, change `"version": "1.1.0"` to `"version": "1.2.0"`.

- [ ] **Step 3: Fix typescript-dev version**

In `plugins/typescript-dev/.claude-plugin/plugin.json`, change `"version": "1.1.0"` to `"version": "1.2.0"`.

- [ ] **Step 4: Fix unity-dev version**

In `plugins/unity-dev/.claude-plugin/plugin.json`, change `"version": "1.4.0"` to `"version": "1.6.0"`.

- [ ] **Step 5: Verify no root plugin.json remains**

Run: `find plugins -maxdepth 2 -name 'plugin.json' -not -path '*/.claude-plugin/*'`
Expected: no output (no root plugin.json files)

- [ ] **Step 6: Verify all .claude-plugin/plugin.json versions match marketplace**

Run:
```bash
for dir in plugins/*/; do
  name=$(basename "$dir")
  pv=$(grep -o '"version"[^"]*"[^"]*"' "$dir/.claude-plugin/plugin.json" 2>/dev/null | grep -o '[0-9.]*' || echo "MISSING")
  mv=$(python -c "import json; d=json.load(open('.claude-plugin/marketplace.json')); print(next((p['version'] for p in d['plugins'] if p['name']=='$name'), 'NOT_FOUND'))")
  echo "$name: plugin=$pv marketplace=$mv $([ '$pv' = '$mv' ] && echo 'OK' || echo 'MISMATCH')"
done
```
Expected: all show matching versions

---

### Task 11: Stage and Commit

- [ ] **Step 1: Review all changes**

Run: `git status`
Expected: new files in `plugins/codex-collaboration/`, modified `.githooks/pre-commit`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, `README.md`, deleted old plugin dirs and root plugin.json files.

- [ ] **Step 2: Stage all changes**

```bash
git add plugins/codex-collaboration/ .claude-plugin/marketplace.json README.md CLAUDE.md .githooks/pre-commit
git add plugins/implementation-prd/.claude-plugin/plugin.json plugins/python-dev/.claude-plugin/plugin.json plugins/typescript-dev/.claude-plugin/plugin.json plugins/unity-dev/.claude-plugin/plugin.json
git rm -r plugins/collaborative-loop plugins/cross-review
git rm shared/scripts/check-codex.sh
git rm plugins/implementation-prd/plugin.json plugins/lsp-setup/plugin.json plugins/python-dev/plugin.json plugins/typescript-dev/plugin.json plugins/unity-dev/plugin.json
```

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
Replace collaborative-loop + cross-review with unified codex-collaboration plugin (v1.0.0)

- Merge two plugins into one with shared domain knowledge layer
- Delegate all Codex interaction to official codex plugin (openai/codex-plugin-cc)
- Remove WSL/MINGW-specific code, bash scripts, manual codex orchestration
- Add bilateral consensus gate (both models must agree before action)
- Align all plugins with official Claude Code plugin structure (.claude-plugin/plugin.json only)
- Fix version mismatches in python-dev, typescript-dev, unity-dev
- Update pre-commit hook to check .claude-plugin/plugin.json
EOF
)"
```
Expected: commit succeeds (pre-commit hook passes)
