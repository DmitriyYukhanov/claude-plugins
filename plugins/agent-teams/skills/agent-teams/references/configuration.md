# Agent Teams - Configuration & Architecture Reference

## Table of Contents

- [Architecture](#architecture)
- [Split Pane Setup](#split-pane-setup)
- [Permissions](#permissions)
- [Context and Communication](#context-and-communication)
- [Token Usage](#token-usage)
- [Task Management](#task-management)
- [Storage Locations](#storage-locations)
- [Limitations](#limitations)

## Architecture

An agent team consists of:

| Component | Role |
|-----------|------|
| **Team lead** | Main Claude Code session that creates the team, spawns teammates, coordinates work |
| **Teammates** | Separate Claude Code instances working on assigned tasks |
| **Task list** | Shared list of work items teammates claim and complete |
| **Mailbox** | Messaging system for inter-agent communication |

## Split Pane Setup

Split pane mode requires **tmux** or **iTerm2**.

### tmux

Install through your system's package manager:
- macOS: `brew install tmux`
- Ubuntu/Debian: `sudo apt install tmux`
- See https://github.com/tmux/tmux/wiki/Installing for other platforms

Note: tmux has known limitations on certain operating systems and traditionally works best on macOS. Using `tmux -CC` in iTerm2 is the suggested entrypoint.

### iTerm2

1. Install the `it2` CLI: https://github.com/mkusaka/it2
2. Enable the Python API: iTerm2 > Settings > General > Magic > Enable Python API

### Display mode settings

```json
{
  "teammateMode": "auto"
}
```

Options:
- `"auto"` (default): Uses split panes if already in tmux, in-process otherwise
- `"in-process"`: All teammates in main terminal
- `"tmux"`: Split-pane mode, auto-detects tmux vs iTerm2

Per-session override:

```bash
claude --teammate-mode in-process
```

Split-pane mode is NOT supported in: VS Code integrated terminal, Windows Terminal, or Ghostty.

## Permissions

- Teammates start with the lead's permission settings
- If lead runs with `--dangerously-skip-permissions`, all teammates do too
- After spawning, you can change individual teammate modes
- You cannot set per-teammate modes at spawn time

To reduce permission prompt interruptions, pre-approve common operations in permission settings before spawning teammates.

## Context and Communication

Each teammate has its own context window. When spawned, a teammate loads:
- CLAUDE.md files from working directory
- MCP servers
- Skills
- The spawn prompt from the lead

The lead's conversation history does NOT carry over.

### Communication mechanisms

- **Automatic message delivery**: Messages delivered automatically to recipients
- **Idle notifications**: Teammate notifies lead when finished
- **Shared task list**: All agents see task status and claim available work
- **message**: Send to one specific teammate
- **broadcast**: Send to all teammates (use sparingly - costs scale with team size)

## Token Usage

Agent teams use significantly more tokens than a single session. Each teammate has its own context window, and usage scales with the number of active teammates.

Worth the extra tokens for: research, review, new feature work.
More cost-effective with single session: routine tasks.

## Task Management

Tasks have three states: **pending**, **in progress**, **completed**.

Tasks can depend on other tasks. A pending task with unresolved dependencies cannot be claimed until dependencies are completed.

### Assignment modes

- **Lead assigns**: Tell the lead which task to give to which teammate
- **Self-claim**: Teammates pick up next unassigned, unblocked task after finishing

Task claiming uses file locking to prevent race conditions.

The system manages task dependencies automatically - when a teammate completes a task, blocked tasks unblock without manual intervention.

Tip: Having 5-6 tasks per teammate keeps everyone productive and lets the lead reassign work if someone gets stuck.

## Storage Locations

- **Team config**: `~/.claude/teams/{team-name}/config.json`
- **Task list**: `~/.claude/tasks/{team-name}/`

The team config contains a `members` array with each teammate's name, agent ID, and agent type. Teammates can read this file to discover other team members.

## Limitations

Current experimental limitations:

- **No session resumption with in-process teammates**: `/resume` and `/rewind` do not restore in-process teammates. After resuming, the lead may message teammates that no longer exist. Tell the lead to spawn new ones.
- **Task status can lag**: Teammates sometimes fail to mark tasks completed, blocking dependent tasks. Check manually and update if needed.
- **Shutdown can be slow**: Teammates finish current request/tool call before shutting down.
- **One team per session**: Clean up current team before starting a new one.
- **No nested teams**: Only the lead can manage the team. Teammates cannot spawn their own teams.
- **Lead is fixed**: Cannot promote a teammate or transfer leadership.
- **Permissions set at spawn**: All teammates start with lead's permission mode.
- **Split panes require tmux or iTerm2**: In-process mode works in any terminal.

CLAUDE.md files work normally - teammates read them from their working directory.
