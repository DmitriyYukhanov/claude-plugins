# agent-dispatch

Label a GitHub issue `agent` and your own machine picks it up. A tick every three minutes runs
`/issue-to-pr:run N --headless` under your own Claude Code or Codex login; the run's question and
its "ready to merge" arrive as comments on the issue, and your reply there, or on the PR, starts
the next run. Windows, macOS and Linux.

## How it works

Each tick starts at most one run:

1. **Replies first.** An issue waiting on you (`agent:waiting` or `agent:review`) with a new
   comment of yours since the run parked.
2. **Then the queue.** The oldest open issue labelled `agent` by you, oldest first within a repo;
   repos are tried in the order `repos.conf` lists them.

The tick sets `agent:running`, starts the run and waits for it. The run itself parks the issue at
`agent:waiting` (it has a question), `agent:review` (a PR waits for your `merge`), or closes it by
merging. A run that ends without doing either is marked `agent:failed` with a comment pointing at
its log on your machine; the log itself never leaves it.

Only you count: an `agent` label someone else applied, or a comment someone else wrote, starts
nothing. The same goes for edits: if someone else changes the title or body after you label the
issue `agent`, it waits until you label it `agent` again, even if a run has parked it since.
Everything is posted from your own GitHub account, so GitHub will not notify you about it; setup
prints a saved search to watch instead.

## Install

```
/plugin install agent-dispatch@dmitriy-claude-plugins
```

or, in Codex, `codex plugin add agent-dispatch@dmitriy-claude-plugins`. It needs
[issue-to-pr](../issue-to-pr/README.md) 9.4.0 or newer in every host your repos use. Then run
`/agent-dispatch:setup`: it checks the machine and prints the repo list, labels, saved search and
scheduler entry to install. It installs nothing itself.

## `~/.agent-dispatch/`

- `repos.conf`: one repo per line, `<main checkout path> | claude|codex | trivial|standard|complex|none`.
  The last field is the `--auto-merge` threshold.
- `logs/`: `tick.log`, and one log per run.
- `paused`: created when a CLI errors out (usually logged out or out of allowance). No run starts
  until you delete it. Create it yourself to stop dispatching: disabling or uninstalling the plugin
  leaves the scheduled tick running.
- `lock/`: the run in progress. A tick that died leaves it behind; the next tick stops what is
  left of that run and marks the issue failed.

## Limits

One run at a time, on one machine. A run is stopped after four hours. On Windows, install
PowerShell with `winget install Microsoft.PowerShell` rather than from the Store: processes the
Store build starts cannot be stopped with the rest of the run. If Windows policy blocks the job
object the launcher needs to hold a run, no run starts at all, and the tick reports it as a
failure. On macOS and Linux a process that detaches into its own session escapes the stop; none
of the tested CLIs does. The check for edits runs when the tick picks the issue, so an edit that
lands in the few seconds before the run reads the issue still gets through.
