#!/usr/bin/env bash
# Contract tests for dispatch.sh. Fixtures: a fake gh serving files from $FIX, fake claude and
# codex acting out FAKE_CLI_MODE, and a test clock (date, sleep) so four hours pass in seconds.
# shellcheck disable=SC2034,SC2088,SC2153
# SC2034: OUT/ERR/RC are read by assert_rc() in the sourced assert.sh, a file shellcheck does not
# follow from here. SC2088: the log path assertion shows a literal `~`, on purpose. SC2153: a
# sourced dispatch.sh's own $LOCK, misread as a typo of another test's unrelated local $lock.

setup_env() { # [host] -> HOME, $FIX, PATH with the fakes, one configured repo octo/widgets
  export HOME="$TEST_TMPDIR/home" FIX="$TEST_TMPDIR/fix"
  mkdir -p "$HOME/.agent-dispatch" "$FIX" "$TEST_TMPDIR/checkout"
  REAL_SLEEP=$(command -v sleep)
  export REAL_SLEEP
  export PATH="$AD_FIXTURES/bin:$AD_FIXTURES/fake-gh:$AD_FIXTURES/fake-cli:$PATH"
  export FAKE_GH_FIX="$FIX" FAKE_CLI_LOG="$FIX/cli.log" FAKE_CLOCK="$FIX/clock"
  printf '1000\n' >"$FAKE_CLOCK"
  printf 'octo\n' >"$FIX/user"
  printf 'octo/widgets\n' >"$FIX/repo"
  printf '# path | host | auto-merge\n%s | %s | trivial\n' "$TEST_TMPDIR/checkout" "${1:-claude}" \
    >"$HOME/.agent-dispatch/repos.conf"
}

assert_gh_called_with() { assert_contains "$(cat "$FIX/gh.log" 2>/dev/null)" "gh $1" "gh was not called with: $1"; }
on_windows_host() { case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) return 0 ;; esac; return 1; }

dispatch() { # -> OUT ERR RC
  OUT=$("$BASH" "$AD_SCRIPTS/dispatch.sh" 2>"$TEST_TMPDIR/.err")
  RC=$?
  ERR=$(cat "$TEST_TMPDIR/.err")
}

open_issue() { # n labels,csv [actor] -> an open issue, its labels, and who last labelled it agent
  printf '%s\t%s\n' "$1" "$2" >>"$FIX/issues"
  printf '%s\n' "$2" | tr ',' '\n' >"$FIX/labels-$1"
  printf '%s\n' "${3:-octo}" >"$FIX/events-$1"
}

comment() { # n id login [marker] -> one projected comment on thread n
  printf '%s\t%s\t%s\n' "$2" "$3" "${4:-}" >>"$FIX/comments-$1"
}

cli_log() { cat "$FIX/cli.log" 2>/dev/null; }

test_marker_is_issue_to_prs_copy() {
  cmp "$AD_SCRIPTS/marker.sh" "$AD_SCRIPTS/../../issue-to-pr/scripts/lib/marker.sh" ||
    fail "agent-dispatch's marker.sh has drifted from issue-to-pr's copy"
}

test_queue_launches_the_oldest_issue_the_owner_labelled() {
  setup_env
  open_issue 9 agent
  open_issue 4 agent
  export FAKE_CLI_MODE=flip:agent:review
  dispatch
  assert_rc 0
  assert_key "$OUT" ISSUE "octo/widgets#4"
  assert_key "$OUT" PICK queue
  assert_key "$OUT" TICK "done"
  assert_key "$OUT" OUTCOME agent:review
  assert_eq "claude -p --dangerously-skip-permissions --output-format stream-json --verbose /issue-to-pr:run 4 --headless --auto-merge trivial" \
    "$(cli_log)"
  assert_gh_called_with "issue edit 4 -R octo/widgets --add-label agent:running --remove-label agent,agent:waiting,agent:review,agent:failed"
  [ -e "$FIX/posted-4" ] && fail "a run that parked itself needs no dispatcher comment"
  [ -d "$HOME/.agent-dispatch/lock" ] && fail "the lock outlived the run"
  if on_windows_host; then assert_key "$OUT" LAUNCHER job; else assert_key "$OUT" LAUNCHER group; fi
}

test_an_agent_label_someone_else_applied_is_skipped() {
  setup_env
  open_issue 4 agent mallory
  printf 'octo\nmallory\n' >"$FIX/events-4"
  dispatch
  assert_key "$OUT" TICK idle
  [ -z "$(cli_log)" ] || fail "launched on a label the owner did not apply"
}

test_an_unverifiable_label_actor_is_skipped() {
  setup_env
  open_issue 4 agent
  : >"$FIX/fail-events-4"
  dispatch
  assert_key "$OUT" TICK idle
}

