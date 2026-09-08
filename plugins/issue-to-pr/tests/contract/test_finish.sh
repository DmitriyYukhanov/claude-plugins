#!/usr/bin/env bash

SHA_OK="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

enter() { cd "$1" || fail "could not enter $1"; }

mk_worktree() { # repo branch -> worktree at repo-worktrees/issue-6 with one pushed commit
  local repo=$1 branch=$2 wt="$TEST_TMPDIR/repo-worktrees/issue-6"
  git -C "$repo" worktree add "$wt" -b "$branch" main >/dev/null 2>&1
  printf 'work\n' >"$wt/work.txt"
  git -C "$wt" add work.txt
  git -C "$wt" commit -qm work
  git -C "$wt" push -q -u origin "$branch" 2>/dev/null || true
  printf '%s' "$wt"
}

merge_setup() { # scenario [receipt-gates] -> cwd in the worktree, receipt for SHA_OK written
  REPO=$(init_repo_with_remote)
  WT=$(mk_worktree "$REPO" feat/issue-6-x)
  enter "$WT"
  use_fake_gh "$1"
  write_receipt "$REPO" feat/issue-6-x "$SHA_OK" "${2:-test}"
}

cleanup_setup() { # scenario -> cwd in the main checkout, worktree on feat/issue-6-x
  REPO=$(init_repo_with_remote)
  WT=$(mk_worktree "$REPO" feat/issue-6-x)
  enter "$REPO"
  use_fake_gh "$1"
}

branch_survives() { git -C "$REPO" show-ref --verify --quiet refs/heads/feat/issue-6-x; }

test_merge_squashes_the_head_the_receipt_covers() {
  merge_setup happy
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" BASE_IS_DEFAULT true
  assert_gh_called "pr merge feat/issue-6-x --squash --match-head-commit $SHA_OK"
}

test_merge_reports_a_non_default_base() {
  merge_setup stacked-base
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED_INTO feat/issue-5-parent
  assert_key "$OUT" BASE_IS_DEFAULT false
}

test_merge_says_unknown_when_the_default_branch_is_unreadable() {
  merge_setup default-branch-unreadable
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" BASE_IS_DEFAULT unknown
}

test_merge_refuses_a_head_no_receipt_covers() {
  local repo wt
  repo=$(init_repo_with_remote)
  wt=$(mk_worktree "$repo" feat/issue-6-x)
  enter "$wt"
  use_fake_gh happy
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON gates-unverified
  write_receipt "$repo" feat/issue-6-x bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_gh_not_called "pr merge" "merged with no receipt, or one for another head"
}

test_merge_refuses_a_receipt_without_the_test_gate() {
  merge_setup happy smoke
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_gh_not_called "pr merge" "a smoke or install run overwrites the receipt; neither ran the tests on this head"
}

test_merge_refuses_a_method_gh_would_read_as_a_bypass() {
  merge_setup happy
  run_script finish.sh merge 6 --branch feat/issue-6-x --method admin
  assert_rc 4
  assert_gh_not_called "pr merge" "--method admin reached gh as --admin, which bypasses branch protection"
}

test_merge_pushes_the_branch_not_whatever_the_cwd_is_on() {
  merge_setup happy
  enter "$REPO" # the main checkout, on main, with a local commit origin does not have
  printf 'local only\n' >"$REPO/local.txt"
  git -C "$REPO" add local.txt
  git -C "$REPO" commit -qm "local only"
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  [ "$(git -C "$REPO" rev-parse origin/main)" != "$(git -C "$REPO" rev-parse main)" ] ||
    fail "a bare git push published the main checkout's own branch"
}

test_merge_refuses_a_review_requesting_changes() {
  merge_setup review-changes-requested
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON review-blocked
  assert_gh_not_called "pr merge"
}

test_merge_refuses_when_the_pr_cannot_be_read() {
  merge_setup pr-unreadable
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_gh_not_called "pr merge"
}

test_merge_surfaces_gh_own_refusal_and_claims_nothing() {
  merge_setup protected
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_contains "$OUT" "Protected branch update failed"
  assert_not_contains "$OUT" "MERGED=true"
}

