# Step 0 — the config, the base, and claiming the issue

## The config file — `.claude/issue-to-pr/config.md`

Optional per-project settings in YAML frontmatter. Before writing anything into
`.claude/issue-to-pr/`, give that directory its own `.gitignore` whose **first** rule is `*`, never
touching the project's own. The gate receipt lands there, and a run's files under `runs/task-<N>/` —
that path is `<RUN_DIR>`, and cleanup takes it.

```yaml
---
board:
  url: https://github.com/users/<you>/projects/<N>   # or .../orgs/<org>/projects/<N>
  status_map: {in_progress: …, in_review: …}         # optional; pin exact columns - R/board.md
base_branch: auto            # auto | dev | main | <branch-name>
typecheck_cmd: npm run typecheck
test_cmd: npm test
visual_cmd: npm run visual   # optional; UI/visual verification
smoke_cmd: npm run smoke     # optional; post-merge smoke
checks_timeout: 20           # optional; minutes to wait on pending PR checks
---
```

Every field is optional; unknown keys are ignored. Never invent a command. A `commands:` block was
an accepted alias before 7.0.0 and is not read now: if you see one, say so rather than silently
working the commands out again.

## Resolving the base

`base_branch` names it outright, or `auto` works it out. `auto` trusts **origin** and nothing
else: a local `dev` whose remote counterpart was deleted after a merge still looks like a
trunk and would silently become the branch point.

Ask read-only, and spell the ref in full — `git ls-remote origin refs/heads/dev`, because
`--heads origin dev` also matches `release/dev`. Three outcomes, three answers:

| `ls-remote` | base | say |
|---|---|---|
| answered, `dev` is there | `dev` | nothing |
| answered, `dev` is gone | the repo's default branch | warn if a **local** `dev` exists: origin has none, pin `base_branch` if that is wrong |
| could not reach origin | `refs/remotes/origin/dev` if it exists, else the default branch | warn either way — a stale tracking ref may name a branch deleted upstream |

Then make the base **resolve locally**, or `git worktree add` hard-stops Step 1 on a base that is
perfectly reachable — a `--single-branch` or `--depth 1` clone has never fetched it. Fetch the base
and the default branch, the one the in-place fallback switches onto:

```bash
git fetch origin --no-prune --quiet "+refs/heads/<BASE>:refs/remotes/origin/<BASE>"
```

`--no-prune` is not optional: with `fetch.prune` set, a probe that runs on every task would delete
the user's remote-tracking refs. Fetch **one refspec per invocation** — `git fetch` fails the whole
call if any refspec names a ref the remote lacks.

`START_POINT` is `origin/<BASE>` when that ref verifies. Otherwise fall back and say so: a local
`<BASE>` means you are cutting from a branch nothing verified; no ref at all means Step 1 will stop
at `invalid-start-point`, so fetch it or pin a different `base_branch`.

## Claiming the issue

Read `state`, `title` and `assignees` with one `gh issue view`. Assign yourself
(`gh issue edit <N> --add-assignee @me`) only when the issue is unassigned or already yours.
**Assigned to someone else is a hard stop** — say who, and ask before any further work.

Every warning above is part of Step 0's answer, even on a run that then stops for another reason.
