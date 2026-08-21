#!/usr/bin/env bash
# changed-paths.sh - print every path this branch touched, one per line, so the Step 7
# review reads the real surface of the change (spec sec 5.2 security overlay).
#
#   changed-paths.sh --base <ref>
#
# Whether any of it is security relevant is the reviewer's call, not a matcher's.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

base_ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) base_ref=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    *) shift ;;
  esac
done

[ -n "$base_ref" ] ||
  degrade no-base "changed-paths: pass --base <ref>"

# Degrade rather than print an empty list. Nothing downstream can tell "this branch
# changed nothing" from "the base does not resolve", and the second one read as the
# first is a review pass silently skipped.
git rev-parse --git-dir >/dev/null 2>&1 ||
  degrade not-a-git-repo "changed-paths: --base needs a git repository - run it from the worktree"
git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null 2>&1 ||
  degrade base-unresolvable "changed-paths: '$base_ref' resolves to no commit - read the diff yourself"

# Three sources, because this runs at Step 7, BEFORE the Step 9 commit: what is
# committed on this branch, what is edited and not yet committed, and what is new and
# untracked. The first is a THREE-dot diff on purpose - a two-dot diff against a base
# that moved meanwhile lists files this branch never touched.
{
  git diff --name-only "$base_ref...HEAD" 2>/dev/null
  git diff --name-only HEAD 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
} | sort -u
