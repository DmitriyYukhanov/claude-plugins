#!/usr/bin/env bash

test_marker_parses_a_state_marker_and_ignores_unknown_keys() {
  source "$ITP_SCRIPTS/lib/marker.sh"
  parse_marker $'<!-- issue-to-pr state=review step=7 color=red pr=12 head=abc issue-read=5 pr-read=9 -->\r' ||
    fail "a well-formed state marker was rejected"
  assert_eq "review 7 12 abc 5 9" "$M_STATE $M_STEP $M_PR $M_HEAD $M_IREAD $M_PREAD"
}

test_marker_rejects_what_is_not_a_state_marker() {
  local m
  source "$ITP_SCRIPTS/lib/marker.sh"
  for m in '' '<!-- issue-to-pr -->' '<!-- issue-to-pr   -->' 'state=review' \
    '<!-- issue-to-pr state=bogus -->' '<!-- issue-to-pr state=review pr=x1 -->' \
    '<!-- issue-to-pr state=review issue-read=-1 -->' '<!-- issue-to-pr step=3 -->'; do
    ! parse_marker "$m" || fail "accepted: [$m]"
  done
  parse_marker '<!-- issue-to-pr state=waiting -->' || fail "rejected a bare state"
  assert_eq "waiting" "$M_STATE$M_PR$M_HEAD" "fields reset between calls"
}

test_marker_jq_takes_the_last_marker_line_and_a_trimmed_lowercased_body() {
  command -v jq >/dev/null 2>&1 || return 0
  local out
  source "$ITP_SCRIPTS/lib/marker.sh"
  out=$(printf '%s' '[{"id":101,"user":{"login":"octo"},"body":"Report\r\n<!-- issue-to-pr state=waiting -->\r\nmore\r\n<!-- issue-to-pr state=review pr=12 -->\r\n"},{"id":102,"user":{"login":"octo"},"body":"Merge "}]' |
    jq -r "$MARKER_JQ" | tr -d '\r')
  assert_contains "$out" $'101\tocto\t<!-- issue-to-pr state=review pr=12 -->\treport' "the last marker line"
  assert_contains "$out" $'\n102\tocto\t\tmerge' "an unmarked body, trimmed and lowercased"
}
