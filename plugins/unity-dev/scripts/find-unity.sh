#!/usr/bin/env bash
# find-unity.sh — Detect Unity editor path for a given project.
# Usage: find-unity.sh <project-path>
# Output: Full path to Unity editor binary on stdout.
# Exit codes: 0 = found, 1 = not found.
#
# Detection order:
#   1. UNITY_EDITOR_PATH environment variable (direct override)
#   2. Unity Hub install path (from config or CLI) + project version

set -euo pipefail

PROJECT_PATH="${1:?Usage: find-unity.sh <project-path>}"

# --- Read Unity version from project ---
VERSION_FILE="$PROJECT_PATH/ProjectSettings/ProjectVersion.txt"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "ERROR: ProjectVersion.txt not found at $VERSION_FILE" >&2
  exit 1
fi

UNITY_VERSION=$(grep -oP '(?<=m_EditorVersion: )\S+' "$VERSION_FILE")
if [[ -z "$UNITY_VERSION" ]]; then
  echo "ERROR: Could not parse Unity version from $VERSION_FILE" >&2
  exit 1
fi
echo "Detected Unity version: $UNITY_VERSION" >&2

# --- Step 1: UNITY_EDITOR_PATH env var (direct override) ---
if [[ -n "${UNITY_EDITOR_PATH:-}" ]]; then
  UNITY_EDITOR_PATH="${UNITY_EDITOR_PATH//\\//}"
  if [[ -f "$UNITY_EDITOR_PATH" ]]; then
    echo "$UNITY_EDITOR_PATH"
    exit 0
  fi
  echo "WARNING: UNITY_EDITOR_PATH set but not found: $UNITY_EDITOR_PATH" >&2
fi

# --- Step 2: Find Unity via Hub ---

# Determine OS-specific paths
detect_os() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|*_NT*) echo "windows" ;;
    Darwin*)                     echo "macos" ;;
    Linux*)                      echo "linux" ;;
    *)                           echo "unknown" ;;
  esac
}

OS="$(detect_os)"

# Get Hub AppData directory (where secondaryInstallPath.json lives)
get_hub_appdata() {
  case "$OS" in
    windows) echo "${APPDATA:-$HOME/AppData/Roaming}/UnityHub" ;;
    macos)   echo "$HOME/Library/Application Support/UnityHub" ;;
    linux)   echo "${XDG_CONFIG_HOME:-$HOME/.config}/UnityHub" ;;
  esac
}

# Get default editor install path (when no custom path is configured)
get_default_install_path() {
  case "$OS" in
    windows) echo "C:/Program Files/Unity/Hub/Editor" ;;
    macos)   echo "/Applications/Unity/Hub/Editor" ;;
    linux)   echo "$HOME/Unity/Hub/Editor" ;;
  esac
}

# Construct editor binary path from install root + version
get_editor_binary() {
  local install_root="$1"
  install_root="${install_root//\\//}"
  case "$OS" in
    windows) echo "$install_root/$UNITY_VERSION/Editor/Unity.exe" ;;
    macos)   echo "$install_root/$UNITY_VERSION/Unity.app/Contents/MacOS/Unity" ;;
    linux)   echo "$install_root/$UNITY_VERSION/Editor/Unity" ;;
  esac
}

# Get Unity Hub binary path
get_hub_binary() {
  case "$OS" in
    windows)
      local candidates=(
        "C:/Program Files/Unity Hub/Unity Hub.exe"
        "${LOCALAPPDATA:-$HOME/AppData/Local}/Programs/Unity Hub/Unity Hub.exe"
      )
      ;;
    macos)
      local candidates=(
        "/Applications/Unity Hub.app/Contents/MacOS/Unity Hub"
      )
      ;;
    linux)
      local candidates=(
        "/usr/bin/unity-hub"
        "/opt/unityhub/unityhub"
        "$HOME/Applications/Unity Hub.AppImage"
      )
      ;;
  esac
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

# --- Step 2a: Read install path from Hub config (fast, no process launch) ---
HUB_APPDATA="$(get_hub_appdata)"
SECONDARY_PATH_FILE="$HUB_APPDATA/secondaryInstallPath.json"

if [[ -f "$SECONDARY_PATH_FILE" ]]; then
  # File contains a JSON string like: "D:\\Path\\To\\Installs"
  INSTALL_ROOT=$(sed 's/^"//;s/"$//;s/\\\\/\//g' "$SECONDARY_PATH_FILE")
  EDITOR_BIN="$(get_editor_binary "$INSTALL_ROOT")"
  if [[ -f "$EDITOR_BIN" ]]; then
    echo "Found via Hub config: $EDITOR_BIN" >&2
    echo "$EDITOR_BIN"
    exit 0
  fi
  echo "Hub config install path exists but Unity $UNITY_VERSION not found there" >&2
fi

# --- Step 2b: Try default Hub install path ---
DEFAULT_PATH="$(get_default_install_path)"
EDITOR_BIN="$(get_editor_binary "$DEFAULT_PATH")"
if [[ -f "$EDITOR_BIN" ]]; then
  echo "Found at default Hub path: $EDITOR_BIN" >&2
  echo "$EDITOR_BIN"
  exit 0
fi

# --- Step 2c: Hub CLI fallback (slow — launches Hub process) ---
if HUB_BIN="$(get_hub_binary)"; then
  echo "Querying Unity Hub CLI..." >&2
  HUB_OUTPUT=$("$HUB_BIN" -- --headless editors -i 2>/dev/null || true)
  if [[ -n "$HUB_OUTPUT" ]]; then
    EDITOR_PATH=$(echo "$HUB_OUTPUT" | grep -i "$UNITY_VERSION" | grep -oP '(?<=installed at )\S+.*' | sed 's/[[:space:]]*$//' | head -1)
    if [[ -n "$EDITOR_PATH" ]]; then
      EDITOR_PATH="${EDITOR_PATH//\\//}"
      if [[ -f "$EDITOR_PATH" ]]; then
        echo "Found via Hub CLI: $EDITOR_PATH" >&2
        echo "$EDITOR_PATH"
        exit 0
      fi
    fi
  fi
fi

echo "ERROR: Unity $UNITY_VERSION not found via Hub." >&2
echo "Set UNITY_EDITOR_PATH env var to your Unity editor binary." >&2
exit 1
