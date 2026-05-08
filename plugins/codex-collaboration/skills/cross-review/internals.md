# Cross-Review Internals

Reference document for the `cross-review` skill. Loaded on demand via Read; not auto-loaded.

When SKILL.md says **"Read `internals.md#anchor`"**, read that section before continuing — the model needs the detail. When SKILL.md says **"See `internals.md#anchor`"**, the section is reference material the model usually doesn't need to load mid-flow.

## Companion CLI contract

The wait-for-codex helpers call:

```
node <codex-companion.mjs> status <job-id> --json
```

Returned JSON shape (verified against `codex-cli 0.128.0+`):

```
{
  "job": {
    "id": <string>,
    "phase": "starting" | "running" | "done" | "failed" | "cancelled",
    "status": <string>,
    "elapsed": <string>,
    "progressPreview": [<string>],
    ...other fields ignored by wait-for-codex
  }
}
```

Terminal phases: `done` (success), `failed`, `cancelled`. `completed` is NOT a phase the companion emits — loops watching for `completed` will hang forever.

## Codex monitoring

After dispatching a Codex task in the background, the parent (Claude or a subagent) is NOT auto-notified when the task reaches a terminal phase. Always run the wait-for-codex helper:

- Bash 4+: `${CLAUDE_PLUGIN_ROOT}/scripts/cross-review/wait-for-codex.sh <job-id>`
- PowerShell: `${CLAUDE_PLUGIN_ROOT}/scripts/cross-review/wait-for-codex.ps1 -JobId <job-id>`

Run via the Bash tool with `run_in_background: true`; the parent gets a single completion notification when the helper exits (exit 0 = done, exit 1 = failed/cancelled, exit 2 = timeout).

## Code-verified policy

Code-verified-only findings (Step 5 graceful-degradation path) are NEVER auto-applied. They become `needs-decision (code-verified)` items with the note: *"Codex couldn't cross-validate this finding; please confirm before applying."* Bilateral consensus is the auto-apply invariant.

## Baseline-map schema

Lazy, populated on first edit to a path; persists across all rounds. Each entry:

```
{
  path: <absolute path>,
  existedAtFirstTouch: <bool>,
  wasUntrackedAtFirstTouch: <bool>,                  // true if `git status --porcelain -- <path>` showed `?? ` at first touch
  hadPreExistingChanges: <bool>,                     // true if `git diff --quiet HEAD -- <path>` exited non-zero at first touch (tracked changes only)
  snapshotContents: <string | null | "deferred">,    // FULL contents at first touch; null if the file did not exist; "deferred" for files larger than the size guard (see below)
  snapshotPathOnDisk: <string | null>                // absolute path to a tmpdir copy when snapshotContents="deferred"; null otherwise
}
```

The map is updated for ALL skill-driven edits: auto-applied, needs-decision-resolved, and deferred-overlap fixes applied post-mediation. The Step 9 rollback partitions touched files into four subsets using `existedAtFirstTouch`, `wasUntrackedAtFirstTouch`, and `hadPreExistingChanges`:

