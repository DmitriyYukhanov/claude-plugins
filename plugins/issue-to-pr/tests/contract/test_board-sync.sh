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

test_board_create_card_ok() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo --create-card "Child A" --board-url https://github.com/users/octo/projects/3
  assert_rc 0
  assert_contains "$OUT" '"OK":"true"'
  assert_contains "$OUT" '"CARD_ID":"DRAFT_ITEM_ID"'
  assert_gh_called "addProjectV2DraftIssue"
}

test_board_create_card_needs_board_url() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo --create-card "Child A"
  assert_rc 0 # best-effort: never hard-stops
  assert_contains "$OUT" '"SKIPPED_REASON":"missing-board-url"'
}

test_board_create_card_api_failure_is_best_effort() {
  use_fake_gh create-card-fail
  run_script board-sync.sh octo-owner/demo-repo --create-card "Child A" --board-url https://github.com/users/octo/projects/3
  assert_rc 0
  assert_contains "$OUT" '"OK":"false"'
  assert_contains "$OUT" '"ERROR":"create-failed"'
}

test_board_convert_draft_ok() {
  use_fake_gh happy
  run_script board-sync.sh octo-owner/demo-repo --convert-draft PVTI_DRAFT_XYZ
  assert_rc 0
  assert_contains "$OUT" '"OK":"true"'
  assert_contains "$OUT" '"ISSUE_URL":"https://github.com/octo-owner/demo-repo/issues/99"'
  assert_gh_called "issue create"
}
