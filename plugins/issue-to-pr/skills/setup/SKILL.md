---
name: setup
description: >-
  Check issue-to-pr prerequisites in Claude Code or Codex: shell, GitHub access, optional
  config and available companion skills. Use when the user asks what issue-to-pr needs
  or hits a setup failure. Diagnose without installing anything.
---

# setup — what the pipeline needs, and what would sharpen it

**You never run an install command here.** Print them and let the human decide: installing a
plugin changes their environment for every project.

## 1. Runtime prerequisites

Check `git --version`, `gh --version`, and `bash --version`. On Windows use Git for Windows'
`bin/bash.exe` (discover it from the Git installation), not a WSL launcher returned by PATH.
Verify `git` and `gh` are reachable inside that Bash too: the bundled scripts call both. Reuse
that executable for script calls.

Missing Git or Bash → report the missing executable and stop. Missing `gh` → point at
<https://cli.github.com/>.

## 2. GitHub access

Run `gh auth status`. Three outcomes:

- **Not installed** → point at <https://cli.github.com/> and stop; nothing else matters yet.
- **Installed, not logged in** → `gh auth login`.
- **Logged in** → read the `Token scopes:` line. `repo` is required; `project` only for board
  mode (card sync at Steps 1 and 7), and without it the run still works on plain issues and says
  once that board sync is off. Add one with `gh auth refresh -s project`. No scopes line at all
  means a fine-grained token, not a broken login: report the scopes as unknown rather than
  missing, and say board sync is skipped either way, since `gh` reads the classic line.

Report the account and the scopes you actually saw, not a summary of them.

## 3. The companions

What each one buys the run is in `../run/references/companions.md`, together with the inline
fallback — that table is the only copy. Inspect the current session's skills and tools, and use
`claude plugin list` only in Claude Code or `codex plugin list` only in Codex when needed.
Report the available capabilities and which ones will use a fallback. A plugin listed as
available is not necessarily installed, enabled or usable in this session. Never describe
another host's built-ins as present or suggest installing a Claude-only command in Codex.

For a missing optional companion, give installation instructions only if requested, verifying
them against that host's CLI help or official documentation. Never imply the pipeline is broken
without optional companions.

## 4. The optional config

`.claude/issue-to-pr/config.md` in the repo, gitignored, every field optional. Without it the run
works the gate commands out at Step 5 and prints a block for you to paste. Worth setting up front
only when the repo has a board, a non-default base branch, or a test command a newcomer would
guess wrong. Schema: `../run/references/configuration.md`. Never write this file from here — it
can be tracked and shared, so what lands in it is the user's decision.

## 5. Report

One short block: runtime and GitHub access, available companions and fallbacks, config status.
Finish with the single next thing to do, or say the setup is complete and they can select the
plugin's `run` skill with an issue number. Use invocation syntax from the current host.
