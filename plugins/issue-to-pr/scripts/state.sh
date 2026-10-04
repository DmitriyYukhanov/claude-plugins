#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

[ "$#" -eq 0 ] || degrade bad-arguments "state: expected no arguments; run inside the owned checkout"
root=$(repo_root)
checkout=$(git rev-parse --show-toplevel 2>/dev/null) || degrade not-a-git-repo "state: not inside a git checkout"
branch=$(git symbolic-ref --quiet --short HEAD) || degrade detached-head "state: check out the owned branch before initializing its state"
assert_run_dir_safe "$checkout" "$branch"
ensure_run_dir "$root" "$branch" || degrade state-unwritable "state: cannot protect the run directory"

for tree in "$root" "$checkout"; do
  tracked=$(git -C "$tree" ls-files -- .claude/issue-to-pr ':!.claude/issue-to-pr/config.md' ':!.claude/issue-to-pr/.gitignore') ||
    stop state-index-unreadable "state: cannot inspect tracked state in $tree"
  [ -z "$tracked" ] || warn "state: review tracked state candidates in $tree; preserve project files and offer targeted index cleanup for generated files only:
$tracked"
  [ "$root" != "$checkout" ] || break
done
emit RUN_DIR "$(branch_dir "$root" "$branch")"
done_ok
