#!/usr/bin/env bash
# worktree.sh - the pipeline's git/gh worktree + merge mechanics (spec sec 4.2).
# SAFETY-CRITICAL. Never uses `git ... --force`, never deletes tracked
# modifications, never merges a head the gates have not covered. Every
# human-judgment stop is an exit code (2), not a silent decision.
#
#   worktree.sh ensure   <N> --branch <b> --start-point <ref>
#   worktree.sh merge    <N> --branch <b> [--ladder-attempt <n>]
#   worktree.sh cleanup  <N> --branch <b> [--keep-branch]
#
# Exit: 0 proceed | 2 stop-and-ask (STOP_REASON=) | 3 permission fallback
# (cut/keep the branch in place) | 4 degraded. `merge` is the ONLY path that
# runs `gh pr merge`; the model must never call it directly.
set -uo pipefail

# No fork: every caller (hooks.json, the tests, contracts.md) invokes this by a path
# with a slash in it, and the value is only ever used to source the line below.
SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# -- argument parse -----------------------------------------------------------
subcmd=${1:-}
shift || true
issue=""
branch=""
start_point=""
keep_branch=0
ladder_attempt=1
LADDER_CAP=3
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) branch=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --start-point) start_point=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --keep-branch) keep_branch=1; shift ;;
    --ladder-attempt) ladder_attempt=${2:-1}; shift 2 2>/dev/null || shift "$#" ;;
    -*) warn "worktree: ignoring unknown flag: $1"; shift ;;
    *) [ -z "$issue" ] && issue=$1; shift ;;
  esac
done

[ -n "$subcmd" ] || degrade missing-subcommand "worktree: subcommand required (ensure|merge|cleanup)"
[ -n "$branch" ] || degrade missing-branch "worktree: --branch required"
[ -n "$issue" ] || degrade missing-issue "worktree: issue number required"
assert_numeric_issue "$issue" worktree

# -- shared helpers -----------------------------------------------------------
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

# pr_mergeability BRANCH -> one TSV line "<mergeable>\t<mergeStateStatus>\t<failing-csv>"
# read structurally through gh's own --jq (no system jq). Empty output means the
# structured read was unavailable (old gh / rate limit) and the caller must fall
# back to the free-text merge classifier. `failing-csv` lists checks whose
# conclusion/state already failed (a doomed PR must never be waited on or merged).
pr_mergeability() {
  # shellcheck disable=SC2016  # $c is a jq variable, not a shell expansion
  gh pr view "$1" --json mergeable,mergeStateStatus,statusCheckRollup --jq \
    '[ (.mergeable // ""), (.mergeStateStatus // ""), ([ .statusCheckRollup[]? | select( ((.conclusion // .state // "") | ascii_upcase) as $c | ($c=="FAILURE" or $c=="ERROR" or $c=="CANCELLED" or $c=="TIMED_OUT") ) | (.name // .context // "check") ] | join(",")) ] | @tsv' \
    2>/dev/null
}

# is_pure_base_merge BASE OLD_HEAD NEW_HEAD -> 0 if merging the base into the branch
# added no PR content of its own. Compares the PR's OWN proposed change before vs
# after via merge-base three-dot diffs (git diff BASE...HEAD is "what the branch
# adds since it forked"). Byte-identical => the base merge only pulled in the base,
# so the existing approval still covers the diff. NOTE: the spec's literal two-dot
# `git diff OLD NEW` is unsound - it includes every unrelated file the base carried
# forward, so it rejects the safe common case; do not "simplify" back to it.
is_pure_base_merge() {
  local base=$1 old=$2 new=$3 d_old d_new
  d_old=$(git diff "$base...$old" 2>/dev/null) || return 1
  d_new=$(git diff "$base...$new" 2>/dev/null) || return 1
  [ "$d_old" = "$d_new" ]
}

