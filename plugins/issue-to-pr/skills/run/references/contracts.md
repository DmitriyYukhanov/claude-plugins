# Script contracts

The pipeline's git/gh mechanics live in tested bash scripts under
`${CLAUDE_PLUGIN_ROOT}/scripts/`, not in prose. Each script owns the *mechanics*; the model owns
*judgment*. Every human-judgment stop is an exit code, never a silent script decision.

## How the scripts talk back

- **Output:** each script prints `KEY=VALUE` lines on stdout, lists comma-joined; hints go to
  stderr.
- **Uniform exit codes:** `0` proceed · `2` stop-and-ask (reason in `STOP_REASON=`, a hint on
  stderr) · `3` sandbox/permission fallback (do it in place) · `4` degraded (could not parse/reach
  something — do that part by hand). Exceptions noted per script below.
- Carry the config values you resolved at Step 0; never re-read the config from inside the
  worktree, which has no copy of it.

On a stop, `worktree.sh` emits the raw failure alongside `STOP_REASON`: `ADD_ERROR`,
`DIRTY_FILES`, `PUSH_ERROR`, `MERGE_ERROR`. Report whichever is present verbatim; it is the only
place the underlying git/gh message survives. A stop is never a fix: report the error rather than
working around it.

## worktree.sh — worktree + merge mechanics (SAFETY-CRITICAL)

`worktree.sh ensure  <N> --branch <b> --start-point <ref>` — Step 1. Creates / resumes /
reattaches the `../<repo>-worktrees/issue-<N>` worktree. Keys: `STATE`
(`CREATED|REATTACHED|RESUMED`), `WT_PATH` and `BRANCH` always, `ORIGINAL_ROOT` and `PR_STATE`
on some paths and not others: read what it printed rather than assuming a key is there. On exit `3`, cut the branch in place with `git switch -c <b> <ref>`. Stops: `bad-checkout-state`,
`stale-unregistered-dir`, `invalid-start-point`, `pr-already-merged`, `worktree-add-failed`.

`worktree.sh merge <N> --branch <b> [--ladder-attempt <n>]` — Step 8. The **only** path that
runs `gh pr merge`. `<b>` may be a PR number; it resolves to that PR's branch first, so it keys
the same receipt `run-gates.sh` wrote whichever form either was given. Keys:
`MERGED MERGE_METHOD MERGED_INTO BASE_IS_DEFAULT ISSUE_STATE PR_URL` (+ `FAILING_CHECKS`,
`LADDER_STEP`, `WARN_NON_DEFAULT_BASE`). Every stop it can emit, with the response it needs, is in
`merge-ladder.md`. `--ladder-attempt` (the model increments it each loop; caps at 3) backstops a
livelock — a model that never increments it disables that backstop. On any stop, nothing is
cleaned up.

`worktree.sh cleanup <N> --branch <b> [--keep-branch]` — Step 9, after a successful merge.
`<b>` may be a PR number here too. Two hard preconditions: the PR is `MERGED` (else stop
`pr-not-merged`), and no open PR is based on this branch (else stop `base-of-open-pr`). The second
read fails closed: a dependents list that could not be read stops at `dependents-unreadable`
rather than assuming none. Removes the worktree (never `--force`; tracked dirtiness → stop
`dirty-tracked-files`), deletes the local + remote branch, prunes the receipt and the run dir.
Keys: `REMOVED DELETED_LOCAL DELETED_REMOTE`, plus `LEFTOVER_DIR` if a directory could not be
removed. **Run it with your shell's cwd in `<original-root>`, not the worktree** — a shell sitting
inside the worktree locks it on Windows so `git worktree remove` only partially succeeds. Cleanup
never auto-deletes an unregistered directory: it reports the path as `LEFTOVER_DIR` and still
removes the remote branch. `DELETED_LOCAL=false` means a still-registered locked worktree remains;
delete that branch and the leftover yourself once whatever holds it is gone.

In the in-place fallback (exit 3) there is no worktree to remove: switch off the branch, delete it
local and remote, and sweep the run's temp by hand, keeping anything committed under `docs/`, the
PR's own content, and whatever the user asked you to keep.

`--keep-branch` — user self-merges / abandons. Removes the worktree only, skips both
preconditions and **never touches the branch or PR**. Keys: `REMOVED KEPT` (`branch-and-pr`),
plus `LEFTOVER_DIR`.

## The hooks you never call

`merge-guard.sh` denies `gh pr merge --admin` specifically and asks on a bare force-push
(`--force-with-lease` passes: it refuses when the remote moved). A plain `gh pr merge` is **not**
denied, so the rule against one is yours to keep, exactly like explicit-path staging and the
in-session go-ahead. Plugin agents ignore hooks, which is why the merge runs in the main session
only.

## run-gates.sh — gates + install + smoke

`run-gates.sh --log-dir <dir> --gate name='<cmd>' [--gate ...]` — every gate run: install at
Step 1, the gates at 5, the re-gates at 6, the commit at 7, the smoke at 9. Runs gates in cwd,
tees each to a log, prints `GATE_<NAME>_EXIT/_TIME/_LOG` + `GATES_RUN GATES_OK`, and surfaces only
a failing gate's last 40 lines (on stderr). **Exit = the first failing gate's own code** (not the
0/2/3/4 contract), or 0 when all pass; `4` on argument misuse. An all-green run leaves a receipt
bound to the HEAD it ran against, which `worktree.sh merge` refuses to merge without.
