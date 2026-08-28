# Tier matrix — scale the machinery to the task

The pipeline runs the same gates every time; the *depth* between them scales to a tier.
Pick it at Step 1 from the issue: `standard` unless the signals below argue otherwise,
`--tier` pins it, and any tier but `standard` is logged in the ledger with the signal that
moved it. Borderline picks the **higher** tier.

| Machinery | trivial | standard | complex |
|---|---|---|---|
| Design | - | mini-design in the PR body | design panel, then `/cross-review` |
| `code-review` level | `low`, 1 pass | `medium`, <=2 passes | `high`, <=3 passes (may raise to `max` on escalation) |

Gates and the security overlay run at every tier, always.

## Signals, strongest first

- **complex:** new behavior rather than a change to behavior that exists, or several
  checklist items, or several existing paths in scope, or a `design` / `ux` / `breaking` label.
- **trivial:** a copy or config change, short, one path at most, no `feature` / `design` label.
- **standard:** everything else, and the answer whenever the signals disagree.

Tier what the run will actually do: a scope the conversation widened past the issue text
tiers on the wider scope.

## Escalation ratchet (one-way)

Count CONFIRMED `code-review` verdicts per pass, and consecutive failures per gate. When
**2+ confirmed bugs land in one review pass**, or **the same gate fails twice**, escalate
the review level one notch (never down). A `trivial` run becomes `standard`, which is what
gives it a design step to re-enter; the matrix grants trivial no design of its own. Report
the raw per-pass counts at Step 9 so a missed ratchet is visible at the merge gate.
