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

Invoked by the model or by you (`/issue-to-pr:run [issue-number | next | "free text"]
[--tier trivial|standard|complex|epic] [--drill]`). The pipeline runs triage, research, design,
implementation, review, PR, approval-gated merge, and cleanup. Hard gates block forward
progress; everything between them scales to the task.

- **Isolated per task.** Each run cuts its branch inside a dedicated
  `../<repo>-worktrees/issue-<N>` git worktree, so several local agents can drive different
  issues in the same clone without clashing.
- **Scaled by tier.** Triage evidence assigns a tier from trivial to epic (`--tier`
  overrides). Research depth, design machinery (an autonomous design panel for complex
  work), review level and passes, the security overlay, and report length all size to it.
- **Autonomous, one question max.** The skill contacts you at three moments: one
  batched question mid-run (only if something genuinely needs your preference), the merge
  gate, and hard stops. Pass `--drill` and it adds a fourth on purpose: the `drill` tutor
  walks you through the design before anything is built, and whatever you dispute there is
  folded into that same batched question. It makes every other decision itself, logs it, and surfaces it in
  the report and PR body.
- **Gates.** Design hardening (cross-review or a multi-agent fallback), tests green
  (typecheck + tests, plus visual checks for UI work), and a code-review loop that runs
  until clean; the review level escalates automatically when passes keep finding real bugs.
- **Beyond a single issue.** A plain request with no number is drafted into an issue and
  run. An epic-sized request is decomposed into dependency-ordered child issues, each
  shipped through its own gated PR. `next` picks the top card from the board.
- **A careful merge gate.** Merge happens only on your explicit in-session approval, never
  on the turn the PR opens. What a script can prove, a script proves: the merge refuses a head
  the gates never ran against, reads the GitHub review itself and stops on a requested change or
  an unread one, and merges with `--match-head-commit`, so a commit landing after the diff you
  were shown stops the merge instead of shipping unseen.
- **Cleanup and a safety net.** After the merge it deletes the branch, tears down the
  worktree, and clears temp artifacts (salvaging important files first). An optional smoke
  check runs on the updated base; if it fails, the skill opens a *draft* revert PR, never
  an automatic rollback.
- **Board sync, gracefully.** Cards advance to *in-progress* at branch cut and *in-review*
  at PR open; `Done` is left to GitHub's merge-time automation. A missing `project` token
  scope degrades to link-only and never blocks the PR.

### Skill: `/issue-to-pr:setup`

Run once before your first task. It checks the one hard requirement (`gh`, logged in, with
the `repo` scope, plus `project` for board mode), reports which companion skills are present
and what each missing one would sharpen, and prints the install command for each. It changes
nothing on its own: the commands are yours to run. It also notes that `code-review` and
`simplify` are built into Claude Code and need no install at all.

### Skill: `/issue-to-pr:tune`

Runs leave one-line notes in a friction log when a step fought back. This skill batches
the log into concrete improvements to the pipeline's own scripts and prompts, shows the
evidence, and applies the edits on your approval.

### Configuration (optional)

`.claude/issue-to-pr/config.md` (YAML frontmatter) sets the board URL, base branch, and
typecheck/test/visual/smoke commands. Everything is optional; with no file the run works the
commands out in the worktree where the gates execute, as literals, and prints the block to
paste here once they pass. It never writes this file itself.

That directory holds the plugin's repository-level state - the config, gate receipts, the
friction log - and it ships its own `.gitignore` containing `*`, so none of it reaches
`git status` and your project's `.gitignore` is left alone. (A run's own files -- design notes, state, gate logs --
live there too, under `runs/task-<N>/`, so nothing a run writes lands in your project tree
where test discovery or a bundler would pick it up.) A config at the
older `.claude/issue-to-pr.local.md` path is not read; the run says so once and leaves it for
you to move.

Because the directory is ignored, `git clean -x` treats it as disposable and removes it along
with the config and the gate receipt. Nothing breaks permanently: the commands get worked out
again, but the next merge asks for one more gate run before it will land.

### Companion skills (optional)

Two of the sharpest tools need no install: Claude Code's own `code-review` reviews the
diff at Step 7, and its `simplify` is one of the two lenses of the Step 8 gate. The CLI
registers both, so no marketplace is involved. (An earlier version of this README claimed
the pipeline could not reach `code-review` because copies ship `disable-model-invocation`.
That is a plugin command of the same name, not the built-in skill, and the claim cost
Step 7 a real reviewer for several releases.)

Optional companions that sharpen specific steps: `superpowers:*`, `/deep-research`,
`/cross-review` (from `codex-collaboration`), `humanizer`, and `ponytail` (whose
`ponytail-review` is the Step 8 deletion lens, and whose lazy mode shapes the design from
Step 4 on). Each is used if installed, with an inline fallback otherwise.

## Usage

The skill activates when you ask to pick up a task ("take task 4", "work on issue #7",
"do the next task") or when you describe work that has no issue yet ("fix the flaky login
test"). Or via the slash command:

```text
/issue-to-pr:run 4

/issue-to-pr:run next

/issue-to-pr:run "add dark mode to the settings page" --tier standard
```

## License

MIT
