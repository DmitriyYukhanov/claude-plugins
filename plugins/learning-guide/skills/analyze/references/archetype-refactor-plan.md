# Archetype: refactor-plan

Use when the input is a phased refactoring/migration plan — typical signals: "Phase 1", "rollout", "blockers", "halt criterion", per-phase acceptance gates.

## Section outline (suggested order)

1. **Introduction** — what is being refactored and why.
2. **Architecture before / after** — current vs target shape.
3. **Per-phase walkthroughs** — one section per phase. Include the phase's hard gates.
4. **Blockers** — external dependencies, with owners.
5. **Risks** — known unknowns, mitigations.
6. **Rollout** — how the change reaches users; halt criteria.

## What to look for

- Phase numbering and dependencies — capture as cross-refs into the plan/research docs.
- Hard gates — translate into `:::callout {type=warn}` blocks in the right phase section.
- Halt criteria — translate into `:::callout {type=danger}` blocks.

## Quizzes that work for refactor-plan

- "Which phase ships first?"
- "What gates phase N from starting?"
- "Where is the halt criterion checked?"

## Tone

Decisive. Do not hedge in the body; if the plan does not commit on something, that's a blocker section.
