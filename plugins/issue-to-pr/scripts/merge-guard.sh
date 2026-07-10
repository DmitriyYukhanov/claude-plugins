#!/usr/bin/env bash
# merge-guard.sh - the merge gate as physics (spec sec 4.5). A PreToolUse command
# hook: reads the hook JSON on stdin, finds the target branch of a merge command,
# and ALLOWS it only when a valid approval marker exists (present and unused and
# fresh <30min and its head-SHA still matches the PR head). Otherwise it DENYs
# with the exact remedy. `--admin` is always denied; a force-push asks.
#
# Because plugin agents ignore hooks, merge commands must run only in the MAIN
# session - this guard protects that session.
#
# Output: {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#          "permissionDecision":"allow|deny|ask","permissionDecisionReason":"..."}}
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# hook helpers (hook_decision/allow/deny/ask/passthrough/extract_command) live in
# lib/common.sh, shared with stage-guard.sh.

# merge_branch_of COMMAND -> the ref a `gh pr merge` targets: the first non-flag
# positional (skipping value-taking flags), else the current HEAD. This is a branch
# name for `gh pr merge <branch>` but a bare PR number for `gh pr merge <N>` (both are
# valid gh syntax) -- the caller resolves it to the canonical branch before keying the
# approval marker, so the two forms (and approve.sh given either) agree on one file.
merge_branch_of() {
  local rest=${1#*gh pr merge} tok skip=0
  for tok in $rest; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$tok" in
      -R | --repo | -b | --body | -t | --subject | --body-file | --match-head-commit | --author-email)
        skip=1; continue ;;
      --repo=* | --body=* | --subject=* | --body-file=*) continue ;;
      -*) continue ;;
      *) printf '%s' "$tok"; return ;;
    esac
  done
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''
}

input=$(cat)
# Fast path: only merge / push commands are guarded; everything else defers to the
# normal permission flow without the char-scan.
case "$input" in
  *merge* | *push*) : ;;
  *) hook_passthrough ;;
esac

cmd=$(hook_extract_command "$input")
# Collapse whitespace runs, then strip quotes, so odd spacing (`gh  pr  merge`) and
# a quoted script path (`"...worktree.sh" merge`, which would otherwise hide the
# `worktree.sh merge` substring) can't slip a merge command past the matchers. A
# branch name never contains a quote, so removing them is safe for extraction.
cmd=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ' | tr -d '\042\047')

# Never allow an admin bypass of branch protection.
case "$cmd" in
  *"gh pr merge"*"--admin"*) hook_deny "issue-to-pr: gh pr merge --admin is forbidden - never bypass branch protection. Merge normally after approval." ;;
esac

# A force-push is a human call: match --force, -f, or a +refspec.
case "$cmd" in
  *"git push"*"--force"* | *"git push"*" -f"* | *"git push"*" +"*)
    hook_ask "issue-to-pr: force-push detected - confirm this manually." ;;
esac

# Identify the guarded merge command and its target branch.
branch=""
is_gh_merge=0
case "$cmd" in
  *"worktree.sh merge"*)
    branch=$(printf '%s' "$cmd" | grep -oE -- '--branch[ =]+[^ ]+' | head -1 | sed -E 's/--branch[ =]+//')
    ;;
  *"gh pr merge"*)
    is_gh_merge=1
    branch=$(merge_branch_of "$cmd")
    ;;
esac

# Anything that is not a guarded merge command defers to normal permission flow.
[ -n "$branch" ] || hook_passthrough

root=$(repo_root)
marker=$(marker_path "$root" "$branch")

# The ref may be a PR number rather than the branch approve.sh keyed the marker under
# (or vice versa). Resolve to the canonical branch and retry once before denying, so
# `gh pr merge <PR#>` and `gh pr merge <branch>` always agree on one marker file.
if [ ! -f "$marker" ]; then
  resolved=$(gh pr view "$branch" --json headRefName --jq .headRefName 2>/dev/null || printf '')
  if [ -n "$resolved" ] && [ "$resolved" != "$branch" ]; then
    branch=$resolved
    marker=$(marker_path "$root" "$branch")
  fi
fi

[ -f "$marker" ] || hook_deny "issue-to-pr: no approval marker for $branch. This is the plugin's own merge gate, not a GitHub restriction -- running approve.sh yourself is the normal unlock step, not a bypass. If the user already gave an unambiguous go-ahead, run: bash \"$SCRIPT_DIR/approve.sh\" \"$branch\" --quote \"<verbatim reply>\", then retry the merge. Otherwise ask first; only suggest a manual terminal merge if you have no go-ahead to quote."
used=$(marker_used "$marker")
[ "$used" = false ] || hook_deny "issue-to-pr: the approval for $branch was already used (single-use). Re-approve with approve.sh to merge again."
created=$(marker_str_field "$marker" created_at)
epoch=$(epoch_of "$created")
[ -n "$epoch" ] || hook_deny "issue-to-pr: the approval marker timestamp is unparseable. Re-approve."
age=$(($(now_epoch) - epoch))
[ "$age" -le 1800 ] || hook_deny "issue-to-pr: the approval for $branch is stale (>30 min old). Re-approve."
marker_sha=$(marker_str_field "$marker" pr_head_sha)
cur_sha=$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || printf '')
if [ -z "$cur_sha" ] || [ "$marker_sha" != "$cur_sha" ]; then
  hook_deny "issue-to-pr: the PR head for $branch moved since approval. Re-approve so the marker matches the new head."
fi

# On the direct `gh pr merge` path, consume the marker now so one approval buys one
# merge even without worktree.sh (which consumes on success for the sanctioned path).
if [ "$is_gh_merge" = 1 ]; then
  marker_set_used "$marker"
fi
hook_allow "approval marker for $branch is valid (present, unused, fresh, head-SHA matches)."
