#!/usr/bin/env bash

test_common_emit_keyvalue() {
  source "$ITP_SCRIPTS/lib/common.sh"
  emit FOO bar
  emit BAZ "qux quux"
  local out
  out=$(flush_output)
  assert_key "$out" FOO bar
  assert_key "$out" BAZ "qux quux"
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

test_common_done_ok_exits_0() {
  local out rc
  out=$(bash -c 'source "$1/lib/common.sh"; emit RESULT good; done_ok' _ "$ITP_SCRIPTS" 2>/dev/null)
  rc=$?
  assert_eq 0 "$rc" "done_ok exits 0"
  assert_key "$out" RESULT good
}

test_common_ensure_state_dir_writes_a_self_ignoring_gitignore() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local d first
  d="$TEST_TMPDIR/state"
  ensure_state_dir "$d" || fail "ensure_state_dir reported a failure on a writable path"
  [ -f "$d/.gitignore" ] || fail "no .gitignore was written"
  first=$(grep -v '^#' "$d/.gitignore" | grep -v '^[[:space:]]*$' | head -1)
  assert_eq '*' "$first" 'the FIRST rule must be a star: gitignore lets the last match decide, so a
    star written below any other rule leaves the state directory unignored'
}

test_common_ensure_state_dir_never_clobbers_an_existing_gitignore() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local d
  d="$TEST_TMPDIR/state-existing"
  mkdir -p "$d"
  printf '%s\n' '*' '!keep-me.md' >"$d/.gitignore"
  ensure_state_dir "$d" || fail "ensure_state_dir reported a failure"
  assert_contains "$(cat "$d/.gitignore")" 'keep-me.md' 'a hand-edited rule was overwritten'
}

test_common_ensure_state_dir_reports_a_failure() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local blocked
  blocked="$TEST_TMPDIR/not-a-dir"
  printf 'i am a file\n' >"$blocked"
  if ensure_state_dir "$blocked/state"; then
    fail "ensure_state_dir reported success with a file in the way"
  fi
}

test_common_ensure_state_dir_repairs_an_empty_gitignore() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local d first
  d="$TEST_TMPDIR/state-empty"
  mkdir -p "$d"
  : >"$d/.gitignore"
  ensure_state_dir "$d" || fail "ensure_state_dir reported a failure"
  first=$(grep -v '^#' "$d/.gitignore" | grep -v '^[[:space:]]*$' | head -1)
  assert_eq '*' "$first" 'a zero-byte .gitignore is the wreckage of an interrupted write, not a
    rule; reading it as "already set up" left the directory unignored forever'
}

test_common_branch_dir_never_gives_two_branches_one_directory() {
  source "$ITP_SCRIPTS/lib/common.sh"
  [ "$(branch_dir /r fix/a/b)" != "$(branch_dir /r fix/a-b)" ] ||
    fail "two branch names resolved to one run directory. Cleanup rm -rf's that path, so the
    collision does not merely mix two runs' logs, it deletes the other one's"
}
