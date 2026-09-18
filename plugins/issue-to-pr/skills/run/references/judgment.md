# Judgment — how deep the run goes, and who decides

## Tier

Borderline picks the **higher** tier, and any tier but `standard` is ledgered with the signal that
moved it.

| Machinery | trivial | standard | complex |
|---|---|---|---|
| Design | - | mini-design in the PR body | design panel, then `/cross-review` |
| Review depth | `low`, 1 pass | `medium`, <=2 passes | `high`, <=3 passes (may raise to `max` on escalation) |
| Runtime verification | - | when the diff left something runnable | as standard |

Gates, the security overlay and the external-claim check run at every tier, always. Signals,
strongest first:

- **complex:** new behavior rather than a change to behavior that exists, or several
  checklist items, or several existing paths in scope, or a `design` / `ux` / `breaking` label.
- **trivial:** a copy or config change, short, one path at most, no `feature` / `design` label.
- **standard:** everything else, and the answer whenever the signals disagree.

Tier what the run will actually do: a scope the conversation widened past the issue text tiers on
the wider scope.

Depth describes review coverage, not a model ID or a required tool parameter. Respect the host's
model settings. At every depth trace changed behavior through its callers; increase independent
perspectives and edge-case coverage as depth rises.

**Escalation:** if a review pass confirms two or more real bugs — the second model's pass counts
like any other — raise the review level once and
never lower it; the tier's pass cap is still the cap, and the human at the merge gate is the
backstop. When the cap ends the loop with fixes unread, ledger it ("Work no reviewer saw", below).

## The ask contract — what the spine's three moments mean

The checkpoint needs no state of its own: the ledger already carries it. Write the `asked` entry
when you send the question, even in Step 0, and its `decision` when the answers land. The
checkpoint is spent once every open `asked` item has a decision and, under `--grill`, the user has
confirmed the design — a grill records a decision as each round closes and runs on until that
confirmation, so a closed round is not a closed checkpoint. An answered scope question does not
block independent design work meanwhile. Entries are written before the next tool call, which is
what keeps a compaction from losing them.

1. **Step 3**, which may move **earlier**, to Step 0, when the ambiguity is in the request rather
   than the design. Every open `asked` item goes into the grill's next round — including the
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
`gh pr view` and the gate logs under `.claude/issue-to-pr/` in the main checkout say where it
stopped, and they outrank recollection.

## Two entries always owed

Both are `kind: auto`, and neither replaces an `asked` item: the entry records the evidence, the
choice still goes to the human.

**A claim about the world outside this repo that you have not checked.** One lookup per doubt. The
`question` is the claim, the `decision` is what you built on it, the `rationale` is what you found
**and where** — a conclusion with no source reads like the guess this rule exists to stop. No
search available excuses the lookup, never the entry; say in the `rationale` that the claim went
unchecked and what you assumed instead.

**Work no reviewer saw.** Any change after the last review needs this entry, including final-pass
fixes, simplification cuts and fixes from runtime verification. Passing gates does not mean a
reviewer saw that change. The `rationale` names the files and the unreviewed changes. File it
whenever it applies, unless a later review covered those changes.
