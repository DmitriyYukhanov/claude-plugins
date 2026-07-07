#!/usr/bin/env bash
# review-check.sh - classify a PR's outstanding GitHub review state (spec sec 6.4)
# so Step 11 never merges silently over a CHANGES_REQUESTED review or an unresolved
# inline thread. Reads through gh's own --jq (no system jq). Best-effort: a failed
# read reports clear with READ_OK=false and still exits 0, so a flaky API call never
# blocks a merge the human explicitly approved - it just cannot hide a review.
#
#   review-check.sh <branch> [--json]
#
# Emits REVIEW_STATE=clear|changes_requested|unresolved_threads, UNRESOLVED_THREADS,
# and READ_OK. changes_requested comes from GitHub's own reviewDecision (which already
# collapses each reviewer to their latest review); unresolved_threads is a best-effort
# GraphQL count of open inline threads. reviewThreads is NOT a `gh pr view` field, so
# it must go through the GraphQL API.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

branch=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) enable_json; shift ;;
    -*) warn "review-check: ignoring unknown flag: $1"; shift ;;
    *) [ -z "$branch" ] && branch=$1; shift ;;
  esac
done

[ -n "$branch" ] || degrade missing-branch "review-check: branch required"

# 1. review decision + latest per-reviewer states + PR number in one read.
# reviewDecision alone is unreliable: GitHub leaves it null on repos WITHOUT a
# required-review branch-protection rule (the common case for personal repos), so
# a real "Request changes" would read as clear. Also count the latest reviews whose
# state is CHANGES_REQUESTED and treat either signal as changes_requested.
meta=$(gh pr view "$branch" --json reviewDecision,latestReviews,number --jq \
  '"\(.reviewDecision // "")\t\([ .latestReviews[]? | select(.state == "CHANGES_REQUESTED") ] | length)\t\(.number)"' \
  2>/dev/null || printf '')
if [ -z "$meta" ]; then
  emit REVIEW_STATE clear
  emit UNRESOLVED_THREADS 0
  emit READ_OK false
  done_ok
fi
decision=$(printf '%s' "$meta" | cut -f1)
cr_reviews=$(printf '%s' "$meta" | cut -f2)
pr_num=$(printf '%s' "$meta" | cut -f3)
[ -n "$cr_reviews" ] || cr_reviews=0

if [ "$decision" = CHANGES_REQUESTED ] || [ "$cr_reviews" != 0 ]; then
  emit REVIEW_STATE changes_requested
  emit UNRESOLVED_THREADS 0
  emit READ_OK true
  done_ok
fi

# 2. unresolved inline threads (best-effort; reviewThreads is GraphQL-only).
slug=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || printf '/')
owner=${slug%%/*}
repo=${slug#*/}
unresolved=0
if [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$pr_num" ]; then
  # shellcheck disable=SC2016  # $o/$r/$n are GraphQL variables, not shell expansions
  unresolved=$(gh api graphql \
    -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{isResolved}}}}}' \
    -F o="$owner" -F r="$repo" -F n="$pr_num" \
    --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' \
    2>/dev/null || printf '0')
fi
[ -n "$unresolved" ] || unresolved=0

if [ "$unresolved" != 0 ]; then
  emit REVIEW_STATE unresolved_threads
else
  emit REVIEW_STATE clear
fi
emit UNRESOLVED_THREADS "$unresolved"
emit READ_OK true
done_ok
