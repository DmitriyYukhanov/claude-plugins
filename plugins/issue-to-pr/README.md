# issue-to-pr

A plugin for Claude Code and Codex that drives a GitHub issue from triage to a merge-ready pull
request through a gated pipeline. The input can be a **bare issue**, a **card on a
GitHub Projects (v2) board**, or a **plain request with no issue yet**; the skill drafts
one first. The PR always links the issue so it auto-closes on merge; board cards advance
as work progresses.

## Installation

Claude Code:

```bash
/plugin marketplace add DmitriyYukhanov/claude-plugins
/plugin install issue-to-pr@dmitriy-claude-plugins
```

Codex (user-wide, across local projects):

```bash
codex plugin marketplace add DmitriyYukhanov/claude-plugins
codex plugin add issue-to-pr@dmitriy-claude-plugins
```

Skip marketplace registration if already configured. After a release, run
`codex plugin marketplace upgrade dmitriy-claude-plugins`, then the same `codex plugin add`
command to install the update. Start a new task to pick up the installed skills.

Git, authenticated `gh` and Bash are required; `skills/setup` §1 checks them and, on Windows,
finds Git for Windows' own `bash.exe`. Per-project settings remain optional.

## Features

### Skill: `run`

Invoked by the model or by you (`/issue-to-pr:run [issue-number | "free text"]
[--tier trivial|standard|complex] [--grill]`). The pipeline runs triage, research, design,
implementation, review, PR, approval-gated merge, and cleanup. Hard gates block forward
progress; everything between them scales to the task.

- **Isolated per task.** Each run cuts its branch inside a dedicated
  `../<repo>-worktrees/issue-<N>` git worktree, so several local agents can drive different
  issues in the same clone without clashing.
- **Scaled by tier.** Trivial, standard or complex (`--tier` overrides). Research depth,
  design machinery (an autonomous design panel for complex work), review level and passes,
  and report length all size to it.
- **Autonomous, one checkpoint max.** Three moments: one batched question mid-run (only if
  something needs your preference), the merge gate, and hard stops. `--grill` spends that first
  moment on `grilling` instead, which works the design in rounds of numbered decisions until
  nothing is left silently assumed. Every other decision it makes itself, logs, and surfaces in
  the report and PR body.
- **Gates.** Design hardening (cross-review or a multi-agent fallback), tests green
  (typecheck + tests, plus visual checks for UI work), and a code-review loop that runs
  until clean; the review level escalates automatically when passes keep finding real bugs.
  Once the diff settles, a last pass builds the change and drives it at its own surface.
- **Beyond a single issue.** A plain request with no number is drafted into an issue and run.
- **A careful merge gate.** Merge happens only on your explicit in-session approval, never on
  the turn the PR opens. The merge script refuses a head the gates never ran against and a review
  requesting changes, and passes `--match-head-commit`, so a commit landing after the diff you
  were shown stops the merge rather than shipping unseen. If GitHub refuses the merge, its own
  message is reported and the run says what to do next.
- **Cleanup and a safety net.** Once the PR is merged it deletes the branch, tears down the
  worktree, and clears the run's files; a merge into anything but the default branch is reported
  as one, since GitHub only closes the issue on the default. An optional smoke check runs on the
  updated base; if it fails, the skill opens a *draft* revert PR, never an automatic rollback.
- **Board sync, gracefully.** Cards advance to *in-progress* at branch cut and *in-review*
  at PR open; `Done` is left to GitHub's merge-time automation. A missing `project` token
  scope degrades to link-only and never blocks the PR.

### Skill: `setup`

Run once before your first task. It checks the shell, Git and GitHub access (`repo`, plus
`project` for board mode), then reports the current host's available capabilities and fallbacks.
It diagnoses setup without changing it. Optional companion installation instructions are
provided on request, for the host you are actually using.

### Configuration (optional)

`.claude/issue-to-pr/config.md` (YAML frontmatter) sets the board URL, base branch, and
typecheck/test/visual/smoke commands. Everything is optional; with no file the run works the
commands out in the worktree where the gates execute, as literals, and prints the block to
paste here once they pass. It never writes this file itself. Two keys serve `--headless` runs
only: `human_paths` is one line of space-separated shell globs, and a diff touching one never
merges unattended (a glob cannot contain a space); `after_merge` is the instruction the run
gives itself after cleanup, usually a deploy skill.

Claude Code and Codex use this same config and state directory; the `.claude` name is retained
for compatibility. There is no separate Codex config to keep in sync.

That directory holds the plugin's state: the config, and one folder per branch with its gate
receipt and gate logs. It ships its own `.gitignore` containing `*`, so none of it reaches
`git status` and your project's `.gitignore` is left alone. Runs keep their state in the main
checkout, never in the worktree, so tearing the worktree down can never trip over it.

Being ignored, the directory is disposable to `git clean -x`. Nothing breaks permanently: the
commands get worked out again, and the next merge asks for one more gate run before it lands.

### Companion skills (optional)

The host supplies the tools; the plugin defines the checks. Review, simplification and runtime
verification apply on both hosts, whether performed through an available skill or directly.
Complex designs use three independent proposals and a parent judge when subagents are available;
otherwise the agent works through those perspectives sequentially and reports that limitation.
No hook or companion plugin is required. See the shared
[capability and fallback table](skills/run/references/companions.md).

## Usage

The skill activates when you ask to pick up a task ("take task 4", "work on issue #7") or
when you describe work that has no issue yet ("fix the flaky login test"). Or via the slash command:

```text
/issue-to-pr:run 4

/issue-to-pr:run "add dark mode to the settings page" --tier standard
```

In Codex, select `issue-to-pr:run` or `issue-to-pr:setup` from the skill picker; CLI/IDE users
can type `$` to select a skill. Pass the issue number and the same flags as above. A request
such as "Use issue-to-pr to work on issue #4" also identifies the plugin and task.

## License

MIT
