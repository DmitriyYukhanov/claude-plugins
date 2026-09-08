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
  assert_contains "$OUT" '"continue":true'     'the guard must not glob the command against the cwd: without set -f around the word-splitting, the star expands to a file named +decoy, the plus-refspec test then matches, and a plain push is reported as a force-push'
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

test_mg_closes_a_tab_indented_heredoc_and_still_reads_what_follows_it() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"cat <<-EOF
	docs: gh pr merge --admin is denied
	EOF
gh pr merge 13 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'     'the <<- form strips leading tabs from its terminator: a guard that only matches EOF at column 0 never closes this body, swallows the real merge on the next line, and lets it through'
}

test_mg_reads_the_command_that_follows_a_heredoc_body() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"cat <<A
not a command: gh pr merge --admin
A
gh pr merge 13 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'     'a body that swallows everything after it would hide the real merge on the next line'
}

test_mg_strips_the_body_of_a_second_heredoc_too() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"cat <<A\nnothing here\nA\ncat <<B\ngh pr merge 13 --admin\nB"}}'
  assert_contains "$OUT" '"continue":true'     'a scanner that closes after the first heredoc feeds the second body to the matcher verbatim, and a commit message quoting the admin flag is denied'
  assert_not_contains "$OUT" 'permissionDecision'
}

test_mg_does_not_read_a_quoted_heredoc_marker_as_an_operator() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"printf %s '"'"'<<EOF'"'"'\ngh pr merge 13 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"' \
    'the << sits inside a quoted argument, so it opens no heredoc. Reading it as one swallows the
    real merge on the next line and the guard waves the whole thing through'
}
