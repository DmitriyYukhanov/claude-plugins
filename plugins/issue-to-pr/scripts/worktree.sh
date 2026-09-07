#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

subcmd=${1:-}
shift || true
issue=""
branch=""
start_point=""
keep_branch=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) branch=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --start-point) start_point=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --keep-branch) keep_branch=1; shift ;;
    -*) warn "worktree: ignoring unknown flag: $1"; shift ;;
    *) [ -z "$issue" ] && issue=$1; shift ;;
  esac
done

[ -n "$subcmd" ] || degrade missing-subcommand "worktree: subcommand required (ensure|merge|cleanup)"
[ -n "$branch" ] || degrade missing-branch "worktree: --branch required"
[ -n "$issue" ] || degrade missing-issue "worktree: issue number required"
assert_numeric_issue "$issue" worktree

compute_wt_path() { # root issue
  printf '%s/%s-worktrees/issue-%s' "$(dirname "$1")" "$(basename "$1")" "$2"
}

registered_wt() { # issue [root] -> registered worktree path ending in /issue-<N>, or empty
  (
    if [ -n "${2:-}" ]; then cd "$2" || exit 0; fi
    git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep -E "/issue-$1\$" | head -1
  )
}

branch_exists() { git show-ref --verify --quiet "refs/heads/$1"; }

is_base_branch() { # name -> true if it looks like an integration base
  case "$1" in main | master | dev | develop) return 0 ;; *) return 1 ;; esac
}

pr_state_of() { # branch -> MERGED|OPEN|CLOSED|none|unreadable
  local s
  # --state all, or a merged PR is simply absent: gh lists open ones by default
  s=$(gh pr list --head "$1" --state all --json state --jq '.[0].state // empty' 2>/dev/null) ||
    { printf 'unreadable'; return 0; }
  printf '%s' "${s:-none}"
}

pr_mergeability() {
  # shellcheck disable=SC2016  # $c is a jq variable, not a shell expansion
  gh pr view "$1" --json mergeable,mergeStateStatus,statusCheckRollup --jq \
    '[ (.mergeable // ""), (.mergeStateStatus // ""), ([ .statusCheckRollup[]? | select( ((.conclusion // .state // "") | ascii_upcase) as $c | ($c=="FAILURE" or $c=="ERROR" or $c=="CANCELLED" or $c=="TIMED_OUT") ) | (.name // .context // "check") ] | join(",")) ] | @tsv' \
    2>/dev/null
}

is_pure_base_merge() {
  local base=$1 old=$2 new=$3 d_old d_new
  d_old=$(git diff "$base...$old" 2>/dev/null) || return 1
  d_new=$(git diff "$base...$new" 2>/dev/null) || return 1
  [ "$d_old" = "$d_new" ]
}

remove_worktree() {
  local wt=$1 root=$2 n=$3
  REMOVED=false
  LEFTOVER=""

  if [ ! -e "$wt" ]; then
    git -C "$root" worktree prune 2>/dev/null || true
    REMOVED=true
    return 0
  fi

  if git -C "$root" worktree remove "$wt" 2>/dev/null; then REMOVED=true; return 0; fi

  local still_reg
  still_reg=$(registered_wt "$n" "$root")
  if [ -z "$still_reg" ]; then
    git -C "$root" worktree prune 2>/dev/null || true
    LEFTOVER="$wt"
    return 0
  fi

  local status
  status=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null || printf '')
  if [ -n "$status" ]; then
    emit DIRTY_FILES "$(printf '%s' "$status" | tr '\n' ';')"
    stop dirty-tracked-files "worktree $wt has tracked or unexpected changes - not removing"
  fi

  LEFTOVER="$wt"
  return 0
}

