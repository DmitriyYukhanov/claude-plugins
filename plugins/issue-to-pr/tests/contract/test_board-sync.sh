#!/usr/bin/env bash
# Contract tests for scripts/board-sync.sh (spec §4.4). board-sync ALWAYS exits 0
# and always emits JSON.

test_board_missing_repo_exits_zero() {
  use_fake_gh happy
  run_script board-sync.sh
  assert_rc 0
  assert_contains "$OUT" '"OK":"false"'
  assert_contains "$OUT" '"SKIPPED_REASON":"missing-repo"'
}

test_board_missing_args() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo
  assert_rc 0
  assert_contains "$OUT" '"SKIPPED_REASON":"missing-args"'
}

test_board_scope_missing_hints() {
  use_fake_gh scope-missing
  run_script board-sync.sh octo-owner/demo-repo 6 in_progress
  assert_rc 0
  assert_contains "$OUT" '"SKIPPED_REASON":"missing-scope"'
  assert_contains "$OUT" 'gh auth refresh -s project'
}

test_board_not_member_skips() {
  use_fake_gh board-not-member
  run_script board-sync.sh octo-owner/demo-repo 6 in_progress
  assert_rc 0
  assert_contains "$OUT" '"SKIPPED_REASON":"not-a-member"'
}

test_board_happy_in_progress() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo 6 in_progress
  assert_rc 0
  assert_contains "$OUT" '"OK":"true"'
  assert_contains "$OUT" '"STATUS_SET":"in_progress"'
  assert_gh_called "updateProjectV2ItemFieldValue"
}

test_board_happy_in_review_alias() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo 6 in_review
  assert_rc 0
  assert_contains "$OUT" '"OK":"true"'
}

test_board_option_not_found() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo 6 blocked
  assert_rc 0
  assert_contains "$OUT" '"SKIPPED_REASON":"option-not-found"'
}

test_board_explicit_option_overrides_alias() {
  # 'blocked' matches no alias, but an explicit --option pins a real column.
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo 6 blocked --option "In Progress"
  assert_rc 0
  assert_contains "$OUT" '"OK":"true"'
}

test_board_mutation_failure_reports_and_exits_zero() {
  use_fake_gh board-mutation-fail
  run_script board-sync.sh octo-owner/demo-repo 6 in_progress
  assert_rc 0
  assert_contains "$OUT" '"OK":"false"'
  assert_contains "$OUT" '"ERROR":"mutation-failed"'
}

test_board_create_card_mode_deferred() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo --create-card "New card title"
  assert_rc 0
  assert_contains "$OUT" '"SKIPPED_REASON":"mode-deferred"'
}
