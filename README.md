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

## License

MIT