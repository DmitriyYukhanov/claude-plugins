---
name: setup
description: >-
  Check what issue-to-pr needs and what would sharpen it, then hand the user the exact
  install commands. Verifies gh auth and its scopes, reports which companion skills are
  present and which step each missing one would improve, and explains the optional config
  file. Prints commands for the user to run; installs nothing itself.
when_to_use: When the user runs /issue-to-pr:setup, asks what issue-to-pr needs, or hits a
  preflight failure about gh auth or a missing scope.
argument-hint: ""
user-invocable: true
---

# setup — what the pipeline needs, and what would sharpen it

The pipeline runs standalone. One thing is genuinely required, everything else only makes a
step better, and the run tells you when it fell back. This skill is the one place that says
all of it at once, before the first run rather than in the middle of one.

**You never run an install command here.** Print them and let the human decide. Installing a
plugin changes their environment for every project, which is not a call a setup report makes.

## 1. The hard requirement: `gh`

Run `gh auth status`. Three outcomes:

- **Not installed** → point at <https://cli.github.com/> and stop; nothing else matters yet.
- **Installed, not logged in** → `gh auth login`.
- **Logged in** → read the `Token scopes:` line. `repo` is required; `project` only for board
  mode (`next`, and card sync at Steps 1 and 9), and without it the run still works on plain
  issues and says once that board sync is off. Add one with `gh auth refresh -s project`.
  No scopes line at all means a fine-grained token, not a broken login, and `gh auth refresh`
  does not apply to one. Report the scopes as unknown rather than missing. On a repo with a
  board, add that board sync will be skipped anyway: `preflight.sh` and `board-sync.sh` both
  read that classic line, so a fine-grained token holding real project access still reads as
  missing to them. Under-warning here defeats the point of running this before the first task.

Report the account and the scopes you actually saw, not a summary of them.

## 2. What ships in Claude Code already

`code-review` (Step 7) and `simplify` (Step 8) are registered by the CLI itself. There is
nothing to install and no marketplace involved, and an official plugin also called
`code-review` is a different thing. Say they are present, so nobody goes looking.

## 3. The companions

Run `claude plugin list` and read what is installed and enabled. For each row below, report
**present** or **missing**; for a missing one, say in one line what it buys and print the
command. Never imply the pipeline is broken without them.

| Companion | Buys you | Install |
|---|---|---|
| `ponytail` | Lazy mode from Step 4 on, so over-engineering is prevented rather than reviewed; its `ponytail-review` is one of the two Step 8 lenses | `/plugin marketplace add DietrichGebert/ponytail` then `/plugin install ponytail@ponytail` |
| `superpowers` | Brainstorming, written plans, TDD discipline and systematic debugging at Steps 3–6, plus the done-claims rule that holds for the whole run | `/plugin marketplace add anthropics/claude-plugins-official` then `/plugin install superpowers@claude-plugins-official` |
| `humanizer` | Step 9–10 prose that does not read like a machine wrote it | `/plugin install humanizer@dmitriy-claude-plugins` |
| `drill` | `--drill` runs: the tutor walks you through the design at Step 4.5, before it is built | `/plugin marketplace add timini/drill-me` then `/plugin install drill@drill-me` |
| `codex-collaboration` | `/cross-review`, a second model critiquing the design at Step 4 | Codex first: `/plugin marketplace add openai/codex-plugin-cc`, `/plugin install codex@openai-codex`, `/codex:setup`. Then `/plugin install codex-collaboration@dmitriy-claude-plugins` |
| `/deep-research` | Step 3 research on external topics. Codebase questions go to a forked research subagent either way, so this is the smaller half | Comes from your own setup or another plugin |

`../run/references/companions.md` carries the same list with the inline
fallback each one degrades to. If a row here and a row there disagree, that file wins.

## 4. The optional config

`.claude/issue-to-pr/config.md` in the repo, gitignored, every field optional. Without it the
run works the gate commands out at Step 6 and prints a block for you to paste. Worth setting
up front only when the repo has a board, a non-default base branch, or a test command a
newcomer would guess wrong. Schema: `../run/references/configuration.md`.

Never write this file from here. It can be tracked and shared, so what lands in it is the
user's decision.

## 5. Report

One short block: `gh` and its scopes, what is built in, present companions on one line,
missing ones with what each buys and its command, config status. Finish with the single
next thing to do, or say the setup is complete and they can run `/issue-to-pr:run <issue>`.
