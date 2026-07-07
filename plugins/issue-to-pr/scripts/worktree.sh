#!/usr/bin/env bash
# worktree.sh - the pipeline's git/gh worktree + merge mechanics (spec sec 4.2).
# SAFETY-CRITICAL. Never uses `git ... --force`, never deletes tracked
# modifications, never merges without a valid approval marker. Every
# human-judgment stop is an exit code (2), not a silent decision.
#
#   worktree.sh ensure   <N> --branch <b> --start-point <ref>
#   worktree.sh merge    <N> --branch <b> [--ladder-attempt <n>]
#   worktree.sh cleanup  <N> --branch <b> [--salvage-to <dir>]
#   worktree.sh teardown <N>              [--salvage-to <dir>]
#   worktree.sh revert   <N> --branch <b>            # draft revert PR (sec 6.5)
#
# Exit: 0 proceed | 2 stop-and-ask (STOP_REASON=) | 3 permission fallback
# (cut/keep the branch in place) | 4 degraded. `merge` is the ONLY path that
# runs `gh pr merge`; the model must never call it directly. `revert` NEVER
# merges - it only opens a draft PR for the human to decide on.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# -- argument parse -----------------------------------------------------------
subcmd=${1:-}
shift || true
issue=""
branch=""
start_point=""
salvage_to=""
ladder_attempt=1
LADDER_CAP=3
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) branch=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --start-point) start_point=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --salvage-to) salvage_to=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --ladder-attempt) ladder_attempt=${2:-1}; shift 2 2>/dev/null || shift "$#" ;;
    --json) enable_json; shift ;;
    -*) warn "worktree: ignoring unknown flag: $1"; shift ;;
    *) [ -z "$issue" ] && issue=$1; shift ;;
  esac
done

[ -n "$subcmd" ] || degrade missing-subcommand "worktree: subcommand required (ensure|merge|cleanup|teardown)"
[ -n "$issue" ] || degrade missing-issue "worktree: issue number required"

# -- shared helpers -----------------------------------------------------------
main_worktree() { git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1; }

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

detect_deps() { # dir -> sets DEPS_MANIFEST, INSTALL_HINT
  local d=$1
  if [ -f "$d/pnpm-lock.yaml" ]; then DEPS_MANIFEST=node; INSTALL_HINT='pnpm install'
  elif [ -f "$d/yarn.lock" ]; then DEPS_MANIFEST=node; INSTALL_HINT='yarn install'
  elif [ -f "$d/package-lock.json" ] || [ -f "$d/package.json" ]; then DEPS_MANIFEST=node; INSTALL_HINT='npm install'
  elif [ -f "$d/requirements.txt" ]; then DEPS_MANIFEST=python; INSTALL_HINT='pip install -r requirements.txt'
  elif [ -f "$d/pyproject.toml" ]; then DEPS_MANIFEST=python; INSTALL_HINT='pip install -e .'
  elif [ -f "$d/Cargo.toml" ]; then DEPS_MANIFEST=rust; INSTALL_HINT='cargo fetch'
  elif [ -f "$d/go.mod" ]; then DEPS_MANIFEST=go; INSTALL_HINT='go mod download'
  else DEPS_MANIFEST=none; INSTALL_HINT=''
  fi
}

salvage_artifacts() { # wt salvage_dir issue -> sets SALVAGED
  SALVAGED=""
  local wt=$1 dst=$2 n=$3 f src
  [ -n "$dst" ] || return 0
  mkdir -p "$dst" 2>/dev/null || return 0
  for f in design.md progress.md state.json; do
    src="$wt/tmp/task-$n/$f"
    if [ -f "$src" ]; then cp "$src" "$dst/" 2>/dev/null || true; fi
  done
  SALVAGED=$dst
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

  # Still registered: refused because the tree is dirty. Classify.
  local status line p tracked_dirty=0
  # --untracked-files=all so an untracked tmp/ is listed as individual files
  # (tmp/task-N/foo), not collapsed to a bare "?? tmp/" that would misclassify.
  status=$(git -C "$wt" status --porcelain --untracked-files=all 2>/dev/null || printf '')
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      '??'*)
        p=${line#?? }
        case "$p" in
          "tmp/task-$n/"*) : ;; # our own working dir - safe to drop
          *) tracked_dirty=1 ;;  # unexpected untracked file - do not delete
        esac
        ;;
      *) tracked_dirty=1 ;; # tracked modification / staged change
    esac
  done <<EOF
