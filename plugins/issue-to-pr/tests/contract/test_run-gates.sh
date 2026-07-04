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

test_gates_json_output() {
  run_script run-gates.sh --json --log-dir "$TEST_TMPDIR/logs" --gate 'ok=true'
  assert_rc 0
  assert_contains "$OUT" '"GATE_OK_EXIT":"0"'
  assert_contains "$OUT" '"GATES_OK":"true"'
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
