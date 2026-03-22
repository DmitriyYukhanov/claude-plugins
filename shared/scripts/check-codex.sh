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
    # Handle MINGW-style: /d/... → /mnt/d/...
    elif [[ "$p" =~ ^/([A-Za-z])/ ]]; then
        local drive="${BASH_REMATCH[1]}"
        drive="${drive,,}"  # lowercase
        p="/mnt/${drive}/${p:3}"
    fi
    # Normalize backslashes
    echo "${p//\\//}"
}

# --- Resolve codex path in WSL ---

# When codex is installed via nvm/fnm/volta, `wsl -- codex` fails because it
# runs a non-interactive, non-login shell that doesn't source ~/.bashrc or
# ~/.profile, so node version manager paths are never added to PATH.
#
# We resolve the absolute path once during validation using `bash -lc` (which
# sources init files), then use that absolute path for all subsequent calls.
_WSL_CODEX_PATH=""

_resolve_wsl_codex() {
    local wsl_timeout="${CODEX_WSL_TIMEOUT:-30}"
    local resolved=""
    local probe_exit=0

    # Try login shell first (sources ~/.profile → ~/.bashrc, loads nvm/fnm/volta)
    if command -v timeout &>/dev/null; then
        resolved="$(timeout "$wsl_timeout" wsl -- bash -lc 'command -v codex' 2>/dev/null)" || probe_exit=$?
    else
        resolved="$(wsl -- bash -lc 'command -v codex' 2>/dev/null)" || probe_exit=$?
    fi

    if [[ "$probe_exit" -eq 124 ]]; then
        echo "FAIL: WSL timed out after ${wsl_timeout}s (cold start?). Retry or set CODEX_WSL_TIMEOUT higher." >&2
        return 1
    fi

    # If login shell didn't find it, try interactive shell (sources ~/.bashrc directly)
    if [[ -z "$resolved" ]]; then
        resolved="$(wsl -- bash -ic 'command -v codex' 2>/dev/null)" || true
    fi

    # Last resort: probe common node version manager paths directly
    if [[ -z "$resolved" ]]; then
        resolved="$(wsl -- bash -c '
            for d in \
                "$HOME/.nvm/versions/node"/*/bin \
                "$HOME/.fnm/node-versions"/*/installation/bin \
                "$HOME/.volta/bin" \
                "$HOME/.local/bin" \
                "$HOME/.npm-global/bin" \
                /usr/local/bin \
            ; do
                if [[ -x "$d/codex" ]]; then
                    echo "$d/codex"
                    exit 0
                fi
            done
            exit 1
        ' 2>/dev/null)" || true
    fi

    if [[ -z "$resolved" ]]; then
        return 1
    fi

    _WSL_CODEX_PATH="$resolved"
    return 0
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
            if ! _resolve_wsl_codex; then
                echo "FAIL: codex CLI not found in WSL." >&2
                echo "  Install inside WSL: npm install -g @openai/codex" >&2
                echo "  If installed via nvm/fnm/volta, ensure the node version manager" >&2
                echo "  is sourced in ~/.bashrc before the interactive guard." >&2
                return 1
            fi
            echo "OK: MINGW detected — codex reachable via WSL at $_WSL_CODEX_PATH" >&2
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
# In MINGW mode, uses the resolved absolute path ($_WSL_CODEX_PATH) to avoid
# PATH issues with nvm/fnm/volta-managed installations.
codex_run() {
    case "$CODEX_ENV" in
        mingw)
            local wsl_cwd
            wsl_cwd="$(_to_wsl_path "$(pwd)")"
            # MSYS_NO_PATHCONV prevents MINGW from mangling Linux-absolute paths
            # (e.g., /home/user/.nvm/... → C:/Program Files/Git/home/...)
            MSYS_NO_PATHCONV=1 wsl --cd "$wsl_cwd" -- "$_WSL_CODEX_PATH" "$@"
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