- `existedAtFirstTouch=false` → newly-created files (delete to revert).
- `existedAtFirstTouch=true` AND `wasUntrackedAtFirstTouch=true` → pre-existing untracked files (restore from `snapshotContents` / `snapshotPathOnDisk`; `git restore` does not work because the file isn't in the index).
- `existedAtFirstTouch=true` AND `wasUntrackedAtFirstTouch=false` AND `hadPreExistingChanges=true` → tracked with pre-existing edits (use `git restore --patch`).
- `existedAtFirstTouch=true` AND `wasUntrackedAtFirstTouch=false` AND `hadPreExistingChanges=false` → tracked, no pre-existing edits (use `git restore`).

**Size guard.** For files where contents at first-touch exceed `1 MiB`, set `snapshotContents = "deferred"` and write the contents to a per-run scratch path (e.g., `<TMPDIR>/cross-review-<run-id>/<sanitized-path>`); store the scratch path in `snapshotPathOnDisk`. The Step 9 rollback for the pre-existing-untracked partition copies from `snapshotPathOnDisk` instead of inlining contents. The threshold is implementer-tunable; do not skip auto-apply just because a file is large.

**Two-tier baseline.** The `snapshotContents` (or `snapshotPathOnDisk`) above is the **run-level** baseline. It is consumed by the Step 9 rollback for the pre-existing-untracked partition. The partial-apply `revert` verb (within a single round) restores from a separate **pass-level** journal — see `## Partial-apply state`.

## Auto-apply mechanics

The full algorithm SKILL.md Step 8 references:

1. **Lazy baseline (per path).** Before the FIRST edit to a path within the run, populate a baseline-map entry: `existedAtFirstTouch` (filesystem check), `wasUntrackedAtFirstTouch` (`git status --porcelain` shows `?? `), `hadPreExistingChanges` (`git diff --quiet HEAD` exit code), `snapshotContents` (full contents — read-then-store; `null` if the file doesn't exist; `"deferred"` if larger than the size guard, with `snapshotPathOnDisk` set). Baseline is per-path-per-run, not per-round; updates only on first touch.

2. **Pass journal (per apply pass within a round).** At the START of each apply pass (auto-fixable items, or the post-Step-7 needs-decision-resolved pass), capture a journal entry for every file the pass plans to edit: `{path, contentsAtPassStart}`. The journal is discarded at end of the round.

3. **Dirty-tree gate (per never-gate-cleared file).** For every apply pass, compute `delta` = files this pass will edit AND that have not yet been gate-cleared in this run. If `delta` is empty, skip the gate. Otherwise run `dirty-tree-probe` on `delta`, parse each JSON line, and if any has `dirty=true`, `untracked=true`, or `wouldCreate=true`, present the gate prompt with the dirty-tree gate response enum. After the user replies `proceed`, mark every file in `delta` as gate-cleared for the rest of the run.

4. **Pre-apply re-probe.** Right before the apply pass starts (after gate clearance), re-run `dirty-tree-probe` on the same `delta`. If dirty bits changed since the gate fired, abort the pass and re-present the gate. (Catches mid-round manual edits between gate and apply.)

5. **Overlap detection.** For each item in the pass, compute its footprint per `## Overlap footprint`. Overlap with a needs-decision item's footprint → defer to the post-Step-7 pass.

6. **Apply.** Use existing skill discovery and subagent dispatch logic. Update baseline map on first touch of each path; update pass journal as edits land. Tag each applied item with provenance (`agreed` | `cross-validated` | `evidence-resolved`).

7. **Partial-apply failure.** First failure stops the pass. Surface the partial-apply prompt; resolve per `## Partial-apply state`.

8. **No commits.** Working-tree only.

## Overlap footprint

Two findings overlap when ANY of these is true (computed per-pair):

- **File-level:** identical absolute path.
- **Hunk-level (same file):** the byte/line range of one fix's edit intersects the other's.
- **Symbol-level (same file):** both reference the same function/class/method name as their primary target.
- **Test-expectation:** both modify the same `expect(...)` / `assert*(...)` call site.

**Tie-break: if unsure, defer.** False positives (deferring a non-overlapping fix) are cheap; false negatives (auto-applying an overlap) silently invalidate the user's needs-decision context.

## Response enums

### Needs-decision

Verbs (case-insensitive); item numbers must match presentation order:

- `fix` — apply the proposed fix as-is.
- `dismiss` — drop and continue this round; record under "Dismissed (user decision)" in the summary.
- `fix with changes: <inline edits>` — apply the user's variant. The colon `:` after the verb is mandatory; everything after it (until end-of-line or next item-number entry) is the fix payload.
- `stop` — halt the run; emit summary as `user stopped`.

**Verb precedence.** `stop` is checked first. If ANY item in the batch carries `stop`, exit the run immediately after parsing — do not drop dismissed items, do not apply remaining fixes, do not advance to re-review. The skill emits the summary with `Exit reason: user stopped` and lists every needs-decision item under "Pending at user-stop" with its verb (or "(no decision)" if the batch was incomplete). Otherwise resolution proceeds through the post-stop steps of the resolution order in SKILL.md Step 7 step 1 (drop dismissed → apply remaining → record dismissed → re-review).

Example response: `1: fix, 2: dismiss, 3: fix with changes: use param X instead of Y, 4: stop` → run halts, no edits applied (item 3's fix is NOT applied because item 4 carries `stop`).

On unparseable input: re-prompt with the format example. Do not guess intent.

### Partial-apply failure

Verbs (case-insensitive):

- `retry [N]: <guidance>` — re-attempt fix N with the guidance applied to the fix payload. Colon is mandatory.
- `revert` — restore every file edited in THIS pass to its `contentsAtPassStart` from the pass journal. Run-level baseline is not touched; fixes from earlier rounds remain.
- `skip` — continue with the remaining fixes in the pass (caller advances to re-review or the next pipeline step after the pass completes); the failed fix is recorded under "Skipped (apply failed)" in the summary.
- `stop` — halt the run; emit summary as `user stopped`. Earlier successful fixes in this pass remain on disk (no `revert`).

Example: `retry 2: use parameterized query instead of string concat`.

### Dirty-tree gate response

Verbs (case-insensitive); response is **all-or-nothing for the current delta**:

- `proceed` — continue with the auto-apply pass; mark every file in the delta as gate-cleared for the rest of the run.
- `stop` — take the dirty-tree decline path (Step 9 exit reason `dirty-tree decline`); current round's findings become informational; no fixes applied this round.

Partial-file responses (e.g., "skip file X but proceed for Y") are NOT supported; treat any input that is not exactly `proceed` as `stop`.

## Partial-apply state

State machine for partial-apply failure recovery within a single apply pass:

| State | Trigger | Next state |
|---|---|---|
| `applying` | (default during apply pass) | `failed` (on first error) or `done` (all succeeded) |
| `failed` | error mid-apply | `prompt` (surface partial-apply enum to user) |
| `prompt` | user replies `retry N: <guidance>` | `applying` for fix N (with guidance applied), then continue with fixes N+1, N+2... |
| `prompt` | user replies `revert` | `reverting` |
| `prompt` | user replies `skip` | record fix N in run-local skip-set; resume `applying` from fix N+1 |
| `prompt` | user replies `stop` | exit the run with `Exit reason: user stopped`; do NOT revert earlier successful fixes in this pass |
| `reverting` | (replaying pass-journal `contentsAtPassStart`) | `done` (pass net-effect = 0; the round's apply work is finished) |
| `done` | all fixes resolved or all skipped | return to caller — the pre-Step-7 invocation returns control to Step 7 (presentation); the post-Step-7 invocation returns control to the round-bookkeeping step (re-review or final exit) |

**Revert scope.** `revert` operates on the **pass journal** (per-pass) only. Files edited in earlier rounds keep those edits — `revert` does not roll back to the run-level baseline. The Step 9 final-summary rollback is the route to a full-run revert (using the run-level baseline-map).

**Skip-set semantics.** A fix recorded in the skip-set is not auto-retried in subsequent rounds of the same run. The user must re-run cross-review (fresh run) to retry. The skip-set does NOT persist across runs.

## Progress-update branch table

Emit ONE single-line status after auto-apply, before launching the next round (or exiting):

| Condition | Message |
|---|---|
| X = 0 AND Y = 0 | (suppress — Step 9 stable-round exit fires) |
| ROUND < MAX_ROUNDS AND Y > 0 | `Round N complete: applied X auto-fixable, awaiting your response on Y needs-decision item(s).` |
| ROUND < MAX_ROUNDS AND Y = 0 AND X > 0 | `Round N complete: applied X auto-fixable, moving to round N+1.` |
| ROUND = MAX_ROUNDS AND Y > 0 | `Round N complete (final round): applied X auto-fixable. Resolve the Y needs-decision item(s) below to apply final fixes; no further re-review will run.` |
| ROUND = MAX_ROUNDS AND Y = 0 AND X > 0 | `Round N complete: applied X auto-fixable; max rounds reached, no further re-review.` |

X = auto-fixable applied this round; Y = needs-decision items pending.

## Mid-loop manual edits

Editing a file between rounds during an autonomous run is partially supported:

- **Within a round (between gate and apply):** caught by the pre-apply re-probe (auto-apply mechanics step 4). The gate re-fires.
- **Between rounds (after the round ended, before the next round dispatches):** silently overwritten — the file was already gate-cleared in the prior round. Rely on the final-summary rollback block as the recovery boundary.

## Test plan

Manual scenarios to verify the implementation. Not an automated gate; run each by hand or fold into integration tests.

| Scenario | Expected | Verifies |
|---|---|---|
| Clean tree, all-agreed | Round 1 fast-path → Step 8 apply → Step 7 informational → exit "all clean" or "stable round" | Fast-path no longer skips apply |
| Mixed findings, clean tree | Standard pipeline; needs-decision items surfaced; auto-fixable applied automatically | Auto-apply eligibility |
| Dirty tree on touched file | Gate fires before first apply; `proceed` → continue; `stop` → exit "dirty-tree decline" with no edits | Gate + decline path |
| Round 2 introduces new touched file | Gate re-fires for the never-gate-cleared file only | Per-delta gate, gate-cleared set |
| Post-Step-7 apply touches new file (not in original delta) | New gate fires before the post-Step-7 apply | Auto-apply mechanics step 3 (gate scope) |
| Partial-apply failure, user `retry N: ...` succeeds | Fix N applies with guidance, remaining fixes continue | Retry semantics |
| Partial-apply failure, user `revert` mid round 2 | Round 2's pass journal restored; round 1's fixes remain | Revert scope (pass journal vs run baseline) |
| User dismisses needs-decision with overlapping deferred fix | Both dropped together | Overlap dependency |
| Batched response includes `stop` alongside `fix` items | Run halts immediately; no fixes applied; pending items recorded | `stop` precedence |
| User responds with malformed needs-decision input | Skill re-prompts with format example; does not guess intent | Re-prompt loop |
| Codex cross-validation fails (one side) | Code-verified items become needs-decision; never auto-applied; stable-round cannot fire | Code-verified policy |
| Round 3 (max rounds) produces findings | Apply round 3; emit "max rounds reached" or "final round" message; exit | No round 4 |
| Auto-apply creates a new file | Baseline map records `existedAtFirstTouch=false`; rollback lists under "Newly created files" with `rm` instructions | Newly-created files subset |
| Codex job dispatched from subagent | Parent runs wait-for-codex helper after dispatch | Subagent gap |
| Mid-round manual edit between gate and apply | Pre-apply re-probe catches it; gate re-fires | Auto-apply mechanics step 4 |
| `--max-rounds 0` invocation | Skill rejects at parse time with clear error message | Decision #4 validation |
| Auto-apply edits a pre-existing untracked file | Baseline records `wasUntrackedAtFirstTouch=true` + `snapshotContents`; rollback restores from `snapshotContents` (not `git restore`) | Untracked-file rollback partition |
| Auto-apply touches a 5 MiB pre-existing untracked file | Baseline records `snapshotContents="deferred"` + `snapshotPathOnDisk`; rollback copies from `snapshotPathOnDisk` | Size guard + untracked rollback |
| Partial-apply failure, user `stop` after one fix succeeded | Run halts; earlier successful fix remains on disk; failed fix recorded under "Skipped (apply failed)"; exit reason `user stopped` | `stop` in partial-apply enum |
