# Live2Reels Source Map

This skill was derived from a four-file implementation bundle for `Live2Reels Desktop`. Use this file as a compact worked example of what "implementation-ready" means.

## Bundle Shape

The source bundle contained:

- `live2reels_prd_ru.md`
- `live2reels_contracts.md`
- `live2reels_schema.sql`
- `live2reels_testplan.md`

That shape became the default output of this skill.

## What The PRD Demonstrated

The PRD did not stop at product narrative. It included:

- product summary, context, goals, KPI, and north star;
- MVP scope, non-goals, and future ideas;
- assumptions, persona, user stories, and end-to-end scenarios;
- functional requirements grouped by capability;
- internal algorithm notes for highlight detection and scoring;
- UX screen inventory;
- recommended stack and architecture principles;
- data-model overview, invariants, and business rules;
- non-functional requirements, security, privacy, and licensing;
- acceptance criteria, epic breakdown, phased implementation order;
- default technical decisions, risk mitigation, demo flow, and Definition of Done.

The key lesson: an implementation-ready PRD picks defaults and names constraints instead of leaving them implicit.

## What The Contracts Demonstrated

The contracts file covered four layers:

1. domain types and enums;
2. IPC contracts between UI and background services;
3. HTTP contracts for auth, subscription, and cloud analysis;
4. render input props plus validation and error envelopes.

The key lesson: if the product crosses a boundary, the bundle should define that boundary explicitly.

## What The Schema Demonstrated

The schema was not a toy example. It modeled:

- user and license state;
- project and source assets;
- transcription, analysis, render, and export jobs;
- highlight candidates and reel scripts;
- usage metering and settings.

The key lesson: durable workflow stages and restart-safe pipelines need first-class persisted state.

## What The Test Plan Demonstrated

The test plan covered:

- fixtures;
- unit tests for normalization, scoring, chunking, and guards;
- integration tests for ingest, transcription, analysis, render, auth, and restart resilience;
- E2E happy paths and fallback paths;
- golden or snapshot checks for ranking and rendering;
- performance or smoke tests;
- negative tests;
- exit criteria for demo readiness.

The key lesson: the test plan should verify the bundle's claims, especially for async pipelines and generated output.

## Design Patterns Worth Reusing

- Keep the MVP vertical slice smaller than the full product vision.
- Separate deterministic pre-processing from provider-specific or AI-powered stages.
- Make pluggable providers explicit in contracts and entitlement rules.
- Prefer form-based or structured editing over building a full editor too early.
- Make render props and background job payloads fully serializable.
- Design every long-running stage to survive restart or crash.

## Adaptation Guidance

When adapting this pattern to another product or feature:

- keep the section structure, but swap in domain-specific entities and workflows;
- keep the same cross-file discipline between PRD, contracts, schema, and test plan;
- trim sections that do not apply only after stating why they are absent;
- preserve acceptance criteria, phased implementation order, risks, and Definition of Done, because those are what make the bundle executable by another agent.
