# Custom Claude Code plugins and skills

Personal collection of Claude Code plugins and skills for structured, high-quality development workflows. Augments the official Claude plugins marketplace.

## Installation

Add this marketplace to Claude Code:

```bash
/plugin marketplace add DmitriyYukhanov/claude-plugins
```

Then install the plugins you want to use:

```bash
/plugin install agent-teams
/plugin install codex-collaboration
/plugin install humanizer
/plugin install implementation-prd
/plugin install learning-guide
/plugin install lsp-setup
/plugin install python-dev
/plugin install tg-alerts
/plugin install tg-voice
/plugin install typescript-dev
/plugin install unity-dev
```

You can also install individual plugins directly, for example:

```bash
/plugin install python-dev@DmitriyYukhanov/claude-plugins
/plugin install typescript-dev@DmitriyYukhanov/claude-plugins
```

## Highlights

| Plugin | What it does |
|--------|-------------|
| [codex-collaboration](#codex-collaboration) | Cross-model Claude + Codex collaboration — sequential drive/validate loops and parallel dual review |
| [implementation-prd](#implementation-prd) | Turn feature requests into build-ready spec bundles with PRDs, contracts, schemas, and test plans |
| [agent-teams](#agent-teams) | Orchestrate multiple Claude Code instances working in parallel with shared tasks and messaging |
| [tg-alerts](#tg-alerts) | Add Telegram error/alert notifications to any project — guided setup with reference implementations |
| [tg-voice](#tg-voice) | Auto-transcribe Telegram voice messages using local Whisper via PostToolUse hook |

## All Plugins

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
- **cross-review** — Parallel dual review. Both Claude and Codex review independently, findings are cross-validated and triaged, disagreements surfaced for user decision.

**Requires** the [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc). Install it first:
1. `/plugin marketplace add openai/codex-plugin-cc`
2. `/plugin install codex@openai-codex`
3. `/codex:setup` to verify

[View skill documentation](./plugins/codex-collaboration/skills/collaborative-loop/SKILL.md)

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

[View skill documentation](./plugins/lsp-setup/skills/lsp-setup/SKILL.md)

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

[View skill documentation](./plugins/tg-alerts/skills/tg-alerts/SKILL.md)

### tg-voice

Transcribe Telegram voice messages using local Whisper:
- PostToolUse hook automatically transcribes `.oga` voice messages downloaded via the Telegram channel plugin
- `/voice-to-text-config` skill for guided setup: faster-whisper installation, model download, and end-to-end verification
- Configurable model size via `WHISPER_MODEL` env var (default: `base`)

**Requires:** `faster-whisper` (`pip install faster-whisper`) and the [Telegram channel plugin](https://github.com/anthropics/claude-code).

[View plugin](./plugins/tg-voice/)

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
- `/unity-dev` command for full workflow orchestration
- Architecture design with Mermaid diagrams
- C# coding guidelines following Microsoft conventions
- EditMode/PlayMode testing patterns
- Unity-specific code review agent
- Code simplification agent

[View documentation](./plugins/unity-dev/README.md)

## Claude.ai Skills

Skills for the Claude.ai web interface (not Claude Code). Install via the Skills section in Claude.ai settings.

### humanizer

Rewrites AI-generated text to sound more natural and human. Converted from [blader/humanizer](https://github.com/blader/humanizer) for Claude.ai usage.

**File:** `skills/claude.ai/humanizer.skill`

## License

MIT