test_live_states_are_skipped_and_a_failed_retry_is_picked() {
  setup_env
  open_issue 3 agent,agent:running
  open_issue 5 agent,agent:waiting
  open_issue 6 agent,agent:review
  open_issue 8 agent,agent:failed
  export FAKE_CLI_MODE=flip:agent:review
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#8"
  assert_gh_called_with "issue edit 8 -R octo/widgets --add-label agent:running --remove-label agent,agent:waiting,agent:review,agent:failed"
  assert_eq "agent:review" "$(cat "$FIX/labels-8")" "the start edit cleared agent and agent:failed"
}

test_an_owner_reply_on_the_issue_goes_before_the_queue() {
  setup_env
  open_issue 2 agent
  open_issue 7 agent:waiting
  comment 7 100 octo
  comment 7 101 octo '<!-- issue-to-pr state=waiting step=3 issue-read=100 -->'
  comment 7 102 octo
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#7"
  assert_key "$OUT" PICK reply
}

test_r1_a_four_column_row_with_an_empty_marker_is_a_plain_reply() {
  # Real MARKER_JQ output has 4 columns (id, login, marker, body). IFS=$'\t' read collapses the
  # marker/body tab pair on a plain reply, so this pins the parameter-expansion split instead.
  setup_env
  open_issue 7 agent:waiting
  comment 7 100 octo
  comment 7 101 octo '<!-- issue-to-pr state=waiting step=3 issue-read=100 -->'
  printf '%s\t%s\t\t%s\n' 102 octo 'looks good' >>"$FIX/comments-7"
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#7"
  assert_key "$OUT" PICK reply
}

test_an_owner_reply_on_the_pr_resumes_the_issue() {
  setup_env
  open_issue 7 agent:review
  comment 7 101 octo '<!-- issue-to-pr state=review step=7 tier=standard pr=12 head=abc issue-read=100 pr-read=200 -->'
  comment 12 200 octo
  comment 12 201 octo
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#7"
  assert_key "$OUT" PICK reply
}

test_read_marked_and_foreign_comments_are_not_replies() {
  setup_env
  open_issue 7 agent:waiting
  comment 7 100 octo
  comment 7 101 octo '<!-- issue-to-pr state=waiting issue-read=100 -->'
  comment 7 102 octo '<!-- issue-to-pr -->'
  comment 7 103 mallory
  dispatch
  assert_key "$OUT" TICK idle
}

test_a_reply_posted_while_the_run_was_parking_is_picked() {
  setup_env
  open_issue 7 agent:waiting
  comment 7 100 octo
  comment 7 102 octo
  comment 7 103 octo '<!-- issue-to-pr state=waiting issue-read=100 -->'
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#7"
}

test_replies_on_both_threads_start_one_run() {
  setup_env
  open_issue 7 agent:review
  comment 7 101 octo '<!-- issue-to-pr state=review pr=12 issue-read=100 pr-read=200 -->'
  comment 7 102 octo
  comment 12 201 octo
  dispatch
  assert_key "$OUT" TICK "done"
  assert_eq 1 "$(cli_log | grep -c .)" "one tick, one run"
}

test_a_state_comment_by_anyone_else_or_malformed_authorizes_nothing() {
  setup_env
  open_issue 7 agent:waiting
  comment 7 100 mallory '<!-- issue-to-pr state=waiting issue-read=1 -->'
  comment 7 101 octo '<!-- issue-to-pr state=bogus issue-read=1 -->'
  comment 7 102 octo '<!-- issue-to-pr state=waiting issue-read=x1 -->'
  comment 7 103 octo
  dispatch
  assert_key "$OUT" TICK idle
}

test_a_run_that_leaves_agent_running_is_failed_with_its_log_path() {
  setup_env
  open_issue 4 agent
  export FAKE_CLI_MODE=exit:0
  dispatch
  assert_rc 0
  assert_key "$OUT" OUTCOME agent:failed
  assert_contains "$(cat "$FIX/posted-4")" '<!-- issue-to-pr state=failed -->'
  assert_contains "$(cat "$FIX/posted-4")" '~/.agent-dispatch/logs/octo_widgets_4_20260101T000000Z.log'
  assert_eq "agent:failed" "$(cat "$FIX/labels-4")"
  [ -e "$HOME/.agent-dispatch/paused" ] && fail "a clean exit is not a CLI error"
  return 0
}

test_a_failed_run_carries_the_pr_from_a_prior_review_state() {
  # Amendment #2: reconcile reads the issue's own current state; if it names a PR, the failure
  # marker carries it too, so issue-to-pr's headless_guard can still find the run's PR.
  setup_env
  open_issue 4 agent
  comment 4 100 octo '<!-- issue-to-pr state=review step=7 tier=standard pr=12 head=abc issue-read=90 pr-read=91 -->'
  export FAKE_CLI_MODE=exit:0
  dispatch
  assert_rc 0
  assert_key "$OUT" OUTCOME agent:failed
  assert_contains "$(cat "$FIX/posted-4")" '<!-- issue-to-pr state=failed pr=12 -->'
}

