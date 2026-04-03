---
name: unity-run
description: Use when running Unity from CLI for any purpose — builds, tests, method execution, asset imports. Handles Unity installation detection, batchmode execution, and log monitoring. Other unity-dev skills depend on this for CLI execution.
---

# Run Unity CLI

Execute Unity in batchmode from the command line. This skill handles finding the Unity installation and constructing the CLI command. Calling skills (tests, builds) provide the specific flags.

## Step 1: Find the Unity project

Starting from the current working directory, locate `ProjectSettings/ProjectVersion.txt` by walking up or using Glob. The directory containing `ProjectSettings/` is the project root.

If the user provides a project path explicitly, use that instead.

## Step 2: Detect Unity installation

Use the plugin's detection script:

```bash
UNITY_PATH=$("${CLAUDE_PLUGIN_ROOT}/scripts/find-unity.sh" "<project-root>")
```

The script auto-detects Unity via Hub config, default paths, and Hub CLI fallback. It reads the project's `ProjectVersion.txt` to find the matching editor version.

If detection fails, ask the user to set `UNITY_EDITOR_PATH` environment variable.

## Step 3: Build and run the command

Construct the Unity CLI command with batchmode defaults:

```bash
"$UNITY_PATH" -batchmode -projectPath "<project-root>" <caller-flags> -logFile - -quit
```

**Defaults (always include unless caller overrides):**
- `-batchmode` — no GUI
- `-projectPath` — the detected project root
- `-logFile -` — stream log to stdout (use a file path if caller needs to parse logs separately)
- `-quit` — exit after execution

**Caller provides:** the purpose-specific flags (e.g., `-runTests`, `-buildTarget`, `-executeMethod`).

**Timeout:** Set to 600000ms (10 minutes) by default. Builds may need longer — caller can override.

## Step 4: Report results

After execution:
- Report Unity exit code (0 = success, non-zero = failure)
- If `-logFile -` was used, relevant log output is already in stdout
- If a log file was used, read the last 50 lines on failure for diagnostics

## Common flags reference

| Purpose | Flags |
|---------|-------|
| Run tests | `-runTests -testPlatform EditMode -testResults <path>` |
| Android build | `-buildTarget Android -executeMethod <method>` |
| iOS build | `-buildTarget iOS -executeMethod <method>` |
| Execute method | `-executeMethod <ClassName.MethodName>` |
| Import assets | `-importPackage <path>` |
| No graphics | `-nographics` (add for headless servers) |

## Platform notes

- **Windows:** Unity path uses forward slashes in bash. The detection script handles conversion.
- **PATH inheritance:** Unity inherits PATH from its parent process (Unity Hub). After PATH changes, restart Hub + Editor.
