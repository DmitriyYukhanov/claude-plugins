#!/usr/bin/env bash

mk_repo() { init_repo_with_remote; }

mk_worktree() { # repo branch -> worktree path at repo-worktrees/issue-6, pushed
  local repo=$1 branch=$2 wt="$TEST_TMPDIR/repo-worktrees/issue-6"
  git -C "$repo" worktree add "$wt" -b "$branch" main >/dev/null 2>&1
  printf 'work\n' >"$wt/work.txt"
  git -C "$wt" add work.txt
  git -C "$wt" commit -qm work
  git -C "$wt" push -q -u origin "$branch" 2>/dev/null || true
  printf '%s' "$wt"
}

SHA_OK="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

test_wt_ensure_creates() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-new --start-point main
  assert_rc 0
  assert_key "$OUT" STATE CREATED
  assert_key "$OUT" BRANCH feat/issue-6-new
  assert_key_present "$OUT" WT_PATH
}

test_wt_ensure_reattaches_existing_branch() {
  local repo; repo=$(mk_repo); cd "$repo"
  git -C "$repo" branch feat/issue-6-x main
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 0
  assert_key "$OUT" STATE REATTACHED
}

test_wt_ensure_resumes() {
  local repo; repo=$(mk_repo); mk_worktree "$repo" feat/issue-6-x >/dev/null; cd "$repo"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 0
  assert_key "$OUT" STATE RESUMED
  assert_key "$OUT" PR_STATE none
}

test_wt_ensure_resume_pr_merged_stops() {
  local repo; repo=$(mk_repo); mk_worktree "$repo" feat/issue-6-x >/dev/null; cd "$repo"
  use_fake_gh pr-merged
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 2
  assert_key "$OUT" STOP_REASON pr-already-merged
}

test_wt_ensure_detached_is_bad_checkout() {
  local repo; repo=$(mk_repo); cd "$repo"
  git worktree add --detach "$TEST_TMPDIR/repo-worktrees/issue-6" main >/dev/null 2>&1
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 2
  assert_key "$OUT" STOP_REASON bad-checkout-state
}

test_wt_ensure_stale_unregistered_dir_stops() {
  local repo; repo=$(mk_repo); cd "$repo"
  mkdir -p "$TEST_TMPDIR/repo-worktrees/issue-6"
  printf 'x\n' >"$TEST_TMPDIR/repo-worktrees/issue-6/leftover"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 2
  assert_key "$OUT" STOP_REASON stale-unregistered-dir
}

test_wt_ensure_invalid_start_point_stops() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point no-such-ref
  assert_rc 2
  assert_key "$OUT" STOP_REASON invalid-start-point
}

test_wt_merge_happy_path() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD squash
  assert_gh_called "pr merge feat/issue-6-x --squash --match-head-commit"
}

test_wt_merge_reports_a_non_default_base() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh stacked-base
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGED_INTO feat/issue-5-parent
  assert_key "$OUT" BASE_IS_DEFAULT false
  assert_contains "$OUT" "WARN_NON_DEFAULT_BASE"
}

test_wt_merge_into_the_default_base_says_so() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_key "$OUT" BASE_IS_DEFAULT true
  assert_not_contains "$OUT" "WARN_NON_DEFAULT_BASE"
}

test_wt_merge_unknown_base_when_the_default_branch_is_unreadable() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh default-branch-unreadable
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" BASE_IS_DEFAULT unknown
}

test_wt_cleanup_refuses_a_branch_an_open_pr_is_based_on() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh has-dependent-pr
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON base-of-open-pr
  if ! git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "cleanup deleted a branch an open PR is based on"
  fi
}

test_wt_cleanup_stops_when_the_dependents_list_cannot_be_read() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh dependents-unreadable
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON dependents-unreadable
  if ! git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "cleanup deleted the branch after failing to read whether a PR depends on it"
  fi
}

test_wt_merge_squash_disallowed_falls_back_to_merge() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh squash-disallowed
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD merge
}

test_wt_merge_rebase_only_fallback() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh rebase-only
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD rebase
}

