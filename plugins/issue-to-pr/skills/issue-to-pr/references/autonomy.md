# Autonomy — ask contract, ledger, and state (spec sec 5.1 + 5.5)

The pipeline decides what it reasonably can on its own, records every decision, and
surfaces the automatic ones where the human already looks (the report and the PR body).

## Ask contract — three moments only

Contact the user at exactly three points:
1. **Step 4.5 checkpoint** — ONE batched `AskUserQuestion`, only if the ledger has open
   `asked` items. This is the single mid-run question.
2. **The merge gate** (Step 11) — always.
3. **A hard stop** — an exit-2 with no safe default (e.g. `WARN_CLAIMED_BY`, a
   gate-critical unknown).

A question is for the user (`kind: asked`) only when it is:
- **preference-bound** — public API naming, user-visible UX/copy, paid/external
  resources, a new external dependency or license, or a breaking API/schema change; or
- **gate-critical unresolvable** — no test command is detectable, so the gates cannot run.

Everything else is decided autonomously (`kind: auto`) and logged. Forbidden: proceeding
past the checkpoint with a gate-critical unknown; asking mid-implementation anything that
fits moment (1).

## Ledger

`state.json.ledger[]`, each `{question, decision, rationale, kind: asked|auto}`, appended
**immediately, before the next tool call** (so a compaction can't lose a decision). Render
the `auto` entries as a **"Decisions made autonomously"** section in the Step 10 report AND
the PR body — the human reviews them at the merge gate they already attend. A Step 10 canary
cross-checks the ledger entry count against the visible autonomous work.

## state.json (schema v1) + step.log

`tmp/task-<N>/state.json` (model-owned; the model reads/writes it as JSON) plus an
append-only `tmp/task-<N>/step.log` that every side-effecting script writes one flat
`KEY=VALUE` line to — the script-authored ground truth that survives a crash between a
side effect and the model's state write.

```json
{ "schema_version": 1, "issue": 7, "tier": "standard", "branch": "…", "wt_path": "…",
  "original_root": "…", "base": "dev", "start_point": "origin/dev",
  "cmds": {"typecheck": "…", "test": "…", "visual": null, "smoke": null},
  "board": {"project_id": "…", "item_id": "…", "field_id": "…", "options": {…}},
  "steps": {"preflight": {"done": true, "at": "…"}, "…": {}},
  "ledger": [{"question": "…", "decision": "…", "rationale": "…", "kind": "auto"}],
  "metrics": {"gate_runs": 3, "gate_fail_streak": {}, "confirmed_bugs_this_pass": 0,
    "review_passes": 2, "review_level": "medium", "design_panel_ran": false,
    "research_fork_invocations": 0, "review_fallback_used": "design-panel",
    "board_lookup_calls": 0, "started_at": "…"} }
```

- `tier` is written after Step 2 (null/pending before that).
- **metrics** is the telemetry the Step 10 report prints so the owner can confirm the tier
  scaled the work (which machinery fired, review level/passes, a rough spend proxy).

## Resume after compaction

Read `state.json`. If it is absent OR does not parse, treat it as absent and fall back to
re-running preflight + reading `progress.md` + `step.log`. Otherwise cross-check each
`steps.<name>.done` against a matching `step.log` line — **the log wins on a mismatch** —
re-verify cheap outcomes (PR state via `gh pr view`), and jump to the first incomplete step.
Anchor every `Edit` against state.json on the step name (or another unique key); prefer a
whole-file `Write` when uniqueness is uncertain (the schema has repeated `{done,at}` fragments).
