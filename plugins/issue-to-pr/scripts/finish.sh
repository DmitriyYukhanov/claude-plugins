#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# finish.sh merge   <N> --branch <b> [--method squash|merge|rebase] [--auto <threshold> --tier <tier>]
# finish.sh cleanup <N> --branch <b> [--keep-branch]
# The two actions a run cannot take back: merging the PR and deleting its branch and worktree.
subcmd=${1:-}
shift || true
issue="" branch="" method=squash keep_branch=0 auto="" tier="" auto_given=0 tier_given=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) branch=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --method) method=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --keep-branch) keep_branch=1; shift ;;
    --auto) auto=${2:-}; auto_given=1; shift 2 2>/dev/null || shift "$#" ;;
    --tier) tier=${2:-}; tier_given=1; shift 2 2>/dev/null || shift "$#" ;;
    -*) degrade unknown-flag "finish: unknown flag '$1'. Ignoring it would let a mistyped --keep-branch delete the branch anyway" ;;
    *) [ -z "$issue" ] && issue=$1; shift ;;
  esac
done
[ -n "$branch" ] || degrade missing-branch "finish: --branch required"
case "$method" in squash | merge | rebase) : ;; *) degrade bad-method "finish: --method must be squash, merge or rebase, got '$method'" ;; esac
[ -n "$issue" ] || degrade missing-issue "finish: issue number required"
if [ "$auto_given" = 1 ] || [ "$tier_given" = 1 ]; then
  # presence, not value: an empty --auto would otherwise skip the guard and merge attended
  [ -n "$auto" ] && [ -n "$tier" ] || degrade auto-needs-tier "finish: --auto and --tier go together, each with a value: the threshold means nothing without the run's tier"
  [ -n "$(tier_rank "$auto")" ] || degrade bad-tier "finish: --auto must be trivial, standard, complex or none, got '$auto'"
  case "$tier" in trivial | standard | complex) : ;; *) degrade bad-tier "finish: --tier must be trivial, standard or complex, got '$tier'" ;; esac
fi
assert_numeric_issue "$issue" finish
root=$(repo_root)
[ -n "$root" ] || degrade not-a-git-repo "finish: not inside a git repository"

