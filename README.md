# Custom Claude Code plugins and skills

[![Last release](https://img.shields.io/github/release-date/DmitriyYukhanov/claude-plugins?label=last%20release)](https://github.com/DmitriyYukhanov/claude-plugins/releases)
[![Last commit](https://img.shields.io/github/last-commit/DmitriyYukhanov/claude-plugins)](https://github.com/DmitriyYukhanov/claude-plugins/commits/main)
[![License: MIT](https://img.shields.io/github/license/DmitriyYukhanov/claude-plugins)](./LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin%20marketplace-d97757)](https://code.claude.com/docs/en/discover-plugins)

Personal collection of Claude Code plugins and skills for structured, high-quality development workflows. Augments the official Claude plugins marketplace.

## Installation

Add this marketplace to Claude Code:

```bash
/plugin marketplace add DmitriyYukhanov/claude-plugins
```

Then install plugins by name. The `@` suffix is the marketplace name `dmitriy-claude-plugins` (from this repo's `marketplace.json`), not the GitHub path:

```bash
/plugin install issue-to-pr@dmitriy-claude-plugins
/plugin install codex-collaboration@dmitriy-claude-plugins
```

You can also run `/plugin` to browse and install interactively.

## Plugins

| Plugin | Category | What it does |
|--------|----------|--------------|
| [agent-teams](#agent-teams) | productivity | Orchestrate multiple Claude Code instances working in parallel with shared tasks and messaging |
| [codex-collaboration](#codex-collaboration) | workflow | Cross-model Claude + Codex collaboration: drive/validate loops and parallel dual review |
| [humanizer](#humanizer) | writing | Remove AI-writing patterns from English and Russian text, with automatic language detection |
| [implementation-prd](#implementation-prd) | productivity | Turn feature requests into build-ready spec bundles with PRDs, contracts, schemas, and test plans |
| [issue-to-pr](#issue-to-pr) | workflow | Drive a GitHub issue or Project board card through a worktree-isolated, gated pipeline to an approved, merged PR |
| [learning-guide](#learning-guide) | development | Generate self-contained, interactive HTML learning guides that work offline |
| [lsp-setup](#lsp-setup) | development | Detect project languages and set up LSP servers and Claude Code LSP plugins |
| [python-dev](#python-dev) | development | Python development workflow: architecture, coding guidelines, pytest patterns, and a review agent |
| [tg-alerts](#tg-alerts) | operations | Add Telegram error and alert notifications to any project, with guided setup and reference implementations |
| [tg-voice](#tg-voice) | operations | Transcribe Telegram voice messages automatically with local Whisper |
| [typescript-dev](#typescript-dev) | development | TypeScript development workflow: architecture, coding guidelines, testing patterns, and a review agent |
| [unity-dev](#unity-dev) | development | Unity C# workflow: architecture, coding guidelines, tests, CLI builds and runs, and review agents |

## Plugin details

### agent-teams

Set up and orchestrate Claude Code agent teams with:
- Auto-activating skill for agent team setup and coordination
- Teams vs subagents decision guide
- Display modes (in-process and split pane)
- Prompt templates for code review, debugging, and exploration
- Configuration reference with architecture, permissions, and limitations

[View documentation](./plugins/agent-teams/README.md)

### codex-collaboration

Cross-model collaboration between Claude and Codex with two workflows:

- **collaborative-loop** — Sequential drive/validate/act cycles. Claude analyzes, Codex validates each finding, both models must agree before any action is taken. Iterates until approved or max rounds.
- **cross-review** — Parallel dual review. Both Claude and Codex review independently. Findings confirmed by reviewer agreement, cross-validation, or evidence research are auto-applied each round; only genuinely inconclusive disagreements surface for user decision.

The default Codex model is `gpt-5.6-sol` (requires Codex CLI 0.143.0 or newer); if unavailable it falls back to `gpt-5.5`, then `gpt-5.4`.

**Requires** the [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc). Install it first:
1. `/plugin marketplace add openai/codex-plugin-cc`
2. `/plugin install codex@openai-codex`
3. `/codex:setup` to verify

[View documentation](./plugins/codex-collaboration/README.md)

### humanizer

Auto-routing EN + RU humanizer for Claude Code that removes signs of AI-generated writing:
- Auto-detects language by Cyrillic ratio (≥60 % → RU, ≤10 % → EN, otherwise asks)
- English ruleset — vendored from [blader/humanizer](https://github.com/blader/humanizer), 29 patterns from Wikipedia AI Cleanup
- Russian ruleset — vendored from [ilyautov/humanizer-ru](https://github.com/ilyautov/humanizer-ru), 44 patterns with hard bans and triple-pass audit
- Explicit overrides ("humanize as English" / "обработай как русский") and mixed-text handling
- Optional voice calibration from a writing sample

Distinct from the Claude.ai-only `humanizer.skill` listed below — this is a Claude Code plugin with auto-routing.

[View documentation](./plugins/humanizer/README.md)

### implementation-prd

Implementation-ready spec bundle authoring with:
- Auto-activating skill for turning requests into build-ready spec bundles
- Templates for product, system, and feature PRDs, contracts, schemas, data models, and test plans
- `init-spec-bundle.sh` scaffolding script for standard 4-file bundles
- Quality gates checklist and cross-file alignment rules
- Worked example from a real desktop app project

[View documentation](./plugins/implementation-prd/README.md)

### issue-to-pr

Drive a single GitHub issue from triage to a merge-ready pull request through a gated pipeline:

- One flow for a **bare issue** or a **card on a GitHub Projects (v2) board** — Step 0 resolves the input and decides whether board-status sync applies.
- Each run works in its own `../<repo>-worktrees/issue-<N>` git worktree, so concurrent local agents on different issues never clash.
- Hard gates that block forward progress: design hardening (cross-review or a multi-agent fallback), tests green (typecheck + tests, plus visual checks for UI), and a code-review loop that runs until clean or five passes.
- Scales the work to the task's **tier** (trivial through epic): research depth, design (an autonomous design panel for complex work), review level, and report length all size to the issue — and it asks **at most one batched question**, deciding everything else itself and surfacing those decisions in the report and PR.
- Takes on more than a single issue: a plain request with no number is drafted into an issue and run; a from-scratch, **epic**-sized request is decomposed into dependency-ordered child issues, each shipped through its own gated PR; and after a merge, an optional smoke check on the base opens a *draft* revert PR (never an automatic rollback) if the change broke something.
- A robust merge gate: it reads any GitHub review first (a changes-requested review or an unresolved thread reroutes as a change request), and a behind-base PR is updated and re-checked automatically — but re-merged without asking again only when the base merge left the PR's own diff untouched.
- Opens the PR and stops; once you approve it in-session it squash-merges, then deletes the branch, tears down the worktree, and clears the run's temp artifacts (keeping anything important).
- The PR auto-links the issue (`Closes #N`) to close on merge; board cards advance to *in-progress* at branch cut and *in-review* at PR open, with `Done` left to GitHub's merge-time automation.
- Graceful by default — missing the `project` token scope degrades to link-only, and a failed status write never blocks the PR.
- The `/issue-to-pr:tune` skill reads the friction log that runs leave behind and turns it into batched improvements to the pipeline.
- Optional `.claude/issue-to-pr.local.md` for board URL, base branch, and test commands (auto-detected when unset); companion skills (`superpowers:*`, `/deep-research`, `/cross-review`, `humanizer`, `/code-review`) used if installed, with inline fallbacks otherwise.

[View documentation](./plugins/issue-to-pr/README.md)

### learning-guide

Generate self-contained, offline-first, interactive HTML learning guides for any artifact:

- **`analyze`** skill — reads input artifact(s) (codebase, planning session, refactor plan, generic doc), writes a `tour-spec.json` describing sections, embedded sources, cross-refs, quizzes, and external link maps. Hands off to render.
- **`render`** skill — runs the bundled zero-dependency Node renderer to produce `index.html` plus launcher scripts. Idempotent for generated artifacts; re-runnable from the shell after hand-edits to the spec.
- **`learning-guide`** entry-point skill — explains the flow and dispatches to the right step.

**Requires** Node.js on PATH. No `npm install` step.

[View documentation](./plugins/learning-guide/README.md)

### lsp-setup

Set up LSP (Language Server Protocol) for Claude Code projects with:
- Auto-detection of project languages from source files and project markers
- Automatic installation of language server binaries and Claude Code LSP plugins
- Environment-aware setup (MINGW, WSL, macOS, Linux) with gotcha handling
- State machine workflow that resumes from any point (install → restart → validate)
- Post-restart validation confirming LSP operations work per language
- Supports all 12 official LSP plugins (C#, Python, TypeScript/JS, Go, Rust, Java, Kotlin, Lua, PHP, Ruby, Swift, C/C++)

[View documentation](./plugins/lsp-setup/README.md)

### python-dev

Python development workflow with:
- `/python-dev` command for end-to-end workflows (discovery → architecture → implementation → review → testing)
- Architecture patterns, protocols, and Mermaid diagrams
- PEP 8-aligned coding guidelines and type-hint best practices
- pytest-based testing patterns, fixtures, mocking, and coverage guidance
- Python-specific review agent that can delegate to general feature review

[View documentation](./plugins/python-dev/README.md)

### tg-alerts

Add Telegram error/alert notifications to any project:
- Interactive 7-phase setup: @BotFather bot creation, chat ID discovery, code generation, integration, testing
- Reference implementations for Python async (FastAPI), Python sync (Django/Flask), and Node.js/TypeScript (Express/NestJS)
- Built-in deduplication, HTML formatting, graceful failure handling, and fire-and-forget delivery

[View documentation](./plugins/tg-alerts/README.md)

### tg-voice

Transcribe Telegram voice messages using local Whisper:
- PostToolUse hook automatically transcribes `.oga` voice messages downloaded via the Telegram channel plugin
- `/voice-to-text-config` skill for guided setup: faster-whisper installation, model download, and end-to-end verification
- Configurable model size via `WHISPER_MODEL` env var (default: `base`)

**Requires:** `faster-whisper` (`pip install faster-whisper`) and the [Telegram channel plugin](https://github.com/anthropics/claude-code).

[View documentation](./plugins/tg-voice/README.md)

### typescript-dev

TypeScript development workflow with:
- `/typescript-dev` command for full-stack TypeScript workflows
- Architecture design for modules, interfaces, and test stubs with Mermaid diagrams
- TypeScript coding guidelines, async patterns, and framework-aware checks
- Testing patterns for unit, integration, and E2E tests (Jest/Vitest style)
- TypeScript-specific review agent that can delegate to general feature review

[View documentation](./plugins/typescript-dev/README.md)

### unity-dev

Unity C# development workflow with:
- `/unity-dev` skill orchestrating the full workflow: discovery, architecture, implementation, review, testing
- `unity-run` skill for CLI execution (builds, tests, method execution, asset imports) with Unity installation auto-detection and log monitoring
- `/unity-tests-run` skill running Unity Test Framework tests via CLI batchmode
- Architecture design with Mermaid diagrams, C# coding guidelines following Microsoft conventions, EditMode/PlayMode test patterns
- Unity-specific review, simplification, and test-runner agents

[View documentation](./plugins/unity-dev/README.md)

## Claude.ai Skills

Skills for the Claude.ai web interface (not Claude Code). Install via the Skills section in Claude.ai settings.

### humanizer

Rewrites AI-generated text to sound more natural and human. Converted from [blader/humanizer](https://github.com/blader/humanizer) for Claude.ai usage.

**File:** `skills/claude.ai/humanizer.skill`

## License

MIT
