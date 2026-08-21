#!/usr/bin/env bash
# Contract tests for scripts/run-gates.sh (spec §4.3).

test_gates_all_pass() {
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'typecheck=true' --gate 'test=true'
  assert_rc 0
  assert_key "$OUT" GATE_TYPECHECK_EXIT 0
  assert_key "$OUT" GATE_TEST_EXIT 0
  assert_key "$OUT" GATES_OK true
  assert_key "$OUT" GATES_RUN 2
}

test_gates_fail_fast_stops_at_first_failure() {
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'boom=exit 7' --gate 'never=true'
  assert_rc 7
  assert_key "$OUT" GATE_BOOM_EXIT 7
  assert_key "$OUT" GATES_OK false
  assert_key "$OUT" GATES_RUN 1
  assert_not_contains "$OUT" "GATE_NEVER_EXIT"
}

test_gates_failing_tail_on_stderr() {
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'boom=echo boomtext; exit 1'
  assert_rc 1
  assert_contains "$ERR" "boomtext"
  assert_contains "$ERR" "failed"
}

test_gates_missing_log_dir_degrades() {
  run_script run-gates.sh --gate 'x=true'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-log-dir
}

test_gates_no_gates_degrades() {
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs"
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON no-gates
}

test_gates_empty_command_degrades_not_green() {
  # An unresolved '<test_cmd>' must not pass as green via `bash -c ""`.
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'typecheck='
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON empty-gate-command
}

test_gates_key_naming_normalizes_hyphen() {
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'type-check=true'
  assert_rc 0
  assert_key "$OUT" GATE_TYPE_CHECK_EXIT 0
}

test_gates_log_file_written() {
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'hello=echo hi-there'
  assert_rc 0
  local content
  content=$(cat "$TEST_TMPDIR"/logs/hello-*.log 2>/dev/null)
  assert_contains "$content" "hi-there"
}

# 2.11.0: a green run leaves the receipt worktree.sh merge checks. Bound to the HEAD
# it ran against, because the only question at the merge is whether the gates saw the
# content being merged.
test_gates_green_leaves_a_receipt_for_this_head() {
  local repo head
  repo=$(init_repo "$TEST_TMPDIR/gr")
  git -C "$repo" switch -qc feat/issue-6-x
  cd "$repo" || fail "cd failed"
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'test=true'
  assert_rc 0
  head=$(git -C "$repo" rev-parse HEAD)
  assert_key "$OUT" GATES_RECEIPT "$head"
  assert_contains "$(cat "$repo/.claude/issue-to-pr/gates-feat-issue-6-x.json")" "$head"
}

test_gates_red_leaves_no_receipt() {
  local repo
  repo=$(init_repo "$TEST_TMPDIR/gr-red")
  git -C "$repo" switch -qc feat/issue-6-x
  cd "$repo" || fail "cd failed"
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'test=false'
  assert_rc 1
  if [ -e "$repo/.claude/issue-to-pr/gates-feat-issue-6-x.json" ]; then
    fail "a failing suite left a receipt"
  fi
}

# run-gates.sh is useful outside a checkout too, and a receipt it cannot write is not
# a reason to redden a green suite. The merge is where the absence is felt.
test_gates_outside_a_repo_still_pass() {
  mkdir -p "$TEST_TMPDIR/norepo-gates"
  cd "$TEST_TMPDIR/norepo-gates" || fail "cd failed"
  run_script run-gates.sh --log-dir "$TEST_TMPDIR/logs" --gate 'test=true'
  assert_rc 0
  assert_key "$OUT" GATES_OK true
}

