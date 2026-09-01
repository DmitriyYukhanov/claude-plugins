# Script contracts

The pipeline's git/gh mechanics live in tested bash scripts under
`${CLAUDE_PLUGIN_ROOT}/scripts/` (this plugin), not in prose. Each script owns the *mechanics*;
the model owns *judgment*. Every human-judgment stop is an exit code, never a silent script
decision.

## How the scripts talk back

- **Output:** each script prints `KEY=VALUE` lines on stdout, lists comma-joined; hints go to
  stderr. That printed block is your proof a step passed — never claim one without it.
- **Uniform exit codes:** `0` proceed · `2` stop-and-ask (reason in `STOP_REASON=`, a hint on
  stderr) · `3` sandbox/permission fallback (do it in place) · `4` degraded (could not parse/reach
  something — do that part by hand). Exceptions noted per script below.
- Read the config **once in the main checkout** at Step 0 (`R/configuration.md`) and carry the
  resolved values; never re-read it from inside the worktree.

On a stop, `worktree.sh` emits the raw failure alongside `STOP_REASON`: `ADD_ERROR`,
`DIRTY_FILES`, `PUSH_ERROR`, `MERGE_ERROR`. Report whichever is present verbatim; it is the only
place the underlying git/gh message survives. A stop is never a fix: report the error rather
than working around it.

## worktree.sh — worktree + merge mechanics (SAFETY-CRITICAL)

`worktree.sh ensure  <N> --branch <b> --start-point <ref>` — Step 1. Creates / resumes /
reattaches the `../<repo>-worktrees/issue-<N>` worktree. Keys: `STATE`
(`CREATED|REATTACHED|RESUMED`), `WT_PATH ORIGINAL_ROOT BRANCH PR_STATE`. You work the
install command out from the worktree's manifests and run it through `run-gates.sh`.
Stops: `bad-checkout-state · stale-unregistered-dir · invalid-start-point · pr-already-merged`;
exit `3` → cut the branch in place with `git switch -c <b> <ref>`.

`worktree.sh merge <N> --branch <b> [--ladder-attempt <n>]` — Step 10. The **only** path that
runs `gh pr merge`. `<b>` may be a PR number; it resolves to that PR's branch first, so it keys
the same receipt `run-gates.sh` wrote whichever form either was given. Refuses a head no green
receipt covers, reads the GitHub review itself and fails closed, then pushes and runs the
merge-failure ladder (sec 6.3): a structured pre-check classifies the PR and emits a typed stop
per rung. The merge carries `--match-head-commit`, so GitHub itself refuses if the head moved
between the read and the merge. Keys: `MERGED MERGE_METHOD MERGED_INTO BASE_IS_DEFAULT ISSUE_STATE PR_URL` (+
`FAILING_CHECKS`, `LADDER_STEP`, `WARN_NON_DEFAULT_BASE`). **`BASE_IS_DEFAULT` reads `true` only
when the landing branch is proved to be the default one** — `false` when the PR merged into
another feature branch, `unknown` when a ref could not be read. Step 11 owns what each of the
three means for cleanup. Stops: `pr-head-unreadable · gates-unverified · review-blocked ·
review-unreadable · push-rejected · checks-failed · merge-conflict · update-branch-failed ·
base-update-unverified · content-changed-needs-reapproval · checks-pending ·
merge-ladder-exhausted · merge-failed` — the model's response to each rung is in `merge-ladder.md`.
`--ladder-attempt` (the model increments it each loop; caps at 3) backstops a livelock. On any
stop, nothing is cleaned up.

`worktree.sh cleanup <N> --branch <b> [--keep-branch]` — Step 11, after a successful merge.
`<b>` may be a PR number here too (everything past the precondition is git, which cannot read one).
Two hard preconditions: the PR is `MERGED` (else stop `pr-not-merged`), and no open PR is based
on this branch (else stop `base-of-open-pr` — GitHub only retargets a stacked PR once its base is
already gone, so deleting first strands that work). The second read fails closed: a dependents
list that could not be read stops at `dependents-unreadable` rather than assuming none. Removes the
worktree (never `--force`; tracked dirtiness → stop `dirty-tracked-files`), deletes the local +
remote branch, prunes the receipt and the run dir. Keys: `REMOVED DELETED_LOCAL DELETED_REMOTE`, plus
`LEFTOVER_DIR` if a directory could not be removed. **Run it with your shell's cwd in
`<original-root>`, not the worktree** — a shell sitting inside the worktree locks it on Windows so
`git worktree remove` only partially succeeds. Cleanup never auto-deletes an unregistered
directory (same protection as `ensure`): it reports the path as `LEFTOVER_DIR` and still removes
the remote branch. Check `DELETED_LOCAL` — if a still-registered locked worktree remains
it stays `false`; delete that branch and the leftover yourself once whatever holds it is gone.

In the in-place fallback (exit 3) there is no worktree to remove, so Step 11 sweeps the run's
temp by hand instead: keep anything committed under `docs/`, the PR's own content, and whatever
the user asked you to keep.

`--keep-branch` — user self-merges / abandons. Removes the worktree only, skips both
preconditions and **never touches the branch or PR**. Keys: `REMOVED KEPT` (`branch-and-pr`),
plus `LEFTOVER_DIR`.

## The hooks you never call

`merge-guard.sh` denies an admin merge and asks on a bare force-push (`--force-with-lease`
passes: it refuses when the remote moved). It is a PreToolUse hook in
`hooks/hooks.json`, it passes everything else through, and plugin agents ignore hooks — which is
why the merge runs in the main session only. Explicit-path staging is a rule you keep, not a hook
that stops you. No file proves the go-ahead either: keeping it is yours.

## run-gates.sh — gates + install + smoke

`run-gates.sh --log-dir <dir> --gate name='<cmd>' [--gate ...]` — Steps 1/6/8. Runs gates in cwd,
tees each to a log, prints `GATE_<NAME>_EXIT/_TIME/_LOG` + `GATES_RUN GATES_OK`, and surfaces only
a failing gate's last 40 lines (on stderr). **Exit = the first failing gate's own code** (not the
0/2/3/4 contract), or 0 when all pass; `4` on argument misuse.
