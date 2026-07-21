#!/usr/bin/env bash
# Contract tests for scripts/lib/common.sh (the output + exit-code contract).

test_common_emit_keyvalue() {
  source "$ITP_SCRIPTS/lib/common.sh"
  emit FOO bar
  emit BAZ "qux quux"
  local out
  out=$(flush_output)
  assert_key "$out" FOO bar
  assert_key "$out" BAZ "qux quux"
}

test_common_json_mode_escapes() {
  source "$ITP_SCRIPTS/lib/common.sh"
  OUTPUT_JSON=1
  emit A 'he said "hi"'
  emit B $'line1\nline2'
  local out
  out=$(flush_output)
  assert_contains "$out" '{'
  assert_contains "$out" '"A":"he said \"hi\""'
  assert_contains "$out" '"B":"line1\nline2"'
}

test_common_slugify() {
  source "$ITP_SCRIPTS/lib/common.sh"
  assert_eq "feat-issue-6-foo" "$(slugify 'Feat/Issue 6: Foo!')"
  assert_eq "a-b" "$(slugify '  a   b  ')"
}

test_common_join_by() {
  source "$ITP_SCRIPTS/lib/common.sh"
  assert_eq "a,b,c" "$(join_by , a b c)"
  assert_eq "a b|c d" "$(join_by '|' 'a b' 'c d')"
  assert_eq "" "$(join_by ,)"
}

test_common_stop_exits_2_with_reason() {
  local out rc
  out=$(bash -c 'source "$1/lib/common.sh"; emit CTX yes; stop bad-thing "human hint"' _ "$ITP_SCRIPTS" 2>/dev/null)
  rc=$?
  assert_eq 2 "$rc" "stop exits 2"
  assert_key "$out" CTX yes
  assert_key "$out" STOP_REASON bad-thing
}

test_common_stop_hint_on_stderr() {
  local err
  err=$(bash -c 'source "$1/lib/common.sh"; stop reason "the human hint"' _ "$ITP_SCRIPTS" 2>&1 1>/dev/null)
  assert_contains "$err" "the human hint"
}

test_common_fallback_exits_3() {
  bash -c 'source "$1/lib/common.sh"; fallback perms' _ "$ITP_SCRIPTS" >/dev/null 2>&1
  assert_eq 3 "$?" "fallback exits 3"
}

test_common_degrade_exits_4() {
  bash -c 'source "$1/lib/common.sh"; degrade parse' _ "$ITP_SCRIPTS" >/dev/null 2>&1
  assert_eq 4 "$?" "degrade exits 4"
}

test_common_strip_heredoc_bodies_blanks_body() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local cmd out
  cmd=$'git commit -m "$(cat <<EOF\nfix: mentions gh pr merge in prose\nEOF\n)"'
  out=$(strip_heredoc_bodies "$cmd")
  assert_not_contains "$out" "gh pr merge"
  assert_contains "$out" "<<EOF"
  assert_contains "$out" "EOF"
}

test_common_strip_heredoc_bodies_dash_variant_tab_indented_terminator() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local cmd out
  cmd=$'cat <<-EOF\n\t\tgh pr merge 13\n\tEOF'
  out=$(strip_heredoc_bodies "$cmd")
  assert_not_contains "$out" "gh pr merge"
}

test_common_strip_heredoc_bodies_multiple_heredocs() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local cmd out
  cmd=$'cat <<A\nfirst gh pr merge\nA\necho mid\ncat <<B\nsecond git add -A\nB'
  out=$(strip_heredoc_bodies "$cmd")
  assert_not_contains "$out" "gh pr merge"
  assert_not_contains "$out" "git add -A"
  assert_contains "$out" "echo mid"
}

test_common_strip_heredoc_bodies_no_heredoc_is_unchanged() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local out
  out=$(strip_heredoc_bodies "gh pr merge feat/issue-6-x --squash")
  assert_contains "$out" "gh pr merge feat/issue-6-x --squash"
}

test_common_done_ok_exits_0() {
  local out rc
  out=$(bash -c 'source "$1/lib/common.sh"; emit RESULT good; done_ok' _ "$ITP_SCRIPTS" 2>/dev/null)
  rc=$?
  assert_eq 0 "$rc" "done_ok exits 0"
  assert_key "$out" RESULT good
}
