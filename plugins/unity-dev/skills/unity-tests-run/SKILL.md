---
name: unity-tests-run
description: Run Unity Test Framework tests via CLI batchmode with auto-detection of Unity installation
argument-hint: "[EditMode|PlayMode] [category] [filter]"
---

# Run Unity Tests

**Depends on:** unity-dev:unity-run for Unity CLI detection and execution.

Spawn the `unity-test-runner` agent with these parameters:

- Platform: `$ARGUMENTS.platform` (default: EditMode)
- Category: `$ARGUMENTS.category` (if provided)
- Filter: `$ARGUMENTS.filter` (if provided)
- User's original request for any additional context