test_wt_missing_branch_value_does_not_hang() {
  local out rc
  out=$(timeout 15 bash "$ITP_SCRIPTS/worktree.sh" merge 6 --branch 2>/dev/null)
  rc=$?
  if [ "$rc" = 124 ]; then fail "worktree.sh hung on --branch with no value"; fi
  assert_eq 4 "$rc" "should degrade (missing-branch), not hang"
}

test_wt_merge_pending_checks_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh pending-checks
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON checks-pending
}

test_wt_merge_push_rejected_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  git -C "$wt" remote set-url origin "$TEST_TMPDIR/does-not-exist.git"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON push-rejected
}

test_wt_cleanup_pr_not_merged_stops() {
  local repo; repo=$(mk_repo); mk_worktree "$repo" feat/issue-6-x >/dev/null; cd "$repo"
  use_fake_gh pr-open
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON pr-not-merged
}

test_wt_cleanup_happy_removes_and_deletes() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REMOVED true
  assert_key "$OUT" DELETED_LOCAL true
  assert_key "$OUT" DELETED_REMOTE true
  if [ -d "$wt" ]; then fail "worktree dir still exists after cleanup"; fi
  if git -C "$repo" ls-remote --exit-code --heads origin feat/issue-6-x >/dev/null 2>&1; then
    fail "the remote branch survived cleanup"
  fi
}

test_wt_cleanup_dirty_tracked_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  printf 'changed\n' >>"$wt/README.md" # tracked modification
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON dirty-tracked-files
}

test_wt_cleanup_resolves_pr_number_to_the_branch() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch 13
  assert_rc 0
  assert_key "$OUT" DELETED_LOCAL true
  if git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "cleanup by PR number left the merged branch behind"
  fi
}

test_wt_cleanup_in_place_deletes_checked_out_branch() {
  local repo; repo=$(mk_repo); cd "$repo"
  git -C "$repo" switch -c feat/issue-6-x main >/dev/null 2>&1
  git -C "$repo" push -q -u origin feat/issue-6-x 2>/dev/null || true
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" DELETED_LOCAL true
  if git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "in-place cleanup did not delete the checked-out branch"
  fi
}

test_wt_cleanup_reports_unregistered_leftover_dir() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  git -C "$repo" worktree remove "$wt"
  mkdir -p "$wt"
  printf 'stale\n' >"$wt/leftover"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key_present "$OUT" LEFTOVER_DIR
  assert_contains "$OUT" "issue-6"
  assert_key "$OUT" DELETED_LOCAL true # branch cleanup still runs
  if [ ! -d "$wt" ]; then fail "unregistered dir must be reported, not deleted"; fi
}

test_wt_cleanup_keep_branch_removes_the_tree_and_keeps_the_branch() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh happy # PR is OPEN: --keep-branch is exempt from the merged precondition
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x --keep-branch
  assert_rc 0
  assert_key "$OUT" REMOVED true
  assert_key "$OUT" KEPT branch-and-pr
  if ! git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "--keep-branch must not delete the branch"
  fi
  assert_gh_not_called "pr list"
}


test_wt_merge_ladder_exhausted_caps_before_anything() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x --ladder-attempt 4
  assert_rc 2
  assert_key "$OUT" STOP_REASON merge-ladder-exhausted
  assert_gh_not_called "pr" # the cap must fire before ANY GitHub interaction
}

test_wt_merge_checks_failed_stops_before_merge() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh checks-failing
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON checks-failed
  assert_key_present "$OUT" FAILING_CHECKS
  assert_gh_not_called "pr merge" # a doomed check must never blind-merge
}

test_wt_merge_conflict_stops_without_update() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh merge-conflict-state
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON merge-conflict
  assert_gh_not_called "pr update-branch"
  assert_gh_not_called "pr merge"
}

test_wt_merge_update_branch_failure_is_distinct() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh behind-update-fail
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON update-branch-failed
  assert_gh_called "pr update-branch"
  assert_gh_not_called "pr merge"
}

