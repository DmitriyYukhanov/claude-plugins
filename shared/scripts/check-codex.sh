#!/usr/bin/env bash
# Detect environment and set up codex command with WSL support.
#
# When SOURCED by other scripts: sets CODEX_ENV and exports codex_run() function.
# When RUN DIRECTLY: validates codex reachability and prints status (exit 0/1).
#
# Environment detection:
#   mingw  — running in MINGW/MSYS on Windows → codex runs via WSL
#   wsl    — running inside WSL → codex runs directly
#   native — running on Linux/macOS → codex runs directly
#
# Exports (when sourced):
#   CODEX_ENV    — "mingw" | "wsl" | "native"
#   codex_run()  — runs codex with correct path/CWD handling

set -euo pipefail

# --- Environment detection ---

_detect_codex_env() {
    local uname_s
    uname_s="$(uname -s 2>/dev/null || echo unknown)"

    case "$uname_s" in
        MINGW*|MSYS*)
            CODEX_ENV="mingw"
            ;;
        Linux*)
            if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null; then
                CODEX_ENV="wsl"
            else
                CODEX_ENV="native"
            fi
            ;;
        *)
            CODEX_ENV="native"
            ;;
    esac
}

# --- Path conversion ---

# Convert Windows/MINGW path to WSL path.
# D:/foo/bar → /mnt/d/foo/bar, D:\foo\bar → /mnt/d/foo/bar
# Passthrough for paths that are already POSIX.
_to_wsl_path() {
    local p="$1"
    # Handle drive letter: D:/... or D:\...
    if [[ "$p" =~ ^([A-Za-z]):[/\\] ]]; then
        local drive="${BASH_REMATCH[1]}"
        drive="${drive,,}"  # lowercase
        p="/mnt/${drive}/${p:3}"
    fi
    # Normalize backslashes
    echo "${p//\\//}"
}

# --- Validation ---

_validate_codex() {
    _detect_codex_env

    case "$CODEX_ENV" in
        mingw)
            if ! command -v wsl &>/dev/null; then
                echo "FAIL: Running in MINGW but WSL is not available." >&2
                echo "  Codex CLI requires WSL on Windows. Install WSL: wsl --install" >&2
                return 1
            fi
            # Check codex is installed inside WSL
            if ! wsl -- bash -lc "command -v codex" &>/dev/null; then
                echo "FAIL: codex CLI not found in WSL." >&2
                echo "  Install inside WSL: npm install -g @openai/codex" >&2
                return 1
            fi
            echo "OK: MINGW detected — codex reachable via WSL" >&2
            ;;
        wsl)
            if ! command -v codex &>/dev/null; then
                echo "FAIL: codex CLI not found." >&2
                echo "  Install: npm install -g @openai/codex" >&2
                return 1
            fi
            echo "OK: WSL detected — codex available directly" >&2
            ;;
        native)
            if ! command -v codex &>/dev/null; then
                echo "FAIL: codex CLI not found." >&2
                echo "  Install: npm install -g @openai/codex" >&2
                return 1
            fi
            echo "OK: codex available directly" >&2
            ;;
    esac
    return 0
}

# --- codex_run: portable codex invocation ---

# Usage: codex_run <codex_args...>
# Call from the project directory (after cd). Handles CWD translation for MINGW→WSL.
codex_run() {
    case "$CODEX_ENV" in
        mingw)
            local wsl_cwd
            wsl_cwd="$(_to_wsl_path "$(pwd)")"
            wsl --cd "$wsl_cwd" -- codex "$@"
            ;;
        *)
            codex "$@"
            ;;
    esac
}

# --- Entry point ---

_validate_codex || exit 1

# If run directly (not sourced), just print status and exit.
# If sourced, CODEX_ENV and codex_run are now available to the parent script.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "CODEX_ENV=$CODEX_ENV"
fi