test_merge_stops_when_the_push_is_rejected() {
  merge_setup happy
  git -C "$WT" remote set-url origin "$TEST_TMPDIR/does-not-exist.git"
  run_script finish.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_gh_not_called "pr merge"
}

test_cleanup_removes_the_tree_both_branches_and_the_run_dir() {
  cleanup_setup pr-merged
  write_receipt "$REPO" feat/issue-6-x "$SHA_OK"
  run_script finish.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REMOVED true
  assert_key "$OUT" DELETED_LOCAL true
  assert_key "$OUT" DELETED_REMOTE true
  [ ! -d "$WT" ] || fail "the worktree survived cleanup"
  ! branch_survives || fail "the local branch survived cleanup"
  ! git -C "$REPO" ls-remote --exit-code --heads origin feat/issue-6-x >/dev/null 2>&1 ||
    fail "the remote branch survived cleanup"
  [ ! -e "$(run_dir_of "$REPO" feat/issue-6-x)" ] || fail "the run directory survived cleanup"
}

test_cleanup_refuses_an_unmerged_pr() {
  cleanup_setup pr-open
  run_script finish.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON pr-not-merged
  branch_survives || fail "cleanup deleted the branch of an open PR"
  [ -d "$WT" ] || fail "cleanup removed the worktree of an open PR"
}

test_cleanup_refuses_a_branch_an_open_pr_is_based_on_or_cannot_check() {
  cleanup_setup has-dependent-pr
  run_script finish.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON base-of-open-pr
  branch_survives || fail "cleanup deleted a branch an open PR is based on"
  use_fake_gh dependents-unreadable
  run_script finish.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  branch_survives || fail "cleanup deleted the branch without knowing whether a PR depends on it"
}

test_cleanup_refuses_a_dirty_worktree() {
  cleanup_setup pr-merged
  printf 'changed\n' >>"$WT/README.md"
  run_script finish.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON dirty-tracked-files
  [ -d "$WT" ] || fail "a dirty worktree was removed"
  branch_survives || fail "the branch of a dirty worktree was deleted"
}

test_cleanup_reports_an_unregistered_leftover_dir_instead_of_deleting_it() {
  cleanup_setup pr-merged
  git -C "$REPO" worktree remove "$WT"
  mkdir -p "$WT"
  printf 'stale\n' >"$WT/leftover"
  run_script finish.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key_present "$OUT" LEFTOVER_DIR
  assert_key "$OUT" DELETED_LOCAL true
  [ -d "$WT" ] || fail "an unregistered directory must be reported, not deleted"
}

test_cleanup_keep_branch_removes_the_tree_and_touches_nothing_else() {
  cleanup_setup happy # PR still open: --keep-branch is exempt from the merged precondition
  run_script finish.sh cleanup 6 --branch feat/issue-6-x --keep-branch
  assert_rc 0
  assert_key "$OUT" REMOVED true
  [ ! -d "$WT" ] || fail "--keep-branch did not remove the worktree"
  branch_survives || fail "--keep-branch deleted the branch"
  assert_gh_not_called "pr list"
}

test_cleanup_in_place_deletes_the_checked_out_branch() {
  local repo
  repo=$(init_repo_with_remote)
  enter "$repo"
  git -C "$repo" switch -qc feat/issue-6-x main
  git -C "$repo" push -q -u origin feat/issue-6-x 2>/dev/null || true
  use_fake_gh pr-merged
  run_script finish.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" DELETED_LOCAL true
}

test_a_traversing_issue_token_deletes_nothing() {
  cleanup_setup pr-merged
  run_script finish.sh cleanup '6/../../../.git' --branch feat/issue-6-x
  assert_rc 4
  [ -d "$REPO/.git" ] || fail "a traversing issue token reached rm"
  branch_survives || fail "a rejected call still deleted the branch"
}

test_a_missing_branch_value_does_not_hang() {
  local rc
  timeout 15 bash "$ITP_SCRIPTS/finish.sh" merge 6 --branch >/dev/null 2>&1
  rc=$?
  [ "$rc" != 124 ] || fail "finish.sh hung on --branch with no value"
  assert_eq 4 "$rc" "should degrade, not hang"
}
