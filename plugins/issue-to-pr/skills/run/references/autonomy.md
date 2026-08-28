# Autonomy — the ask contract and the ledger

The pipeline decides what it reasonably can on its own, records every decision, and
surfaces the automatic ones where the human already looks: the report and the PR body.

## Ask contract — three moments, plus one the user asks for

Contact the user at these three points, and at a fourth only if asked (below):

1. **Step 4 checkpoint** — ONE batched `AskUserQuestion`, only if the ledger has open
   `asked` items. This is the single mid-run question.
2. **The merge gate** (Step 10) — always.
3. **A hard stop** — an exit-2 with no safe default (e.g. `WARN_CLAIMED_BY`, a
   gate-critical unknown).

A question is for the user (`kind: asked`) only when it is:

- **preference-bound** — public API naming, user-visible UX/copy, paid/external
  resources, a new external dependency or license, or a breaking API/schema change; or
- **gate-critical unresolvable** — no test command is detectable, so the gates cannot run.

Everything else is decided autonomously (`kind: auto`) and logged. Forbidden: proceeding
past the checkpoint with a gate-critical unknown; asking mid-implementation anything that
fits moment (1).

## The fourth moment: `--drill`

Append each objection to the ledger **as it is raised**, never in a batch at the end: a
tutoring session is long enough for the context to compact, and a decision that lived only
in the drill's transcript is gone when it does.

## Ledger

Keep one entry per judgment call: `{question, decision, rationale, kind: asked|auto}`,
written down **before the next tool call**, so a compaction cannot lose it. Render the
`auto` entries as a **"Decisions made autonomously"** section in the Step 9 report AND
the PR body — the human reviews them at the merge gate they already attend.

## Resume after an interruption

`git status`, `gh pr view` and the gate logs under `<RUN_DIR>/logs` answer where the run
stopped. Trust them over recollection — they are what the outside world actually shows.