# remove_worktree wt root issue -> sets REMOVED and (on a stubborn dir) LEFTOVER.
# Never uses --force, never STOPs on a merely-locked dir, and never auto-deletes an
# UNREGISTERED directory (same protection as ensure's stale-unregistered-dir): git
# only ever unregisters a clean worktree, but an unregistered path could also be a
# stale remnant or something the user parked there, so we report it instead of
# deleting it. STOPs only on tracked/unexpected changes in a still-registered tree.
remove_worktree() {
  local wt=$1 root=$2 n=$3
  REMOVED=false
  LEFTOVER=""

  # Nothing on disk: just tidy git's records.
  if [ ! -e "$wt" ]; then
    git -C "$root" worktree prune 2>/dev/null || true
    REMOVED=true
    return 0
  fi

  if git -C "$root" worktree remove "$wt" 2>/dev/null; then REMOVED=true; return 0; fi

  # Removal refused. If the worktree is NO LONGER registered, git partially
  # succeeded (unregistered it on Windows but a lock left the directory) or it was
  # never a worktree. Either way, do not delete it - prune git's records and report
  # the leftover so the model/user can inspect and remove it deliberately.
  local still_reg
  still_reg=$(registered_wt "$n" "$root")
  if [ -z "$still_reg" ]; then
    git -C "$root" worktree prune 2>/dev/null || true
    LEFTOVER="$wt"
    return 0
  fi

  # Still registered: refused because the tree is dirty. A run keeps its own files
  # under the state directory now, so anything left in here belongs to somebody else
  # and is not ours to delete - except a state directory the worktree picked up
  # itself, from a run that pointed at a relative log dir. That one is ours.
  local status
  status=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null |
    grep -v '^?? \.claude/issue-to-pr/' || printf '')
  if [ -n "$status" ]; then
    emit DIRTY_FILES "$(printf '%s' "$status" | tr '\n' ';')"
    stop dirty-tracked-files "worktree $wt has tracked or unexpected changes - not removing"
  fi

  if git -C "$root" worktree remove "$wt" 2>/dev/null; then REMOVED=true; return 0; fi
  # Clean but still un-removable (a lock persists): report, do not STOP - the branch
  # can still be cleaned up. Run cleanup from the main checkout to avoid
  # this (a shell whose cwd is the worktree locks it on Windows).
  LEFTOVER="$wt"
  return 0
}

# -- subcommands --------------------------------------------------------------

cmd_ensure() {
  [ -n "$start_point" ] || degrade missing-start-point "worktree ensure: --start-point required"

  local root reg wt_path add_out state actual_branch
  root=$(repo_root)
  [ -n "$root" ] || degrade not-a-git-repo "worktree ensure: not inside a git repository"
  wt_path=$(compute_wt_path "$root" "$issue")
  reg=$(registered_wt "$issue")

  # Registered but its directory vanished -> prune and fall through to recreate.
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
    # PR state on resume: a merged PR means there is nothing left to do here.
    local pr_state
    pr_state=$(gh pr list --head "$actual_branch" --json state --jq '.[0].state' 2>/dev/null || printf '')
    pr_state=${pr_state:-none}
    if [ "$pr_state" = MERGED ]; then
      emit WT_PATH "$wt_path"
      emit BRANCH "$actual_branch"
      emit PR_STATE merged
      stop pr-already-merged "PR for $actual_branch is merged - run cleanup"
    fi
    emit PR_STATE "$(printf '%s' "$pr_state" | tr '[:upper:]' '[:lower:]')"
  else
    # Unregistered directory already on disk -> never auto-delete or rename it.
    if [ -e "$wt_path" ]; then
      emit WT_PATH "$wt_path"
      stop stale-unregistered-dir "a directory exists at $wt_path but is not a registered worktree"
    fi
    if branch_exists "$branch"; then
      add_out=$(git worktree add "$wt_path" "$branch" 2>&1) || { handle_add_error "$add_out"; return; }
      state=REATTACHED
    else
      add_out=$(git worktree add "$wt_path" -b "$branch" "$start_point" 2>&1) || { handle_add_error "$add_out"; return; }
      state=CREATED
    fi
    actual_branch=$branch
  fi

  emit WT_PATH "$wt_path"
  emit ORIGINAL_ROOT "$root"
  emit STATE "$state"
  emit BRANCH "$actual_branch"
  done_ok
}

