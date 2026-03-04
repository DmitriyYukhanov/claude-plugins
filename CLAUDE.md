# Claude Plugins Repository

Collection of Claude Code plugins: skills, agents, hooks, and commands.

## Plugin Version Bumping (MANDATORY)

When you modify ANY file inside `plugins/<name>/`, you MUST also bump the `"version"` in that plugin's `plugin.json` **and** update the matching version in `.claude-plugin/marketplace.json` before committing. A pre-commit hook enforces both — commits without a version bump or with mismatched marketplace versions will be rejected.

**Semantic Versioning (follow Keep a Changelog):**
- **PATCH** (x.y.Z) — bug fixes, typo corrections, minor documentation tweaks
- **MINOR** (x.Y.0) — new features, skill improvements, prompt changes, non-breaking additions
- **MAJOR** (X.0.0) — breaking changes to skill behavior, major restructuring, removed functionality

**Examples:**
- Fixed a typo in a skill → PATCH (1.1.0 → 1.1.1)
- Rewrote a prompt template, added new sections → MINOR (1.1.0 → 1.2.0)
- Removed a skill, changed plugin interface → MAJOR (1.2.0 → 2.0.0)

## Git Hooks

This repo uses `.githooks/` for tracked git hooks. After cloning, run:
```bash
git config core.hooksPath .githooks
```

## Repository Structure

```
plugins/
  <plugin-name>/
    plugin.json          # Manifest with name, version, description
    skills/              # Skill definitions (SKILL.md files)
    hooks/               # Plugin hooks
    agents/              # Agent definitions
    commands/            # Slash commands
skills/
  claude.ai/             # Skills for the Claude.ai web interface (not Claude Code)
    *.skill              # Binary skill files installable via Claude.ai settings
.claude-plugin/
  marketplace.json       # Plugin marketplace listing (versions must match plugin.json)
docs/                    # Documentation and plans
.githooks/               # Git hooks (pre-commit version enforcement)
```
