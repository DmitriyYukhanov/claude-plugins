# Autonomy — the ask contract and the ledger

The pipeline decides what it reasonably can on its own, records every decision, and
surfaces the automatic ones where the human already looks: the report and the PR body.

## Ask contract — three moments

Contact the user at these three points and nowhere else.

1. **Step 4 checkpoint** — ONE batched `AskUserQuestion`, only if the ledger has open `asked`
   items. It may move **earlier**, to Step 0, when the ambiguity is in the request rather than
   the design. `--grill` spends the same slot instead: `mattpocock-skills:grilling` works the
   design tree in rounds until the frontier is empty and the user confirms, and it **replaces**
   the question, so every open `asked` item goes into its first round — including the Step 0
   scope question, and including items the grill would never reach on its own, like a new
   dependency or a gate command Step 6 could not settle. Ledger each decision **as its round
   closes**: a grill runs long enough to compact, and a decision left only in its transcript is
   gone when it does. Anything surfacing after it belongs to moment (3).
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
reaches the PR body. Neither replaces an `asked` item: where the contract reserves a choice for
the human, usually a new **external** dependency, the entry records the evidence and the choice
still goes to them. Checking is never a way to skip the question.

**A claim about the world outside this repo that you have not checked.** Look it up before you
build on it, at any tier, one lookup per doubt (Step 2's survey of unknowns is a different thing
and only `complex` runs it). The `question` is the claim, the `decision` is what you built on it,
the `rationale` is what you found **and where**: a conclusion with no source reads like the guess
this rule exists to stop. It goes here and **never into a design file** — `design.md` exists only
on `complex` and Step 11 prunes it, so a citation left there dies unread.

Use whatever search the session offers, except `/deep-research` (`R/companions.md`). No search at
all excuses the lookup, never the entry: say in the `rationale` that the claim went unchecked and
what you assumed instead.

**Work no reviewer saw.** The last review pass a tier allows changed something, or Step 8 cut
after the loop closed: either way it reaches the merge gate unread. Not gated on the ratchet,
which needs two confirmed bugs; one bug on the final pass leaves its fix exactly as unread. The
`question` is what went unreviewed, the `decision` is that you stopped rather than overrunning
the cap, the `rationale` names the files so the reader knows where to look hardest. File it
whenever it applies and never otherwise, since a caveat on every run is one nobody reads.

## Resume after an interruption

`git status`, `gh pr view` and the gate logs under `<RUN_DIR>/logs` answer where the run stopped.
Trust them over recollection.
