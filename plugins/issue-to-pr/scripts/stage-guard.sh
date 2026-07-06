#!/usr/bin/env bash
# stage-guard.sh - PreToolUse hook that enforces explicit-path staging (a hard
# rule) the way merge-guard.sh enforces the merge gate. It DENIES `git add -A`,
# `git add --all`, and `git add .`, which would sweep in local-only artifacts
# (docs/superpowers, .serena, tmp/task-*). Everything else passes through to the
# normal permission flow. Shares the hook helpers in lib/common.sh.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

input=$(cat)
# Fast path: only `git add` commands are guarded.
case "$input" in
  *"git add"*) : ;;
  *) hook_passthrough ;;
esac

cmd=$(hook_extract_command "$input")
cmd=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ' | tr -d '\042\047')

case "$cmd" in
  *"git add"*" -A"* | *"git add"*" --all"* | *"git add"*" ." | *"git add"*" . "* | *"git add"*" :/"*)
    hook_deny "git add -A / --all / . / :/ stages everything, including local-only artifacts (docs/superpowers, .serena, tmp/task-*). Stage explicit paths instead: git add path1 path2." ;;
esac

hook_passthrough
