#!/usr/bin/env bash
# worktree.sh - the pipeline's git/gh worktree + merge mechanics (spec sec 4.2).
# SAFETY-CRITICAL. Never uses `git ... --force`, never deletes tracked
# modifications, never merges without a valid approval marker. Every
# human-judgment stop is an exit code (2), not a silent decision.
#
#   worktree.sh ensure   <N> --branch <b> --start-point <ref>
#   worktree.sh merge    <N> --branch <b>
#   worktree.sh cleanup  <N> --branch <b> [--salvage-to <dir>]
#   worktree.sh teardown <N>              [--salvage-to <dir>]
#
# Exit: 0 proceed | 2 stop-and-ask (STOP_REASON=) | 3 permission fallback
# (cut/keep the branch in place) | 4 degraded. `merge` is the ONLY path that
# runs `gh pr merge`; the model must never call it directly.
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
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch) branch=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --start-point) start_point=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --salvage-to) salvage_to=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
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

registered_wt() { # issue -> registered worktree path ending in /issue-<N>, or empty
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep -E "/issue-$1\$" | head -1
}

branch_exists() { git show-ref --verify --quiet "refs/heads/$1"; }

is_base_branch() { # name -> true if it looks like an integration base
  case "$1" in main | master | dev | develop) return 0 ;; *) return 1 ;; esac
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

# remove_worktree wt root issue -> sets REMOVED; STOPs on tracked dirtiness.
# Never uses --force: a refused removal is classified from `git status --porcelain`.
remove_worktree() {
  local wt=$1 root=$2 n=$3
  REMOVED=false
  if git -C "$root" worktree remove "$wt" 2>/dev/null; then REMOVED=true; return 0; fi

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
  stop worktree-remove-failed "could not remove $wt cleanly (no --force is ever used)"
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

  # -- 3. squash-merge, with fallbacks ------------------------------------------
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
    # v1.2.0: one immediate retry, then hand back. The auto-watch ladder is v2.0 (sec 6.3).
    if ! merge_out=$(gh pr merge "$branch" --squash 2>&1); then
      stop checks-pending "required checks are still pending - wait for green, then re-run merge"
    fi
  else
    emit MERGE_ERROR "$(printf '%s' "$merge_out" | tr '\n' ' ')"
    stop merge-failed "gh pr merge failed - see MERGE_ERROR"
  fi

  # -- 4. consume the marker + honest outcome check -----------------------------
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
  if [ -n "$reg" ]; then
    remove_worktree "$wt_path" "$root" "$issue"
  fi

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
  if [ -n "$reg" ]; then
    remove_worktree "$wt_path" "$root" "$issue"
  fi
  emit REMOVED "$REMOVED"
  emit SALVAGED "${SALVAGED:-}"
  emit KEPT "branch-and-pr" # teardown never touches the branch or PR
  done_ok
}

case "$subcmd" in
  ensure) cmd_ensure ;;
  merge) cmd_merge ;;
  cleanup) cmd_cleanup ;;
  teardown) cmd_teardown ;;
  *) degrade unknown-subcommand "worktree: unknown subcommand '$subcmd'" ;;
esac
