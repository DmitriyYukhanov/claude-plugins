# Demo Refactor Plan

Synthetic plan for the learning-guide plugin's `refactor-plan` archetype.

## Phase 1 — Test harness

Establish characterization tests for the legacy reconciler before any rewrite. Acceptance: green CI with no flaky tests.

## Phase 2 — Provider isolation

Wrap the existing third-party SDK behind an internal contract. Acceptance: legacy callers compile against the new interface.

## Phase 3 — Rollout

Roll out via experiment configs at 5% → 25% → 100%. Halt criterion: error rate exceeds 0.5% over a 1-hour window.

## Blockers

- DOC-100 — onboarding wiki update pending docs team.
- TICKET-101 — pipeline schema sign-off.

## Risks

1. Provider rate limits during isolation phase.
2. Experiment skew if user IDs are not hashed consistently.
