# PRD - {{FEATURE_NAME}}
Version: 0.1
Status: Draft / Implementation-ready
Language: {{LANGUAGE}}
Audience: AI coding agent + human reviewer

---

## 1. Feature Summary

- What the feature adds to the existing product, service, or platform.
- The consumer-visible, operator-visible, or system-visible outcome.
- Why this is being added now.

---

## 2. Current State And Problem

- What exists today.
- Where the current system or workflow fails.
- What pain this feature removes.

---

## 3. Goal And Success Metric

### 3.1 Feature Goal
- One clear sentence.

### 3.2 Success Metric
- Measurable outcome.

### 3.3 Non-Goals
- Explicit exclusions.

---

## 4. Constraints From The Existing System

- Existing architecture or surface area the feature must respect.
- Rollout, migration, entitlement, or compatibility constraints.

---

## 5. Personas And Affected Roles

- Primary actor.
- Secondary actors or reviewers.

---

## 6. User Stories

### Primary Flow
- As a {{persona}}, I want ...

### Operator / Caller / Support Flow
- As a {{role_or_system}}, I want ...

### Failure / Recovery Flow
- As a {{persona}}, I want ...

---

## 7. Main Scenarios

### Scenario A - Primary Happy Path
1. ...
2. ...

### Scenario B - Existing State Migration Or Upgrade
1. ...
2. ...

### Scenario C - Failure Or Retry Path
1. ...
2. ...

---

## 8. Functional Requirements

Write each capability as `FR-*`.

### FR-1. Entry Point
- Trigger and validation.
- Caller-visible, user-visible, or operator-visible states.

### FR-2. Core Behavior
- Main logic.
- Persistence and side effects.

### FR-3. Async / Background Work
- Job states, progress, retry, restart.

---

## 9. Architecture Delta

- Which existing modules change.
- Which new modules or services are introduced.
- Which boundaries need contracts.

---

## 10. Data-Model Delta

- New entities, fields, indexes, migrations, or state shapes.
- Or explicit statement that there is no schema delta and where state lives instead.

---

## 11. State Machine And Error Handling

- Lifecycle states.
- Validation rules.
- Recoverable vs terminal failures.

---

## 12. Security / Privacy / Entitlement

- Access control.
- Data handling.
- Billing, quota, or licensing effects.

---

## 13. Acceptance Criteria

Numbered, objective, and testable.

---

## 14. Implementation Phases

### Phase 1 - Minimum Working Slice
- ...

### Phase 2 - Interfaces / Reliability
- ...

### Phase 3 - Hardening
- ...

---

## 15. Risks And Mitigations

### Risk 1 - ...
- Mitigation:

### Risk 2 - ...
- Mitigation:

---

## 16. Definition Of Done

- Code exists.
- Changed boundaries have contracts.
- Storage or data-model changes are captured or explicitly not needed.
- Happy-path and failure-path tests exist.
- Errors are actionable.
- The feature is reachable from the intended existing flow or system entry point.
