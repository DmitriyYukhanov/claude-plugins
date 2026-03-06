---
name: unity-tests-run
description: Run Unity Test Framework tests via CLI batchmode with auto-detection of Unity installation
arguments:
  - name: platform
    description: "Test platform: EditMode, PlayMode (default: EditMode)"
    required: false
  - name: category
    description: "Test category filter (semicolon-separated, e.g., 'E2E;Integration')"
    required: false
  - name: filter
    description: "Test name filter (semicolon-separated or regex, e.g., 'MonoBuild')"
    required: false
---

# Run Unity Tests

Spawn the `unity-test-runner` agent with these parameters:

- Platform: `$ARGUMENTS.platform` (default: EditMode)
- Category: `$ARGUMENTS.category` (if provided)
- Filter: `$ARGUMENTS.filter` (if provided)
- User's original request for any additional context
