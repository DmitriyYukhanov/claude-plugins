# Step 0 — the config, the base, and the board

Everything here resolves against the **main checkout**, never a worktree. The config is
usually untracked, so a worktree has no copy of it, and on a resume you are standing in one.

## The config file — `.claude/issue-to-pr/config.md`

Optional per-project settings: YAML frontmatter, optional markdown notes below. That
directory holds the plugin's repository-level state and carries its own `.gitignore` whose
**first** rule is `*`, so a teammate without the plugin never sees a file they cannot place
and the project's own `.gitignore` is never edited. Create it that way before writing
anything into it — the friction log and the gate receipt both land there. A run's own files
live beside it under `runs/task-<N>/` and go at cleanup. A config left at the pre-2.5 path
(`.claude/issue-to-pr.local.md`) is not read: say so once and leave the file alone.

```yaml
---
board:
  url: https://github.com/users/<you>/projects/<N>   # or .../orgs/<org>/projects/<N>
  status_map:                                        # optional; pin exact columns
    in_progress: In Progress                         # column to set when work starts (Step 1)
    in_review: In Review                             # column to set when the PR opens (Step 9)
base_branch: auto            # auto | dev | main | <branch-name>
typecheck_cmd: npm run typecheck
test_cmd: npm test
visual_cmd: npm run visual   # optional; UI/visual verification
smoke_cmd: npm run smoke     # optional; post-merge smoke
checks_timeout: 20           # optional; minutes to wait on pending PR checks
---
```

Every field is optional; unknown keys are ignored. A nested `commands:` block with
`typecheck` / `test` / `visual` / `smoke` keys is an accepted alias for the `*_cmd` scalars.
A command the config does not name is worked out at Step 6, in the worktree the gates run
in, always as a literal such as `npm test`. Step 8 prints the block for you to paste and
never writes this file itself. A genuinely ambiguous suite — a monorepo with one per package
— is asked about at Step 4, never guessed at. Never invent a command.

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

Then make the base **resolve locally**, or `git worktree add` hard-stops Step 1 on a base that
is perfectly reachable — a `--single-branch` or `--depth 1` clone has never fetched it. Fetch
the base and the default branch (the one the in-place fallback switches onto):

```bash
git fetch origin --no-prune --quiet "+refs/heads/<BASE>:refs/remotes/origin/<BASE>"
```

`--no-prune` is not optional: a user with `fetch.prune` set would otherwise have their
remote-tracking refs deleted as a side effect of a probe that runs on every task. And fetch
**one refspec per invocation** — `git fetch` fails the whole call if any single refspec names
a ref the remote lacks, so an absent default branch would take the base down with it.

`START_POINT` is `origin/<BASE>` when that ref verifies. Otherwise fall back and say so:
a local `<BASE>` means you are cutting from a branch nothing verified; no ref at all means
Step 1 will stop at `invalid-start-point`, so fetch it or pin a different `base_branch`.

## Claiming the issue

Read `state`, `title` and `assignees` with one `gh issue view`. Assign yourself
(`gh issue edit <N> --add-assignee @me`) only when the issue is unassigned or already yours.
**Assigned to someone else is a hard stop** — say who, and ask before any further work.
Never run a design on an issue somebody else has taken.

## Warnings

Every "say so" above is part of Step 0's answer, including on the runs that then stop for
another reason. Report them; a warning nobody prints is a warning that was never raised.

## The board

Only when the config names `board.url`. It is **best-effort at every step**: any failure is
reported in one line and the run continues. A board hiccup never blocks the pipeline, and
nothing here is worth debugging mid-run.

`gh auth status` must list the `project` scope. Without it, say once that board sync is off
and carry on with plain issues; the fix is `gh auth refresh -s project`. A fine-grained token
prints no scopes line at all — that is unknown, not missing, and board sync is skipped either
way, because `gh` reads the classic line.

Run the whole chain as **one backgrounded command**, so it costs the run no wait:

```bash
item=$(gh api graphql -f query='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){projectItems(first:20){nodes{id project{id url}}}}}}' \
  -F owner=<OWNER> -F repo=<REPO> -F num=<N> \
  --jq '.data.repository.issue.projectItems.nodes[] | select("<BOARD_URL>"=="" or .project.url=="<BOARD_URL>") | "\(.id)\t\(.project.id)"' | head -1)
[ -n "$item" ] || { echo "not on the board"; exit 0; }
opts=$(gh api graphql -f query='query($proj:ID!,$field:String!){node(id:$proj){... on ProjectV2 {field(name:$field){... on ProjectV2SingleSelectField {id options{id name}}}}}}' \
  -F proj="${item#*$'\t'}" -F field=Status \
  --jq '.data.node.field as $f | $f.options[] | "\($f.id)\t\(.name)\t\(.id)"')
```

`opts` empty means the board has no `Status` field at all, which is not the same as a Status
field with no matching column — say which one it was. Otherwise pick the option: `status_map`
pins the exact column name and is authoritative when set; without it match case- and
punctuation-insensitively against the target, where *in progress* also answers to doing,
started, wip, in development, and *in review* to review, reviewing, code review, pr open,
ready for review. Then set it:

```bash
gh api graphql -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$opt}}){projectV2Item{id}}}' \
  -F proj=<PROJECT_ID> -F item=<ITEM_ID> -F field=<FIELD_ID> -F opt=<OPTION_ID>
```

`Done` is never set here: GitHub's own automation moves the card when the PR merges into the
default branch.
