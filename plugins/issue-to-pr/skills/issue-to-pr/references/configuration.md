# Configuration — `.claude/issue-to-pr.local.md`

Optional per-project settings, read from `.claude/issue-to-pr.local.md` in the repo root
(the `plugin-settings` `.claude/<plugin>.local.md` convention: YAML frontmatter, optional
markdown notes below). Every field is optional. With no file, the skill auto-detects
commands and runs by the issue argument.

## Schema

```yaml
---
board:
  url: https://github.com/users/<you>/projects/<N>   # or .../orgs/<org>/projects/<N>
  status_field: Status                                # board's single-select field name (default "Status")
  status_map:                                         # optional; omit to use smart matching
    in_progress: In Progress                          # column to set when work starts (Step 1)
    in_review: In Review                              # column to set when the PR opens (Step 9)
base_branch: auto            # auto | dev | main | <branch-name>
typecheck_cmd: npm run typecheck
test_cmd: npm test
visual_cmd: npm run visual   # optional; UI/visual verification
---

Free-form notes for humans can go here; the skill only reads the frontmatter.
```

## Field semantics

- **board.url** — the Projects (v2) board for "do the next task" and for deciding which
  board to sync when an issue belongs to several. Omit for pure issue-mode.
- **board.status_field** — name of the board's single-select status field. Defaults to
  `Status`.
- **board.status_map** — explicit column names for the two pipeline touchpoints. Omit and
  the skill matches by name (see below).
- **base_branch** — `auto` resolves to `dev` if that branch exists, else `main`. Or pin a
  branch name. The branch you cut from and the PR target are always this same ref.
- **typecheck_cmd / test_cmd / visual_cmd** — the project's commands for the Step 6/8 gates.
  `visual_cmd` is only needed for UI work.

## Auto-detect (when a command is not configured)

Resolve in this order; stop at the first hit:

1. **`package.json` `scripts`** — `test_cmd` from a `test` script; `typecheck_cmd` from
   `typecheck` / `type-check` / `tsc`; `visual_cmd` from `visual` / `e2e` / `playwright`.
2. **Other manifests** — `Makefile` targets (`test`, `typecheck`), `cargo test` /
   `cargo check` (Cargo.toml), `pytest` / `mypy` (pyproject.toml / setup.cfg), `go test ./...`
   (go.mod).
3. **`CLAUDE.md` / `README.md`** — a documented "Run / test" section.

If none of these yields a test or typecheck command, ask the user once for it (and suggest
they save it to `.claude/issue-to-pr.local.md`). Never invent a command.

## Status-name smart matching (when `status_map` is omitted)

Case-insensitive, against the board's actual option names:

- **in_progress** ← `in progress`, `in-progress`, `doing`, `wip`, `started`
- **in_review** ← `in review`, `review`, `ready for review`, `pr open`, `code review`

No confident match and nothing in `status_map` → ask once which column to use, or skip the
status write with a note (never block the pipeline on it).
