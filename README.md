# Custom Claude Code plugins and skills

Personal collection of Claude Code plugins and skills for structured, high-quality development workflows. Augments the official Claude plugins marketplace.

## Installation

Add this marketplace to Claude Code:

```bash
/plugin marketplace add DmitriyYukhanov/claude-plugins
```

Then install the plugins you want to use:

```bash
/plugin install unity-dev
/plugin install python-dev
/plugin install typescript-dev
/plugin install agent-teams
/plugin install cross-review
/plugin install collaborative-loop
/plugin install implementation-prd
/plugin install lsp-setup
```

You can also install individual plugins directly, for example:

```bash
/plugin install python-dev@DmitriyYukhanov/claude-plugins
/plugin install typescript-dev@DmitriyYukhanov/claude-plugins
```

## Available Plugins

### unity-dev

Unity C# development workflow with:
- `/unity-dev` command for full workflow orchestration
- Architecture design with Mermaid diagrams
- C# coding guidelines following Microsoft conventions
- EditMode/PlayMode testing patterns
- Unity-specific code review agent
- Code simplification agent

[View documentation](./plugins/unity-dev/README.md)

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

### typescript-dev

TypeScript development workflow with:
- `/typescript-dev` command for full-stack TypeScript workflows
- Architecture design for modules, interfaces, and test stubs with Mermaid diagrams
- TypeScript coding guidelines, async patterns, and framework-aware checks
- Testing patterns for unit, integration, and E2E tests (Jest/Vitest style)
- TypeScript-specific review agent that can delegate to general feature review

[View documentation](./plugins/typescript-dev/README.md)

### agent-teams

Set up and orchestrate Claude Code agent teams with:
- Auto-activating skill for agent team setup and coordination
- Teams vs subagents decision guide
- Display modes (in-process and split pane)
- Prompt templates for code review, debugging, and exploration
- Configuration reference with architecture, permissions, and limitations

[View documentation](./plugins/agent-teams/README.md)

### cross-review

Cross-review workflow between Claude and Codex CLI for:
- Dual review of plans, architecture, design docs, and code
- Review/triage/fix loops with explicit disagreement handling
- Dynamic skill discovery for applying agreed fixes
- Multi-round review process with cleanup of intermediate artifacts

[View skill documentation](./plugins/cross-review/skills/cross-review/SKILL.md)

### collaborative-loop

Sequential AI-to-AI collaboration loop with:
- One model drives (writes/fixes), the other reviews with structured verdicts
- Iterates until APPROVED, MINOR_ISSUES, or max rounds reached
- Stall detection with mediator escalation for persistent disagreements
- Supports Claude or Codex as driver via `--driver` flag
- Artifact-type-aware prompts for code, plans, architecture, and design docs

[View skill documentation](./plugins/collaborative-loop/skills/collaborative-loop/SKILL.md)

### implementation-prd

Implementation-ready spec bundle authoring with:
- Auto-activating skill for turning requests into build-ready spec bundles
- Templates for product, system, and feature PRDs, contracts, schemas, data models, and test plans
- `init-spec-bundle.sh` scaffolding script for standard 4-file bundles
- Quality gates checklist and cross-file alignment rules
- Worked example from a real desktop app project

[View documentation](./plugins/implementation-prd/README.md)

## Claude.ai Skills

Skills for the Claude.ai web interface (not Claude Code). Install via the Skills section in Claude.ai settings.

### humanizer

Rewrites AI-generated text to sound more natural and human. Converted from [blader/humanizer](https://github.com/blader/humanizer) for Claude.ai usage.

**File:** `skills/claude.ai/humanizer.skill`

## License

MIT
