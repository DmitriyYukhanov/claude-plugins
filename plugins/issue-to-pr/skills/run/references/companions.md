# Companion skills — preferred path and inline fallback

The pipeline runs standalone. Each companion sharpens one step; when it is absent, run the
fallback inline and tell the user what would have improved the result. Never let a missing
companion silently degrade quality without saying so.

| Capability | Preferred (if installed) | Inline fallback |
|---|---|---|
| Written plan (Step 5) | `superpowers:writing-plans` | Write a short ordered plan (files to touch, test-first steps, gates) before coding. |
| Design critique (Step 3, complex) | `/codex-collaboration:cross-review` over the produced design | Adversarially self-critique the design against the code, then revise. |
| Humanizing human-facing text (Step 9) | `humanizer:humanizer` | Self-edit the PR body / report to drop AI-tell phrasing; flag that a humanizer pass would help. |
| Lazy design and build (Steps 3–5) | `ponytail:ponytail full`, set once before the design | Design and build against the same ladder by hand: does this need to exist, does the stdlib or the platform already do it, can it be one line. |
| Grilling the design (Step 4, `--grill` only) | `mattpocock-skills:grilling` over the design you just built | Hand the design over in the batched question itself, with your open `asked` items, and take their objections as the round. Still one contact, not two. |
| Deletion lens (Step 8) | `ponytail:ponytail-review` over the run's diff | Re-read the diff hunting only for what to delete: reinvented stdlib, one-caller abstractions, config nobody sets, flags nobody passes. |
| Simplification lens (Step 8) | `simplify` | Re-read the diff for what survives but reads worse than it has to: a branch that only ever takes one path, a loop the stdlib has a name for, a comment explaining a name that should have been the name. |
| Diff review loop (Step 7) | `code-review` at the tier's level | Independent adversarial review subagents (2–3) critique the diff for correctness, reuse, and regressions; iterate. |

`code-review`, `simplify` and `verify` are **built into Claude Code** — invoke them by bare
name, no install, no namespace, no `if installed` branch. `code-review` sizes its own finder
fan-out to the diff.
`verify` has no row because it has no fallback: you cannot approximate driving a built artifact
by reading the diff again.

`deep-research` is built in as well but is **not the run's to use**: since 2.1.218 Claude Code
starts it only when the user types it. No branch, no row — Step 2 uses its `Explore` subagent,
and a user wanting the deeper sweep runs the command in their own turn.

Ponytail's `SubagentStart` hook carries the mode into every subagent, so setting it once at
Step 3 is the whole wiring. Step 7's reviewers inherit it: it governs how a confirmed bug gets
fixed, never whether it counts as one.

Step 8 runs `verify` **last**, after the simplification gate has stopped moving the diff. A
FAIL is stop-and-fix and re-gate, never a ratchet count: the ratchet raises the review level, a
level buys another review pass, and by Step 8 the loop has closed. The fix then lands after the
last review pass, so "Work no reviewer saw" in `R/autonomy.md` covers it.
