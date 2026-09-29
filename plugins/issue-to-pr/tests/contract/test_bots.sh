#!/usr/bin/env bash

bots_setup() { # -> cwd in a repo, fake gh and a fake clock at 0, fixtures in FAKE_GH_FIX
  REPO=$(init_repo "$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")")
  cd "$REPO" || fail "could not enter $REPO"
  use_fake_gh happy
  export FAKE_GH_FIX="$TEST_TMPDIR/fix"
  rm -rf "$FAKE_GH_FIX" && mkdir -p "$FAKE_GH_FIX"
  FAKE_CLOCK_DIR=$(cd "${FAKE_GH_DIR:?}/../fake-clock" && pwd)
  export FAKE_CLOCK_DIR PATH="$FAKE_CLOCK_DIR:$PATH"
  export FAKE_NOW="$TEST_TMPDIR/now"
  printf '0\n' >"$FAKE_NOW"
}

fx() { printf '%s\n' "$2" >"$FAKE_GH_FIX/$1"; } # fixture[@t] body
clock() { cat "$FAKE_NOW"; }
posted() { grep -c -- "$1" "$FAKE_GH_FIX/posted" 2>/dev/null || printf 0; }
waits() { # the model re-runs the call while it says WAIT_MORE
  local n=0
  run_script bots.sh wait 12 "$@"
  while [ "${ITP_BOTS_ONCE:-}" != 1 ] && [ "$RC" = 0 ] && [ "$n" -lt 40 ] && printf '%s' "$OUT" | grep -qx 'WAIT_MORE=true'; do
    n=$((n + 1))
    run_script bots.sh wait 12 "$@"
  done
}

test_no_bots_waits_out_the_grace_window_and_posts_nothing() {
  bots_setup
  waits
  assert_rc 0
  assert_key "$OUT" BOTS none
  [ "$(clock)" -ge 240 ] || fail "gave up before the grace window: $(clock)"
  assert_eq 0 "$(posted body)" "posted a comment with no bot to ask"
}

test_coderabbit_is_done_when_its_status_says_completed() {
  bots_setup
  fx status@0 $'pending\tReview queued'
  fx status@60 $'pending\tReview in progress'
  fx status@300 $'success\tReview completed'
  waits
  assert_rc 0
  assert_key "$OUT" BOT_coderabbit "done"
  [ "$(clock)" -ge 300 ] || fail "left before the review finished: $(clock)"
}

test_final_coderabbit_states_end_the_wait_at_once() {
  local st
  for st in 'Review skipped: draft pull request|unavailable:skipped' 'Review paused|unavailable:paused'; do
    bots_setup
    fx status@0 "success	${st%%|*}"
    waits
    assert_key "$OUT" BOT_coderabbit "${st#*|}"
    assert_eq 0 "$(clock)" "waited on a final state: ${st%%|*}"
    assert_eq 0 "$(posted coderabbitai)" "resumed or re-asked a review the owner paused"
  done
}

test_a_short_rate_limit_is_waited_out_and_asked_again_once() {
  bots_setup
  fx status@0 $'success\tReview rate limited'
  fx comments-12 $'5\tcoderabbitai[bot]\t0\tReview limit reached. Next included review available in 12 minutes.'
  fx status@800 $'pending\tReview in progress'
  fx status@900 $'success\tReview completed'
  waits
  assert_rc 0
  assert_key "$OUT" BOT_coderabbit "done"
  assert_eq 1 "$(posted '@coderabbitai review')" "the review is asked for exactly once"
  [ "$(clock)" -ge 720 ] || fail "asked before the window opened: $(clock)"
}

test_a_long_rate_limit_is_reported_not_waited() {
  bots_setup
  fx status@0 $'success\tReview rate limited'
  fx comments-12 $'5\tcoderabbitai[bot]\t0\tNext included review available in 45 minutes.'
  waits
  assert_key "$OUT" BOT_coderabbit unavailable:rate-limited-45m
  assert_eq 0 "$(clock)" "waited on a 45-minute limit"
  assert_eq 0 "$(posted coderabbitai)"
}

test_a_review_that_never_ends_times_out_inside_the_budget() {
  bots_setup
  fx status@0 $'pending\tReview in progress'
  ITP_BOTS_SLICE=99999 waits
  assert_rc 0
  assert_key "$OUT" BOT_coderabbit timeout
  [ "$(clock)" -ge 1200 ] && [ "$(clock)" -lt 1300 ] || fail "budget is 20 minutes, ran to $(clock)"
}

test_a_slice_returns_early_and_the_next_call_keeps_the_budget() {
  bots_setup
  fx status@0 $'pending\tReview in progress'
  ITP_BOTS_ONCE=1 ITP_BOTS_SLICE=300 waits --request-codex
  assert_rc 0
  assert_key "$OUT" WAIT_MORE true
  ITP_BOTS_SLICE=99999 waits --request-codex
  assert_key "$OUT" BOT_coderabbit timeout
  [ "$(clock)" -lt 1300 ] || fail "the second call restarted the budget: $(clock)"
  assert_eq 1 "$(posted '@codex review')" "re-asked Codex on the second call"
}

test_codex_is_asked_once_and_done_on_a_review_of_the_head() {
  bots_setup
  fx reactions@10 eyes
  fx reviews@120 77
  waits --request-codex
  assert_rc 0
  assert_key "$OUT" BOT_codex "done"
  assert_eq 1 "$(posted '@codex review')"
  grep -q -- '<!-- issue-to-pr -->' "$FAKE_GH_FIX/posted" || fail "the request carries no marker, so headless reads it as the owner"
}

