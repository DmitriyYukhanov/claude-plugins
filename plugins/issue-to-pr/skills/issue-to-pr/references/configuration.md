# Configuration - `.claude/issue-to-pr/config.md`

Optional per-project settings (YAML frontmatter, optional markdown notes below), read from
`.claude/issue-to-pr/config.md` in the main checkout. That directory holds the plugin's
repository-level state and carries its own `.gitignore` holding `*`, so a teammate without
the plugin installed never sees a file they cannot place and the project's own `.gitignore`
is never edited. (A run's scratch files are separate: they live in the worktree under
`tmp/task-<N>/` and go with it at teardown.) A config left at the pre-2.5 path
(`.claude/issue-to-pr.local.md`) is not read: the run says so once and leaves the file
alone, so move across whatever you want to keep. Every field is optional. With no file, the run works the gate
commands out at Step 6 and pins back the ones that passed.

## Schema

```yaml
---
board:
  url: https://github.com/users/<you>/projects/<N>   # or .../orgs/<org>/projects/<N>
  status_field: Status                                # board's single-select field name (default "Status")
  status_map:                                         # optional; pin exact columns (overrides alias matching)
    in_progress: In Progress                          # column to set when work starts (Step 1)
    in_review: In Review                              # column to set when the PR opens (Step 9)
base_branch: auto            # auto | dev | main | <branch-name>
typecheck_cmd: npm run typecheck
test_cmd: npm test
visual_cmd: npm run visual   # optional; UI/visual verification
smoke_cmd: npm run smoke     # optional; post-merge smoke (v2.0)
checks_timeout: 20           # optional; minutes to wait on pending PR checks (v2.0)
---

Free-form notes for humans can go here; the skill only reads the frontmatter.
```

(A nested `commands:` block with `typecheck` / `test` / `visual` / `smoke` keys is also accepted
as an alias for the top-level `*_cmd` scalars.)

## Field semantics

- **board.url** - the Projects (v2) board for "do the next task" and for choosing which board to
  sync when an issue belongs to several. Omit for pure issue-mode.
- **board.status_field** - name of the board's single-select status field (default `Status`).
  `board-sync.sh` matches the target column (`in_progress` / `in_review`) to the board's actual
  option names with a built-in alias table (e.g. "Doing", "WIP", "Code Review").
- **board.status_map** - optional exact column names for the two touchpoints, for boards whose
  columns fall outside the alias table (localized or unusual names). When set, `preflight.sh`
  emits `STATUS_MAP_IN_PROGRESS` / `STATUS_MAP_IN_REVIEW` and the pipeline passes the value to
  `board-sync.sh --option <name>`, which then matches that column exactly and skips alias
  guessing.
- **base_branch** - `auto` resolves to `dev` if that branch exists (locally or on the remote),
  else `main`. Or pin a branch name. The branch you cut from and the PR target are always this
  same ref.
- **typecheck_cmd / test_cmd / visual_cmd** - the project's commands for the Step 6/8 gates.
  `visual_cmd` is only for UI work.

## Resolution

`preflight.sh` (Step 0) parses this file and reports the commands it names. It is read from
the **main checkout**, where it lives and the only tree certain to exist that early.

A command this file does not name comes back empty, and the run works it out at Step 6 in the
worktree the gates execute in, always as a literal such as `npm test`. A repository whose suite
is genuinely ambiguous, a monorepo with one per package, gets asked about rather than guessed
at, and the answer belongs here. Never invent a command.
