# Tier matrix — scale the machinery to the task

The pipeline runs the same gates every time; the *depth* between them scales to a tier.
Pick it at Step 1 from the issue: `standard` unless the signals below argue otherwise,
`--tier` pins it, and any tier but `standard` is logged in the ledger with the signal that
moved it. Borderline picks the **higher** tier.

| Machinery | trivial | standard | complex |
|---|---|---|---|
| Design | - | mini-design in the PR body | design panel, then `/cross-review` |
| `code-review` level | `low`, 1 pass | `medium`, <=2 passes | `high`, <=3 passes (may raise to `max` on escalation) |
| Step 8 `verify` | - | when the diff left something runnable | as standard |

Gates, the security overlay, and the external-claim check run at every tier, always; the last
of those lives in `R/autonomy.md` with the other ledger rules.

## Signals, strongest first

- **complex:** new behavior rather than a change to behavior that exists, or several
  checklist items, or several existing paths in scope, or a `design` / `ux` / `breaking` label.
- **trivial:** a copy or config change, short, one path at most, no `feature` / `design` label.
- **standard:** everything else, and the answer whenever the signals disagree.

Tier what the run will actually do: a scope the conversation widened past the issue text
tiers on the wider scope.

## Escalation ratchet (one-way)

Count CONFIRMED `code-review` verdicts per pass, and consecutive failures per gate. When
**2+ confirmed bugs land in one review pass**, or **the same gate fails twice**, escalate the
review level one notch (never down). A `trivial` run becomes `standard`, which raises the cap
along with the tier and gives it both a design step and the Step 8 verify slot to re-enter;
raising a level inside a tier buys no extra pass. Report the raw per-pass counts at Step 9 so a
missed ratchet is visible at the merge gate.

The cap is the cap: another pass is how a review loop stops terminating, and the human at the
merge gate is the backstop. Stop, and ledger what stopping cost — `R/autonomy.md`, "Work no
reviewer saw", owed whether or not the ratchet ever fired.
