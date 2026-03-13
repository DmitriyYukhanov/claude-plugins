-- {{SPEC_NAME}} - schema or schema delta
-- Replace the placeholders below with real DDL.
-- If the feature has no durable storage change, keep this file and state that explicitly.

PRAGMA foreign_keys = ON;

-- Example:
-- CREATE TABLE IF NOT EXISTS example_entity (
--   id TEXT PRIMARY KEY,
--   status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'completed', 'failed')),
--   payload_json TEXT NOT NULL DEFAULT '{}',
--   created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
--   updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
-- );

-- Capture:
-- 1. durable entities and keys;
-- 2. lifecycle status constraints;
-- 3. foreign keys and deletion behavior;
-- 4. uniqueness and check constraints;
-- 5. indexes only when they materially affect expected access paths.

-- Invariants:
-- - ...
-- - ...
