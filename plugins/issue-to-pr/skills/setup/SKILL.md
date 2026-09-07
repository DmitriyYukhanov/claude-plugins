---
name: setup
description: >-
  Check what issue-to-pr needs and what would sharpen it, then hand over the exact install
  commands. Use when the user asks what issue-to-pr needs, or hits a Step 0 failure about
  gh auth or a missing scope. Verifies gh auth and its scopes, reports which companion
  skills are present and what each missing one would sharpen, and explains the optional
  config file. Prints commands for the user to run; installs nothing itself.
user-invocable: true
---

# setup — what the pipeline needs, and what would sharpen it

**You never run an install command here.** Print them and let the human decide: installing a
plugin changes their environment for every project.

## 1. The hard requirement: `gh`

Run `gh auth status`. Three outcomes:

- **Not installed** → point at <https://cli.github.com/> and stop; nothing else matters yet.
- **Installed, not logged in** → `gh auth login`.
- **Logged in** → read the `Token scopes:` line. `repo` is required; `project` only for board
  mode (card sync at Steps 1 and 7), and without it the run still works on plain issues and says
  once that board sync is off. Add one with `gh auth refresh -s project`. No scopes line at all
  means a fine-grained token, not a broken login: report the scopes as unknown rather than
  missing, and say board sync is skipped either way, since `gh` reads the classic line.

Report the account and the scopes you actually saw, not a summary of them.

## 2. What ships in Claude Code already

`code-review` (Step 6), `simplify` and `verify` (both Step 6) are registered by the CLI itself —
nothing to install, no marketplace involved. An official plugin is also called `code-review`; it
is a different thing. `deep-research` needs no install either, for a different reason: Claude Code
only starts it when the user types it, so the pipeline can never call it, and Step 2 uses its own
`Explore` subagent instead.

## 3. The companions

What each one buys the run is in `../run/references/companions.md`, together with the inline
fallback it degrades to — that table is the only copy. Run `claude plugin list`, report every row
below as **present** or **missing**, and for a missing one give the one line it sharpens plus its
command. Never imply the pipeline is broken without them.

| Companion | Install |
|---|---|
| `ponytail` | `/plugin marketplace add DietrichGebert/ponytail` then `/plugin install ponytail@ponytail` |
| `superpowers` | `/plugin marketplace add anthropics/claude-plugins-official` then `/plugin install superpowers@claude-plugins-official` |
| `humanizer` | `/plugin install humanizer@dmitriy-claude-plugins` |
| `mattpocock-skills` | `/plugin marketplace add anthropics/claude-plugins-official` then `/plugin install mattpocock-skills@claude-plugins-official` |
| `codex-collaboration` | Codex first: `/plugin marketplace add openai/codex-plugin-cc`, `/plugin install codex@openai-codex`, `/codex:setup`. Then `/plugin install codex-collaboration@dmitriy-claude-plugins` |

## 4. The optional config

`.claude/issue-to-pr/config.md` in the repo, gitignored, every field optional. Without it the run
works the gate commands out at Step 5 and prints a block for you to paste. Worth setting up front
only when the repo has a board, a non-default base branch, or a test command a newcomer would
guess wrong. Schema: `../run/references/configuration.md`. Never write this file from here — it
can be tracked and shared, so what lands in it is the user's decision.

## 5. Report

One short block: `gh` and its scopes, what is built in, present companions on one line, missing
ones with what each buys and its command, config status. Finish with the single next thing to do,
or say the setup is complete and they can run `/issue-to-pr:run <issue>`.
