# Companion skills — preferred path and inline fallback

The pipeline runs standalone; when a companion is absent, run the fallback inline and say so, so a
missing one never degrades the result silently.

| Capability | Preferred (if installed) | Inline fallback |
|---|---|---|
| Written plan (Step 4) | `superpowers:writing-plans` | Write a short ordered plan (files to touch, test-first steps, gates) before coding. |
| Design critique (Step 2, complex) | `/codex-collaboration:cross-review` over the produced design | Adversarially self-critique the design against the code, then revise. |
| Humanizing human-facing text (Step 7) | `humanizer:humanizer` | Self-edit the PR body / report to drop AI-tell phrasing; flag that a humanizer pass would help. |
| Lazy design and build (Steps 2–4) | `ponytail:ponytail full`, set once before the design | Design and build against the same ladder by hand: does this need to exist, does the stdlib or the platform already do it, can it be one line. |
| Grilling the design (Step 3, `--grill` only) | `mattpocock-skills:grilling` over the design you just built | Hand the design over in the batched question itself, with your open `asked` items, and take their objections as the round. Still one contact, not two. |
| Deletion lens (Step 6) | `ponytail:ponytail-review` over the run's diff | Re-read the diff hunting only for what to delete: reinvented stdlib, one-caller abstractions, config nobody sets, flags nobody passes. |

`code-review`, `simplify` and `verify` are **built into Claude Code** — bare name, no install, no
namespace, no `if installed` branch, and no row above, because a fallback table has nothing to say
about a skill that is always there. `code-review` reviews the diff at the tier's level; `simplify`
is the other half of the simplification gate, for what survives the deletion pass but still reads
worse than it has to; `verify` drives the built artifact, which no re-reading approximates, and it
runs after the gate stops moving the diff, so its fix lands after the last review pass and owes a
"Work no reviewer saw" entry (`R/judgment.md`). The adversarial subagents Step 6 may add are an
extra pass too, not a fallback: 2–3 independent reviewers on the diff, in the foreground, until it
comes back clean.

`deep-research` is built in as well but is **not the run's to use**: Claude Code starts it only
when the user types it, so it gets no row and no branch.

Ponytail's `SubagentStart` hook carries the mode into every subagent, so setting it once at Step 2
is the whole wiring. Step 6's reviewers inherit it: it governs how a confirmed bug gets fixed,
never whether it counts as one.
