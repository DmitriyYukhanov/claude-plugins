# Judgment — how deep the run goes, and who decides

## Tier

Borderline picks the **higher** tier, and any tier but `standard` is ledgered with the signal that
moved it.

| Machinery | trivial | standard | complex |
|---|---|---|---|
| Design | - | mini-design in the PR body | design panel, then `/cross-review` |
| `code-review` level | `low`, 1 pass | `medium`, <=2 passes | `high`, <=3 passes (may raise to `max` on escalation) |
| Step 6 `verify` | - | when the diff left something runnable | as standard |

Gates, the security overlay and the external-claim check run at every tier, always. Signals,
strongest first:

- **complex:** new behavior rather than a change to behavior that exists, or several
  checklist items, or several existing paths in scope, or a `design` / `ux` / `breaking` label.
- **trivial:** a copy or config change, short, one path at most, no `feature` / `design` label.
- **standard:** everything else, and the answer whenever the signals disagree.

Tier what the run will actually do: a scope the conversation widened past the issue text tiers on
the wider scope.

### Escalation ratchet (one-way)

Count CONFIRMED `code-review` verdicts per pass and consecutive failures per gate; 2+ confirmed
bugs in one pass, or the same gate failing twice, raises the review level one notch and never
lowers it. A `verify` FAIL is not one of those failures: it is stop-and-fix, never a count, or two
of them buy review passes the cap exists to forbid. A `trivial` run becomes `standard`, which raises
the cap along with the tier and gives it both a design step and the `verify` slot to re-enter;
raising a level inside a tier buys no extra pass. The cap is then the cap — another pass is how a review loop stops terminating, and the human
at the merge gate is the backstop. Stop, and ledger the cost ("Work no reviewer saw", below).

## The ask contract — what the spine's three moments mean

1. **Step 3**, which may move **earlier**, to Step 0, when the ambiguity is in the request rather
   than the design. Every open `asked` item goes into the grill's first round — including the
   Step 0 scope question, and including items the grill would never reach on its own, like a new
   dependency or a gate command Step 5 could not settle.
2. **The merge gate**.
3. **A hard stop**: an exit-2, a gate-critical unknown, or a preference-bound choice that surfaced
   too late for moment (1). The checkpoint being spent is not a licence to decide it alone.

A question is for the user (`kind: asked`) only when it is **preference-bound** — public API
naming, user-visible UX/copy, paid or external resources, a new external dependency or license, or
a breaking API/schema change — or **gate-critical unresolvable**, meaning no test command is
detectable and the gates cannot run. Everything else is decided autonomously (`kind: auto`) and
logged. Forbidden: proceeding past the checkpoint with a gate-critical unknown, and asking
mid-implementation anything that fits moment (1).

## Ledger

One entry per judgment call: `{question, decision, rationale, kind: asked|auto}`, written down
**before the next tool call**, so a compaction cannot lose it. Only the `auto` entries render, as a
**"Decisions made autonomously"** section in both the Step 7 report and the PR body, so the wrong
`kind` means the entry never reaches its reader. A long run does compact: afterwards `git status`,
`gh pr view` and the gate logs under `<RUN_DIR>/logs` say where it stopped, and they outrank
recollection.

## Two entries always owed

Both are `kind: auto`, and neither replaces an `asked` item: the entry records the evidence, the
choice still goes to the human.

**A claim about the world outside this repo that you have not checked.** One lookup per doubt. The
`question` is the claim, the `decision` is what you built on it, the `rationale` is what you found
**and where** — a conclusion with no source reads like the guess this rule exists to stop. It goes
here and **never into a design file**: `design.md` exists only on `complex` and Step 9 prunes it,
so a citation left there dies unread. No search available excuses the lookup, never the entry; say
in the `rationale` that the claim went unchecked and what you assumed instead.

**Work no reviewer saw.** The last review pass a tier allows changed something, or the
simplification gate cut after the loop closed: either way it reaches the merge gate unread. Not
gated on the ratchet, which needs two confirmed bugs; one bug on the final pass leaves its fix
exactly as unread. The `rationale` names the files, so the reader knows where to look hardest.
File it whenever it applies and never otherwise, since a caveat on every run is one nobody reads.