$status
EOF

  if [ "$tracked_dirty" = 1 ]; then
    emit DIRTY_FILES "$(printf '%s' "$status" | tr '\n' ';')"
    stop dirty-tracked-files "worktree $wt has tracked or unexpected changes - not removing"
  fi

  # Only our tmp working dir was in the way: remove it explicitly, retry once.
  rm -rf "${wt:?}/tmp/task-$n" 2>/dev/null || true
  if git -C "$root" worktree remove "$wt" 2>/dev/null; then REMOVED=true; return 0; fi
  # Clean but still un-removable (a lock persists): report, do not STOP - the branch
  # and marker can still be cleaned up. Run cleanup from the main checkout to avoid
  # this (a shell whose cwd is the worktree locks it on Windows).
  LEFTOVER="$wt"
  return 0
}

# -- subcommands --------------------------------------------------------------

cmd_ensure() {
  [ -n "$branch" ] || degrade missing-branch "worktree ensure: --branch required"
  [ -n "$start_point" ] || degrade missing-start-point "worktree ensure: --start-point required"

  local root reg wt_path add_out state actual_branch
  root=$(main_worktree)
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

  detect_deps "$wt_path"
  emit WT_PATH "$wt_path"
  emit ORIGINAL_ROOT "$root"
  emit STATE "$state"
  emit BRANCH "$actual_branch"
  emit DEPS_MANIFEST "$DEPS_MANIFEST"
  emit INSTALL_HINT "$INSTALL_HINT"
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
      fallback worktree-permission-denied "cannot create a worktree here - cut the branch in place: git switch -c $branch $start_point"
      ;;
    *)
      emit ADD_ERROR "$(printf '%s' "$raw" | tr '\n' ' ')"
      stop worktree-add-failed "git worktree add failed"
      ;;
  esac
}

cmd_merge() {
  [ -n "$branch" ] || degrade missing-branch "worktree merge: --branch required"
  [ "$ladder_attempt" -le "$LADDER_CAP" ] || stop merge-ladder-exhausted "the merge ladder retried $LADDER_CAP times without landing $branch. Resolve the PR state on GitHub by hand, then re-approve."
  local root marker used created created_epoch age marker_sha cur_sha
  root=$(main_worktree)
  [ -n "$root" ] || degrade not-a-git-repo "worktree merge: not inside a git repository"

  # -- 1. approval marker: exists  and  unused  and  fresh (<30m)  and  head-SHA match ------
  marker=$(marker_path "$root" "$branch")
  [ -f "$marker" ] || stop no-valid-approval "no approval marker for $branch - the model must run approve.sh after judging the reply a go-ahead"
  used=$(marker_used "$marker")
  [ "$used" = false ] || stop no-valid-approval "approval marker already used (single-use) - re-approve to merge again"
  created=$(marker_str_field "$marker" created_at)
  created_epoch=$(epoch_of "$created")
  [ -n "$created_epoch" ] || stop no-valid-approval "approval marker timestamp is unparseable - re-approve"
  age=$(( $(now_epoch) - created_epoch ))
  [ "$age" -le 1800 ] || stop no-valid-approval "approval marker is stale (>30 min) - re-approve"
  marker_sha=$(marker_str_field "$marker" pr_head_sha)
  cur_sha=$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || printf '')
  if [ -z "$cur_sha" ] || [ "$marker_sha" != "$cur_sha" ]; then
    stop no-valid-approval "PR head moved since approval (approved $marker_sha, now ${cur_sha:-unknown}); re-approve"
  fi

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
        if ! bash "$SCRIPT_DIR/approve.sh" --refresh "$branch" >/dev/null 2>&1; then
          stop marker-refresh-failed "could not refresh the approval marker after updating $branch to its base. Re-approve."
        fi
        emit LADDER_STEP base-merged-refreshed
      else
        stop content-changed-needs-reapproval "merging the base into $branch changed the PR's own diff. Re-review the updated PR and re-approve - the earlier approval no longer covers it."
      fi
    fi
  fi

  # -- 4. squash-merge, with fallbacks ------------------------------------------
  local merge_method=squash merge_out
  if merge_out=$(gh pr merge "$branch" --squash 2>&1); then
    :
  elif printf '%s' "$merge_out" | grep -qiE 'squash.*not allowed|not allowed.*squash|squash merging is not allowed'; then
    # Squash disallowed: fall back to the repo's other allowed method (merge, then rebase).
    if merge_out=$(gh pr merge "$branch" --merge 2>&1); then
      merge_method=merge
    elif merge_out=$(gh pr merge "$branch" --rebase 2>&1); then
      merge_method=rebase
    else
      emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
      stop merge-failed "gh pr merge failed after --merge and --rebase fallbacks"
    fi
  elif printf '%s' "$merge_out" | grep -qiE 'pending|not mergeable.*check|checks are still'; then
    # One immediate retry; if still pending, hand back. The bounded watch loop is
    # session-owned (references/merge-ladder.md): the model waits with gh pr checks
    # --watch up to CHECKS_TIMEOUT, then re-runs merge - the approval stays valid.
    if ! merge_out=$(gh pr merge "$branch" --squash 2>&1); then
      stop checks-pending "required checks are still pending on $branch. Watch them to green (references/merge-ladder.md), then re-run merge - the approval stays valid."
    fi
  else
    emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
    stop merge-failed "gh pr merge failed - see MERGE_ERROR"
  fi

  # -- 5. consume the marker + honest outcome check -----------------------------
  marker_set_used "$marker"
  local issue_state pr_url
  issue_state=$(gh issue view "$issue" --json state --jq .state 2>/dev/null || printf '')
  pr_url=$(gh pr view "$branch" --json url --jq .url 2>/dev/null || printf '')
  emit MERGED true
  emit MERGE_METHOD "$merge_method"
  emit ISSUE_STATE "$issue_state"
  emit PR_URL "$pr_url"
  done_ok
}

