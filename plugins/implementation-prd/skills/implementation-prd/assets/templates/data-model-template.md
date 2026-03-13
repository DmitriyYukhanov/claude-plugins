# {{SPEC_NAME}} - Data Model
Version: 0.1

Use this file when the work does not need a relational SQL schema or when state is represented in another form.

---

## 1. State Summary

- What state exists.
- Why it exists.
- Which component owns it.

---

## 2. Entities Or State Shapes

List the important entities, documents, in-memory structures, files, cache records, or client-side stores.

---

## 3. Lifecycle And Invariants

- Allowed states and transitions.
- Ownership rules.
- Uniqueness, deduplication, idempotency, or retention rules.

---

## 4. Persistence Or Storage Strategy

- Where state lives: browser storage, filesystem, document DB, cache, external service, or no durable storage.
- Serialization format.
- Recovery, reconciliation, or migration notes.

---

## 5. Keys And Relationships

- IDs, lookup keys, partition keys, or foreign-key-like references.
- Relationship rules and deletion behavior.

---

## 6. No-Schema Note

If there is intentionally no durable storage change, state that explicitly here and explain why the feature does not require a schema delta.
