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

open_issue() { # n labels,csv [actor] -> an open issue, its labels, and who last applied the
  # label pick() cares about here: agent:waiting or agent:review if the issue carries one
  # (the reply path checks that one), else agent (the queue path's own check).
  local lbl
  printf '%s\t%s\n' "$1" "$2" >>"$FIX/issues"
  printf '%s\n' "$2" | tr ',' '\n' >"$FIX/labels-$1"
  case ",$2," in
    *,agent:waiting,*) lbl=agent:waiting ;;
    *,agent:review,*) lbl=agent:review ;;
    *) lbl=agent ;;
  esac
  printf '%s\t%s\n' "$lbl" "${3:-octo}" >"$FIX/events-$1"
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
  printf 'agent\tocto\nagent\tmallory\n' >"$FIX/events-4"
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

test_a_reply_on_a_parked_label_someone_else_applied_is_skipped() {
  setup_env
  open_issue 7 agent:waiting
  printf 'agent:waiting\tmallory\n' >"$FIX/events-7"
  comment 7 100 octo
  comment 7 101 octo '<!-- issue-to-pr state=waiting issue-read=100 -->'
  comment 7 102 octo
  dispatch
  assert_key "$OUT" TICK idle
  [ -z "$(cli_log)" ] || fail "launched on a parked label a stranger applied, despite a valid owner reply"
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
  # The events projection keeps every agent* label application (owner_approved picks the ones it
  # needs) and every rename, and nothing else; a rename has no label.
  assert_eq "$(printf 'labeled\tagent\tmallory\t2026-09-26T09:00:00Z\nlabeled\tagent:waiting\tocto\t2026-09-26T09:20:00Z\nrenamed\t\tocto\t2026-09-26T09:30:00Z')" \
    "$(printf '%s' '[{"event":"labeled","label":{"name":"agent"},"actor":{"login":"mallory"},"created_at":"2026-09-26T09:00:00Z"},{"event":"labeled","label":{"name":"bug"},"actor":{"login":"octo"},"created_at":"2026-09-26T09:10:00Z"},{"event":"labeled","label":{"name":"agent:waiting"},"actor":{"login":"octo"},"created_at":"2026-09-26T09:20:00Z"},{"event":"unlabeled","label":{"name":"agent"},"actor":{"login":"octo"},"created_at":"2026-09-26T09:25:00Z"},{"event":"renamed","actor":{"login":"octo"},"created_at":"2026-09-26T09:30:00Z","rename":{"from":"a","to":"b"}}]' | jq -r "$JQ_LABEL_EVENTS" | tr -d '\r')"
  # GraphQL: a never-edited issue has a null lastEditedAt and editor; an edited one names both.
  assert_eq "$(printf '\t')" \
    "$(printf '%s' '{"data":{"repository":{"issue":{"lastEditedAt":null,"editor":null}}}}' | jq -r "$JQ_EDIT" | tr -d '\r')"
  assert_eq "$(printf '2026-09-26T11:00:00Z\tmallory')" \
    "$(printf '%s' '{"data":{"repository":{"issue":{"lastEditedAt":"2026-09-26T11:00:00Z","editor":{"login":"mallory"}}}}}' | jq -r "$JQ_EDIT" | tr -d '\r')"
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

kill_stray_run() { # safety net for a launching test: a broken stop must not strand the fake
  # CLI's real gate process (a 600s sleep) or, on Windows, the job.ps1 launcher, even when the
  # test itself fails. Chained with the runner's own EXIT trap, which this replaces.
  local leader='' child=''
  if [ -s "$FIX/hang.pids" ]; then read -r leader child <"$FIX/hang.pids"; fi
  [ -n "$leader" ] && kill -KILL "$leader" 2>/dev/null
  [ -n "$child" ] && kill -KILL "$child" 2>/dev/null
  if on_windows_host && [ -f "$HOME/.agent-dispatch/lock/run" ]; then
    taskkill //F //PID "$(cat "$HOME/.agent-dispatch/lock/run" 2>/dev/null)" >/dev/null 2>&1
  fi
  cd / 2>/dev/null
  rm -rf "$TEST_TMPDIR"
}

test_the_deadline_stops_the_run_and_fails_it() {
  local leader child start
  setup_env
  trap kill_stray_run EXIT
  open_issue 4 agent
  export FAKE_CLI_MODE=hang FAKE_SLEEP_STEP=3600 FAKE_SLEEP_REAL=1
  start=$SECONDS
  dispatch
  # SECONDS is bash's own real-time clock, untouched by the fake date/sleep fixtures: a stop that
  # does nothing would still "pass" once the real 600s sleep ends on its own, just 500x too slow.
  [ "$((SECONDS - start))" -lt 120 ] || fail "the tick took $((SECONDS - start))s; the stop did nothing and it waited out the real 600s sleep"
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
  trap kill_stray_run EXIT
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

test_a_failed_issue_listing_is_an_error_not_idle() {
  setup_env
  open_issue 4 agent
  : >"$FIX/fail-issues"
  dispatch
  assert_rc 1
  assert_key "$OUT" REASON github
  assert_key "$OUT" TICK error
  [ -z "$(cli_log)" ] || fail "launched without a listing"
}

# F1: an edit to the title or body by anyone but the owner, after the owner's latest application
# of the label that makes the issue eligible, holds it until the owner labels it again.
labelled_at() { # n label actor time -> the issue's event history holds only that application
  printf '%s\t%s\t%s\n' "$2" "$3" "$4" >"$FIX/events-$1"
}
body_edited() { # n time login -> GraphQL's lastEditedAt and editor for the issue
  printf '%s\t%s\n' "$2" "$3" >"$FIX/graphql-$1"
}

test_a_body_a_stranger_edited_after_the_label_is_skipped() {
  setup_env
  open_issue 4 agent
  labelled_at 4 agent octo 2026-09-26T10:00:00Z
  body_edited 4 2026-09-26T11:00:00Z mallory
  dispatch
  assert_key "$OUT" TICK idle
  [ -z "$(cli_log)" ] || fail "ran a body a stranger rewrote after the owner's label"
  assert_gh_called_with "api graphql"
}

test_a_body_the_owner_edited_after_the_label_is_picked() {
  setup_env
  open_issue 4 agent
  labelled_at 4 agent octo 2026-09-26T10:00:00Z
  body_edited 4 2026-09-26T11:00:00Z octo
  export FAKE_CLI_MODE=flip:agent:review
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#4"
}

test_a_title_a_stranger_renamed_after_the_label_is_skipped() {
  setup_env
  open_issue 4 agent
  printf 'agent\tocto\t2026-09-26T10:00:00Z\nrenamed\tmallory\t2026-09-26T11:00:00Z\n' >"$FIX/events-4"
  dispatch
  assert_key "$OUT" TICK idle
  [ -z "$(cli_log)" ] || fail "ran a title a stranger renamed after the owner's label"
}

test_edits_before_the_label_are_approved_by_it() {
  setup_env
  open_issue 4 agent
  printf 'agent\tocto\t2026-09-26T08:00:00Z\nrenamed\tmallory\t2026-09-26T09:00:00Z\nagent\tocto\t2026-09-26T10:00:00Z\n' \
    >"$FIX/events-4"
  body_edited 4 2026-09-26T09:30:00Z mallory
  export FAKE_CLI_MODE=flip:agent:review
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#4"
}

# The reply path's content approval is the owner's latest `agent` label, not the park the run itself
# applied: an edit by someone else after it, mid-run included, holds the issue.
reply_issue_7() { # a parked issue 7 with a pending owner reply
  open_issue 7 "$1"
  comment 7 100 octo
  comment 7 101 octo '<!-- issue-to-pr state=waiting issue-read=100 -->'
  comment 7 102 octo
}

test_a_reply_on_an_issue_a_stranger_edited_since_the_agent_label_is_skipped() {
  setup_env
  reply_issue_7 agent:waiting
  printf 'agent\tocto\t2026-09-26T08:00:00Z\nagent:waiting\tocto\t2026-09-26T10:00:00Z\n' >"$FIX/events-7"
  body_edited 7 2026-09-26T09:00:00Z mallory
  dispatch
  assert_key "$OUT" TICK idle "an edit while the run worked is not covered by its park"
  body_edited 7 2026-09-26T11:00:00Z mallory
  dispatch
  assert_key "$OUT" TICK idle
  rm "$FIX/graphql-7"
  printf 'agent\tocto\t2026-09-26T08:00:00Z\nrenamed\tmallory\t2026-09-26T09:00:00Z\nagent:waiting\tocto\t2026-09-26T10:00:00Z\n' \
    >"$FIX/events-7"
  dispatch
  assert_key "$OUT" TICK idle
  printf 'agent\tocto\t2026-09-26T08:00:00Z\nagent:waiting\tocto\t2026-09-26T10:00:00Z\n' >"$FIX/events-7"
  body_edited 7 2026-09-26T07:00:00Z mallory
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#7" "an edit before the agent label is covered by it"
  assert_key "$OUT" PICK reply
}

test_the_owner_relabelling_agent_re_approves_a_parked_issue() {
  setup_env
  reply_issue_7 agent,agent:waiting
  printf 'agent\tocto\t2026-09-26T08:00:00Z\nagent:waiting\tocto\t2026-09-26T10:00:00Z\nagent\tocto\t2026-09-26T12:00:00Z\n' \
    >"$FIX/events-7"
  body_edited 7 2026-09-26T09:00:00Z mallory
  dispatch
  assert_key "$OUT" ISSUE "octo/widgets#7"
  assert_key "$OUT" PICK reply
  assert_eq 1 "$(cli_log | grep -c .)" "one tick, one run: the queue path skips a parked issue"
}

test_a_parked_label_someone_else_applied_still_blocks_the_reply() {
  setup_env
  reply_issue_7 agent:waiting
  printf 'agent\tocto\t2026-09-26T08:00:00Z\nagent:waiting\tmallory\t2026-09-26T10:00:00Z\n' >"$FIX/events-7"
  dispatch
  assert_key "$OUT" TICK idle
}

test_an_unreadable_edit_history_is_skipped() {
  setup_env
  open_issue 4 agent
  : >"$FIX/fail-graphql-4"
  dispatch
  assert_key "$OUT" TICK idle
  [ -z "$(cli_log)" ] || fail "ran an issue whose edits could not be checked"
}

# F7: a reply run that parks again with the cursors it started from, while the reply that started
# it is still above them, would be picked again every tick; it fails instead.
test_a_reply_run_that_parks_without_reading_the_reply_fails() {
  setup_env
  open_issue 7 agent:waiting
  comment 7 100 octo
  comment 7 101 octo '<!-- issue-to-pr state=waiting issue-read=100 -->'
  comment 7 102 octo
  export FAKE_CLI_MODE=flip:agent:waiting
  dispatch
  assert_rc 0
  assert_key "$OUT" PICK reply
  assert_key "$OUT" OUTCOME agent:failed
  assert_contains "$(cat "$FIX/posted-7" 2>/dev/null)" "parked again without reading your reply"
  assert_contains "$(cat "$FIX/posted-7")" '<!-- issue-to-pr state=failed -->'
  assert_eq "agent:failed" "$(cat "$FIX/labels-7")"
  [ -e "$HOME/.agent-dispatch/paused" ] && fail "an unread reply is not a CLI error"
  return 0
}

test_a_review_run_that_parks_without_reading_the_pr_reply_fails_with_its_pr() {
  setup_env
  open_issue 7 agent:review
  comment 7 101 octo '<!-- issue-to-pr state=review step=7 pr=12 issue-read=100 pr-read=200 -->'
  comment 12 201 octo
  export FAKE_CLI_MODE=flip:agent:review
  dispatch
  assert_key "$OUT" OUTCOME agent:failed
  assert_contains "$(cat "$FIX/posted-7" 2>/dev/null)" '<!-- issue-to-pr state=failed pr=12 -->'
  assert_eq "agent:failed" "$(cat "$FIX/labels-7")"
}

test_a_reply_run_that_moved_its_cursor_stays_parked() {
  # The run read 102 and parked at a new cursor; 104 arrived while it ran and waits for the next tick.
  setup_env
  open_issue 7 agent:waiting
  comment 7 100 octo
  comment 7 101 octo '<!-- issue-to-pr state=waiting issue-read=100 -->'
  comment 7 102 octo
  export FAKE_CLI_MODE=flip:agent:waiting \
    FAKE_CLI_COMMENTS='103\tocto\t<!-- issue-to-pr state=waiting issue-read=102 -->\n104\tocto\t\n'
  dispatch
  assert_key "$OUT" OUTCOME agent:waiting
  [ -e "$FIX/posted-7" ] && fail "a run that read the reply needs no dispatcher comment"
  assert_eq "agent:waiting" "$(cat "$FIX/labels-7")"
}

# F2: the launcher's id reaches the lock before the CLI can start; a launch without it is kept.
test_a_dead_ticks_launch_without_a_run_id_keeps_the_lock() {
  local lock
  setup_env
  lock="$HOME/.agent-dispatch/lock"
  open_issue 4 agent:running
  mkdir -p "$lock"
  printf 'octo/widgets\n' >"$lock/repo"
  printf '4\n' >"$lock/issue"
  dead_pid >"$lock/tick"
  : >"$lock/launched"
  dispatch
  assert_rc 1
  assert_key "$OUT" REASON recover
  [ -d "$lock" ] || fail "the launcher may still be starting; its lock must survive"
  [ -e "$FIX/posted-4" ] && fail "reconciled a run that may still be starting"
  return 0
}

test_the_windows_launcher_records_its_own_pid_before_bash_starts() {
  on_windows_host || { printf 'job.ps1 only runs on Windows; skipped\n'; return 0; }
  local d="$TEST_TMPDIR/lock"
  mkdir -p "$d"
  # The script checks, from inside the run, that `run` already names a live powershell.exe.
  # shellcheck disable=SC2016 # $(cat ...) runs inside the generated script, not here
  printf 'tasklist //FI "PID eq $(cat %q)" //NH > %q\n' "$d/run" "$d/seen" >"$d/run.sh"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$AD_SCRIPTS/job.ps1")" \
    "$(cygpath -w "$BASH")" "$(cygpath -w "$d/run.sh")" </dev/null >/dev/null 2>&1
  assert_eq 0 "$?" "exit code"
  assert_contains "$(tr '[:upper:]' '[:lower:]' <"$d/seen")" powershell.exe "run did not name the launcher while bash ran"
}

# F6: the launcher's own failures are not CLI errors.
test_a_launcher_that_cannot_start_the_run_exits_96() {
  on_windows_host || { printf 'job.ps1 only runs on Windows; skipped\n'; return 0; }
  printf 'exit 0\n' >"$TEST_TMPDIR/run.sh"
  # No lock directory next to the script: job.ps1 cannot record its pid, so bash must never start.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$AD_SCRIPTS/job.ps1")" \
    "$(cygpath -w "$BASH")" "$(cygpath -w "$TEST_TMPDIR/nowhere/run.sh")" </dev/null >/dev/null 2>&1
  assert_eq 96 "$?" "exit code"
}

test_launcher_exit_codes_name_their_cause() {
  setup_env
  # shellcheck source=../../scripts/dispatch.sh
  source "$AD_SCRIPTS/dispatch.sh"
  mkdir -p "$LOCK"
  write_run_script "$TEST_TMPDIR/gone" claude 4 trivial "$TEST_TMPDIR/run.log"
  "$BASH" "$LOCK/run.sh"
  assert_eq 97 "$?" "exit code"
  run_cause 97 claude "$TEST_TMPDIR/run.log" "$TEST_TMPDIR/gone"
  assert_eq "the checkout $TEST_TMPDIR/gone is missing" "$CAUSE"
  assert_eq 0 "$CLIERR" "a missing checkout is not a CLI error"
  # shellcheck disable=SC2329 # replaces the sourced dispatch.sh's own, which gone/run_cause call
  on_windows() { return 0; }
  run_cause 96 claude "$TEST_TMPDIR/run.log" "$TEST_TMPDIR/checkout"
  assert_eq "the Windows launcher could not start the run" "$CAUSE"
  assert_eq 2 "$CLIERR" "every launch would fail the same way: pause"
  run_cause 3 codex "$TEST_TMPDIR/run.log" "$TEST_TMPDIR/checkout"
  assert_eq "the codex CLI exited with code 3" "$CAUSE"
  assert_eq 1 "$CLIERR"
}

test_a_launcher_failure_pauses_without_blaming_a_logout() {
  setup_env
  open_issue 4 agent:running
  # shellcheck source=../../scripts/dispatch.sh
  source "$AD_SCRIPTS/dispatch.sh"
  mkdir -p "$AD_HOME/logs"
  OUT=$(reconcile octo/widgets 4 "the Windows launcher could not start the run" "$AD_HOME/logs/x.log" 2)
  assert_key "$OUT" PAUSED true
  [ -e "$HOME/.agent-dispatch/paused" ] || fail "paused was not created"
  assert_contains "$(cat "$FIX/posted-4")" "paused"
  assert_not_contains "$(cat "$FIX/posted-4")" "logged out"
}

# F3: "could not check" is never "stopped".
test_an_unreadable_process_list_is_not_a_stopped_run() {
  setup_env
  # shellcheck source=../../scripts/dispatch.sh
  source "$AD_SCRIPTS/dispatch.sh"
  # shellcheck disable=SC2329 # replaces the sourced dispatch.sh's own, which gone/run_cause call
  on_windows() { return 0; }
  mkdir -p "$TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 1\n' >"$TEST_TMPDIR/bin/tasklist"
  chmod +x "$TEST_TMPDIR/bin/tasklist"
  PATH="$TEST_TMPDIR/bin:$PATH"
  if gone 4242; then fail "a failed tasklist was read as a stopped run"; fi
  printf '#!/bin/sh\necho "INFO: No tasks are running which match the specified criteria."\n' >"$TEST_TMPDIR/bin/tasklist"
  gone 4242 || fail "tasklist's own no-match answer is a stopped run"
}

test_a_run_that_outlives_its_stop_keeps_the_lock() {
  setup_env
  trap kill_stray_run EXIT
  open_issue 4 agent
  export FAKE_CLI_MODE=hang FAKE_SLEEP_STEP=3600 FAKE_SLEEP_REAL=0.1
  # A stop that does nothing stands in for one that did not take: the tick must not block on wait.
  # shellcheck disable=SC2016 # $1 belongs to the nested shell
  OUT=$("$BASH" -c 'source "$1"; stop_run() { :; }; main' _ "$AD_SCRIPTS/dispatch.sh" 2>"$TEST_TMPDIR/.err")
  RC=$?
  ERR=$(cat "$TEST_TMPDIR/.err")
  assert_rc 1
  assert_key "$OUT" REASON recover
  [ -d "$HOME/.agent-dispatch/lock" ] || fail "a run still alive after its stop keeps the lock"
  [ -e "$FIX/posted-4" ] && fail "reconciled a run that is still alive"
  return 0
}

# A launched marker with no run id means "still starting" only briefly: job.ps1 records its pid
# before it starts bash, so a launcher silent for over a minute never ran the CLI.
test_a_dead_ticks_stale_launch_without_a_run_id_is_reconciled() {
  local lock
  setup_env
  lock="$HOME/.agent-dispatch/lock"
  open_issue 4 agent:running
  mkdir -p "$lock"
  printf 'octo/widgets\n' >"$lock/repo"
  printf '4\n' >"$lock/issue"
  dead_pid >"$lock/tick"
  : >"$lock/launched"
  touch -t 202001010000 "$lock/launched"
  : >"$FIX/issues"
  dispatch
  assert_rc 0
  assert_key "$OUT" RECOVERED "octo/widgets#4"
  assert_eq "agent:failed" "$(cat "$FIX/labels-4")"
  [ -d "$lock" ] && fail "a stale launch kept the lock"
  return 0
}

test_the_launcher_exits_96_without_bash_and_passes_the_scripts_code_through() {
  on_windows_host || { printf 'job.ps1 only runs on Windows; skipped\n'; return 0; }
  local ps1
  ps1=$(cygpath -w "$AD_SCRIPTS/job.ps1")
  mkdir -p "$TEST_TMPDIR/lock"
  printf 'exit 5\n' >"$TEST_TMPDIR/lock/run.sh"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" "$(cygpath -w "$TEST_TMPDIR/no-bash.exe")" \
    "$(cygpath -w "$TEST_TMPDIR/lock/run.sh")" </dev/null >/dev/null 2>&1
  assert_eq 96 "$?" "a bash.exe that cannot start is the launcher's failure"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" "$(cygpath -w "$BASH")" \
    "$(cygpath -w "$TEST_TMPDIR/lock/run.sh")" </dev/null >/dev/null 2>&1
  assert_eq 5 "$?" "the script's own exit code passes through"
}
