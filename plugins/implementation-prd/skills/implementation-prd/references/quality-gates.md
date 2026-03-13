# Quality Gates

Use this checklist before calling a bundle implementation-ready.

## Decision Quality

- Choose a default architecture, storage model, and integration pattern whenever the decision is obvious from the context.
- Avoid "could use X or Y" unless the user explicitly wants options.
- Keep the scope narrow enough for one implementation pass.

## Scope Quality

- State the MVP clearly.
- State explicit non-goals.
- Separate future ideas from the MVP so they do not leak into implementation.
- Make assumptions visible if the user did not provide enough detail.

## Execution Quality

- Define at least one happy path end to end.
- Define at least one failure path for each risky stage.
- Model long-running work with job state, progress, retry, and restart safety when applicable.
- Include entitlement, quota, security, privacy, or compliance rules if the feature touches them.

## Interface Quality

- Keep contracts serializable and implementation-oriented.
- Name enums and states once, then reuse them exactly.
- Include validation rules and error envelopes.
- Specify provider abstractions when behavior can vary behind a stable interface.

## Data Quality

- Persist only durable state that the system actually needs.
- Capture key invariants directly in the schema or explicit data-model artifact.
- State when there is no schema delta instead of silently omitting the topic.

## Test Quality

- Prove the main workflow with E2E or end-to-end-equivalent coverage.
- Prove core logic with unit tests.
- Prove boundaries with integration tests.
- Add negative and retry cases for failure-prone paths.
- Add golden or snapshot checks when output shape, ranking, formatting, rendering, or protocol output is part of the system value.

## Bundle-Level Red Flags

The bundle is not ready if any of these remain:

- vague acceptance criteria such as "works well" or "feels fast";
- unresolved TODOs in core flows;
- missing failure behavior for background or external calls;
- contracts that introduce types or states not defined elsewhere;
- schema states or data-model states that the PRD never explains;
- test plan that merely repeats requirements without concrete fixtures or expected results.

## Final Read-Through

Before handing the bundle to a coding agent:

1. Read the PRD as the owner of the target surface. The scope should be sharp whether this is a product, service, platform module, or feature.
2. Read the contracts as an implementer. The interfaces should be buildable.
3. Read the storage artifact as a persistence or state owner. The invariants should be explicit.
4. Read the test plan as a reviewer. The exit criteria should prove acceptance.

If one of those reads fails, fix the bundle before implementation starts.