cmd_ensure() {
  [ -n "$start_point" ] || degrade missing-start-point "worktree ensure: --start-point required"

  local root reg wt_path add_out state actual_branch pr_state
  root=$(repo_root)
  [ -n "$root" ] || degrade not-a-git-repo "worktree ensure: not inside a git repository"
  wt_path=$(compute_wt_path "$root" "$issue")
  reg=$(registered_wt "$issue")

  if [ -n "$reg" ] && [ ! -d "$reg" ]; then
    git worktree prune 2>/dev/null || true
    reg=""
  fi

  if [ -n "$reg" ]; then
    actual_branch=$(git -C "$reg" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
    if [ -z "$actual_branch" ] || [ "$actual_branch" = HEAD ]; then
      emit WT_PATH "$reg"
      stop bad-checkout-state "resumed worktree is detached - check it out on its feature branch"
    fi
    if is_base_branch "$actual_branch"; then
      emit WT_PATH "$reg"
      stop bad-checkout-state "resumed worktree is on base '$actual_branch', not a feature branch"
    fi
    state=RESUMED
    wt_path=$reg
    pr_state=$(pr_state_of "$actual_branch")
  else
    if [ -e "$wt_path" ]; then
      emit WT_PATH "$wt_path"
      stop stale-unregistered-dir "a directory exists at $wt_path but is not a registered worktree"
    fi
    actual_branch=$branch
    if branch_exists "$branch"; then
      state=REATTACHED
      pr_state=$(pr_state_of "$branch")
      [ "$pr_state" = unreadable ] &&
        warn "worktree: could not read whether $branch already has a merged PR; if it does, cleanup is the command, not this one"
    else
      state=CREATED
      pr_state=none
    fi
  fi

  if [ "$pr_state" = MERGED ]; then
    [ "$state" = RESUMED ] && emit WT_PATH "$wt_path"
    emit BRANCH "$actual_branch"
    emit PR_STATE merged
    stop pr-already-merged "PR for $actual_branch is merged - run cleanup"
  fi

  # nothing above this line has built anything, so no key names a path that may not exist yet
  if [ "$state" = REATTACHED ]; then
    add_out=$(git worktree add "$wt_path" "$branch" 2>&1) || { handle_add_error "$add_out"; return; }
  elif [ "$state" = CREATED ]; then
    add_out=$(git worktree add "$wt_path" -b "$branch" "$start_point" 2>&1) || { handle_add_error "$add_out"; return; }
  fi

  local run_dir
  run_dir=$(branch_dir "$root" "$actual_branch")
  if ! ensure_state_dir "$(state_dir "$root")" || ! mkdir -p "$run_dir" 2>/dev/null; then
    warn "worktree: could not create $run_dir - write the run's files somewhere else and say so"
  fi
  emit WT_PATH "$wt_path"
  emit ORIGINAL_ROOT "$root"
  emit BRANCH "$actual_branch"
  emit PR_STATE "$(printf '%s' "$pr_state" | tr '[:upper:]' '[:lower:]')"
  emit STATE "$state"
  emit RUN_DIR "$run_dir"
  done_ok
}

handle_add_error() {
  local raw=$1
  case "$raw" in
    *"invalid reference"* | *"not a valid"* | *"unknown revision"*)
      stop invalid-start-point "start-point '$start_point' is not a valid ref"
      ;;
    *"Permission denied"* | *"permission denied"* | *"Operation not permitted"*)
      local in_place_root
      in_place_root=$(repo_root)
      if [ -n "$in_place_root" ] && ensure_state_dir "$(state_dir "$in_place_root")" &&
        mkdir -p "$(branch_dir "$in_place_root" "$branch")" 2>/dev/null; then
        emit RUN_DIR "$(branch_dir "$in_place_root" "$branch")"
      fi
      fallback worktree-permission-denied "cannot create a worktree here - cut the branch in place: git switch -c $branch $start_point"
      ;;
    *)
      emit ADD_ERROR "$(printf '%s' "$raw" | tr '\n' ' ')"
      stop worktree-add-failed "git worktree add failed"
      ;;
  esac
}