# handle_add_error RAW - classify a failed `git worktree add`.
handle_add_error() {
  local raw=$1
  case "$raw" in
    *"already exists"*)
      # Race: someone registered it between the scan and the add. Rescan once.
      local reg2
      reg2=$(registered_wt "$issue")
      if [ -n "$reg2" ]; then
        emit WT_PATH "$reg2"
        emit STATE RESUMED
        emit BRANCH "$(git -C "$reg2" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"
        done_ok
      fi
      stop stale-unregistered-dir "worktree add reported 'already exists' but nothing is registered"
      ;;
    *"invalid reference"* | *"not a valid"* | *"unknown revision"*)
      stop invalid-start-point "start-point '$start_point' is not a valid ref"
      ;;
    *"Permission denied"* | *"permission denied"* | *"Operation not permitted"*)
      # The one branch in this file with no test: provoking a real permission-denied
      # `worktree add` needs a fixture that behaves the same on Linux and Windows, and
      # chmod does not. Kept because deleting it turns a graceful in-place fallback
      # (exit 3) into a stop-and-ask.
      fallback worktree-permission-denied "cannot create a worktree here - cut the branch in place: git switch -c $branch $start_point"
      ;;
    *)
      emit ADD_ERROR "$(printf '%s' "$raw" | tr '\n' ' ')"
      stop worktree-add-failed "git worktree add failed"
      ;;
  esac
}