cmd_merge() {
  local pr head_sha decision base_ref receipt push_out merge_out default_ref base_rev listfile globs f g
  # reviewDecision alone is null on a base branch that does not require review, however many
  # reviews a PR has, so the reviews themselves decide and the field only confirms them
  pr=$(gh pr view "$branch" --json headRefOid,reviewDecision,latestReviews,baseRefName \
    --jq '"\(.headRefOid)\t\(if .reviewDecision == "CHANGES_REQUESTED" or any(.latestReviews[]?; .state == "CHANGES_REQUESTED") then "CHANGES_REQUESTED" else .reviewDecision // "" end)\t\(.baseRefName)"' 2>/dev/null) || pr=""
  head_sha=$(printf '%s' "$pr" | cut -f1)
  decision=$(printf '%s' "$pr" | cut -f2)
  base_ref=$(printf '%s' "$pr" | cut -f3)
  case "$head_sha" in '' | null)
    stop pr-unreadable "issue-to-pr: could not read the PR for $branch. Check it exists and gh is authenticated, then hand back." ;;
  esac

  receipt=$(receipt_path "$root" "$branch")
  if [ ! -f "$receipt" ] || [ "$(json_str_field "$receipt" head_sha)" != "$head_sha" ]; then
    stop gates-unverified "issue-to-pr: no green gate receipt for ${head_sha:0:12}. Repeat run/SKILL.md Steps 5-7 on this head, then re-approve."
  fi
  case ",$(json_str_field "$receipt" gates)," in
    *,test,*) : ;;
    *) stop gates-unverified "issue-to-pr: the receipt for ${head_sha:0:12} covers '$(json_str_field "$receipt" gates)', not the test gate (a smoke or install run overwrites it). Run the full gate set on this head, then re-approve." ;;
  esac
  [ "$decision" != CHANGES_REQUESTED ] ||
    stop review-blocked "issue-to-pr: $branch has a review requesting changes. Address it, push, re-run the gates, and re-approve."

  if [ -n "$auto" ]; then
    [ "$(tier_rank "$tier")" -le "$(tier_rank "$auto")" ] ||
      stop auto-tier "issue-to-pr: a $tier run does not merge unattended under an --auto-merge $auto threshold. Comment on the PR that it waits for 'merge', label agent:review, and end the turn."
    if git rev-parse --verify -q "origin/$base_ref^{commit}" >/dev/null; then base_rev="origin/$base_ref"
    elif git rev-parse --verify -q "$base_ref^{commit}" >/dev/null; then base_rev=$base_ref
    else stop auto-base-unresolved "issue-to-pr: neither origin/$base_ref nor $base_ref resolves here, so the human-path check cannot read the diff. Fetch the base and re-run."
    fi
    # the diff runs over the local branch: the fixture's constant sha never resolves, and the
    # receipt plus --match-head-commit already bind the merge to head_sha.
    # --no-renames prints the source path too; -z prints each path raw and NUL-terminated, which
    # is the only form git never C-quotes - a path holding " or \ is quoted whatever
    # core.quotePath says, and a quoted path matches no glob a human wrote
    listfile="$(branch_dir "$root" "$branch")/logs/auto-diff.list"
    mkdir -p "${listfile%/*}" 2>/dev/null
    git diff --no-renames --name-only -z "$base_rev...$branch" >"$listfile" 2>/dev/null ||
      stop auto-diff-unreadable "issue-to-pr: could not read the diff $base_rev...$branch for \
the human-path check, so the merge cannot be proved safe. Fetch the base and re-run."
    [ -s "$listfile" ] ||
      stop auto-diff-empty "issue-to-pr: the diff $base_rev...$branch is empty, so the human-path check has nothing to prove; a PR with no diff against its base does not merge unattended. Comment on the PR that it waits for 'merge', label agent:review, and end the turn."
    set -f
    globs=$(config_line "$root" human_paths) ||
      stop auto-config-unreadable "issue-to-pr: .claude/issue-to-pr/config.md exists but could not be read, so human_paths is unknown; fix the file and re-run."
    while IFS= read -r -d '' f; do
      for g in $globs; do
        # shellcheck disable=SC2254  # $g is a glob from the config and must expand as a pattern
        case "$f" in $g)
          set +f
          emit HUMAN_PATH "$f"
          stop auto-human-path "issue-to-pr: $f matches human_paths '$g'; this PR waits for a human 'merge'. Comment, label agent:review, end the turn." ;;
        esac
      done
    done <"$listfile"
    set +f
    rm -f "$listfile"
  fi

  if ! push_out=$(git push origin "$branch" 2>&1); then
    emit PUSH_ERROR "$(printf '%s' "$push_out" | tr '\n' ' ')"
    stop push-rejected "issue-to-pr: git push was rejected. The remote branch moved under you: fetch, look at what landed, and re-approve rather than assuming the approval still covers the diff you showed."
  fi
  if ! merge_out=$(gh pr merge "$branch" "--$method" --match-head-commit "$head_sha" 2>&1); then
    emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
    stop merge-failed "issue-to-pr: gh pr merge refused; report MERGE_ERROR verbatim. If it says this merge method is not allowed, re-run once with --method merge (then rebase). If checks are still pending, 'gh pr checks $branch --watch', then re-run. The same refusal a third time is a livelock: hand back."
  fi
  emit MERGED true
  if [ -n "$auto" ]; then
    emit AUTO_MERGED true
    emit AUTO_TIER "$tier"
  fi
  emit MERGE_METHOD "$method"
  emit MERGED_INTO "$base_ref"
  default_ref=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || printf '')
  if [ -z "$base_ref" ] || [ -z "$default_ref" ]; then
    emit BASE_IS_DEFAULT unknown
  elif [ "$base_ref" != "$default_ref" ]; then
    emit BASE_IS_DEFAULT false
    emit WARN_NON_DEFAULT_BASE "merged into '$base_ref', not '$default_ref' - the issue stays open and this work has NOT reached the default branch"
  else
    emit BASE_IS_DEFAULT true
  fi
  done_ok
}

