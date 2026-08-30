# Tier matrix — scale the machinery to the task

The pipeline runs the same gates every time; the *depth* between them scales to a tier.
Pick it at Step 1 from the issue: `standard` unless the signals below argue otherwise,
`--tier` pins it, and any tier but `standard` is logged in the ledger with the signal that
moved it. Borderline picks the **higher** tier.

| Machinery | trivial | standard | complex |
|---|---|---|---|
| Design | - | mini-design in the PR body | design panel, then `/cross-review` |
| `code-review` level | `low`, 1 pass | `medium`, <=2 passes | `high`, <=3 passes (may raise to `max` on escalation) |

Gates, the security overlay, and the external-claim check run at every tier, always.

That last one is not the research step wearing a smaller hat. Step 2 is a survey of unknowns
and only `complex` runs it; this is one lookup for one doubt, and it fires on a `trivial` copy
change exactly as it does on a design panel. The trigger is not the kind of work but the kind
of claim: anything about how the world outside this repository behaves that you are about to
act on and are not sure of. A design, a test, a line of code, a dependency you are picking, a
command you are about to run, a sentence you are putting in the docs. Then look it up.

What you find goes in the **ledger** (`R/autonomy.md`), never into a design file.
`<RUN_DIR>/design.md` is not a surface a reader can count on: it exists only on `complex` or
under `--drill`, and Step 11 prunes it whenever the change landed on the default branch. The
ledger is the one path that reaches the PR body from every tier. One entry, the whole shape
`autonomy.md` defines, `kind: auto` because only `auto` entries render: the claim is the
`question`, what you then did with the answer is the `decision`, and the `rationale` carries
what you found **and where**. A conclusion with no source reads exactly like the guess this
rule exists to stop, so the citation is the part that does the work.

A session with no search is not an exemption from the rule, only from the lookup. Ledger it the
same way, with the `rationale` saying the claim went unchecked and what you assumed instead.
Building on an unverified assumption is a judgment call like any other, and the merge gate is
where someone can weigh it.

Any search the session offers, except `/deep-research`, which is never the run's to start
(`R/companions.md`). Nothing else is named, deliberately: ranking search tools belongs to
whatever instructions the operator runs under, not to this plugin.

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