cmd_merge() {
  [ "$ladder_attempt" -le "$LADDER_CAP" ] || stop merge-ladder-exhausted "the merge ladder retried $LADDER_CAP times without landing $branch. Resolve the PR state on GitHub by hand, then re-approve."
  local root cur_sha
  root=$(repo_root)
  [ -n "$root" ] || degrade not-a-git-repo "worktree merge: not inside a git repository"

  # Every gh call below accepts a PR number; the receipt is keyed by BRANCH NAME.
  # Resolve the ref once, or `merge --branch 42` hunts for a receipt written under
  # the branch name and stops on a run whose gates were green.
  branch=$(canonical_branch "$branch")
  cur_sha=$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || printf '')
  [ -n "$cur_sha" ] || stop pr-head-unreadable "issue-to-pr: could not read the PR head for $branch. Check the PR exists and gh is authenticated."

  # -- 1. the gates covered THIS head, and GitHub has no outstanding review ----
  # Both were promises the model had to keep by remembering to. The receipt is
  # written by run-gates.sh on an all-green run and names the HEAD it ran against,
  # so a merge of anything the gates did not see stops here. The review read fails
  # CLOSED: "could not tell" is not "clear".
  local receipt receipt_sha rstate
  receipt=$(receipt_path "$root" "$branch")
  receipt_sha=""
  [ -f "$receipt" ] && receipt_sha=$(json_str_field "$receipt" head_sha)
  if [ "$receipt_sha" != "$cur_sha" ]; then
    local covers="none found"
    [ -n "$receipt_sha" ] && covers="covers ${receipt_sha:0:12}"
    stop gates-unverified "issue-to-pr: no green gate receipt for ${cur_sha:0:12} (receipt $covers). Re-run run-gates.sh on this head, then re-approve."
  fi
  rstate=$(review_state "$branch")
  case "$rstate" in
    clear) : ;;
    changes_requested) stop review-blocked "issue-to-pr: $branch has a review requesting changes. Address it, push, re-run the gates, and re-approve." ;;
    unresolved_threads) stop review-blocked "issue-to-pr: $branch has unresolved review threads. Resolve them on GitHub, then re-approve." ;;
    *) stop review-unreadable "issue-to-pr: could not read the review state of $branch. Check it yourself before merging; this gate does not pass on an unread review." ;;
  esac

  # -- 2. push the branch (must already track upstream from Step 9) -------------
  if ! push_out=$(git push 2>&1); then
    emit PUSH_ERROR "$(printf '%s' "$push_out" | tr '\n' ' ')"
    stop push-rejected "git push was rejected - resolve remotely, then re-approve"
  fi

  # -- 3. merge-failure ladder pre-check (sec 6.3) ------------------------------
  # A structured read classifies the PR BEFORE any gh pr merge, so a doomed or
  # behind PR never blind-merges. Empty read (old gh / rate limit) falls through
  # to the free-text classifier in step 4.
  local mstat mergeable_v state_v failing_v
  mstat=$(pr_mergeability "$branch")
  if [ -n "$mstat" ]; then
    mergeable_v=$(printf '%s' "$mstat" | cut -f1)
    state_v=$(printf '%s' "$mstat" | cut -f2)
    failing_v=$(printf '%s' "$mstat" | cut -f3)
    if [ -n "$failing_v" ]; then
      emit FAILING_CHECKS "$failing_v"
      stop checks-failed "required checks failed on $branch ($failing_v). Fix them, push, re-run the gates, and re-approve; do not wait on a check that already failed."
    fi
    if [ "$mergeable_v" = CONFLICTING ]; then
      stop merge-conflict "$branch conflicts with its base. Resolve the conflict locally, push, re-run the gates, and re-approve."
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
      # A real update-branch ALWAYS advances the head. If we cannot OBSERVE an
      # advanced head (fetch failed / stale tracking ref), we cannot prove the
      # base merge is pure - so never assume it. Comparing old..old would read
      # trivially "pure" and merge an unreviewed change; stop instead.
      if [ -z "$new_head" ] || [ "$new_head" = "$old_head" ]; then
        stop base-update-unverified "updated $branch to its base but could not confirm the new head (the fetch may have failed). Re-run merge once the branch is fetched, or re-approve."
      fi
      if is_pure_base_merge "origin/$base_ref" "$old_head" "$new_head"; then
        emit LADDER_STEP base-merged-clean
        # The PR's own diff is proved untouched, so the go-ahead still stands. The
        # gates are a separate promise: they never ran against base+diff, and a
        # receipt a base update could walk past would not be a gate at all.
        stop gates-unverified "updated $branch to its base. Pull the new head, re-run run-gates.sh, then re-run merge."
      else
        stop content-changed-needs-reapproval "merging the base into $branch changed the PR's own diff. Re-review the updated PR and re-approve - the earlier approval no longer covers it."
      fi
    fi
  fi

  # -- 4. squash-merge, with fallbacks ------------------------------------------
  local merge_method=squash merge_out
  if merge_out=$(gh pr merge "$branch" --squash --match-head-commit "$cur_sha" 2>&1); then
    :
  elif printf '%s' "$merge_out" | grep -qiE 'squash.*not allowed|not allowed.*squash|squash merging is not allowed'; then
    # Squash disallowed: fall back to the repo's other allowed method (merge, then rebase).
    if merge_out=$(gh pr merge "$branch" --merge --match-head-commit "$cur_sha" 2>&1); then
      merge_method=merge
    elif merge_out=$(gh pr merge "$branch" --rebase --match-head-commit "$cur_sha" 2>&1); then
      merge_method=rebase
    else
      emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
      stop merge-failed "gh pr merge failed after --merge and --rebase fallbacks"
    fi
  elif printf '%s' "$merge_out" | grep -qiE 'pending|not mergeable.*check|checks are still'; then
    # One immediate retry; if still pending, hand back. The bounded watch loop is
    # session-owned (references/merge-ladder.md): the model waits with gh pr checks
    # --watch up to CHECKS_TIMEOUT, then re-runs merge - the approval stays valid.
    # The retry carries --match-head-commit too: it is the only thing standing between
    # a push landing in this window and a merge of a head no gate receipt covers.
    if ! merge_out=$(gh pr merge "$branch" --squash --match-head-commit "$cur_sha" 2>&1); then
      stop checks-pending "required checks are still pending on $branch. Watch them to green (references/merge-ladder.md), then re-run merge - the approval stays valid."
    fi
  else
    emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
    stop merge-failed "gh pr merge failed - see MERGE_ERROR"
  fi

  local issue_state pr_url base_ref default_ref _pr_fields
  issue_state=$(gh issue view "$issue" --json state --jq .state 2>/dev/null || printf '')
  emit MERGED true

  # WHERE it merged, not just that it did: a PR stacked on another feature branch
  # merges into that branch, leaving the issue open and the work off the default one.
  # One call for both fields, one field per line - the same batching preflight's repo
  # read uses, and for the same reason.
  mapfile -t _pr_fields < <(gh pr view "$branch" --json url,baseRefName --jq '.url, .baseRefName' 2>/dev/null)
  pr_url=${_pr_fields[0]:-}
  base_ref=${_pr_fields[1]:-}
  # Asked of the API, not of `refs/remotes/origin/HEAD`: that ref mirrors whatever the
  # source repo's HEAD was at clone time (often some feature branch) and may not be set
  # at all. A fast wrong answer defeats the whole point of this signal.
  default_ref=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || printf '')
  emit MERGED_INTO "$base_ref"
  # Fails CLOSED, like the review read above: a ref that did not come back is `unknown`,
  # never `true`. Reporting "this reached the default branch" on the run that could not
  # find out is the exact false all-clear this block exists to prevent.
  if [ -z "$base_ref" ] || [ -z "$default_ref" ]; then
    emit BASE_IS_DEFAULT unknown
  elif [ "$base_ref" != "$default_ref" ]; then
    emit BASE_IS_DEFAULT false
    emit WARN_NON_DEFAULT_BASE "merged into '$base_ref', not '$default_ref' - the issue stays open and this work has NOT reached the default branch"
  else
    emit BASE_IS_DEFAULT true
  fi
  emit MERGE_METHOD "$merge_method"
  emit ISSUE_STATE "$issue_state"
  emit PR_URL "$pr_url"
  done_ok
}