registered_wt() { # the registered worktree ending in /issue-<N>, or empty
  git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep -E "/issue-$issue\$" | head -1
}

remove_worktree() { # path -> REMOVED, LEFTOVER; stops on a dirty tree, never forces
  local wt=$1 status
  REMOVED=false
  LEFTOVER=""
  if [ ! -e "$wt" ]; then
    git -C "$root" worktree prune 2>/dev/null
    REMOVED=true
    return 0
  fi
  if git -C "$root" worktree remove "$wt" 2>/dev/null; then
    REMOVED=true
    return 0
  fi
  if [ -z "$(registered_wt)" ]; then
    git -C "$root" worktree prune 2>/dev/null
    LEFTOVER=$wt
    return 0
  fi
  status=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null || printf '')
  if [ -n "$status" ]; then
    emit DIRTY_FILES "$(printf '%s' "$status" | tr '\n' ';')"
    stop dirty-tracked-files "worktree $wt has tracked or unexpected changes - not removing"
  fi
  LEFTOVER=$wt
}

cmd_cleanup() {
  local pr_state dependents wt_path wt_branch def deleted_local=false deleted_remote=false
  if [ "$keep_branch" -eq 0 ]; then
    pr_state=$(gh pr view "$branch" --json state --jq .state 2>/dev/null || printf '')
    [ "$pr_state" = MERGED ] || stop pr-not-merged "PR for $branch is '${pr_state:-unknown}', not MERGED - refusing cleanup"
    dependents=$(gh pr list --base "$branch" --state open --json number --jq '[.[].number] | join(", ")' 2>/dev/null) ||
      stop dependents-unreadable "could not read whether an open PR is based on $branch - check on GitHub, then delete the branch by hand"
    [ -z "$dependents" ] || stop base-of-open-pr "$branch is the base of open PR(s) $dependents - retarget or merge them before deleting it"
  fi

  wt_path=$(registered_wt)
  if [ -n "$wt_path" ] && [ -e "$wt_path" ]; then
    wt_branch=$(git -C "$wt_path" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '')
    [ "$wt_branch" = "$branch" ] ||
      stop worktree-branch-mismatch "worktree $wt_path is on '${wt_branch:-detached or unreadable}', expected '$branch' - refusing cleanup"
  fi
  [ -n "$wt_path" ] || wt_path="$(dirname "$root")/$(basename "$root")-worktrees/issue-$issue"
  cd "$root" 2>/dev/null || true
  remove_worktree "$wt_path"
  emit REMOVED "$REMOVED"
  if [ "$keep_branch" -eq 1 ]; then
    emit KEPT branch-and-pr
    [ -n "$LEFTOVER" ] && emit LEFTOVER_DIR "$LEFTOVER"
    done_ok
  fi

  if [ "$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')" = "$branch" ]; then
    def=$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
    if [ -n "$def" ] && [ "$def" != "$branch" ]; then
      git -C "$root" switch "$def" >/dev/null 2>&1 || git -C "$root" checkout --detach >/dev/null 2>&1
    else
      git -C "$root" checkout --detach >/dev/null 2>&1
    fi
  fi
  if git -C "$root" show-ref --verify --quiet "refs/heads/$branch" && git -C "$root" branch -D "$branch" >/dev/null 2>&1; then
    deleted_local=true
  fi
  if git -C "$root" push origin --delete "$branch" >/dev/null 2>&1; then
    deleted_remote=true
  fi
  rm -rf "$(branch_dir "$root" "$branch")" 2>/dev/null

  emit DELETED_LOCAL "$deleted_local"
  emit DELETED_REMOTE "$deleted_remote"
  [ -n "$LEFTOVER" ] && emit LEFTOVER_DIR "$LEFTOVER"
  done_ok
}

case "$subcmd" in
  merge) cmd_merge ;;
  cleanup) cmd_cleanup ;;
  *) degrade unknown-subcommand "finish: subcommand required (merge|cleanup), got '$subcmd'" ;;
esac
