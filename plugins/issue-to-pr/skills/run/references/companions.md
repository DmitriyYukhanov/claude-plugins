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
| Human drill on the design (Step 4, `--drill` only) | `drill:me` over `<RUN_DIR>/design.md` | Hand the file to the user to read and ask them directly. |
| Deletion lens (Step 8) | `ponytail:ponytail-review` over the run's diff | Re-read the diff hunting only for what to delete: reinvented stdlib, one-caller abstractions, config nobody sets, flags nobody passes. |
| Simplification lens (Step 8) | `simplify` | Re-read the diff for what survives but reads worse than it has to: a branch that only ever takes one path, a loop the stdlib has a name for, a comment explaining a name that should have been the name. |
| Diff review loop (Step 7) | `code-review` at the tier's level | Independent adversarial review subagents (2–3) critique the diff for correctness, reuse, and regressions; iterate. |

`code-review` and `simplify` are **built into Claude Code** — invoke them by bare name, no
install, no namespace, no `if installed` branch. They carry their own fallbacks when the
Agent tool is unavailable, and `code-review` sizes its own finder fan-out to the diff.

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

These are recommendations, not requirements — the skill checks availability at the relevant
step and proceeds either way.
