---
name: agent-teams
description: >
  Set up and orchestrate Claude Code agent teams - multiple Claude Code instances
  working together with shared tasks, inter-agent messaging, and centralized
  management. Use when the user wants to (1) create or start an agent team for
  parallel work, (2) configure agent team settings like display mode or teammate
  mode or permissions, (3) coordinate teammates for code review or debugging or
  feature development or research, (4) understand when to use agent teams vs
  subagents, (5) troubleshoot agent team issues. Triggers include mentions of
  "agent team", "team of agents", "parallel agents", "teammates", "split pane",
  "tmux teammates", "delegate mode", "spawn teammates", or wanting multiple
  Claude instances collaborating.
---

# Agent Teams

Coordinate multiple Claude Code instances working together. One session acts as team lead, spawning and coordinating teammates that work independently in their own context windows and communicate directly with each other.

## Quick Setup

### 1. Enable the feature (experimental, disabled by default)

Add to `settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

Or set the environment variable directly:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

### 2. Start a team

Tell Claude to create an agent team with a natural language prompt describing the task and team structure:

```
Create an agent team to review PR #142. Spawn three reviewers:
- One focused on security implications
- One checking performance impact
- One validating test coverage
```

Claude creates the team, spawns teammates, coordinates work, and synthesizes results.

## When to Use Agent Teams vs Subagents

| Criteria | Use Subagents | Use Agent Teams |
|----------|--------------|-----------------|
| Workers need to talk to each other | No | Yes |
| Task is focused, result-only matters | Yes | No |
| Complex work requiring discussion | No | Yes |
| Token budget is tight | Yes (lower cost) | No (higher cost) |
| Workers need shared task list | No | Yes |

Best use cases for agent teams:
- **Research and review**: parallel investigation of different aspects
- **New modules/features**: each teammate owns a separate piece
- **Debugging competing hypotheses**: test theories in parallel
- **Cross-layer coordination**: frontend, backend, and tests each owned by different teammates

## Display Modes

Two modes available. Set in `settings.json` or via CLI flag.

**In-process** (default fallback): All teammates in your main terminal.
- `Shift+Up/Down` to select a teammate
- `Enter` to view a teammate's session, `Escape` to interrupt
- `Ctrl+T` to toggle task list

**Split panes**: Each teammate gets its own pane (requires tmux or iTerm2).
- Click into a pane to interact directly

```json
{ "teammateMode": "in-process" }
```

Or per-session:

```bash
claude --teammate-mode in-process
```

The default `"auto"` uses split panes if already in tmux, otherwise in-process.

For split pane prerequisites and troubleshooting, see [references/configuration.md](references/configuration.md).

## Key Controls

### Specify teammates and models

```
Create a team with 4 teammates to refactor these modules in parallel.
Use Sonnet for each teammate.
```

### Require plan approval

```
Spawn an architect teammate to refactor the authentication module.
Require plan approval before they make any changes.
```

The lead reviews and approves/rejects plans autonomously. Influence with criteria: "only approve plans that include test coverage."

### Delegate mode

Press `Shift+Tab` to cycle into delegate mode. Restricts the lead to coordination-only (no code changes), forcing it to delegate all implementation to teammates.

### Talk to teammates directly

Each teammate is a full Claude Code session. Message any teammate directly to give instructions, ask questions, or redirect.

### Shut down and clean up

```
Ask the researcher teammate to shut down
```

When done:

```
Clean up the team
```

Always use the lead to clean up. Shut down all teammates first.

## Best Practices

1. **Give teammates enough context** in spawn prompts - they don't inherit the lead's conversation history
2. **Size tasks appropriately** - self-contained units producing clear deliverables (a function, test file, or review)
3. **Aim for 5-6 tasks per teammate** to keep everyone productive
4. **Avoid file conflicts** - break work so each teammate owns different files
5. **Start with research/review tasks** if new to agent teams
6. **Monitor and steer** - check in on progress, redirect as needed

## Prompt Templates

### Parallel code review

```
Create an agent team to review PR #142. Spawn three reviewers:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them each review and report findings.
```

### Competing hypotheses debugging

```
Users report the app exits after one message instead of staying connected.
Spawn 5 agent teammates to investigate different hypotheses. Have them talk to
each other to try to disprove each other's theories, like a scientific debate.
Update the findings doc with whatever consensus emerges.
```

### Multi-angle exploration

```
I'm designing a CLI tool that helps developers track TODO comments across
their codebase. Create an agent team to explore this from different angles: one
teammate on UX, one on technical architecture, one playing devil's advocate.
```

## Troubleshooting

- **Teammates not appearing**: Press `Shift+Down` to cycle through; check tmux is installed for split mode
- **Too many permission prompts**: Pre-approve common operations in permission settings before spawning
- **Teammates stopping on errors**: Check output and give additional instructions, or spawn a replacement
- **Lead implements instead of delegating**: Say "Wait for your teammates to complete their tasks before proceeding" or use delegate mode
- **Orphaned tmux sessions**: `tmux ls` then `tmux kill-session -t <session-name>`

For full configuration details, architecture, and limitations, see [references/configuration.md](references/configuration.md).
