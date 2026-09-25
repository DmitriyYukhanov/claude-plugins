# Claude Plugins Repository

Collection of Claude Code plugins: skills, agents, hooks, and scripts. Issues and PRs live in `DmitriyYukhanov/claude-plugins`.

## Repository hygiene

- `docs/superpowers/` and `.serena/` are local-only and gitignored. Never commit them.
- Stage with explicit paths (`git add <path>`), never `git add -A` or `git add .`.
- Before committing, run `git diff --cached --name-only`; anything under those two directories gets `git restore --staged <path>`.

## Plugin versioning

Any change under `plugins/<name>/` bumps `"version"` in `plugins/<name>/.claude-plugin/plugin.json` and the matching entry in `.claude-plugin/marketplace.json`. The pre-commit hook enforces the bump and its changelog entry only on commits to `main` or `master`, and rejects the two manifests disagreeing on any branch; on a development branch nothing else checks the bump, so bump the version and add the CHANGELOG entry yourself before opening the PR, since GitHub's squash-merge runs no hook.

Semantic Versioning:

- PATCH (x.y.Z): bug fixes, typos, minor documentation tweaks
- MINOR (x.Y.0): new features, skill improvements, prompt changes, non-breaking additions
- MAJOR (X.0.0): breaking changes to skill behavior, major restructuring, removed functionality

## Changelog

Every version bump adds an entry to `plugins/<name>/CHANGELOG.md` in [Keep a Changelog](https://keepachangelog.com/) format (Added, Changed, Deprecated, Removed, Fixed, Security). On `main` the pre-commit hook rejects a bump without one.

Entry rules:

- One short sentence per entry, imperative mood, describing the user-facing outcome: "Add search skill", not "Added search skill".
- No implementation details (step numbers, file names, tool names) and no vague filler ("various improvements").
- Group sub-changes by user-visible outcome. Internal-only changes are not documented.
- Every version header carries an ISO 8601 date: `## [1.2.0] - 2026-04-03`.
- Write the entry as you make the change, not at release time.

Good: "Cross-validation step: each model verifies the other's findings before presenting to user"
Bad: "Cross-validation step (Step 5): after initial triage, each model's findings are verified by the other model before presenting to user, using CONFIRM/REJECT/REFINE verdicts from validation-format.md"

Template for a new plugin:

```markdown
# Changelog

All notable changes to the **<plugin-name>** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - YYYY-MM-DD

### Added
- Initial release description
```

Releases are automatic: a push to `main` that touches `plugins/**` assembles the updated changelogs into a GitHub Release. Never create a release by hand.

## New plugin checklist

A new `plugins/<name>/` directory needs all four. The pre-commit hook checks the manifest, the marketplace entry and the README section on every branch, and the CHANGELOG entry only on a commit to main or master:

1. `plugins/<name>/.claude-plugin/plugin.json`: manifest with name, version, description (the only location Claude Code reads)
2. `plugins/<name>/CHANGELOG.md`: initial `[1.0.0]` entry
3. `.claude-plugin/marketplace.json`: entry with matching version, description, author, source, category, homepage
4. `README.md`: install command and a `### <plugin-name>` section, in alphabetical position

## Git hooks

Tracked hooks live in `.githooks/`. After cloning, run `git config core.hooksPath .githooks`.

## Skill writing

Skill authoring guidance (frontmatter, SKILL.md structure, scripts, subagents, validation) lives in [`docs/skill-creation.md`](docs/skill-creation.md).

## Repository structure

```
plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json        # Plugin manifest (the only location Claude Code reads)
    CHANGELOG.md         # Per-plugin changelog
    skills/              # Skill definitions (SKILL.md files)
    hooks/               # Plugin hooks
    agents/              # Agent definitions (.md files)
    commands/            # Slash commands (legacy; new plugins ship skills instead)
    scripts/             # Shell scripts
skills/
  claude.ai/             # Binary .skill files for the Claude.ai web interface, not Claude Code
.claude-plugin/
  marketplace.json       # Marketplace listing (versions must match plugin.json)
.github/workflows/       # Plugin tests and the auto-release on push to main
.githooks/               # Tracked git hooks (pre-commit enforcement)
docs/
  skill-creation.md      # Skill authoring best practices
  agents/                # Per-repo config the engineering skills read
```

## Agent skills

### Issue tracker

Issues live as GitHub issues in `DmitriyYukhanov/claude-plugins`, driven through the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and one `docs/adr/` at the repo root. See `docs/agents/domain.md`.
