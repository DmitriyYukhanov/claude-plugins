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

### Skill: `issue-to-pr`

Invoked by the model or by you (`/issue-to-pr [issue-number | next | "free text"]
[--tier trivial|standard|complex|epic]`). The pipeline runs triage, research, design,
implementation, review, PR, approval-gated merge, and cleanup. Hard gates block forward
progress; everything between them scales to the task.

- **Isolated per task.** Each run cuts its branch inside a dedicated
  `../<repo>-worktrees/issue-<N>` git worktree, so several local agents can drive different
  issues in the same clone without clashing.
- **Scaled by tier.** Triage evidence assigns a tier from trivial to epic (`--tier`
  overrides). Research depth, design machinery (an autonomous design panel for complex
  work), review level and passes, the security overlay, and report length all size to it.
- **Autonomous, one question max.** The skill contacts you at exactly three moments: one
  batched question mid-run (only if something genuinely needs your preference), the merge
  gate, and hard stops. It makes every other decision itself, logs it, and surfaces it in
  the report and PR body.
- **Gates.** Design hardening (cross-review or a multi-agent fallback), tests green
  (typecheck + tests, plus visual checks for UI work), and a code-review loop that runs
  until clean; the review level escalates automatically when passes keep finding real bugs.
- **Beyond a single issue.** A plain request with no number is drafted into an issue and
  run. An epic-sized request is decomposed into dependency-ordered child issues, each
  shipped through its own gated PR. `next` picks the top card from the board.
- **A careful merge gate.** Merge happens only on your explicit in-session approval, never
  on the turn the PR opens. GitHub reviews are read first: a changes-requested review or an
  unresolved thread reroutes into the change-request path with full re-gating. A
  behind-base PR is updated and re-checked automatically.
- **Cleanup and a safety net.** After the merge it deletes the branch, tears down the
  worktree, and clears temp artifacts (salvaging important files first). An optional smoke
  check runs on the updated base; if it fails, the skill opens a *draft* revert PR, never
  an automatic rollback.
- **Board sync, gracefully.** Cards advance to *in-progress* at branch cut and *in-review*
  at PR open; `Done` is left to GitHub's merge-time automation. A missing `project` token
  scope degrades to link-only and never blocks the PR.

### Skill: `/issue-to-pr:tune`

Runs leave one-line notes in a friction log when a step fought back. This skill batches
the log into concrete improvements to the pipeline's own scripts and prompts, shows the
evidence, and applies the edits on your approval.

### Configuration (optional)

`.claude/issue-to-pr.local.md` (YAML frontmatter) sets the board URL, base branch, and
typecheck/test/visual/smoke commands. Everything is optional; with no file the skill
auto-detects commands from the project. Auto-detected commands that passed get pinned back
into the config after a successful run.

### Companion skills (optional)

Optional companions that sharpen specific steps: `superpowers:*`, `/deep-research`,
`/cross-review` (from `codex-collaboration`), `humanizer`, and `/code-review`. Each is
used if installed, with an inline fallback otherwise. `/code-review` commonly ships
`disable-model-invocation`, which blocks the pipeline from calling it mid-run regardless
of install state — the adversarial-subagent fallback is the realistic default for Step 7.

## Usage

The skill activates when you ask to pick up a task ("take task 4", "work on issue #7",
"do the next task") or when you describe work that has no issue yet ("fix the flaky login
test"). Or via the slash command:

```text
/issue-to-pr 4

/issue-to-pr next

/issue-to-pr "add dark mode to the settings page" --tier standard
```

## License

MIT
