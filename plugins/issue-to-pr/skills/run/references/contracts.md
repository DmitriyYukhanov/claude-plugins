# Script contracts

The pipeline's git/gh mechanics live in tested bash scripts under
`${CLAUDE_PLUGIN_ROOT}/scripts/` (this plugin), not in prose. Each script owns the *mechanics*;
the model owns *judgment*. Every human-judgment stop is an exit code, never a silent script
decision. This file is the reference: what to call, when, and how to read the result.

## How the scripts talk back

- **Output:** each script prints `KEY=VALUE` lines on stdout (the machine block); board-sync.sh
  alone prints a JSON object. Lists are comma-joined strings. Human hints go to
  stderr. A green run is a handful of lines — that printed block IS your
  verification-before-completion proof.
- **Uniform exit codes:** `0` proceed · `2` stop-and-ask (reason in `STOP_REASON=`, a hint on
  stderr) · `3` sandbox/permission fallback (do it in place) · `4` degraded (could not parse/reach
  something — do that part by hand). Exceptions noted per script below.
- Read config **once in the main checkout** and carry the resolved values; never re-read it from
  inside the worktree. It lives in `.claude/issue-to-pr/`, which is ignored by a rule the plugin
  puts there itself, so a worktree normally has no copy at all.

## Three rules that stay with the model (never in a script)

