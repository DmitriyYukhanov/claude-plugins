#!/usr/bin/env bash

gates_repo() { # cwd moves into a fresh repo checked out on feat/issue-6-x
  REPO=$(init_repo "$TEST_TMPDIR/gr")
  git -C "$REPO" switch -qc feat/issue-6-x
  cd "$REPO" || fail "could not enter the test repo"
}

test_gates_all_pass() {
  gates_repo
  run_script run-gates.sh --gate 'typecheck=true' --gate 'test=true'
  assert_rc 0
  assert_key "$OUT" GATE_TYPECHECK_EXIT 0
  assert_key "$OUT" GATE_TEST_EXIT 0
  assert_key "$OUT" GATES_OK true
  assert_key "$OUT" GATES_RUN 2
}

test_gates_fail_fast_stops_at_first_failure() {
  gates_repo
  run_script run-gates.sh --gate 'boom=exit 7' --gate 'never=true'
  assert_rc 7
  assert_key "$OUT" GATE_BOOM_EXIT 7
  assert_key "$OUT" GATES_OK false
  assert_key "$OUT" GATES_RUN 1
  assert_not_contains "$OUT" "GATE_NEVER_EXIT"
}

test_gates_failing_tail_on_stderr() {
  gates_repo
  run_script run-gates.sh --gate 'boom=echo boomtext; exit 1'
  assert_rc 1
  assert_contains "$ERR" "boomtext"
  assert_contains "$ERR" "failed"
}

test_gates_a_split_gate_value_degrades_instead_of_running_a_truncated_command() {
  gates_repo
  # what a quote inside a config command does to an inline --gate: the wrapper closes early and
  # the rest of the command arrives as separate arguments.
  run_script run-gates.sh --gate 'test=npm run check' 'unit"'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON unknown-argument
  assert_not_contains "$OUT" "GATE_TEST_EXIT" \
    "the truncated command must not run: dropping the split-off words is how a gate reports green
    on half a command"
}

test_gates_no_gates_degrades() {
  gates_repo
  run_script run-gates.sh
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON no-gates
}

test_gates_empty_command_degrades_not_green() {
  gates_repo
  run_script run-gates.sh --gate 'typecheck='
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON empty-gate-command
}

test_gates_key_naming_normalizes_hyphen() {
  gates_repo
  run_script run-gates.sh --gate 'type-check=true'
  assert_rc 0
  assert_key "$OUT" GATE_TYPE_CHECK_EXIT 0
}

test_gates_log_lands_in_the_run_directory_under_an_ignored_state_dir() {
  gates_repo
  run_script run-gates.sh --gate 'hello=echo hi-there; exit 1'
  assert_rc 1
  assert_contains "$(cat "$(run_dir_of "$REPO" feat/issue-6-x)"/logs/hello-*.log 2>/dev/null)" "hi-there"
  assert_contains "$(cat "$REPO/.claude/issue-to-pr/.gitignore" 2>/dev/null)" '*'     "run-gates is the first writer of the state directory on the in-place fallback, where no
    worktree ensure ran, and an unignored one puts every gate log into git status"
}

test_gates_green_leaves_a_receipt_for_this_head() {
  local head
  gates_repo
  run_script run-gates.sh --gate 'test=true'
  assert_rc 0
  head=$(git -C "$REPO" rev-parse HEAD)
  assert_key "$OUT" GATES_RECEIPT "$head"
  assert_contains "$(cat "$(receipt_file "$REPO" feat/issue-6-x)")" "$head"
}

test_gates_red_leaves_no_receipt() {
  gates_repo
  run_script run-gates.sh --gate 'test=false'
  assert_rc 1
  if [ -e "$(receipt_file "$REPO" feat/issue-6-x)" ]; then
    fail "a failing suite left a receipt"
  fi
}

test_gates_outside_a_repo_degrades() {
  mkdir -p "$TEST_TMPDIR/norepo-gates"
  cd "$TEST_TMPDIR/norepo-gates" || fail "could not enter the temp dir"
  run_script run-gates.sh --gate 'test=true'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON not-a-git-repo
}

test_gates_unwritable_state_dir_degrades_before_running_anything() {
  gates_repo
  mkdir -p "$REPO/.claude"
  printf 'blocking file\n' >"$REPO/.claude/issue-to-pr"
  run_script run-gates.sh --gate 'test=true'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON log-dir-unwritable
  assert_not_contains "$OUT" "GATE_TEST_EXIT"
}

test_gates_two_names_that_key_alike_degrade_rather_than_report_over_each_other() {
  gates_repo
  run_script run-gates.sh --gate 'type-check=true' --gate 'type check=false'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON duplicate-gate
  assert_not_contains "$OUT" GATE_TYPE_CHECK_EXIT \
    "both names key to GATE_TYPE_CHECK_EXIT: emitting it twice leaves a reader of the first
    occurrence looking at the passing gate while the failing one is invisible"
}

test_gates_a_single_quoted_value_degrades_instead_of_running_nothing() {
  gates_repo
  # shellcheck disable=SC2016  # not expanding is the whole point: this is the caller's mistake
  run_script run-gates.sh --gate 'test=$t'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON unexpanded-gate-command
  assert_not_contains "$OUT" GATES_OK \
    "the literal text \$t survives word-splitting whole, so the unknown-argument guard never sees
    it; bash -c on it expands to nothing and exits 0, which is a green gate over no command and a
    receipt the merge would accept"
}

test_gates_a_command_substitution_is_still_allowed_through() {
  gates_repo
  # shellcheck disable=SC2016  # deferring the substitution to the gate runner is deliberate here
  run_script run-gates.sh --gate 'probe=$(printf true) && true'
  assert_rc 0
  assert_key "$OUT" GATE_PROBE_EXIT 0 \
    "a value the caller single-quoted on purpose to defer a substitution is not the mistake the
    literal-dollar guard is looking for"
}

test_gates_a_detached_head_degrades_rather_than_keying_a_receipt_to_HEAD() {
  gates_repo
  git -C "$REPO" checkout -q --detach
  run_script run-gates.sh --gate 'test=true'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON detached-head
  if [ -e "$(run_dir_of "$REPO" HEAD)" ]; then
    fail "a detached checkout wrote branch-HEAD/, which the merge looks for under the real branch
    name, so re-running the gates can never satisfy it"
  fi
}

test_gates_say_so_when_the_receipt_cannot_be_written() {
  gates_repo
  mkdir -p "$(receipt_file "$REPO" feat/issue-6-x)"
  run_script run-gates.sh --gate 'test=true'
  assert_rc 0
  assert_key "$OUT" GATES_OK true
  assert_not_contains "$OUT" GATES_RECEIPT
  assert_contains "$ERR" "the merge will refuse this head" \
    "green gates and no receipt is exactly what the merge refuses; saying nothing leaves the model
    reporting a pass and the merge stopping with no line connecting the two"
}

test_gates_a_single_quoted_positional_degrades_too() {
  gates_repo
  # shellcheck disable=SC2016  # not expanding is the caller's mistake this guard exists to catch
  run_script run-gates.sh --gate 'test=$1'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON unexpanded-gate-command \
    "a positional or special parameter expands to nothing under bash -c just as a named one does"
}