test_codex_answers_are_read_from_its_replies_to_the_request() {
  local c
  for c in "Codex Review: Didn't find any major issues. Nice work!|done" \
    'To use Codex here, create a Codex account and connect to github.|unavailable:no-account'; do
    bots_setup
    fx comments-12@30 "901	chatgpt-codex-connector[bot]	30	${c%%|*}"
    waits --request-codex
    assert_key "$OUT" BOT_codex "${c#*|}"
  done
  bots_setup
  fx comments-12 $'850\tchatgpt-codex-connector[bot]\t0\tDidn'"'"'t find any major issues.'
  waits --request-codex
  assert_key "$OUT" BOT_codex unavailable:not-connected
}

test_codex_thumbs_up_is_done_and_silence_is_not_connected() {
  bots_setup
  fx reactions@20 +1
  waits --request-codex
  assert_key "$OUT" BOT_codex "done"
  bots_setup
  waits --request-codex
  assert_key "$OUT" BOT_codex unavailable:not-connected
  [ "$(clock)" -ge 240 ] || fail "gave up on Codex before the grace window"
}

test_github_unreadable_three_times_stops() {
  bots_setup
  : >"$FAKE_GH_FIX/fail-status"
  waits
  assert_rc 2
  assert_key "$OUT" STOP_REASON bots-unreadable
}

test_threads_lists_the_open_threads() {
  bots_setup
  fx threads $'T1\tcoderabbitai\ta.sh\thttps://x/1\nT2\tcoderabbitai\tb.sh\thttps://x/2'
  run_script bots.sh threads 12
  assert_rc 0
  assert_key "$OUT" THREADS_OPEN 2
  assert_contains "$OUT" "THREAD=T2	coderabbitai	b.sh	https://x/2"
}

test_reply_answers_then_resolves_and_never_resolves_unanswered() {
  bots_setup
  printf 'Fixed in abc123.\n' >"$TEST_TMPDIR/body"
  run_script bots.sh reply T1 --body-file "$TEST_TMPDIR/body"
  assert_rc 0
  assert_key "$OUT" RESOLVED true
  assert_gh_called "addPullRequestReviewThreadReply"
  assert_gh_called "resolveReviewThread"
  assert_contains "$(gh_log)" "<!-- issue-to-pr -->" "the reply carries no marker"
  bots_setup
  : >"$FAKE_GH_FIX/fail-reply"
  run_script bots.sh reply T1 --body-file "$TEST_TMPDIR/body"
  assert_rc 2
  assert_key "$OUT" STOP_REASON reply-failed
  assert_gh_not_called "resolveReviewThread" "resolved a thread nobody answered"
}

test_bad_calls_degrade() {
  bots_setup
  run_script bots.sh wait
  assert_rc 4
  run_script bots.sh wait 12 --bogus
  assert_rc 4
  run_script bots.sh nope 12
  assert_rc 4
  run_script bots.sh reply T1
  assert_rc 4
}

test_a_request_posted_on_the_last_tick_of_a_slice_is_not_posted_again() {
  bots_setup
  fx status@0 $'success\tReview rate limited'
  fx comments-12 $'5\tcoderabbitai[bot]\t0\tNext included review available in 12 minutes.'
  ITP_BOTS_ONCE=1 ITP_BOTS_SLICE=750 waits
  assert_key "$OUT" WAIT_MORE true
  waits
  assert_eq 1 "$(posted '@coderabbitai review')" "the slice forgot it had already asked"
}

test_an_expired_rate_limit_is_asked_again_at_once_and_then_waited_on() {
  bots_setup
  printf '5000\n' >"$FAKE_NOW"
  fx status $'success\tReview rate limited'
  fx status@5100 $'pending\tReview in progress'
  fx status@5200 $'success\tReview completed'
  fx comments-12 $'5\tcoderabbitai[bot]\t100\tNext included review available in 47 minutes.'
  waits
  assert_eq 1 "$(posted '@coderabbitai review')" "a limit that ran out long ago still counted as 47 minutes"
  assert_key "$OUT" BOT_coderabbit "done"
}

test_the_most_recently_updated_limit_notice_wins() {
  bots_setup
  fx status $'success\tReview rate limited'
  fx comments-12 $'5\tcoderabbitai[bot]\t100\tNext included review available in 12 minutes.\n6\tcoderabbitai[bot]\t50\tNext included review available in 45 minutes.'
  ITP_BOTS_ONCE=1 waits
  assert_key "$OUT" WAIT_MORE true
  assert_not_contains "$OUT" "rate-limited" "read the stale 45-minute notice"
}

test_a_pending_status_without_text_is_still_waited_on() {
  bots_setup
  fx status@0 $'pending\t'
  fx status@400 $'success\tReview completed'
  waits
  assert_key "$OUT" BOT_coderabbit "done"
}

test_a_default_slice_fits_a_two_minute_tool_call() {
  bots_setup
  fx status $'pending\tReview in progress'
  ITP_BOTS_ONCE=1 waits
  assert_key "$OUT" WAIT_MORE true
  [ "$(clock)" -le 100 ] || fail "one call ran $(clock) seconds"
}

test_a_failed_codex_reviews_read_is_not_silence() {
  bots_setup
  : >"$FAKE_GH_FIX/fail-reviews"
  waits --request-codex
  assert_rc 2
  assert_key "$OUT" STOP_REASON bots-unreadable
}

test_codex_grace_runs_from_its_request_not_from_the_first_wait() {
  bots_setup
  waits
  assert_key "$OUT" BOTS none
  fx reactions@300 eyes
  fx reviews@400 77
  waits --request-codex
  assert_key "$OUT" BOT_codex "done"
}