1. **Approval interpretation (Step 11).** Only a script can be told a reply is a go-ahead — *you*
   judge that. Merge only on an unambiguous instruction to merge THIS PR ("merge it", "lgtm ship
   it", "approved"). A change request → implement, re-run the gates, re-report, wait again.
   Anything vague → ask for an explicit confirmation. Then, and only then, run the merge.
2. **Merge only in the main session.** Plugin agents ignore hooks, so the merge-approval hook
   guards the main session only. Never delegate a merge command to a subagent or workflow agent.
3. **A conflict is a stop, not a fix.** Content conflicts, branch protection, failed checks →
   the script exits 2 and hands control back. Report the exact error; do not auto-resolve.

## preflight.sh — Step 0 probe (run once, from anywhere in the repository)

`preflight.sh <N> [--claim] [--config <path>]`

Collapses auth, repo identity, base resolution, gate-command detection, issue state, worktree
state, and board membership into one call. `--claim` assigns the issue to you (warns, does not
steal, if someone else holds it). Every probe resolves against the main checkout, so the answer
does not change with the directory you start in; a relative `--config` you pass yourself is the
one exception and stays relative to you. The `CMD_*` values are **repository-root-relative and
must not be split** — run the gates from the root of your checkout (Step 1's `cd WT_PATH`, or
the repository root in the exit-3 in-place fallback), or a root-relative runner path exits 127.

Keys: `GH_OK SCOPES OWNER REPO DEFAULT_BRANCH BASE START_POINT CMD_TYPECHECK CMD_TEST CMD_VISUAL
CMD_SMOKE CONFIG_PRESENT CONFIG_PATH RUN_DIR ISSUE_STATE ISSUE_TITLE
ISSUE_ASSIGNEES WORKTREE_STATE WORKTREE_PATH BOARD_CONFIGURED BOARD_MEMBER BOARD_STATUS_FIELD
STATUS_MAP_IN_PROGRESS STATUS_MAP_IN_REVIEW
CHECKS_TIMEOUT WARNINGS` (and `WARN_CLAIMED_BY` when relevant).
Exit `2` gh-auth-failed · `4` config-parse-failed / missing-issue.
`WORKTREE_STATE` ∈ `absent | resumable | registered-missing-dir | stale-dir | pr-merged`.

## worktree.sh — worktree + merge mechanics (SAFETY-CRITICAL)

`worktree.sh ensure  <N> --branch <b> --start-point <ref>` — Step 1. Creates / resumes /
reattaches the `../<repo>-worktrees/issue-<N>` worktree. Keys: `STATE`
(`CREATED|REATTACHED|RESUMED`), `WT_PATH ORIGINAL_ROOT BRANCH INSTALL_HINT
PR_STATE`. You run the install (`INSTALL_HINT`) visibly, piping it through `run-gates.sh`.
Stops: `bad-checkout-state · stale-unregistered-dir · invalid-start-point · pr-already-merged`;
exit `3` → cut the branch in place with `git switch -c <b> <ref>`.

`worktree.sh merge <N> --branch <b> [--ladder-attempt <n>]` — Step 11. The **only** path that
runs `gh pr merge`. `<b>` may be a PR number; it resolves to that PR's branch first, so it keys
the same receipt `run-gates.sh` wrote whichever form either was given. Refuses a head no green
receipt covers, reads the GitHub review itself and fails closed, then pushes and runs the
merge-failure ladder (sec 6.3): a structured pre-check classifies the PR and emits a typed stop
per rung. The merge carries `--match-head-commit`, so GitHub itself refuses if the head moved
between the read and the merge. Keys: `MERGED MERGE_METHOD ISSUE_STATE PR_URL` (+
`FAILING_CHECKS`, `LADDER_STEP`). Stops: `pr-head-unreadable · gates-unverified · review-blocked ·
review-unreadable · push-rejected · checks-failed · merge-conflict · update-branch-failed ·
base-update-unverified · content-changed-needs-reapproval · checks-pending ·
merge-ladder-exhausted · merge-failed` — the model's response to each rung is in `merge-ladder.md`.
`--ladder-attempt` (the model increments it each loop; caps at 3) backstops a livelock. On any
stop, nothing is cleaned up.

`worktree.sh cleanup <N> --branch <b> [--salvage-to <dir>]` — Step 12, after a successful merge.
`<b>` may be a PR number here too (everything past the precondition is git, which cannot read one).
Hard precondition: the PR is `MERGED` (else stop `pr-not-merged` — deleting an open PR's branch is
mechanically impossible). Salvages `<RUN_DIR>/{design.md,progress.md,state.json,step.log}` first — a relative
`--salvage-to` lands under the **main checkout**, not cwd, so it survives the removal — removes the
worktree (never `--force`; tracked dirtiness → stop `dirty-tracked-files`), deletes the local +
remote branch. Keys: `REMOVED DELETED_LOCAL DELETED_REMOTE SALVAGED`, plus
`LEFTOVER_DIR` if a directory could not be removed. **Run it with your shell's cwd in
`<original-root>`, not the worktree** — a shell sitting inside the worktree locks it on Windows so
`git worktree remove` only partially succeeds. Cleanup never auto-deletes an unregistered
directory (same protection as `ensure`): it reports the path as `LEFTOVER_DIR` and still removes
the remote branch. Check `DELETED_LOCAL` — if a still-registered locked worktree remains
it stays `false`; delete that branch and the leftover yourself once whatever holds it is gone.

`worktree.sh teardown <N> [--salvage-to <dir>]` — user self-merges / abandons. Removes the
worktree only; **never touches the branch or PR**. Keys: `REMOVED SALVAGED KEPT`
(`branch-and-pr | in-place`), plus `LEFTOVER_DIR` if a directory could not be removed.

`worktree.sh revert <N> --branch <b>` — Step 12 post-merge safety net (sec 6.5). When the smoke
gate fails on the updated base, opens a **draft** revert PR of the squash commit on a fresh
`revert/issue-<N>-<slug>` branch off the refreshed base. NEVER merges — the human decides. Keys:
`REVERT_BRANCH REVERT_PR_URL REVERT_COMMIT`. Stops: `revert-branch-failed · revert-conflict ·
revert-push-failed · revert-pr-failed`; degrade `no-merge-commit` if the PR is not merged.

## Merge gate — what is enforced, and by what

- **The go-ahead is prose, and only prose.** No file proves a human agreed. An approval marker
  used to sit here; the same model that runs the pipeline wrote it, with whatever quote it judged
  a go-ahead, and the hook could not see the conversation. It proved freshness, single use and a
  head SHA, never intent. Rule 1 above is the whole gate, and it is yours to keep.
- **The gates are enforced by the receipt.** `run-gates.sh` leaves one naming the HEAD it ran
  against; the merge refuses a head no receipt covers (`gates-unverified`).
- **The review is enforced by the merge, failing closed** (`review-blocked`, `review-unreadable`).
- **The head is enforced by GitHub.** `gh pr merge --match-head-commit` refuses if a commit landed
  after the diff you were shown.
- `merge-guard.sh` (hook, `hooks/hooks.json`, PreToolUse on Bash) — denies `gh pr merge --admin`,
  asks on a force-push, passes everything else through. You never call it directly.

## run-gates.sh — gates + install + smoke

`run-gates.sh --log-dir <dir> --gate name='<cmd>' [--gate ...]` — Steps 1/6/8. Runs gates in cwd,
tees each to a log, prints `GATE_<NAME>_EXIT/_TIME/_LOG` + `GATES_RUN GATES_OK`, and surfaces only
a failing gate's last 40 lines (on stderr). **Exit = the first failing gate's own code** (not the
0/2/3/4 contract), or 0 when all pass; `4` on argument misuse.

## board-sync.sh — Projects (v2) status (best-effort)

`board-sync.sh <owner/repo> <N> <in_progress|in_review> [--board-url U] [--status-field F]`
Wraps the whole GraphQL chain (membership → field/option match via an alias table → mutation).
**Always exits 0**, always JSON: `OK` plus `SKIPPED_REASON` / `ERROR` / `HINT` (the hint carries
`gh auth refresh -s project` when the scope is missing). Run it with `run_in_background: true`;
board writes never block the pipeline. Step 1 → `in_progress`, Step 9 → `in_review`; `Done` is
left to GitHub's automation on the default-branch merge. Epic mode (sec 6.1) adds two best-effort
forms (still always exit 0): `board-sync.sh <owner/repo> --create-card "<title>" --board-url U`
(adds a draft card → `CARD_ID`) and `board-sync.sh <owner/repo> --convert-draft <itemId>`
(draft → real issue → `ISSUE_URL`).

## changed-paths.sh - the surface of the change (v2.9.0)

`changed-paths.sh --base <BASE>` -> one path per line, no `KEY=value`. Run from the worktree;
it collects the three sources the overlay needs at Step 7, before the Step 9 commit: committed
(three-dot against the base), edited-not-committed, and untracked. Exit `4` (`no-base`,
`not-a-git-repo`, `base-unresolvable`) rather than an empty list, because nothing downstream can
tell "changed nothing" from "could not read the diff". Whether any of it is security relevant is
your call at Step 7, not the script's (`tier-matrix.md`).

## stage-guard.sh - explicit-path staging hook (v1.3.0)

PreToolUse hook (in `hooks/hooks.json`, alongside merge-guard): denies `git add -A` / `--all`
/ `.` and passes everything else through, so staging stays explicit. You never call it directly.

## workflows/design-panel.js — Step 4 design, complex+ only

Called as `Workflow({scriptPath: "S/../workflows/design-panel.js", args:{issue, title,
contextFiles, constraints, openQuestions}})`. Three proposers, two adversarial critics, an
opus judge; it returns `design_md`, `rejected_alternatives` and open questions.

**Accept the result only if all three hold:** `received_issue` equals the issue number you
passed, `design_md` is non-empty, and `rejected_alternatives.length >= 1`. Anything else,
including a panel that throws, means design inline instead.

A `received_issue` mismatch looks like partial success and is not: the panel never saw its args,
so design the **whole** issue yourself, not the part a proposer reconstructed.
