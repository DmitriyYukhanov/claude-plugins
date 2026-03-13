# Spec Bundle Blueprint

Use this blueprint when drafting or reviewing an implementation-ready bundle.

## Standard File Set

| File | Default | Purpose |
| --- | --- | --- |
| `*_prd.md` | Always | Product, system, or feature intent, scope, surfaces, architecture, business rules, acceptance, implementation order |
| `*_contracts.md` | Always | Domain types, external and internal boundaries, payloads, events, validation, errors |
| `*_schema.sql` | Common | SQL schema or migration delta |
| `*_data-model.md` | Common | NoSQL model, frontend state model, integration state, or explicit no-schema-change note |
| `*_testplan.md` | Always | Fixtures, test matrix, negative paths, exit criteria |

Keep the four artifacts aligned. The PRD defines behavior, contracts define interfaces, the storage artifact defines persistence or state shape, and the test plan proves the whole bundle.

## Product PRD Sections

For a net-new product or subsystem, the PRD should usually contain:

1. Short description
2. Context and problem
3. Product goal, KPI, and north star
4. MVP scope, non-goals, and later-phase ideas
5. Assumptions and hard constraints
6. Persona or primary operator
7. User stories by stage of the workflow
8. End-to-end scenarios
9. Functional requirements grouped as `FR-*`
10. Internal systems or algorithm notes for the core differentiator
11. Experience surfaces such as screens, routes, endpoints, commands, or jobs
12. Architecture and recommended stack
13. Logical flow and module boundaries
14. Data model overview and invariants
15. Business rules
16. Non-functional requirements
17. Security, privacy, licensing, billing, or quota behavior
18. Acceptance criteria
19. Epic breakdown for implementation
20. Suggested implementation order or phases
21. Default technical decisions the coding agent should assume
22. Key risks and mitigations
23. Demo script if live review matters
24. Definition of Done

## System PRD Sections

For a backend service, platform module, worker pipeline, API product, or internal subsystem, the PRD should usually contain:

1. System summary and ownership
2. Current state and problem
3. Goal, service objective, and explicit non-goals
4. Consumers, callers, or operators
5. Core workflows and failure modes
6. Functional requirements grouped as `FR-*`
7. Interfaces and boundary contracts
8. Architecture and deployment model
9. State model, storage model, or explicit no-storage note
10. Operational concerns such as retries, idempotency, observability, backpressure, and rate limits
11. Security, privacy, and compliance rules
12. Acceptance criteria
13. Implementation phases
14. Risks and mitigations
15. Definition of Done

## Feature PRD Sections

For a complex feature inside an existing product, bias toward deltas:

1. Feature summary and consumer-visible, operator-visible, or system-visible outcome
2. Current state and problem
3. Goal, success metric, and explicit non-goals
4. Constraints from the existing product, service, or platform
5. Personas or roles affected
6. Triggering user stories and workflows
7. Functional requirements grouped as `FR-*`
8. Integration points and architecture delta
9. Storage or data-model delta, or explicit no-schema-change note
10. State transitions and background jobs
11. Rollout, migration, or entitlement implications
12. Acceptance criteria
13. Implementation phases
14. Risks and mitigations
15. Definition of Done

## Contracts File

The contracts file should answer "what must be implemented at every boundary?" Include only the boundaries that exist for the target system:

- domain types and enums;
- repository or service contracts;
- API routes, RPC methods, webhooks, IPC calls, CLI interfaces, queue messages, or event payloads;
- long-running job status models and progress events;
- validation rules and invariants;
- error codes and envelopes;
- provider abstractions or third-party adapter contracts when the design is pluggable.

Prefer typed examples over prose. The consumer of this file should be able to sketch handlers, clients, and tests directly from it.

## Storage Artifact

When the system persists durable relational state, the schema file should define:

- entities or tables;
- primary and foreign keys;
- lifecycle status fields and allowed values;
- uniqueness, check constraints, and invariants;
- audit fields such as `created_at` and `updated_at`;
- indexes only when they materially affect correctness or expected access paths.

If the system is frontend-only, uses NoSQL, stores state in files, or adds no durable relational storage, use `*_data-model.md` instead. Describe the state shape, lifecycle, invariants, ownership, and why there is no SQL schema delta.

## Test Plan File

Use the test plan to prove the bundle is implementable:

- fixture list;
- unit tests for pure rules and transforms;
- integration tests for persistence, adapters, or multi-step workflows;
- E2E or end-to-end-equivalent tests for the main user, API, operator, or automation journeys;
- golden or snapshot tests when layout, rendering, generated output, or deterministic ranking matters;
- performance or smoke tests for large inputs or expensive stages;
- negative tests for validation, quota, entitlement, and retry behavior;
- exit criteria tied back to the PRD acceptance criteria.

## Cross-File Alignment Rules

Apply these checks before finalizing:

- Every `FR-*` in the PRD maps to at least one contract and one test.
- Every persisted lifecycle state appears consistently in PRD text, contract enums, and schema constraints or data-model rules.
- Every external dependency named in the PRD has a contract and at least one failure-path test.
- Every acceptance criterion is measurable and appears again in the test plan exit criteria.
- Default stack and architecture choices in the PRD do not conflict with the contracts or storage artifact.

If any file introduces a new noun, ID format, state, or limit, update the others or remove the mismatch.
