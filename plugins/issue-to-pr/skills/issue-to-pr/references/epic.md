# Epic tier - decompose and iterate (spec sec 6.1)

An epic is a new system too large to drive as one PR. Epic *mode* is ACTIVE (v2.0):
decompose the parent into child issues, then run each child through the full pipeline
in dependency order. It is no longer "treated as complex".

## Detect

Epic when any holds: Step 2 tiers the issue `epic` (a new system described without
reference to code that exists yet - see `tier-matrix.md`); `--tier epic` pins it at the
invocation; or a large free-text request (`entry.md`) triages to epic.

## Decompose

Run the decomposition workflow (the sibling `design-panel.js` mirrors its shape):

```
Workflow({scriptPath: "${CLAUDE_PLUGIN_ROOT}/workflows/epic-decompose.js",
          args:{issue, title, body, contextFiles, constraints}})
```

Returns `{plan_md, children:[{title, body, depends_on[], tier_estimate}], open_questions[],
received_issue}`. Accept only when `received_issue` equals the parent you passed: the script
throws outright if `args.issue` never arrived, and a decomposition of a guessed parent is worse
than none. On a throw, `_failed`, empty `children`, or a mismatch, fall back to an inline
decomposition by hand; route preference-bound `open_questions` to the ledger.

## Checkpoint (the one epic ask)

Show `plan_md` at ONE ledger checkpoint. This is the single mandatory epic ask besides
the per-child merge gates - a preference-bound decision (see `autonomy.md`). The user
approves the breakdown from the rendered plan; never make them read raw JSON.

## Materialize (on approval)

In the parent's order: `gh issue create` per child with a body linking `Part of #<parent>`;
`board-sync.sh <owner/repo> --create-card "<child title>" --board-url <board.url>` per child
(the `--board-url` is required in create-card mode; best-effort, board-mode
only; always exits 0, never hard-stops); then add a checklist of the children to the PARENT
issue.

## Epic state file (model-owned)

`.claude/issue-to-pr/epic-<parent>.json` in the MAIN checkout (gitignored). The MODEL
authors it directly - same precedent as the per-task `state.json`; there is no writer
script. Shape:

```json
{ "parent": 12,
  "created_at": "2026-07-07T10:00:00Z",
  "children": [
    { "issue": 34, "title": "data model",  "depends_on": [],   "state": "merged" },
    { "issue": 35, "title": "service layer","depends_on": [34], "state": "in_progress" },
    { "issue": 36, "title": "API + UI",     "depends_on": [35], "state": "pending" }
  ] }
```

`state` per child: `pending | in_progress | pr_open | merged | skipped`.

## Execute (sequential, in dependency order)

Each child is a FULL Steps 0-12 pipeline run: its own worktree `issue-<childN>`, its own
PR, its own in-session merge gate. The merge gate MUST stay in the main session - hooks do
not bind subagents - so children are NOT parallelized (a spec non-goal). Update the child's
`state` in `epic-<N>.json` as it advances. After a child merges, branch the NEXT child from
the refreshed base, so integration drift is consumed incrementally instead of all at once.

## Reconcile-before-trust

On resume or `next`, re-query `gh issue view <child> --json state` for EVERY child before
trusting `epic-<N>.json`. A child merged or closed outside this run wins over the file -
narrate the delta ("Child #34 was already merged outside this run - marking it merged.")
and never silently overwrite.

## Completion

The parent auto-closes when the last child's PR merges (the final child links
`Closes #<parent>`), or is closed manually. Report the epic with a metrics roll-up across
children (per-child tier, review passes, gate runs).