cmd_cleanup() {
  [ -n "$branch" ] || degrade missing-branch "worktree cleanup: --branch required"
  local root wt_path pr_state
  root=$(main_worktree)
  [ -n "$root" ] || degrade not-a-git-repo "worktree cleanup: not inside a git repository"

  # Hard precondition: the PR must be MERGED. Deleting an open PR's branch is
  # thereby mechanically impossible.
  pr_state=$(gh pr view "$branch" --json state --jq .state 2>/dev/null || printf '')
  [ "$pr_state" = MERGED ] || stop pr-not-merged "PR for $branch is '${pr_state:-unknown}', not MERGED - refusing cleanup"

  local reg
  reg=$(registered_wt "$issue")
  wt_path=${reg:-$(compute_wt_path "$root" "$issue")}

  # Salvage lasting artifacts before the worktree (and its gitignored files) go.
  salvage_artifacts "$wt_path" "$salvage_to" "$issue"

  # Get out of the worktree before removing it.
  cd "$root" 2>/dev/null || true

  REMOVED=false
  LEFTOVER=""
  # remove_worktree also handles an unregistered leftover dir (reports it via
  # LEFTOVER, never deletes it), so call it unconditionally from the main checkout.
  remove_worktree "$wt_path" "$root" "$issue"

  local deleted_local=false deleted_remote=false
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

  # Remove the consumed approval marker if present.
  local marker
  marker=$(marker_path "$root" "$branch")
  [ -f "$marker" ] && rm -f "$marker"

  emit REMOVED "$REMOVED"
  emit DELETED_LOCAL "$deleted_local"
  emit DELETED_REMOTE "$deleted_remote"
  emit SALVAGED "${SALVAGED:-}"
  [ -n "$LEFTOVER" ] && emit LEFTOVER_DIR "$LEFTOVER"
  done_ok
}

