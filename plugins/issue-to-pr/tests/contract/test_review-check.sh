#!/usr/bin/env bash
# Contract tests for scripts/review-check.sh (spec sec 6.4).

test_review_clear() {
  use_fake_gh happy
  run_script review-check.sh feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REVIEW_STATE clear
  assert_key "$OUT" READ_OK true
}

test_review_changes_requested() {
  use_fake_gh review-changes-requested
  run_script review-check.sh feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REVIEW_STATE changes_requested
}

test_review_unresolved_threads() {
  use_fake_gh review-unresolved
  run_script review-check.sh feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REVIEW_STATE unresolved_threads
  assert_key "$OUT" UNRESOLVED_THREADS 2
}

test_review_read_failure_is_clear_best_effort() {
  use_fake_gh review-read-fail
  run_script review-check.sh feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REVIEW_STATE clear
  assert_key "$OUT" READ_OK false
}

test_review_missing_branch_degrades() {
  use_fake_gh happy
  run_script review-check.sh
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-branch
}

test_review_json_mode() {
  use_fake_gh review-changes-requested
  OUT=$(bash "$ITP_SCRIPTS/review-check.sh" feat/issue-6-x --json 2>/dev/null)
  assert_contains "$OUT" '"REVIEW_STATE":"changes_requested"'
}
