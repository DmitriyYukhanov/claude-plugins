# {{SPEC_NAME}} - Test Plan
Version: 0.1

---

## 1. Test Goal

- What the implementation must prove before review or demo.

---

## 2. Strategy

- Unit
- Integration
- End-to-end or end-to-end-equivalent
- Snapshot / golden when output shape matters
- Performance / smoke
- Negative

---

## 3. Fixtures

### F1. Primary Happy-Path Fixture
- ...

### F2. Edge Or Large Fixture
- ...

### F3. Failure Fixture
- ...

---

## 4. Unit Tests

### U-01. Core Rule Or Transform
- Verify:
- Expected:

### U-02. Validation Or Guard
- Verify:
- Expected:

---

## 5. Integration Tests

### I-01. Boundary Or Adapter Flow
Steps:
1. ...
2. ...

Expected:
- ...

### I-02. Persistence Or Multi-Step Workflow
Steps:
1. ...
2. ...

Expected:
- ...

---

## 6. E2E Or End-To-End-Equivalent Tests

### E-01. Primary Happy Path
Steps:
1. ...
2. ...

Expected:
- ...

### E-02. Failure Or Fallback Path
Steps:
1. ...
2. ...

Expected:
- ...

---

## 7. Snapshot / Golden Tests

Add when ranking, rendering, layout, formatting, or deterministic output matters.

### G-01. Example Golden
- Input:
- Expected:

---

## 8. Performance / Smoke Tests

### P-01. Large Input Smoke
- Input:
- Expected:

---

## 9. Negative Tests

### N-01. Validation Failure
- Expected:

### N-02. External Failure / Retry
- Expected:

---

## 10. Exit Criteria

Tie this section directly to the PRD acceptance criteria.

1. ...
2. ...

---

## 11. Recommended Test Stack

- Unit / integration:
- E2E / API flow / worker flow:
- Schema / contract / data-model validation:
- Mocks / fixtures:
