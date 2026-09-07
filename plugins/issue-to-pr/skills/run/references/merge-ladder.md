# Merge-failure ladder - Step 8

`worktree.sh merge` runs a structured pre-check before any `gh pr merge` and stops with a typed
`STOP_REASON` (exit 2) for every failure mode. **The stop's own hint on stderr is the
instruction** - it is written where you have to act on it, and it is the only copy, so a second
one here would only drift from it. On any stop nothing is merged and nothing is cleaned up: do
what the hint says, then re-run `merge`, whose pre-check re-reads live state every call.

Most rungs end there. Two of them open a loop instead, and a loop is longer than a hint. Either
way the bound is the same and it is yours to keep: **the same rung a third time is a livelock
rather than slow progress. Stop and hand back.** Nothing in the script counts for you, and the
behind-base rung writes to the PR on every pass.

## `checks-pending` - the watch loop

Watch the checks green, then re-classify; never trust `--watch`'s bare exit code.

1. `gh pr checks <b> --watch` via the Bash tool's `run_in_background`, bounded by
   `checks_timeout` minutes from the config (default 20 when unset). Windows Git Bash note:
   GNU `timeout` is not guaranteed - if you bound with it, guard `command -v timeout` first and
   fall back to a counted `sleep` loop.
2. When it settles, or when the bound elapses, ALWAYS re-classify with a fresh read: just re-run
   `worktree.sh merge <N> --branch <b>`. A check that has since failed surfaces as
   `checks-failed`, and a now-green PR merges.

At most ONE watch per attempt.

## `gates-unverified` after `LADDER_STEP=base-merged-clean` - the behind-base loop

The script updated the PR to its base and proved the PR's own diff untouched. The new head is
base+diff, which the gates never ran against, and it exists only on the remote. **Pull it first**,
or the receipt binds to the stale local head and the next `merge` stops the same way. Then
re-gate and re-run `merge`.
