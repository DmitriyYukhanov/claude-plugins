# PRD - {{SYSTEM_NAME}}
Version: 0.1
Status: Draft / Implementation-ready
Language: {{LANGUAGE}}
Audience: AI coding agent + human reviewer

Use this template for backend services, APIs, workers, platform modules, internal tools, or other system-first deliverables.

---

## 1. System Summary

- What the system or subsystem is.
- Who owns it.
- What outcome it produces for callers, operators, or downstream systems.

---

## 2. Current State And Problem

- What exists today.
- Which failure, bottleneck, or capability gap this system addresses.
- Why now.

---

## 3. Goal And Service Objective

### 3.1 Primary Goal
- One clear sentence.

### 3.2 Success Metric
- Throughput, latency, accuracy, reliability, adoption, or another measurable outcome.

### 3.3 Non-Goals
- Explicit exclusions.

---

## 4. Consumers And Operators

- Which clients, services, admins, operators, or automations interact with the system.
- Any important assumptions about trust boundaries or traffic shape.

---

## 5. Core Workflows

### Workflow A - Primary Happy Path
1. ...
2. ...

### Workflow B - Retry / Recovery Path
1. ...
2. ...

### Workflow C - Failure / Degraded Mode
1. ...
2. ...

---

## 6. Functional Requirements

Write each capability as `FR-*`.

### FR-1. Ingress / Trigger
- Inputs, validation, auth, rate limits.

### FR-2. Core Processing
- Main behavior.
- State transitions and side effects.

### FR-3. Delivery / Output
- Response, event, artifact, or downstream update behavior.

### FR-4. Operations
- Retries, idempotency, observability, backpressure, or administrative controls.

---

## 7. Interfaces And Contracts

- APIs, RPC methods, commands, events, webhooks, schedulers, or worker boundaries.
- Contract ownership.
- Versioning expectations if relevant.

---

## 8. Architecture And Deployment

### 8.1 Recommended Stack
- Runtime
- Framework
- Storage
- Async processing
- Validation
- Testing

### 8.2 Architectural Principles
- Separation of synchronous and asynchronous work.
- Idempotency and retry boundaries.
- Isolation of external dependencies.

### 8.3 Main Modules
1. ...
2. ...

---

## 9. State And Storage Model

- Durable entities, caches, queues, files, or in-memory state.
- Ownership and lifecycle.
- Reference the schema or data-model artifact.

---

## 10. Operational Model

- Logging, metrics, tracing.
- Alerting or error visibility.
- Concurrency, rate limiting, and backpressure.
- Retry and dead-letter behavior.

---

## 11. Security / Privacy / Compliance

- Authentication and authorization.
- Sensitive data handling.
- Multi-tenant isolation, auditability, or regulatory constraints if relevant.

---

## 12. Acceptance Criteria

Numbered, objective, and testable.

---

## 13. Implementation Phases

### Phase 1 - Minimum Working Slice
- ...

### Phase 2 - Reliability And Operations
- ...

### Phase 3 - Hardening And Rollout
- ...

---

## 14. Default Technical Decisions

List the decisions the coding agent should assume instead of debating:

1. ...
2. ...
3. ...

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
- Storage or data-model changes exist where needed.
- Happy-path and failure-path tests exist.
- Observability and error handling exist where relevant.
- The system is reachable from the intended API, command, job, or operator flow.
