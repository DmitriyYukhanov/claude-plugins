# Merge-failure ladder - Step 8

`worktree.sh merge` runs a structured pre-check before any `gh pr merge` and emits a typed
`STOP_REASON` (exit 2) for every failure mode. The script owns detection and the safe base-merge
refresh; the model owns the bounded CI wait and the re-merge loop. On any stop nothing is merged
and nothing is cleaned up: read the `STOP_REASON`, act per its rung, then re-run `merge` - the
pre-check re-reads live state each call.

## Before the ladder

These five refuse the merge outright rather than opening a loop.

- **`gates-unverified`** - no green gate receipt covers the current head. Re-run `run-gates.sh` on
  it, then re-run `merge`.
- **`review-blocked`** - GitHub carries a requested change. Route it through change-requests; the
  earlier go-ahead no longer covers this PR.
- **`review-unreadable`** - the review state could not be read, so the script refuses rather than
  guessing. A real answer, not a hiccup: hand back and ask.
- **`pr-head-unreadable`** - the PR's head could not be read; hand back.
- **`merge-failed`** - `gh pr merge` failed for a reason the classifier does not recognise. Report
  its `MERGE_ERROR` verbatim and hand back.

## The rungs

- **`checks-failed`** (emits `FAILING_CHECKS=`) - a required check has already failed. Do NOT
  wait on it. Report the named checks and hand back for a fix.

- **`merge-conflict`** - the PR conflicts with its base. Never auto-resolve. Report and hand
  back.

- **`checks-pending`** - required checks are still running. This is the model's watch rung:
  run the watch loop below, then re-run `merge`. Nothing was spent, so the go-ahead still
  stands.

- **`content-changed-needs-reapproval`** - after `gh pr update-branch`, the base merge changed
  the PR's OWN diff. Report the delta versus what was approved and request FRESH approval before
  re-running `merge`.

- **`update-branch-failed`** - the auto base-merge failed. Report and hand back; do the update
  by hand.
- **`base-update-unverified`** - the base merge ran but the new head could not be observed
  (a stale or failed fetch), so purity cannot be proven. Fetch the branch and re-run `merge`,
  or re-approve; never assume the base merge was clean.

- **`push-rejected`** - the script could not push the updated base. Usually the local base is
  simply behind after an earlier merge: `git fetch origin && git merge --ff-only origin/<base>`
  in the MAIN checkout, then re-run `merge`. Every other cause means the remote moved under
  you, so re-approve rather than assuming the approval still covers the diff you showed - which
  is what the script's own hint says.

- **`merge-ladder-exhausted`** - the loop passed `--ladder-attempt` past the cap (3). Stop and
  hand back.

## The watch loop (model-owned, for `checks-pending`)

Watch the checks green, then re-classify - never trust `--watch`'s bare exit code:

1. `gh pr checks <b> --watch` via the Bash tool's `run_in_background`, bounded by
   `checks_timeout` minutes from the config (default 20 when unset). Windows Git Bash
   note: GNU `timeout` is not guaranteed - if you bound with it, guard `command -v timeout`
   first and fall back to a counted `sleep` loop.
2. When it settles (or the bound elapses), ALWAYS re-classify with a fresh read: just re-run
   `worktree.sh merge <N> --branch <b> --ladder-attempt <n+1>`. Its pre-check re-reads state,
   so a now-failed check surfaces as `checks-failed` and a now-green PR merges.

At most ONE watch per attempt, and increment `--ladder-attempt` on each loop.

## The behind-base loop

When the PR is behind its base the script updates it and proves the PR's own diff untouched
(`LADDER_STEP=base-merged-clean`), then stops at `gates-unverified`: the new head is base+diff,
which the gates never ran against, and it exists only on the remote. Pull it first, or the receipt
binds to the stale local head and the next `merge` stops the same way. Then re-gate and re-run.
