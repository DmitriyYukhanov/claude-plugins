# PRD - {{PRODUCT_NAME}}
Version: 0.1
Status: Draft / Implementation-ready
Language: {{LANGUAGE}}
Audience: AI coding agent + human reviewer

---

## 1. Short Description

- What the product or user-facing system is.
- What end-to-end workflow it enables.
- Why the user should prefer this over the current fragmented workflow.

---

## 2. Context And Problem

- Current workflow and where time or quality is lost.
- Existing tools or system constraints.
- Why this matters now.

---

## 3. Product Goal

### 3.1 Primary Goal
- One clear sentence.

### 3.2 MVP KPI
- Measurable outcomes the user must achieve in one session.

### 3.3 North Star
- One sentence.

---

## 4. MVP Scope

### 4.1 In Scope
- Core capabilities only.

### 4.2 Out Of Scope
- Explicit non-goals that protect the MVP.

### 4.3 Later Versions
- Optional future ideas. Keep separate from MVP.

---

## 5. Assumptions And Constraints

- Platform or deployment model.
- Data sensitivity and privacy constraints.
- Licensing, quota, billing, or entitlement constraints.
- Any default technical assumptions the implementation should inherit.

---

## 6. Persona

### Primary Persona
- Who uses the product.
- What they are trying to accomplish.
- Why they care.

---

## 7. User Stories

Group stories by stage of the workflow.

### Ingestion
- As a {{persona}}, I want ...

### Core Workflow
- As a {{persona}}, I want ...

### Editing / Review
- As a {{persona}}, I want ...

### Export / Delivery
- As a {{persona}}, I want ...

---

## 8. Main Scenarios

### Scenario A - Primary Happy Path
1. ...
2. ...

### Scenario B - Alternative Input Or Fallback
1. ...
2. ...

### Scenario C - Failure Recovery
1. ...
2. ...

---

## 9. Functional Requirements

Write each capability as `FR-*`.

### FR-1. Example Capability
- Required behavior.
- States, limits, and validation.
- User-visible, caller-visible, or operator-visible errors or retry path.

### FR-2. Example Capability
- ...

---

## 10. Internal Systems

- Core algorithm, ranking model, orchestration rules, or provider abstraction.
- Default implementation strategy for MVP.
- Structured output expected from the internal system.

---

## 11. Experience Surfaces

- Surface inventory such as screens, routes, admin panels, commands, web views, or extension points.
- What the user or operator can do in each surface.
- Loading, progress, empty, and error states.

---

## 12. Architecture

### 12.1 Recommended Stack
- Runtime
- Client or UI surfaces, if any
- Storage
- Validation
- Background job execution, async processing, or orchestration
- Testing

### 12.2 Architectural Principles
- Separation of concerns.
- Async work placement.
- Local vs remote responsibilities.

### 12.3 Main Modules
1. ...
2. ...

---

## 13. Logical Flow

Add a Mermaid or prose flow showing the end-to-end pipeline.

---

## 14. Data Model Overview

- Reference the schema file.
- List major entities and invariants.

---

## 15. Business Rules

- Gating, quotas, permissions, privacy, billing, or workflow constraints.

---

## 16. Non-Functional Requirements

- Performance
- Reliability
- Maintainability

---

## 17. Security, Privacy, And Compliance

- Authentication and authorization model.
- Data sensitivity classification and handling rules.
- Privacy controls, consent, or data-retention policy.
- Licensing, billing, quota, or entitlement enforcement.
- Compliance requirements if applicable.

---

## 18. Acceptance Criteria

Numbered, objective, and testable.

---

## 19. Epics For The Coding Agent

### Epic A - Foundation
- A1:
- A2:

### Epic B - Core Workflow
- B1:
- B2:

### Epic C - Hardening
- C1:
- C2:

---

## 20. Suggested Implementation Order

### Phase 1 - Vertical Slice
- ...

### Phase 2 - Main Surfaces And Workflows
- ...

### Phase 3 - Reliability / Access / Hardening
- ...

---

## 21. Default Technical Decisions

List the decisions the coding agent should assume instead of debating:

1. ...
2. ...
3. ...

---

## 22. Risks And Mitigations

### Risk 1 - ...
- Mitigation:

### Risk 2 - ...
- Mitigation:

---

## 23. Demo Script

Number the live demo flow if stakeholders will review the result interactively.

---

## 24. Definition Of Done

- Code exists.
- Contract changes exist where needed.
- Storage artifact changes exist where needed.
- Happy-path tests exist.
- Error handling exists.
- The user or operator can reach the capability from the intended surface or entry point.
- Long-running state survives restart when applicable.
