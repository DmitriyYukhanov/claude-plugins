# {{SPEC_NAME}} - Contracts
Version: 0.1

Use this file to define every important boundary in implementation-oriented form.

---

## 1. Domain Types

```ts
export type ExampleStatus = 'queued' | 'running' | 'completed' | 'failed';

export interface ExampleEntity {
  id: string;
  status: ExampleStatus;
  createdAt: string;
  updatedAt: string;
}
```

---

## 2. Internal Boundaries

Add only the boundaries that exist in the target system:

- service-to-service contracts;
- renderer-to-main or client-to-worker contracts;
- route, controller, or command-handler contracts;
- background job requests and responses;
- queue, webhook, or event payloads;
- SDK, CLI, or automation entry points.

### 2.1 Example Command

```ts
type StartExampleRequest = {
  entityId: string;
};

type StartExampleResponse = {
  jobId: string;
  status: ExampleStatus;
};
```

### 2.2 Example Progress Event

```ts
type ExampleProgressEvent = {
  jobId: string;
  status: ExampleStatus;
  progress: number; // 0..1
  message?: string;
};
```

---

## 3. External Contracts

Add REST, GraphQL, RPC, webhook, CLI, file-format, or provider contracts here.

### 3.1 Example Boundary

`POST /v1/examples`

Request:

```json
{
  "name": "example"
}
```

Response 200:

```json
{
  "id": "ex_123",
  "status": "queued"
}
```

---

## 4. Validation Rules

- State and field invariants.
- Length, range, and timing constraints.
- Cross-field rules.

---

## 5. Error Codes

```ts
type AppErrorCode =
  | 'EXAMPLE_NOT_FOUND'
  | 'EXAMPLE_INVALID'
  | 'EXAMPLE_CONFLICT'
  | 'EXAMPLE_FAILED';
```

### Error Envelope

```json
{
  "error": {
    "code": "EXAMPLE_FAILED",
    "message": "Human-readable failure message.",
    "details": {
      "jobId": "job_123"
    }
  }
}
```