cmd_cleanup() {
  local root wt_path pr_state
  root=$(repo_root)
  [ -n "$root" ] || degrade not-a-git-repo "worktree cleanup: not inside a git repository"

  # Same resolution as merge, and for a sharper reason: everything past the gh
  # precondition below is git, which knows nothing about PR numbers. Given a raw
  # number, `gh pr view` would report MERGED and then `git branch -D`
  # lookup would both silently miss, exiting 0 with the merged branch still there.
  branch=$(canonical_branch "$branch")

  # Hard precondition: the PR must be MERGED. Deleting an open PR's branch is
  # thereby mechanically impossible. --keep-branch deletes nothing, so it is exempt.
  if [ "$keep_branch" -eq 0 ]; then
    pr_state=$(gh pr view "$branch" --json state --jq .state 2>/dev/null || printf '')
    [ "$pr_state" = MERGED ] || stop pr-not-merged "PR for $branch is '${pr_state:-unknown}', not MERGED - refusing cleanup"

    # A branch that is the BASE of an open PR must survive: deleting it strands that
    # PR's work. GitHub only retargets a PR to the default branch when its base is
    # already gone, so this is the check that has to happen first, not GitHub's.
    # Fails CLOSED, like the review read at the merge: a list that does not come back
    # is not evidence that there are no dependents, and the delete is irreversible.
    local dependents
    dependents=$(gh pr list --base "$branch" --state open --json number --jq '[.[].number] | join(", ")' 2>/dev/null) ||
      stop dependents-unreadable "could not read whether an open PR is based on $branch - check on GitHub, then delete the branch by hand"
    [ -z "$dependents" ] || stop base-of-open-pr "$branch is the base of open PR(s) $dependents - retarget or merge them before deleting it"
  fi

  local reg
  reg=$(registered_wt "$issue")
  wt_path=${reg:-$(compute_wt_path "$root" "$issue")}

  # Get out of the worktree before removing it.
  cd "$root" 2>/dev/null || true

  REMOVED=false
  LEFTOVER=""
  # remove_worktree also handles an unregistered leftover dir (reports it via
  # LEFTOVER, never deletes it), so call it unconditionally from the main checkout.
  remove_worktree "$wt_path" "$root" "$issue"

  local deleted_local=false deleted_remote=false
  if [ "$keep_branch" -eq 1 ]; then
    emit REMOVED "$REMOVED"
    emit KEPT branch-and-pr
    [ -n "$LEFTOVER" ] && emit LEFTOVER_DIR "$LEFTOVER"
    done_ok
  fi
  # In-place mode (no worktree): the branch may be checked out in root, and a
  # checked-out branch can't be deleted. Move root off it first - to the default
  # branch when known, else detach HEAD.
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
  # Tolerate an already-absent remote ref.
  if git push origin --delete "$branch" >/dev/null 2>&1; then
    deleted_remote=true
  fi

  # The branch is gone, so its gate receipt can never match a head again. Nothing
  # else prunes them since the approval sweep went with the marker in 3.0.0, and a
  # state directory that only ever grows is how the old markers piled up.
  rm -f "$(receipt_path "$root" "$branch")" 2>/dev/null
  # The run's own files go the same way; the design lives in the PR body.
  rm -rf "$(run_dir "$root" "$issue")" 2>/dev/null

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
