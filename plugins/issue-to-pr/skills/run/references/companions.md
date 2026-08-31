# Companion skills — preferred path and inline fallback

The pipeline runs standalone. Each companion sharpens one step; when it is absent, run the
fallback inline and tell the user what would have improved the result. Never let a missing
companion silently degrade quality without saying so.

| Capability | Preferred (if installed) | Inline fallback |
|---|---|---|
| Written plan (Step 5) | `superpowers:writing-plans` | Write a short ordered plan (files to touch, test-first steps, gates) before coding. |
| Design critique (Step 3, complex) | `/cross-review` over the produced design | Adversarially self-critique the design against the code, then revise. |
| Humanizing human-facing text (Step 9) | `humanizer` | Self-edit the PR body / report to drop AI-tell phrasing; flag that a humanizer pass would help. |
| Lazy design and build (Steps 3–5) | `ponytail:ponytail full`, set once before the design | Design and build against the same ladder by hand: does this need to exist, does the stdlib or the platform already do it, can it be one line. |
| Grilling the design (Step 4, `--grill` only) | `mattpocock-skills:grilling` over the design you just built | Hand the design over in the batched question itself, with your open `asked` items, and take their objections as the round. Still one contact, not two. |
| Deletion lens (Step 8) | `ponytail:ponytail-review` over the run's diff | Re-read the diff hunting only for what to delete: reinvented stdlib, one-caller abstractions, config nobody sets, flags nobody passes. |
| Simplification lens (Step 8) | `simplify` | Re-read the diff for what survives but reads worse than it has to: a branch that only ever takes one path, a loop the stdlib has a name for, a comment explaining a name that should have been the name. |
| Diff review loop (Step 7) | `code-review` at the tier's level | Independent adversarial review subagents (2–3) critique the diff for correctness, reuse, and regressions; iterate. |

`code-review`, `simplify` and `verify` are **built into Claude Code** — invoke them by bare
name, no install, no namespace, no `if installed` branch. They carry their own fallbacks when
the Agent tool is unavailable, and `code-review` sizes its own finder fan-out to the diff.
`verify` has no row above because it has no fallback worth the name: driving a built artifact
at its real surface is not something you approximate by reading the diff again. Which tiers get
the slot is `R/tier-matrix.md`; the rules that govern it are at the bottom of this file.

`deep-research` is built in as well, but it is **not the run's to use**: since 2.1.218 Claude
Code starts it only when the user types `/deep-research` themselves. There is no branch here
and no row above, because there is no choice to make. Step 2's `Explore` subagent is simply
what Step 2 does; a user wanting the deeper sweep runs the command in their own turn.

Step 7 declines `code-review --fix`: a sweep of applied fixes lands past the per-fix re-gate
and past the confirmed-bug count the escalation ratchet reads. Fix findings yourself, one at
a time, re-running the gates between them.

Ponytail's own `SubagentStart` hook carries the mode into every subagent, so setting it once
at Step 3 is the whole wiring — pass nothing along. Step 7's reviewers inherit it too; their
prompt says it governs how a confirmed bug gets fixed, never whether it counts as one.

## The Step 8 verify slot

Green gates prove the tests pass. They do not prove the thing the PR claims to do actually
happens. That gap is what the slot closes, and it is why the three rules are what they are.

**Last in the step, after simplification.** That gate is still applying cuts and re-gating, so
anything verified ahead of it was verified against a diff that then moved.

**A diff with nothing runnable skips the slot, rather than recording a skip.** Research, docs and
prose outcomes have no surface to drive, and a verdict collected on every run, most of them
empty, is one nobody reads by the tenth PR. This pipeline's own runs skip more often than not:
its surface is a Claude session reading prose, which no terminal can drive.

**A FAIL never counts toward the ratchet.** The ratchet raises the review level, a level only
buys another review pass, and by Step 8 the loop has closed: the escalation would have nothing
to spend. A FAIL is stop-and-fix and re-gate, and the fix lands after the last review pass,
where "Work no reviewer saw" in `R/autonomy.md` already covers it.

These are recommendations, not requirements — the skill checks availability at the relevant
step and proceeds either way.