test_a_cli_error_pauses_dispatching() {
  setup_env
  open_issue 4 agent
  export FAKE_CLI_MODE=exit:1
  dispatch
  assert_key "$OUT" PAUSED true
  [ -e "$HOME/.agent-dispatch/paused" ] || fail "paused was not created"
  assert_contains "$(cat "$FIX/posted-4")" "paused"
}

test_claude_reporting_an_error_with_exit_0_pauses_too() {
  setup_env
  open_issue 4 agent
  export FAKE_CLI_MODE=is-error
  dispatch
  assert_key "$OUT" RC 0
  assert_key "$OUT" PAUSED true
}

test_a_paused_tick_launches_nothing() {
  setup_env
  open_issue 4 agent
  : >"$HOME/.agent-dispatch/paused"
  dispatch
  assert_key "$OUT" TICK paused
  [ -z "$(cli_log)" ] || fail "launched while paused"
  assert_not_contains "$(cat "$FIX/gh.log" 2>/dev/null)" "issue edit"
}

test_a_failed_running_flip_launches_nothing() {
  setup_env
  open_issue 4 agent
  : >"$FIX/fail-edit"
  dispatch
  assert_rc 1
  assert_key "$OUT" REASON flip
  [ -z "$(cli_log)" ] || fail "launched without the running label"
  [ -d "$HOME/.agent-dispatch/lock" ] && fail "a failed flip must release the lock"
  return 0
}

test_a_malformed_config_line_stops_the_tick() {
  local line
  setup_env
  for line in "$TEST_TMPDIR/checkout | claude" "$TEST_TMPDIR/checkout | gpt | trivial" \
    "$TEST_TMPDIR/checkout | claude | yolo" "$TEST_TMPDIR/nowhere | claude | trivial" \
    "$TEST_TMPDIR/checkout | claude | trivial | extra"; do
    printf '# repos\n%s\n' "$line" >"$HOME/.agent-dispatch/repos.conf"
    dispatch
    assert_rc 1 "accepted: $line"
    assert_key "$OUT" REASON config
    assert_contains "$ERR" "$line"
  done
  printf '%s | claude | trivial\n' "$TEST_TMPDIR/checkout" >"$HOME/.agent-dispatch/repos.conf"
  : >"$FIX/fail-repo"
  dispatch
  assert_key "$OUT" REASON config "a checkout gh cannot name is a config error"
}

test_codex_runs_the_skill_through_exec_with_the_sandbox_bypassed() {
  setup_env codex
  open_issue 4 agent
  export FAKE_CLI_MODE=flip:agent:review
  dispatch
  assert_key "$OUT" TICK "done"
  assert_eq "codex exec --dangerously-bypass-approvals-and-sandbox --json -C $TEST_TMPDIR/checkout \$issue-to-pr:run 4 --headless --auto-merge trivial" \
    "$(cli_log)"
}

test_jq_projections_shape_the_tsv() {
  command -v jq >/dev/null 2>&1 || { printf 'jq not installed; skipped\n'; return 0; }
  # shellcheck source=../../scripts/dispatch.sh
  source "$AD_SCRIPTS/dispatch.sh"
  # A Windows jq writes CRLF line endings; dispatch.sh strips \r wherever it reads a jq TSV
  # (pick's own JQ_ISSUES read, and every row() split), so these comparisons do the same. The
  # literal \r\n inside a body is MARKER_JQ's own @tsv escaping of a real line break in the
  # comment, not the platform artifact, so it is untouched by the strip.
  assert_eq "$(printf '4\tagent,agent:failed')" \
    "$(printf '%s' '[{"number":4,"labels":[{"name":"agent"},{"name":"agent:failed"}]}]' | jq -r "$JQ_ISSUES" | tr -d '\r')"
  local bs="\\" tab=$'\t' nl=$'\n' expected
  expected="7${tab}octo${tab}<!-- issue-to-pr state=waiting issue-read=6 -->${tab}which one?${bs}r${bs}n${bs}r${bs}n<!-- issue-to-pr state=waiting issue-read=6 -->${nl}8${tab}octo${tab}${tab}mit"
  assert_eq "$expected" \
    "$(printf '%s' '[{"id":7,"user":{"login":"octo"},"body":"Which one?\r\n\r\n<!-- issue-to-pr state=waiting issue-read=6 -->"},{"id":8,"user":{"login":"octo"},"body":"MIT"}]' | jq -r "$MARKER_JQ" | tr -d '\r')"
  assert_eq "mallory" \
    "$(printf '%s' '[{"event":"labeled","label":{"name":"agent"},"actor":{"login":"mallory"}},{"event":"labeled","label":{"name":"bug"},"actor":{"login":"octo"}}]' | jq -r "$JQ_LABEL_ACTORS" | tr -d '\r')"
}

