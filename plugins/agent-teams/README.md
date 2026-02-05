# agent-teams

A Claude Code plugin for setting up and orchestrating agent teams - multiple Claude Code instances working together with shared tasks, inter-agent messaging, and coordination.

## Installation

```bash
/plugin install agent-teams@DmitriyYukhanov/claude-plugins
```

## Features

### Skill: `agent-teams`

Auto-activating reference knowledge for orchestrating Claude Code agent teams. Triggers on mentions of agent teams, parallel agents, teammates, split panes, delegate mode, or multi-instance collaboration.

Covers:
- **Quick Setup** - Enable the experimental feature and start your first team
- **Teams vs Subagents** - Decision guide for when to use each approach
- **Display Modes** - In-process (default) and split pane (tmux/iTerm2)
- **Key Controls** - Model selection, plan approval, delegate mode, direct messaging
- **Best Practices** - Task sizing, context, file ownership, monitoring
- **Prompt Templates** - Ready-to-use prompts for code review, debugging, exploration
- **Troubleshooting** - Common issues and fixes
- **Configuration Reference** - Architecture, permissions, tokens, task management, limitations

## Usage

The skill activates automatically when you mention agent teams or related concepts:

```bash
# Start an agent team
Create an agent team to review PR #142 with 3 reviewers

# Configure display mode
Set up split pane mode for agent teams

# Troubleshoot
My agent teammates aren't appearing
```

## License

MIT
