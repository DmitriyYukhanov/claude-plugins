# Claude Plugins Repository

Collection of Claude Code plugins: skills, agents, hooks, commands, and scripts.

## Repository Hygiene (MANDATORY)

`docs/superpowers/` and `.serena/` are **local-only artifacts** — never commit them. They are excluded by `.gitignore`. The Superpowers brainstorming/planning workflow writes specs and plans into `docs/superpowers/specs/` and `docs/superpowers/plans/` for the developer's reference; those files stay on the local machine. Tool caches (`.serena/`, similar) also stay local.

Before every commit, run `git diff --cached --name-only` and confirm no path under `docs/superpowers/` or `.serena/` appears. If one does, abort and unstage with `git restore --staged <path>`. Use targeted `git add <path>` rather than `git add -A` / `git add .` to avoid accidentally staging artifacts.

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

## Changelog (MANDATORY)

Every plugin has a `CHANGELOG.md` in its root directory (`plugins/<name>/CHANGELOG.md`). When you bump a plugin version, you MUST also add a changelog entry. The pre-commit hook enforces this — commits with a version bump but no changelog update will be rejected.

**Format:** [Keep a Changelog](https://keepachangelog.com/) with these categories:
- **Added** — new skills, commands, agents, features
- **Changed** — modifications to existing behavior, prompt rewrites
- **Deprecated** — features that will be removed in a future version
- **Removed** — features removed in this version
- **Fixed** — bug fixes, typo corrections
- **Security** — vulnerability patches

**Changelog style:**
- Each entry should be **one short sentence** describing the user-facing outcome, not the implementation detail
- Good: "Cross-validation step — each model verifies the other's findings before presenting to user"
- Bad: "Cross-validation step (Step 5) — after initial triage, each model's findings are verified by the other model before presenting to user, using CONFIRM/REJECT/REFINE verdicts from validation-format.md"
- Merge related entries — don't list every file or sub-change separately when they serve a single purpose
- Use imperative mood: "Add search skill" not "Added search skill"

**Changelog gotchas — do NOT:**
- Write vague entries like "various improvements" or "bug fixes" — be specific about what changed
- Pad entries with implementation details (step numbers, file names, tool names) — describe WHAT changed for the user, not HOW it was implemented
- List every sub-change as a separate entry — group them by user-visible outcome
- Use commit messages as changelog entries — changelogs are for users, commits are for developers
- Forget the date — every version header MUST include the ISO 8601 date: `## [1.2.0] - 2026-04-03`
- Mix user-facing and internal changes — only document what affects plugin users
- Backfill changelog after the fact from memory — write entries as you make changes, not at release time

**Changelog template for new plugins:**
```markdown
# Changelog

All notable changes to the **<plugin-name>** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - YYYY-MM-DD

### Added
- Initial release description
```

**Release automation:** On push to `main` that touches `plugins/**`, a GitHub Action assembles a combined changelog from all updated plugins and creates a GitHub Release. That is the whole pipeline — it sends no notifications anywhere. You do NOT need to create releases manually; just keep the changelogs accurate.

## New Plugin Checklist (MANDATORY)

When creating a NEW plugin (new `plugins/<name>/` directory), you MUST complete ALL of these:

1. `plugins/<name>/.claude-plugin/plugin.json` — manifest with name, version, description (the only location Claude Code reads)
2. `plugins/<name>/CHANGELOG.md` — initial changelog with `[1.0.0]` entry
3. `.claude-plugin/marketplace.json` — add entry with matching version, description, author, source, category, homepage
4. `README.md` — add install command AND plugin description section (in alphabetical position among plugins)

A pre-commit hook enforces items 1-3. Item 4 (README) is also enforced — commits introducing a new plugin directory without a corresponding README.md entry will be rejected.

## Git Hooks

This repo uses `.githooks/` for tracked git hooks. After cloning, run:
```bash
git config core.hooksPath .githooks
```

## Skill Writing Guidelines

All skill authoring guidance — frontmatter fields, SKILL.md structure, scripts, subagents, validation — lives in [`docs/skill-creation.md`](docs/skill-creation.md).

## Repository Structure

```
plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json        # Plugin manifest (the only location Claude Code reads)
    CHANGELOG.md         # Per-plugin changelog (Keep a Changelog format)
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
.github/
  workflows/
    release-notify.yml   # Auto-release on push to main
docs/                    # Documentation and plans
  skill-creation.md      # Skill authoring best practices
.githooks/               # Git hooks (pre-commit version enforcement)
```
