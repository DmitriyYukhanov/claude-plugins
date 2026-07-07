# Merge-failure ladder - Step 11 (spec sec 6.3)

`worktree.sh merge <N> --branch <b> [--ladder-attempt <n>]` runs a structured pre-check
before any `gh pr merge` and emits a typed `STOP_REASON` (exit 2) for each failure mode. The
script owns detection and the safe base-merge refresh; the model owns the bounded CI wait and
the re-merge loop. On any stop nothing is merged and nothing is cleaned up: read the
`STOP_REASON`, act per its rung, then re-run `merge` - the pre-check re-reads live state each
call. The marker-validity stops (`no-valid-approval`, `push-rejected`, `merge-failed`) hand
back the same way; they are not part of the ladder loop.

## The rungs

- **`checks-failed`** (emits `FAILING_CHECKS=`) - a required check has already failed. Do NOT
  wait on it. Report the named checks and hand back for a fix.
  "required checks failed on <b> (<checks>). Fix them, push, re-run the gates, and re-approve;
  do not wait on a check that already failed."

- **`merge-conflict`** - the PR conflicts with its base. Never auto-resolve. Report and hand
  back. "<b> conflicts with its base. Resolve the conflict locally, push, re-run the gates,
  and re-approve."

- **`checks-pending`** - required checks are still running. This is the model's watch rung:
  run the watch loop below, then re-run `merge`. The approval stays valid (the marker is not
  consumed on a stop). "required checks are still pending on <b>. Watch them to green
  (references/merge-ladder.md), then re-run merge - the approval stays valid."

- **`content-changed-needs-reapproval`** - after `gh pr update-branch`, the base merge changed
  the PR's OWN diff, so the marker is left stale (the head-SHA check plus the merge hook block
  a merge). Report the delta versus what was approved and request FRESH approval; only after
  the user re-approves do you run `approve.sh` again. "merging the base into <b> changed the
  PR's own diff. Re-review the updated PR and re-approve - the earlier approval no longer
  covers it."

- **`update-branch-failed`** / **`marker-refresh-failed`** - the auto base-merge or the
  marker re-stamp failed. Report and hand back; do the update or re-approval by hand.
- **`base-update-unverified`** - the base merge ran but the new head could not be observed
  (a stale or failed fetch), so purity cannot be proven. Fetch the branch and re-run `merge`,
  or re-approve; never assume the base merge was clean.

- **`merge-ladder-exhausted`** - the loop passed `--ladder-attempt` past the cap (3). Stop and
  hand back. "the merge ladder retried 3 times without landing <b>. Resolve the PR state on
  GitHub by hand, then re-approve."

Happy path: on a clean base merge the script auto-updates, refreshes the marker, and merges in
the same call, emitting `LADDER_STEP=base-merged-refreshed`. The model does nothing extra.

## The watch loop (model-owned, for `checks-pending`)

Watch the checks green, then re-classify - never trust `--watch`'s bare exit code:

1. `gh pr checks <b> --watch` via the Bash tool's `run_in_background`, bounded by
   `CHECKS_TIMEOUT` minutes from preflight (default 20 when the key is empty). Windows Git Bash
   note: GNU `timeout` is not guaranteed - if you bound with it, guard `command -v timeout`
   first and fall back to a counted `sleep` loop.
2. When it settles (or the bound elapses), ALWAYS re-classify with a fresh read: just re-run
   `worktree.sh merge <N> --branch <b> --ladder-attempt <n+1>`. Its pre-check re-reads state,
   so a now-failed check surfaces as `checks-failed` and a now-green PR merges.

At most ONE watch per attempt. Increment `--ladder-attempt` on each loop; at the cap, give up
and hand back (`merge-ladder-exhausted`).

## The behind-base loop

When the PR is behind its base, the script handles the clean case itself - update + refresh +
merge in one call (`LADDER_STEP=base-merged-refreshed`), nothing for the model to do. The only
behind-base rung the model acts on is `content-changed-needs-reapproval`: the base merge
altered the PR's own diff, so request fresh approval before re-running `merge`.

## Invariant

The merge gate is never weakened. Every rung either merges with a valid single-use marker or
stops and hands control back; no rung merges on a stale, used, or SHA-mismatched marker, and
the model never runs a bare `gh pr merge` - only `worktree.sh merge` does, and only after its
pre-check passes.
