#!/usr/bin/env bash
# find-unity.sh — Detect Unity editor path for a given project.
# Usage: find-unity.sh <project-path>
# Output: Full path to Unity.exe on stdout.
# Exit codes: 0 = found, 1 = not found.

set -euo pipefail

PROJECT_PATH="${1:?Usage: find-unity.sh <project-path>}"

# --- Step 1: Read Unity version from project ---
VERSION_FILE="$PROJECT_PATH/ProjectSettings/ProjectVersion.txt"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "ERROR: ProjectVersion.txt not found at $VERSION_FILE" >&2
  exit 1
fi

# Extract version (e.g., "2021.3.0f1") from "m_EditorVersion: 2021.3.0f1"
UNITY_VERSION=$(grep -oP '(?<=m_EditorVersion: )\S+' "$VERSION_FILE")
if [[ -z "$UNITY_VERSION" ]]; then
  echo "ERROR: Could not parse Unity version from $VERSION_FILE" >&2
  exit 1
fi
echo "Detected Unity version: $UNITY_VERSION" >&2

# --- Step 2: Try Unity Hub CLI ---
HUB_PATHS=(
  "C:/Program Files/Unity Hub/Unity Hub.exe"
  "$LOCALAPPDATA/Programs/Unity Hub/Unity Hub.exe"
  "$HOME/AppData/Local/Programs/Unity Hub/Unity Hub.exe"
)

for HUB in "${HUB_PATHS[@]}"; do
  if [[ -f "$HUB" ]]; then
    echo "Querying Unity Hub at: $HUB" >&2
    # Unity Hub CLI outputs lines like: "2021.3.0f1 , installed at C:\Program Files\Unity\Hub\Editor\2021.3.0f1\Editor\Unity.exe"
    HUB_OUTPUT=$("$HUB" -- --headless editors -i 2>/dev/null || true)
    if [[ -n "$HUB_OUTPUT" ]]; then
      # Parse: find line matching our version and extract the path
      EDITOR_PATH=$(echo "$HUB_OUTPUT" | grep -i "$UNITY_VERSION" | grep -oP '(?<=installed at )\S+.*' | sed 's/[[:space:]]*$//' | head -1)
      if [[ -n "$EDITOR_PATH" ]]; then
        # Convert backslashes to forward slashes for bash compatibility
        EDITOR_PATH="${EDITOR_PATH//\\//}"
        if [[ -f "$EDITOR_PATH" ]]; then
          echo "$EDITOR_PATH"
          exit 0
        fi
      fi
    fi
    break
  fi
done

# --- Step 3: Fallback — check well-known installation paths ---
KNOWN_PATHS=(
  "C:/Program Files/Unity/Hub/Editor/$UNITY_VERSION/Editor/Unity.exe"
  "C:/Program Files/Unity/$UNITY_VERSION/Editor/Unity.exe"
  "$HOME/Unity/Hub/Editor/$UNITY_VERSION/Editor/Unity.exe"
)

for CANDIDATE in "${KNOWN_PATHS[@]}"; do
  if [[ -f "$CANDIDATE" ]]; then
    echo "Found Unity at well-known path: $CANDIDATE" >&2
    echo "$CANDIDATE"
    exit 0
  fi
done

echo "ERROR: Unity $UNITY_VERSION not found. Checked Unity Hub CLI and well-known paths." >&2
echo "Install Unity $UNITY_VERSION via Unity Hub or pass --unity-path explicitly." >&2
exit 1
