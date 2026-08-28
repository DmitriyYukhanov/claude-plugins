#!/usr/bin/env bash
# Contract tests for scripts/merge-guard.sh. Its failure is silent: a broken matcher
# does not error, it just stops denying.

test_mg_denies_admin_merge() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr merge 7 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_mg_denies_admin_through_odd_spacing_and_quotes() {
  # The script collapses whitespace and strips quotes precisely so neither can
  # smuggle the flag past the matcher.
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh   pr    merge  \"7\"   --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

# Quotes INSIDE the command name, not around an argument: `gh pr "merge"` breaks the
# literal the matcher looks for. Verified by mutation - drop the quote-stripping and
# this command passes straight through while every other test here stays green.
test_mg_denies_admin_when_the_subcommand_itself_is_quoted() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr \"merge\" 7 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
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

# `--force-with-lease` refuses when the remote ref is not the one last fetched, so it cannot
# discard a push nobody here has seen. Asking on it made a rebase-and-push cost a confirmation
# every time, and a gate that fires on the safe form teaches people to click through it.
test_mg_allows_force_with_lease() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git push --force-with-lease"}}'
  # The allow result itself, not merely the absence of `ask`: a guard that denied the lease
  # form would satisfy an assert_not_contains on `ask` and this test would never notice.
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}

# An option between the words defeats a contiguous matcher, and both of these are valid,
# working commands. This is the third bypass of that shape found in one release.
test_mg_denies_admin_merge_with_an_option_before_the_subcommand() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"gh pr --repo octo/demo merge 7 --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_mg_asks_on_a_force_push_behind_a_git_global_option() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git -C . push --force origin main"}}'
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

# The exemption strips the lease flag before matching, so a bare --force alongside it is still
# a bare --force. Without the strip, adding the lease flag anywhere would silence the rule.
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

# The heredoc-blanking half, from the guard's own side rather than common.sh's.
# A commit message that quotes the forbidden command is data, not the command.
test_mg_allows_a_commit_message_quoting_the_admin_flag() {
  run_guard '{"tool_name":"Bash","tool_input":{"command":"git commit -F - <<EOF\ndocs: explain why gh pr merge --admin is denied\nEOF"}}'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}
