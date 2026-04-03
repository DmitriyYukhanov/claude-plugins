# Claude Plugins Repository

Collection of Claude Code plugins: skills, agents, hooks, commands, and scripts.

## Plugin Version Bumping (MANDATORY)

When you modify ANY file inside `plugins/<name>/`, you MUST also bump the `"version"` in that plugin's `.claude-plugin/plugin.json` **and** update the matching version in `.claude-plugin/marketplace.json` before committing. A pre-commit hook enforces both — commits without a version bump or with mismatched marketplace versions will be rejected.

**Semantic Versioning (follow Keep a Changelog):**
- **PATCH** (x.y.Z) — bug fixes, typo corrections, minor documentation tweaks
- **MINOR** (x.Y.0) — new features, skill improvements, prompt changes, non-breaking additions
- **MAJOR** (X.0.0) — breaking changes to skill behavior, major restructuring, removed functionality

**Examples:**
- Fixed a typo in a skill → PATCH (1.1.0 → 1.1.1)
- Rewrote a prompt template, added new sections → MINOR (1.1.0 → 1.2.0)
- Removed a skill, changed plugin interface → MAJOR (1.2.0 → 2.0.0)

## New Plugin Checklist (MANDATORY)

When creating a NEW plugin (new `plugins/<name>/` directory), you MUST complete ALL of these:

1. `plugins/<name>/.claude-plugin/plugin.json` — manifest with name, version, description (the only location Claude Code reads)
2. `.claude-plugin/marketplace.json` — add entry with matching version, description, author, source, category, homepage
3. `README.md` — add install command AND plugin description section (in alphabetical position among plugins)

A pre-commit hook enforces items 1-2. Item 3 (README) is also enforced — commits introducing a new plugin directory without a corresponding README.md entry will be rejected.

## Git Hooks

This repo uses `.githooks/` for tracked git hooks. After cloning, run:
```bash
git config core.hooksPath .githooks
```

## Skill Frontmatter

Use only the fields recognized by Claude Code. The canonical reference is https://docs.anthropic.com/en/docs/claude-code/skills.

Key fields: `name`, `description`, `argument-hint`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `model`, `effort`, `context`, `agent`, `hooks`, `paths`, `shell`.

**`argument-hint`** (string) shows during `/` autocomplete to indicate expected arguments. Example: `argument-hint: "[patch|minor|major] [--silent]"`. Do NOT use `arguments` (array) — that is not a recognized Claude Code field and does nothing.

**`description`** is truncated at 250 characters in the skill listing. Front-load the key use case.

## Repository Structure

```
plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json        # Plugin manifest (the only location Claude Code reads)
    skills/              # Skill definitions (SKILL.md files)
    hooks/               # Plugin hooks
    agents/              # Agent definitions (.md files)
    commands/            # Slash commands
    scripts/             # Utility shell scripts (may contain symlinks to shared/)
skills/
  claude.ai/             # Skills for the Claude.ai web interface (not Claude Code)
    *.skill              # Binary skill files installable via Claude.ai settings
.claude-plugin/
  marketplace.json       # Plugin marketplace listing (versions must match plugin.json)
docs/                    # Documentation and plans
  skill-creation.md      # Skill authoring best practices
.githooks/               # Git hooks (pre-commit version enforcement)
```
