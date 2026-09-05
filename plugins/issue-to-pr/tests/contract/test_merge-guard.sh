#!/usr/bin/env bash

test_mg_denies_admin_merge() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_mg_denies_admin_through_odd_spacing_and_quotes() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh   pr    merge  \"7\"   --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_mg_denies_admin_when_the_subcommand_itself_is_quoted() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr \"merge\" 7 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_mg_allows_a_longer_word_that_merely_contains_a_verb() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr remerge 7 --admin"}}'
  assert_contains "$OUT" '"continue":true'     'has_verbs must match whole tokens: remerge is not merge, and a substring matcher would deny it'
  assert_not_contains "$OUT" 'permissionDecision'     'a substring matcher passes every test in this file except this one'
}

test_mg_decision_does_not_depend_on_what_sits_in_the_working_directory() {
  : >"$TEST_TMPDIR/+decoy"
  cd "$TEST_TMPDIR" || fail "could not enter the temp dir"
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push *"}}'
  assert_contains "$OUT" '"continue":true'     'the guard must not glob the command against the cwd: without set -f around `set -- $cmd` the * expands to a file named +decoy, the plus-refspec test then matches, and a plain push is reported as a force-push'
  assert_not_contains "$OUT" 'permissionDecision'     'a decision that changes with the directory listing is not a decision'
}

test_mg_allows_a_plain_merge() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7 --squash"}}'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}

test_mg_asks_on_force_push() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

test_mg_asks_on_short_force_flag() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}'
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

test_mg_asks_on_plus_refspec() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push origin +main:main"}}'
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

test_mg_allows_force_with_lease() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}

test_mg_denies_admin_merge_with_an_option_before_the_subcommand_because_the_verbs_are_matched_in_order_not_as_one_phrase() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr --repo octo/demo merge 7 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_mg_asks_on_a_force_push_behind_a_git_global_option() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git -C . push --force origin main"}}'
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

test_mg_asks_when_a_bare_force_rides_along_with_a_lease() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease --force origin main"}}'
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

test_mg_allows_a_normal_push() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feat/issue-9-x"}}'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}

test_mg_passthrough_unrelated_command() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}

test_mg_allows_a_commit_message_quoting_the_admin_flag() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<EOF\ndocs: explain why gh pr merge --admin is denied\nEOF"}}'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}
