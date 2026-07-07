# Script contracts

The pipeline's git/gh mechanics live in tested bash scripts under
`${CLAUDE_PLUGIN_ROOT}/scripts/` (this plugin), not in prose. Each script owns the *mechanics*;
the model owns *judgment*. Every human-judgment stop is an exit code, never a silent script
decision. This file is the reference: what to call, when, and how to read the result.

## How the scripts talk back

- **Output:** each script prints `KEY=VALUE` lines on stdout (the machine block). Pass `--json`
  for one flat JSON object with the same keys. Lists are comma-joined strings. Human hints go to
  stderr. A green run is a handful of lines — that printed block IS your
  verification-before-completion proof.
- **Uniform exit codes:** `0` proceed · `2` stop-and-ask (reason in `STOP_REASON=`, a hint on
  stderr) · `3` sandbox/permission fallback (do it in place) · `4` degraded (could not parse/reach
  something — do that part by hand). Exceptions noted per script below.
- Read config **once in the main checkout** (it is gitignored, absent inside the worktree) and
  carry the resolved values; never re-read config from inside the worktree.

## Three rules that stay with the model (never in a script)

1. **Approval interpretation (Step 11).** Only a script can be told a reply is a go-ahead — *you*
   judge that. Merge only on an unambiguous instruction to merge THIS PR ("merge it", "lgtm ship
   it", "approved"). A change request → implement, re-run the gates, re-report, wait again.
   Anything vague → ask for an explicit confirmation. Then, and only then, run `approve.sh`.
2. **Merge only in the main session.** Plugin agents ignore hooks, so the merge-approval hook
   guards the main session only. Never delegate a merge command to a subagent or workflow agent.
3. **A conflict is a stop, not a fix.** Content conflicts, branch protection, failed checks →
   the script exits 2 and hands control back. Report the exact error; do not auto-resolve.

## preflight.sh — Step 0 probe (run once, from the main checkout)

`preflight.sh <N> [--claim] [--json] [--config <path>]`

Collapses auth, repo identity, base resolution, gate-command detection, issue state, worktree
state, and board membership into one call. `--claim` assigns the issue to you (warns, does not
steal, if someone else holds it).

Keys: `GH_OK SCOPES OWNER REPO DEFAULT_BRANCH BASE START_POINT CMD_TYPECHECK CMD_TEST CMD_VISUAL
CMD_SMOKE CMD_SOURCE_TEST CMD_SOURCE_TYPECHECK CONFIG_PRESENT ISSUE_STATE ISSUE_TITLE
ISSUE_ASSIGNEES WORKTREE_STATE WORKTREE_PATH BOARD_CONFIGURED BOARD_MEMBER BOARD_STATUS_FIELD
CHECKS_TIMEOUT WARNINGS` (and `WARN_CLAIMED_BY` when relevant).
Exit `2` gh-auth-failed · `4` config-parse-failed / missing-issue.
`WORKTREE_STATE` ∈ `absent | resumable | registered-missing-dir | stale-dir | pr-merged`.

## worktree.sh — worktree + merge mechanics (SAFETY-CRITICAL)

`worktree.sh ensure  <N> --branch <b> --start-point <ref>` — Step 1. Creates / resumes /
reattaches the `../<repo>-worktrees/issue-<N>` worktree. Keys: `STATE`
(`CREATED|REATTACHED|RESUMED`), `WT_PATH ORIGINAL_ROOT BRANCH DEPS_MANIFEST INSTALL_HINT
PR_STATE`. You run the install (`INSTALL_HINT`) visibly, piping it through `run-gates.sh`.
Stops: `bad-checkout-state · stale-unregistered-dir · invalid-start-point · pr-already-merged`;
exit `3` → cut the branch in place with `git switch -c <b> <ref>`.

`worktree.sh merge <N> --branch <b>` — Step 11. The **only** path that runs `gh pr merge`. Self-
validates the approval marker (present · unused · fresh <30m · head-SHA matches), pushes, squash-
merges (falls back to the repo's allowed method), consumes the marker, then reports the honest
outcome. Keys: `MERGED MERGE_METHOD ISSUE_STATE PR_URL`. Stops: `no-valid-approval ·
push-rejected · checks-pending · merge-failed`. On any stop, nothing is cleaned up.

`worktree.sh cleanup <N> --branch <b> [--salvage-to <dir>]` — Step 12, after a successful merge.
Hard precondition: the PR is `MERGED` (else stop `pr-not-merged` — deleting an open PR's branch is
mechanically impossible). Salvages `tmp/task-<N>/{design,progress,state}` first, removes the
worktree (never `--force`; tracked dirtiness → stop `dirty-tracked-files`), deletes the local +
remote branch, removes the marker. Keys: `REMOVED DELETED_LOCAL DELETED_REMOTE SALVAGED`, plus
`LEFTOVER_DIR` if a directory could not be removed. **Run it with your shell's cwd in
`<original-root>`, not the worktree** — a shell sitting inside the worktree locks it on Windows so
`git worktree remove` only partially succeeds. Cleanup never auto-deletes an unregistered
directory (same protection as `ensure`): it reports the path as `LEFTOVER_DIR` and still removes
the marker + remote branch. Check `DELETED_LOCAL` — if a still-registered locked worktree remains
it stays `false`; delete that branch and the leftover yourself once whatever holds it is gone.

`worktree.sh teardown <N> [--salvage-to <dir>]` — user self-merges / abandons. Removes the
worktree only; **never touches the branch or PR**. Keys: `REMOVED SALVAGED KEPT`
(`branch-and-pr | in-place`), plus `LEFTOVER_DIR` if a directory could not be removed.

## Merge-approval gate — the physics

- `approve.sh <b> --quote "<verbatim reply>"` — Step 11. Run ONLY after you judge the reply an
  unambiguous go-ahead (rule 1). Writes the single-use marker
  `<root>/.claude/issue-to-pr/approval-<b-slug>.json`. `approve.sh --refresh <b>` re-stamps the
  head-SHA after a pure base merge. Keys: `APPROVED|REFRESHED MARKER_PATH PR_HEAD_SHA CREATED_AT`.
- `merge-guard.sh` (hook, `hooks/hooks.json`, PreToolUse on Bash) — allows a merge command only
  with a valid marker; denies `gh pr merge --admin`; asks on force-push; passes every other
  command through. The marker is consumed by `worktree.sh merge`, so it is single-use by
  construction. You never call this directly.

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
left to GitHub's automation on the default-branch merge.

## triage-evidence.sh — objective triage signals (no tier decision)

`triage-evidence.sh <N> [--json]` — Step 2. Emits `LABELS BODY_LENGTH CHECKLIST_ITEMS
REF_PATHS_EXIST REF_PATHS_MISSING NEW_THING_HITS LINKED_ISSUES TITLE` from the issue. You map the
signals to a tier yourself. Exit `4` if the issue cannot be read.

## tier-select.sh - map triage signals to a tier (v1.3.0)

`triage-evidence.sh <N> | tier-select.sh [--tier trivial|standard|complex|epic] [--json]`
Emits `TIER` + `TIER_REASON`. Deterministic rubric (full table + boundaries in
`tier-matrix.md`); `--tier` overrides; borderline picks higher. Always exit 0.

## sensitive-paths.sh - security overlay trigger (v1.3.0)

`git diff --name-only "$BASE"...HEAD | sensitive-paths.sh [--json]` -> `SENSITIVE=true|false`
+ `MATCHED=`. Segment/stem-exact matching (auth, crypto, secrets, payment, migrations, plus
`.env*`/`*.sql`/key material), so `authors.py` / `payment_ui_copy.md` do not false-trip.
`SENSITIVE=true` -> add one `/security-review` pass. Always exit 0.

## pin-config.sh - self-writing config (v1.3.0)

`pin-config.sh --config <path> [--test <cmd>] [--typecheck <cmd>] [--visual <cmd>] [--smoke <cmd>]`
Appends a gate command to the config's frontmatter only if unset (checked with preflight's
shared parser, so a nested `commands:` value counts as set - NEVER overwrites a human value).
Emits `PINNED=<keys>`. Exit 0; 4 if an existing config cannot be parsed (never corrupts it).

## stage-guard.sh - explicit-path staging hook (v1.3.0)

PreToolUse hook (in `hooks/hooks.json`, alongside merge-guard): denies `git add -A` / `--all`
/ `.` and passes everything else through, so staging stays explicit. You never call it directly.
