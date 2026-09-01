# issue-to-pr

A Claude Code plugin that drives a GitHub issue from triage to a merge-ready pull
request through a gated pipeline. The input can be a **bare issue**, a **card on a
GitHub Projects (v2) board**, or a **plain request with no issue yet**; the skill drafts
one first. The PR always links the issue so it auto-closes on merge; board cards advance
as work progresses.

## Installation

```bash
/plugin install issue-to-pr@dmitriy-claude-plugins
```

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
  the turn the PR opens. The merge script refuses a head the gates never ran against, reads the
  GitHub review itself, and passes `--match-head-commit`, so a commit landing after the diff you
  were shown stops the merge rather than shipping unseen.
- **Cleanup and a safety net.** After a merge into the default branch it deletes the branch,
  tears down the worktree, and clears the run's temp files; on any other base, or one it cannot
  confirm, it keeps them and says so. An optional smoke check runs on the updated base; if it
  fails, the skill opens a *draft* revert PR, never an automatic rollback.
- **Board sync, gracefully.** Cards advance to *in-progress* at branch cut and *in-review*
  at PR open; `Done` is left to GitHub's merge-time automation. A missing `project` token
  scope degrades to link-only and never blocks the PR.

### Skill: `/issue-to-pr:setup`

Run once before your first task. It checks the one hard requirement (`gh`, logged in, with
the `repo` scope, plus `project` for board mode), reports which companion skills are present
and what each missing one would sharpen, and prints the install command for each. It changes
nothing on its own: the commands are yours to run. It also names what Claude Code already
registers — `code-review`, `simplify`, `/deep-research` — so nobody hunts an install that
does not exist.

### Configuration (optional)

`.claude/issue-to-pr/config.md` (YAML frontmatter) sets the board URL, base branch, and
typecheck/test/visual/smoke commands. Everything is optional; with no file the run works the
commands out in the worktree where the gates execute, as literals, and prints the block to
paste here once they pass. It never writes this file itself.

That directory holds the plugin's state - the config, gate receipts, and each run's files under
`runs/task-<N>/`. It ships its own `.gitignore` containing `*`, so none of it reaches
`git status` and your project's `.gitignore` is left alone. A config at the older
`.claude/issue-to-pr.local.md` path is not read; the run says so once and leaves it for you.

Being ignored, the directory is disposable to `git clean -x`. Nothing breaks permanently: the
commands get worked out again, and the next merge asks for one more gate run before it lands.

### Companion skills (optional)

Three of the sharpest tools need no install: Claude Code's own `code-review` reviews the
diff at Step 7, its `simplify` is one of the two lenses of the Step 8 gate, and its `verify`
closes that step by driving the built change. The CLI registers all three, so no marketplace
is involved.

`/deep-research` is built in too, but it is yours rather than the pipeline's: Claude Code only
starts it when you type it. Step 2 always uses an `Explore` subagent. For the deeper sweep, run
`/deep-research` in your own turn and hand the summary in.

Optional companions that sharpen specific steps: `superpowers:*`,
`/cross-review` (from `codex-collaboration`), `humanizer`, `mattpocock-skills` (whose
`grilling` is what `--grill` runs), and `ponytail` (whose `ponytail-review` is the Step 8
deletion lens, and whose lazy mode shapes the design from Step 3 on). Each is used if
installed, with an inline fallback otherwise.

## Usage

The skill activates when you ask to pick up a task ("take task 4", "work on issue #7") or
when you describe work that has no issue yet ("fix the flaky login test"). Or via the slash command:

```text
/issue-to-pr:run 4

/issue-to-pr:run "add dark mode to the settings page" --tier standard
```

## License

MIT
