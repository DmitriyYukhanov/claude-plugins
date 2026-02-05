# Dmitriy's Claude Code plugins and skills

Personal collection of Claude plugins and skills.

## Installation

Add this marketplace to Claude Code:

```bash
/plugin marketplace add DmitriyYukhanov/claude-plugins
```

Then install plugins:

```bash
/plugin install unity-dev
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