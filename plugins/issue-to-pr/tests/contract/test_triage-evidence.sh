#!/usr/bin/env bash
# Contract tests for scripts/triage-evidence.sh (spec §4.6).

test_triage_missing_issue_degrades() {
  use_fake_gh happy
  run_script triage-evidence.sh
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-issue
}

test_triage_unreachable_issue_degrades() {
  use_fake_gh issue-unreachable
  run_script triage-evidence.sh 6
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON issue-unreachable
}

test_triage_rich_signals() {
  use_fake_gh triage-rich
  mkdir -p src
  : >src/app.ts # referenced path that exists; docs/missing-file.md does not
  run_script triage-evidence.sh 6
  assert_rc 0
  assert_key "$OUT" LABELS "bug,security"
  assert_key "$OUT" CHECKLIST_ITEMS 2
  assert_key "$OUT" REF_PATHS_EXIST 1
  assert_key "$OUT" REF_PATHS_MISSING 1
  assert_key "$OUT" NEW_THING_HITS 4
  assert_key "$OUT" LINKED_ISSUES 2
  assert_key "$OUT" TITLE "Create a new widget service"
}

test_triage_default_no_labels_no_checklist() {
  use_fake_gh happy # default body references src/app.ts, no checklist, no labels
  run_script triage-evidence.sh 6
  assert_rc 0
  assert_key "$OUT" LABELS ""
  assert_key "$OUT" CHECKLIST_ITEMS 0
  assert_key "$OUT" REF_PATHS_MISSING 1
  assert_key "$OUT" REF_PATHS_EXIST 0
}

test_triage_json_output() {
  use_fake_gh triage-rich
  run_script triage-evidence.sh 6 --json
  assert_rc 0
  assert_contains "$OUT" '"CHECKLIST_ITEMS":"2"'
  assert_contains "$OUT" '"LINKED_ISSUES":"2"'
}
