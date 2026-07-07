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
| Diff review loop (Step 7) | `/code-review` | A manual diff read for correctness, reuse, and regressions; iterate. |

## Install hints (same marketplace)

- `humanizer` and `codex-collaboration` ship in this marketplace
  (`DmitriyYukhanov/claude-plugins`): `/plugin install humanizer`,
  `/plugin install codex-collaboration`. `codex-collaboration` additionally needs the Codex
  plugin and `/codex:setup`.
- `superpowers:*` is the external Superpowers plugin. `/deep-research` and `/code-review`
  come from your own setup or other plugins.

These are recommendations, not requirements — the skill checks availability at the relevant
step and proceeds either way.
