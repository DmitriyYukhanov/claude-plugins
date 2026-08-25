# Companion skills — preferred path and inline fallback

The pipeline runs standalone. Each companion sharpens one step; when it is absent, run the
fallback inline and tell the user what would have improved the result. Never let a missing
companion silently degrade quality without saying so.

| Capability | Preferred (if installed) | Inline fallback |
|---|---|---|
| Design exploration (Step 3) | `superpowers:brainstorming` | Same loop by hand: investigate code + issues, form the best answer, settle unknowns with web/docs, surface only genuine judgment calls. |
| Written plan (Step 5) | `superpowers:writing-plans` | Write a short ordered plan (files to touch, test-first steps, gates) before coding. |
| Test-first discipline (Step 5–6) | `superpowers:test-driven-development` | Write the failing test, watch it fail, implement, watch it pass. |
| Debugging red tests (Step 6) | `superpowers:systematic-debugging` | Reproduce, isolate, hypothesize, fix one cause at a time; re-run. |
| Done-claims (throughout) | `superpowers:verification-before-completion` | Never claim green without pasting the command output. |
| Codebase research (Step 3, complex+) | forked `research` sub-skill (isolated subagent → ≤150-line cited summary); `/deep-research` for external topics | A focused inline exploration distilled to a short summary. |
| Design generation (Step 4, complex+) | `workflows/design-panel.js` (3 proposers → 2 adversarial critics → opus judge), with `/cross-review` critiquing the produced `design_md` | Inline self-review chain: draft, adversarially self-critique against the code, revise. |
| Humanizing human-facing text (Step 9–10) | `humanizer` | Self-edit the PR body / report to drop AI-tell phrasing; flag that a humanizer pass would help. |
| Lazy design and build (Steps 4–5) | `ponytail:ponytail full`, set once before the design | Design and build against the same ladder by hand: does this need to exist, does the stdlib or the platform already do it, can it be one line. |
| Deletion lens (Step 8) | `ponytail:ponytail-review` over the run's diff | Re-read the diff hunting only for what to delete: reinvented stdlib, one-caller abstractions, config nobody sets, flags nobody passes. |
| Simplification lens (Step 8) | `simplify`, built into Claude Code: four angles (reuse, simplification, efficiency, altitude) over the same diff, and it applies what it finds | Re-read the diff for what survives but reads worse than it has to: a branch that only ever takes one path, a loop the stdlib has a name for, a comment explaining a name that should have been the name. |
| Human drill on the design (Step 4.5, `--drill` only) | `drill:me` — the tutor drills the user on the design before it is built | Hand them `<RUN_DIR>/design.md`, say the drill plugin would have made this interactive, and take objections in the same batched question. |
| Diff review loop (Step 7) | `code-review`, built into Claude Code: takes a level and reports findings. It also takes `--fix`; Step 7 does not use it (see the note) | Independent adversarial review subagents (2–3 reviewers) critique the diff for correctness, reuse, and regressions; iterate. |

## Install hints

- `humanizer` and `codex-collaboration` ship in this marketplace
  (`DmitriyYukhanov/claude-plugins`): `/plugin install humanizer`,
  `/plugin install codex-collaboration`. `codex-collaboration` additionally needs the Codex
  plugin and `/codex:setup`.
- `superpowers:*` is the external Superpowers plugin, `ponytail:*` the external Ponytail one
  (`DietrichGebert/ponytail`). `/deep-research` comes from your own setup or another plugin.
- `code-review` and `simplify` need no install at all; see the note below.

## Note: two of these companions are built into Claude Code

`code-review` and `simplify` are registered by the CLI itself, alongside `verify`, `commit`, `pr`
and `workshop`. Invoke them like any skill, by name, with no namespace prefix. They need no
install and no marketplace, and no `if installed` branch applies to them.

Do not confuse the built-in `code-review` skill with the plugin command of the same name in the
official marketplace. Searching `~/.claude/plugins/cache` finds the plugin and tells you nothing
about the built-in, which is exactly the mistake this file used to enshrine: it claimed
`/code-review` was unreachable from a skill run because copies ship `disable-model-invocation`,
and sent Step 7 to an inline fallback for releases while the real reviewer sat one call away. The
cached official copy sets `disable-model-invocation: false`, so the caveat did not even hold for
the plugin. Before concluding a capability is missing, check whether it ships in the CLI.

**Step 7 skips `--fix` on purpose.** The built-in reviewer can apply its own findings with that
flag. The pipeline does not let it, because a sweep of applied fixes lands past the per-fix
re-gate and past `confirmed_bugs_this_pass`, which is the number the escalation ratchet reads.
Fix findings yourself, one at a time, and re-run the gates between them.

## The Step 8 simplification gate

Both lenses are rows in the table above, and their inline fallbacks are the right-hand column.
What follows is why the two numbers in the spine's Step 8 are both two. One instruction that
lives only here: record the pass count in `state.json.metrics.simplify_passes`, so the Step 10
report shows whether the gate converged or hit its cap.

**Two dots, never three.** Step 8 runs before Step 9 commits, so on a fresh branch HEAD is still
the base and `git diff <BASE>...HEAD` compares a commit with itself: zero files, while the whole
run sits uncommitted in the worktree. That is how the gate reviewed nothing and reported clean
from v2.7.0 to v4.0.0; v4.1.0 is the release that fixed it. `git diff <BASE>` reads the working tree; `changed-paths.sh` covers the
files git has never seen.

**Why the cap is two.** One pass cannot check itself: it edits the code and then stops looking,
so a cut that broke a neighbouring path reaches the gates at best and nobody at worst. Pass 2
earns its keep by reading what pass 1 changed; a third reads a diff that stopped moving.

## Note: ponytail carries itself, and it reaches the reviewers too

Ponytail ships a `SubagentStart` hook that injects its ruleset into every subagent from the
persisted mode, so setting it once at Step 4 is the whole wiring: implementation subagents
inherit it and the pipeline passes nothing along. The Step 7 adversarial reviewers inherit it
too, though their job is correctness and lazy mode pulls toward deletion — their prompt says
which is which, and `PONYTAIL_SUBAGENT_MATCHER` scopes the injection by agent type for anyone
who wants a harder fence.

These are recommendations, not requirements — the skill checks availability at the relevant
step and proceeds either way.