test_wt_merge_behind_clean_asks_for_gates() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  printf 'unrelated\n' >"$repo/unrelated.txt"
  git -C "$repo" add unrelated.txt
  git -C "$repo" commit -qm base-advance
  git -C "$repo" push -q origin main
  use_fake_gh behind-clean
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" LADDER_STEP base-merged-clean
  assert_key "$OUT" STOP_REASON gates-unverified
  assert_gh_called "pr update-branch"
  assert_gh_not_called "pr merge" "merged a head no receipt covers"
  assert_contains "$(cat "$ITP_SCRIPTS/worktree.sh")" 'diff "$base...$old"'     'is_pure_base_merge must compare the PR diff with three dots. A two-dot `git diff OLD NEW`
    also lists every unrelated file the base carried forward, so it rejects this clean case;
    reordered, it approves a base merge that changed the PR own diff. Do not simplify the dots away.'
}

test_wt_merge_behind_unverified_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh behind-noadvance
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON base-update-unverified
  assert_gh_called "pr update-branch"
  assert_gh_not_called "pr merge"
}

test_wt_merge_behind_content_changed_needs_reapproval() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  printf 'unrelated\n' >"$repo/unrelated.txt"
  git -C "$repo" add unrelated.txt
  git -C "$repo" commit -qm base-advance
  git -C "$repo" push -q origin main
  use_fake_gh behind-content
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON content-changed-needs-reapproval
  assert_gh_not_called "pr merge"
}

test_wt_merge_clean_passes_precheck() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_gh_not_called "pr update-branch" "a CLEAN read must not take the behind-base branch"
}

test_wt_no_subcommand_degrades() {
  local repo; repo=$(mk_repo); cd "$repo"
  run_script worktree.sh
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-subcommand
}

test_wt_unknown_subcommand_degrades() {
  local repo; repo=$(mk_repo); cd "$repo"
  run_script worktree.sh frobnicate 6 --branch feat/issue-6-x
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON unknown-subcommand
}

test_wt_ensure_without_a_start_point_degrades() {
  local repo; repo=$(mk_repo); cd "$repo"
  run_script worktree.sh ensure 6 --branch feat/issue-6-x
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-start-point
}

test_wt_outside_a_repository_degrades() {
  mkdir -p "$TEST_TMPDIR/bare-ground"
  cd "$TEST_TMPDIR/bare-ground"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON not-a-git-repo
}

test_wt_merge_unrecognised_gh_failure_stops_and_reports_it() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh protected
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON merge-failed
  assert_contains "$OUT" "Protected branch update failed"
  assert_not_contains "$OUT" "MERGED=true"
}

test_wt_ensure_unclassified_add_failure_stops() {
  local repo; repo=$(mk_repo); cd "$repo"
  printf 'not a directory
' > "$(dirname "$repo")/$(basename "$repo")-worktrees"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 2
  assert_key "$OUT" STOP_REASON worktree-add-failed
  assert_key_present "$OUT" ADD_ERROR
}

test_wt_non_numeric_issue_degrades_before_any_path_is_built() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh cleanup '6/../../../.git' --branch feat/issue-6-x
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON invalid-issue
  if [ ! -d "$repo/.git" ]; then fail "the guard let a traversing issue token delete .git"; fi
}

test_wt_merge_without_a_receipt_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON gates-unverified
  assert_gh_not_called "pr merge" "merged with no gate receipt"
}

test_wt_merge_with_a_receipt_for_another_head_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_receipt "$repo" feat/issue-6-x bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON gates-unverified
}

test_wt_merge_stops_on_a_changes_requested_review() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  use_fake_gh review-changes-requested
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON review-blocked
  assert_gh_not_called "pr merge" "merged over a requested change"
}

test_wt_merge_stops_when_the_review_cannot_be_read() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  use_fake_gh review-read-fail
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON review-unreadable
  assert_gh_not_called "pr merge" "merged on an unread review"
}

test_wt_merge_unreadable_head_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  use_fake_gh head-empty
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON pr-head-unreadable
  assert_gh_not_called "pr merge" "merged without knowing the head"
}

test_wt_cleanup_prunes_the_gate_receipt() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  if [ -e "$repo/.claude/issue-to-pr/gates-feat-issue-6-x.json" ]; then
    fail "cleanup left the gate receipt behind"
  fi
}
