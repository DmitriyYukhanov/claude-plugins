---
name: run-tests
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

Run Unity Test Framework tests using the `unity-test-runner` agent.

Spawn the `unity-test-runner` agent to execute the tests. Pass along any arguments the user provided:

- Platform: `$ARGUMENTS.platform` (or EditMode if not specified)
- Category: `$ARGUMENTS.category` (if provided)
- Filter: `$ARGUMENTS.filter` (if provided)

The agent will:
1. Auto-detect the Unity project path from the current working directory
2. Auto-detect the Unity editor installation via Unity Hub CLI
3. Run the tests in batchmode
4. Report results with pass/fail summary and failure details

## Usage Examples

```
/run-tests                              # Run all EditMode tests
/run-tests PlayMode                     # Run all PlayMode tests
/run-tests EditMode E2E                 # Run EditMode tests in E2E category
/run-tests EditMode "" MonoBuild        # Run tests matching "MonoBuild" filter
```