cmd_merge() {
  local root cur_sha
  root=$(repo_root)
  [ -n "$root" ] || degrade not-a-git-repo "worktree merge: not inside a git repository"

  branch=$(canonical_branch "$branch")
  cur_sha=$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || printf '')
  [ -n "$cur_sha" ] || stop pr-head-unreadable "issue-to-pr: could not read the PR head for $branch. Check the PR exists and gh is authenticated, then hand back."

  local receipt receipt_sha rstate
  receipt=$(receipt_path "$root" "$branch")
  receipt_sha=""
  [ -f "$receipt" ] && receipt_sha=$(json_str_field "$receipt" head_sha)
  if [ "$receipt_sha" != "$cur_sha" ]; then
    local covers="none found"
    [ -n "$receipt_sha" ] && covers="covers ${receipt_sha:0:12}"
    stop gates-unverified "issue-to-pr: no green gate receipt for ${cur_sha:0:12} (receipt $covers). Re-run run-gates.sh on this head, then re-approve."
  fi
  if [ "$(json_str_field "$receipt" gates)" = smoke ]; then
    stop gates-unverified "issue-to-pr: the only receipt for ${cur_sha:0:12} covers a post-merge smoke run, not this branch's gates. Run the full gate set on this head, then re-approve."
  fi
  rstate=$(review_state "$branch")
  case "$rstate" in
    clear) : ;;
    changes_requested) stop review-blocked "issue-to-pr: $branch has a review requesting changes. Address it, push, re-run the gates, and re-approve." ;;
    unresolved_threads) stop review-blocked "issue-to-pr: $branch has unresolved review threads. Resolve them on GitHub, then re-approve." ;;
    *) stop review-unreadable "issue-to-pr: could not read the review state of $branch. This is an answer, not a hiccup: check the PR yourself and hand back rather than re-running merge, which will stop here again. The gate does not pass on an unread review." ;;
  esac

  if ! push_out=$(git push 2>&1); then
    emit PUSH_ERROR "$(printf '%s' "$push_out" | tr '\n' ' ')"
    stop push-rejected "issue-to-pr: git push was rejected. Usually the local base is simply behind after an earlier merge: run 'git fetch origin && git merge --ff-only origin/<base>' in the MAIN checkout, then re-run merge. Any other cause means the remote moved under you, so re-approve rather than assuming the approval still covers the diff you showed."
  fi

  local mstat mergeable_v state_v failing_v
  mstat=$(pr_mergeability "$branch")
  [ -n "$mstat" ] || stop mergeability-unreadable "issue-to-pr: could not read whether $branch is mergeable, so the checks, the conflict state and the base distance all went unread. Check the PR yourself and hand back; this gate does not pass on an unread PR."
  if [ -n "$mstat" ]; then
    mergeable_v=$(printf '%s' "$mstat" | cut -f1)
    state_v=$(printf '%s' "$mstat" | cut -f2)
    failing_v=$(printf '%s' "$mstat" | cut -f3)
    if [ -n "$failing_v" ]; then
      emit FAILING_CHECKS "$failing_v"
      stop checks-failed "required checks failed on $branch ($failing_v). Fix them, push, re-run the gates, and re-approve; do not wait on a check that already failed."
    fi
    if [ "$mergeable_v" = CONFLICTING ]; then
      stop merge-conflict "$branch conflicts with its base. Do not resolve it yourself: report the conflict and hand back, because a resolution changes the diff that was approved."
    fi
    if [ "$state_v" = BEHIND ]; then
      local base_ref old_head new_head
      base_ref=$(gh pr view "$branch" --json baseRefName --jq .baseRefName 2>/dev/null || printf '')
      old_head=$(git rev-parse HEAD 2>/dev/null || printf '')
      if ! gh pr update-branch "$branch" >/dev/null 2>&1; then
        stop update-branch-failed "the base could not be merged into $branch automatically. Update the branch by hand, re-run the gates, and re-approve."
      fi
      git fetch --quiet origin "$branch" "$base_ref" 2>/dev/null || true
      new_head=$(git rev-parse "origin/$branch" 2>/dev/null || printf '')
      if [ -z "$new_head" ] || [ "$new_head" = "$old_head" ]; then
        stop base-update-unverified "updated $branch to its base but could not confirm the new head (the fetch may have failed). Re-run merge once the branch is fetched, or re-approve."
      fi
      if is_pure_base_merge "origin/$base_ref" "$old_head" "$new_head"; then
        emit LADDER_STEP base-merged-clean
        stop gates-unverified "updated $branch to its base. Pull the new head, re-run run-gates.sh, then re-run merge."
      else
        stop content-changed-needs-reapproval "merging the base into $branch changed the PR's own diff. Re-review the updated PR and re-approve - the earlier approval no longer covers it."
      fi
    fi
  fi

  local merge_method=squash merge_out
  if merge_out=$(gh pr merge "$branch" --squash --match-head-commit "$cur_sha" 2>&1); then
    :
  elif printf '%s' "$merge_out" | grep -qiE 'squash.*not allowed|not allowed.*squash|squash merging is not allowed'; then
    if merge_out=$(gh pr merge "$branch" --merge --match-head-commit "$cur_sha" 2>&1); then
      merge_method=merge
    elif merge_out=$(gh pr merge "$branch" --rebase --match-head-commit "$cur_sha" 2>&1); then
      merge_method=rebase
    else
      emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
      stop merge-failed "gh pr merge failed after the --merge and --rebase fallbacks. Report MERGE_ERROR verbatim and hand back."
    fi
  elif printf '%s' "$merge_out" | grep -qiE 'pending|not mergeable.*check|checks are still'; then
    if ! merge_out=$(gh pr merge "$branch" --squash --match-head-commit "$cur_sha" 2>&1); then
      stop checks-pending "required checks are still pending on $branch. Watch them to green (references/merge-ladder.md), then re-run merge - the approval stays valid."
    fi
  else
    emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
    stop merge-failed "gh pr merge failed for a reason the classifier does not know. Report MERGE_ERROR verbatim and hand back."
  fi

  local base_ref default_ref
  emit MERGED true
  emit MERGE_METHOD "$merge_method"
  base_ref=$(gh pr view "$branch" --json baseRefName --jq .baseRefName 2>/dev/null || printf '')
  default_ref=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || printf '')
  emit MERGED_INTO "$base_ref"
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

