#!/usr/bin/env bash
# approve.sh - record an in-session merge approval as a single-use marker
# (spec sec 4.5). The model runs this ONLY after judging the user's reply an
# unambiguous go-ahead (Step 11 prose rules are unchanged). The marker is what
# merge-guard.sh (the hook) and worktree.sh merge both validate.
#
#   approve.sh <branch> --quote "<verbatim user reply>"
#   approve.sh --refresh <branch>     # refresh head-SHA after a pure base merge
#
# The marker lives at <repo-root>/.claude/issue-to-pr/approval-<branch-slug>.json
# (repo-level, so it also works in the in-place fallback). Exit 0 on success;
# 4 (degraded) on a usage/environment problem.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

branch=""
quote=""
have_quote=0
refresh=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --quote) quote=${2:-}; have_quote=1; shift 2 2>/dev/null || shift "$#" ;;
    --refresh) refresh=1; shift ;;
    --json) enable_json; shift ;;
    -*) warn "approve: ignoring unknown flag: $1"; shift ;;
    *) [ -z "$branch" ] && branch=$1; shift ;;
  esac
done

[ -n "$branch" ] || degrade missing-branch "approve: branch required"

root=$(repo_root)
[ -n "$root" ] || degrade not-a-git-repo "approve: not inside a git repository"
marker=$(marker_path "$root" "$branch")

sha=$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || printf '')
[ -n "$sha" ] || degrade no-pr-head "approve: could not read the PR head for $branch (is the PR open?)"

created=$(now_iso)

if [ "$refresh" = 1 ]; then
  [ -f "$marker" ] || degrade no-marker-to-refresh "approve --refresh: no existing marker for $branch"
  # Update head-SHA + timestamp in place, preserving quote and used:false.
  tmp="$marker.tmp"
  sed -E "s/\"pr_head_sha\":\"[^\"]*\"/\"pr_head_sha\":\"$sha\"/; s/\"created_at\":\"[^\"]*\"/\"created_at\":\"$created\"/" \
    "$marker" >"$tmp" && mv "$tmp" "$marker"
  emit REFRESHED true
else
  [ "$have_quote" = 1 ] || degrade missing-quote "approve: --quote <verbatim reply> required"
  marker_write "$marker" "$branch" "$sha" "$quote" "$created" false
  emit APPROVED true
fi

emit MARKER_PATH "$marker"
emit PR_HEAD_SHA "$sha"
emit CREATED_AT "$created"
done_ok