wait_for() { # file -> waits up to 20 s for it to be non-empty
  local _i=0
  while [ ! -s "$1" ] && [ "$_i" -lt 100 ]; do
    "$REAL_SLEEP" 0.2
    _i=$((_i + 1))
  done
  [ -s "$1" ] || fail "$1 never appeared"
}

dead_pid() { # -> a pid that has already exited
  local p
  "$BASH" -c 'exit 0' &
  p=$!
  wait "$p"
  printf '%s' "$p"
}

assert_dead() { # pid what
  local _i=0
  while kill -0 "$1" 2>/dev/null && [ "$_i" -lt 25 ]; do
    "$REAL_SLEEP" 0.2
    _i=$((_i + 1))
  done
  if kill -0 "$1" 2>/dev/null; then fail "$2 (pid $1) is still alive"; fi
}

test_the_deadline_stops_the_run_and_fails_it() {
  local leader child
  setup_env
  open_issue 4 agent
  export FAKE_CLI_MODE=hang FAKE_SLEEP_STEP=3600 FAKE_SLEEP_REAL=1
  dispatch
  assert_rc 0
  assert_key "$OUT" OUTCOME agent:failed
  assert_contains "$(cat "$FIX/posted-4")" "4-hour deadline"
  [ -e "$HOME/.agent-dispatch/paused" ] && fail "a deadline is not a CLI error"
  read -r leader child <"$FIX/hang.pids" || fail "the fake run never started"
  assert_dead "$child" "the run's gate"
  assert_dead "$leader" "the run"
}

test_a_live_ticks_lock_is_left_alone() {
  setup_env
  open_issue 4 agent
  mkdir -p "$HOME/.agent-dispatch/lock"
  printf '%s\n' "$$" >"$HOME/.agent-dispatch/lock/tick"
  dispatch
  assert_key "$OUT" TICK busy
  [ -f "$HOME/.agent-dispatch/lock/tick" ] || fail "a live tick's lock was touched"
  [ -z "$(cli_log)" ] || fail "launched next to a live tick"
}

test_a_dead_ticks_lock_without_a_run_is_reconciled() {
  local lock
  setup_env
  lock="$HOME/.agent-dispatch/lock"
  open_issue 4 agent:running
  mkdir -p "$lock"
  printf 'octo/widgets\n' >"$lock/repo"
  printf '4\n' >"$lock/issue"
  dead_pid >"$lock/tick"
  printf '%s\n' "$HOME/.agent-dispatch/logs/octo_widgets_4_20260101T000000Z.log" >"$lock/log"
  : >"$FIX/issues"
  dispatch
  assert_rc 0
  assert_key "$OUT" RECOVERED "octo/widgets#4"
  assert_key "$OUT" TICK idle
  assert_contains "$(cat "$FIX/posted-4")" "stopped before the run finished"
  [ -d "$lock" ] && fail "the recovered lock was kept"
  return 0
}

test_a_dead_ticks_run_is_stopped_and_reconciled() {
  local leader child
  setup_env
  open_issue 4 agent:running
  export FAKE_CLI_MODE=hang
  (
    # shellcheck source=../../scripts/dispatch.sh
    source "$AD_SCRIPTS/dispatch.sh"
    mkdir -p "$LOCK" "$AD_HOME/logs"
    printf 'octo/widgets\n' >"$LOCK/repo"
    printf '4\n' >"$LOCK/issue"
    dead_pid >"$LOCK/tick"
    printf '%s\n' "$AD_HOME/logs/run.log" >"$LOCK/log"
    write_run_script "$TEST_TMPDIR/checkout" claude 4 trivial "$AD_HOME/logs/run.log"
    launch >/dev/null
  )
  wait_for "$FIX/hang.pids"
  read -r leader child <"$FIX/hang.pids"
  dispatch
  assert_rc 0
  assert_key "$OUT" RECOVERED "octo/widgets#4"
  assert_dead "$child" "the dead tick's gate"
  assert_dead "$leader" "the dead tick's run"
  assert_eq "agent:failed" "$(cat "$FIX/labels-4")"
}

test_recovery_keeps_the_lock_while_github_is_unreachable() {
  local lock
  setup_env
  lock="$HOME/.agent-dispatch/lock"
  open_issue 4 agent:running
  mkdir -p "$lock"
  printf 'octo/widgets\n' >"$lock/repo"
  printf '4\n' >"$lock/issue"
  dead_pid >"$lock/tick"
  : >"$FIX/fail-labels-4"
  dispatch
  assert_rc 1
  assert_key "$OUT" REASON recover
  [ -d "$lock" ] || fail "the lock is the only record of the run; it must survive a failed reconcile"
}