cmd_teardown() {
  local root reg wt_path
  root=$(main_worktree)
  [ -n "$root" ] || degrade not-a-git-repo "worktree teardown: not inside a git repository"
  reg=$(registered_wt "$issue")

  # In-place fallback mode: nothing was ever created, so nothing to remove.
  if [ -z "$reg" ]; then
    wt_path=$(compute_wt_path "$root" "$issue")
    if [ ! -d "$wt_path" ]; then
      emit KEPT in-place
      done_ok
    fi
  fi
  wt_path=${reg:-$(compute_wt_path "$root" "$issue")}

  salvage_artifacts "$wt_path" "$salvage_to" "$issue"
  cd "$root" 2>/dev/null || true

  REMOVED=false
  LEFTOVER=""
  remove_worktree "$wt_path" "$root" "$issue"
  emit REMOVED "$REMOVED"
  emit SALVAGED "${SALVAGED:-}"
  [ -n "$LEFTOVER" ] && emit LEFTOVER_DIR "$LEFTOVER"
  emit KEPT "branch-and-pr" # teardown never touches the branch or PR
  done_ok
}

# cmd_revert - post-merge safety net (sec 6.5). When the smoke gate fails on the
# updated base, prepare a DRAFT revert PR of the squash commit and hand back. NEVER
# merges anything - the draft is the human's prepared undo, they still decide.
cmd_revert() {
  [ -n "$branch" ] || degrade missing-branch "worktree revert: --branch required"
  local root base_ref title slug squash_sha rev_branch rev_wt rev_url
  root=$(main_worktree)
  [ -n "$root" ] || degrade not-a-git-repo "worktree revert: not inside a git repository"
  squash_sha=$(gh pr view "$branch" --json mergeCommit --jq '.mergeCommit.oid' 2>/dev/null || printf '')
  [ -n "$squash_sha" ] || degrade no-merge-commit "worktree revert: could not resolve the merge commit for $branch (is the PR merged?)"
  base_ref=$(gh pr view "$branch" --json baseRefName --jq .baseRefName 2>/dev/null || printf 'main')
  title=$(gh pr view "$branch" --json title --jq .title 2>/dev/null || printf 'issue %s' "$issue")
  slug=$(slugify "$title")
  rev_branch="revert/issue-$issue-$slug"

  git -C "$root" fetch --quiet origin "$base_ref" 2>/dev/null || true
  rev_wt=$(compute_wt_path "$root" "revert-$issue")
  if ! git -C "$root" worktree add -b "$rev_branch" "$rev_wt" "origin/$base_ref" >/dev/null 2>&1; then
    stop revert-branch-failed "could not create the revert branch $rev_branch off origin/$base_ref. Revert $squash_sha by hand."
  fi
  if ! git -C "$rev_wt" revert --no-edit "$squash_sha" >/dev/null 2>&1; then
    git -C "$rev_wt" revert --abort >/dev/null 2>&1 || true
    git -C "$root" worktree remove --force "$rev_wt" >/dev/null 2>&1 || true
    git -C "$root" branch -D "$rev_branch" >/dev/null 2>&1 || true
    stop revert-conflict "the automatic revert of $squash_sha did not apply cleanly. Revert it by hand."
  fi
  if ! git -C "$rev_wt" push -u origin "$rev_branch" >/dev/null 2>&1; then
    git -C "$root" worktree remove --force "$rev_wt" >/dev/null 2>&1 || true
    git -C "$root" branch -D "$rev_branch" >/dev/null 2>&1 || true
    stop revert-push-failed "could not push $rev_branch. Push it and open the revert PR by hand."
  fi
  rev_url=$(gh pr create --draft --head "$rev_branch" --base "$base_ref" \
    --title "Revert \"$title\"" \
    --body "Draft revert of #$issue (merge commit $squash_sha) - post-merge smoke failed on $base_ref. Review, then merge to roll back or close to keep the change." \
    2>/dev/null || printf '')
  git -C "$root" worktree remove --force "$rev_wt" >/dev/null 2>&1 || true
  [ -n "$rev_url" ] || stop revert-pr-failed "the revert branch $rev_branch is pushed but the draft PR could not be opened. Open it by hand."
  emit REVERT_BRANCH "$rev_branch"
  emit REVERT_PR_URL "$rev_url"
  emit REVERT_COMMIT "$squash_sha"
  done_ok
}

case "$subcmd" in
  ensure) cmd_ensure ;;
  merge) cmd_merge ;;
  cleanup) cmd_cleanup ;;
  teardown) cmd_teardown ;;
  revert) cmd_revert ;;
  *) degrade unknown-subcommand "worktree: unknown subcommand '$subcmd'" ;;
esac