cmd_cleanup() {
  local root wt_path pr_state
  root=$(repo_root)
  [ -n "$root" ] || degrade not-a-git-repo "worktree cleanup: not inside a git repository"

  branch=$(canonical_branch "$branch")

  if [ "$keep_branch" -eq 0 ]; then
    pr_state=$(gh pr view "$branch" --json state --jq .state 2>/dev/null || printf '')
    [ "$pr_state" = MERGED ] || stop pr-not-merged "PR for $branch is '${pr_state:-unknown}', not MERGED - refusing cleanup"

    local dependents
    dependents=$(gh pr list --base "$branch" --state open --json number --jq '[.[].number] | join(", ")' 2>/dev/null) ||
      stop dependents-unreadable "could not read whether an open PR is based on $branch - check on GitHub, then delete the branch by hand"
    [ -z "$dependents" ] || stop base-of-open-pr "$branch is the base of open PR(s) $dependents - retarget or merge them before deleting it"
  fi

  local reg
  reg=$(registered_wt "$issue")
  wt_path=${reg:-$(compute_wt_path "$root" "$issue")}

  cd "$root" 2>/dev/null || true

  REMOVED=false
  LEFTOVER=""
  remove_worktree "$wt_path" "$root" "$issue"

  local deleted_local=false deleted_remote=false
  if [ "$keep_branch" -eq 1 ]; then
    emit REMOVED "$REMOVED"
    emit KEPT branch-and-pr
    [ -n "$LEFTOVER" ] && emit LEFTOVER_DIR "$LEFTOVER"
    done_ok
  fi
  if [ "$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')" = "$branch" ]; then
    local def
    def=$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
    if [ -n "$def" ] && [ "$def" != "$branch" ]; then
      git -C "$root" switch "$def" >/dev/null 2>&1 || git -C "$root" checkout --detach >/dev/null 2>&1
    else
      git -C "$root" checkout --detach >/dev/null 2>&1 || true
    fi
  fi
  if branch_exists "$branch"; then
    git branch -D "$branch" >/dev/null 2>&1 && deleted_local=true
  fi
  if git push origin --delete "$branch" >/dev/null 2>&1; then
    deleted_remote=true
  fi

  rm -rf "$(branch_dir "$root" "$branch")" 2>/dev/null

  emit REMOVED "$REMOVED"
  emit DELETED_LOCAL "$deleted_local"
  emit DELETED_REMOTE "$deleted_remote"
  [ -n "$LEFTOVER" ] && emit LEFTOVER_DIR "$LEFTOVER"
  done_ok
}

case "$subcmd" in
  ensure) cmd_ensure ;;
  merge) cmd_merge ;;
  cleanup) cmd_cleanup ;;
  *) degrade unknown-subcommand "worktree: unknown subcommand '$subcmd'" ;;
esac
