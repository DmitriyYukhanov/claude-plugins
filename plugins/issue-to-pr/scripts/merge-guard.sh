#!/usr/bin/env bash
# merge-guard.sh - a PreToolUse command hook with two rules: never allow an admin
# bypass of branch protection, and make a force-push a human decision. Everything
# else defers to the normal permission flow.
#
# It used to gate every merge on an approval marker. That marker proved freshness,
# single use and a head-SHA binding, never that a human had agreed: the same model
# that runs the pipeline wrote it, and a hook cannot see the conversation. The one
# guarantee that was real is now GitHub's own - `gh pr merge --match-head-commit`
# refuses when the head moved - and the gates are proved by the receipt run-gates.sh
# leaves. What is left here is the pair a hook can genuinely enforce.
#
# Output: {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#          "permissionDecision":"deny|ask","permissionDecisionReason":"..."}}
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

input=$(cat)
# Fast path: only merge / push commands are inspected at all.
case "$input" in
  *merge* | *push*) : ;;
  *) hook_passthrough ;;
esac

cmd=$(hook_extract_command "$input")
# Blank out heredoc bodies first (data, not command syntax), so a commit message or
# an issue body that discusses this very gate cannot be misread as the command.
cmd=$(strip_heredoc_bodies "$cmd")
# Collapse whitespace runs and strip quotes so odd spacing or a quoted path cannot
# slip a guarded command past the matchers.
cmd=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ' | tr -d '\042\047')

case "$cmd" in
  *"gh pr merge"*"--admin"*)
    hook_deny "issue-to-pr: gh pr merge --admin is forbidden - never bypass branch protection." ;;
esac

# A force-push is a human call: match --force, -f, or a +refspec.
case "$cmd" in
  *"git push"*"--force"* | *"git push"*" -f"* | *"git push"*" +"*)
    hook_ask "issue-to-pr: force-push detected - confirm this manually." ;;
esac

hook_passthrough
