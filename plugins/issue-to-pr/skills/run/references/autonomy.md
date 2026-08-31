# Autonomy — the ask contract and the ledger

The pipeline decides what it reasonably can on its own, records every decision, and
surfaces the automatic ones where the human already looks: the report and the PR body.

## Ask contract — three moments

Contact the user at these three points. Nothing in the run may interrupt them anywhere else; a
flag they passed themselves can.

1. **Step 4 checkpoint** — ONE batched `AskUserQuestion`, only if the ledger has open
   `asked` items. This is the single mid-run question, and it may move **earlier**, to Step 0,
   when the ambiguity is in the request rather than in the design: the same one question, spent
   sooner.

   `--grill` spends the slot differently rather than adding to it: `mattpocock-skills:grilling`
   works the design tree in rounds, each a numbered set of decisions with a recommended answer,
   until the frontier is empty and the user confirms. It **replaces** the batched question, so
   every open `asked` item goes **into** the grill, in its first round: the grill works the
   design tree, the ledger holds what is not on it — a new dependency, a gate command Step 6
   could not settle — and an item the grill never reaches is an item nobody asks. Ledger each
   decision **as its round closes**, never in a batch at the end: a grill runs long enough for
   the context to compact, and a decision that lived only in its transcript is gone when it
   does. Anything surfacing after it belongs to moment (3), like any other late arrival.

   Under the flag the grill **always** runs, including on a run whose scope question already
   went at Step 0: Step 0 cannot defer that one, since an issue it drafts on a guessed scope is
   the wrong issue. The flag is the user electing the longer form, and nothing here cancels it.
2. **The merge gate** (Step 10) — always.
3. **A hard stop** — anything with no safe default: an exit-2 (`WARN_CLAIMED_BY`, a
   gate-critical unknown), or a preference-bound choice that surfaced too late for
   moment (1). The checkpoint being spent is not a licence to decide it alone.

A question is for the user (`kind: asked`) only when it is:

- **preference-bound** — public API naming, user-visible UX/copy, paid/external
  resources, a new external dependency or license, or a breaking API/schema change; or
- **gate-critical unresolvable** — no test command is detectable, so the gates cannot run.

Everything else is decided autonomously (`kind: auto`) and logged. Forbidden: proceeding
past the checkpoint with a gate-critical unknown; asking mid-implementation anything that
fits moment (1).

## Ledger

Keep one entry per judgment call: `{question, decision, rationale, kind: asked|auto}`,
written down **before the next tool call**, so a compaction cannot lose it. Render the
`auto` entries as a **"Decisions made autonomously"** section in the Step 9 report AND
the PR body — the human reviews them at the merge gate they already attend.

## Two things that always earn an entry

Both are `kind: auto`, and only `auto` entries render, so the wrong `kind` means the entry never
reaches the PR body at all. Neither replaces an `asked` item: where the contract above reserves a
choice for the human — a new **external** dependency or license is the usual one — the entry
records the evidence and the choice still goes to them, at Step 4 before the checkpoint and as a
hard stop after it. Checking is what makes that question worth asking, never a way to skip it.

**A claim about the world outside this repo that you have not checked.** Before building on how
something outside it behaves while unsure of it, look it up: a design, a test, a line of code, a
command about to run, a sentence going into the docs. Any tier, and one lookup for one doubt:
Step 2's survey of unknowns is a different thing and only `complex` runs it. The `question` is
the claim, the `decision` is what you built on it, and the `rationale` carries what you found
**and where** — a conclusion with no source reads exactly like the guess this rule exists to
stop.

It goes here and **never into a design file**. `<RUN_DIR>/design.md` exists only on `complex`, and
Step 11 prunes it once the change lands on the default branch, so a citation left there is
deleted before any reader sees it. The ledger is the one path that reaches the PR
body from every tier.

Use whatever search the session offers, except `/deep-research` (`R/companions.md`). Nothing else
is named, deliberately, because ranking search tools belongs to the operator's own instructions.
No search at all is an exemption from the lookup and never from the entry: say in the `rationale`
that the claim went unchecked, and what you assumed instead.

**Work no reviewer saw.** The last review pass a tier allows changed something, or Step 8 applied
a cut after the loop had closed: either way it reaches the merge gate unread. This is **not**
gated on the ratchet, which needs two confirmed bugs; one bug on the final pass leaves its fix
exactly as unread. The `question` is what went unreviewed, the `decision` is that you stopped
rather than overrunning the cap, the `rationale` names the files so the reader knows where to
look hardest. Say it whatever the tier: a `trivial` report is three lines and this is worth one
of them. File it when it applies and not otherwise, since a caveat attached to every run is one
nobody reads.

## Resume after an interruption

`git status`, `gh pr view` and the gate logs under `<RUN_DIR>/logs` answer where the run
stopped. Trust them over recollection — they are what the outside world actually shows.
