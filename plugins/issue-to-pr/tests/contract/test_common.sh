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




# Regression: `sed` exits 0 when its pattern matched nothing, so flipping a marker
# that already said `true` reported success exactly like a real flip - and
# merge-guard.sh's `marker_set_used || hook_deny` exists precisely to tell "I spent
# this approval" from "somebody else already did". One approval, two merges.
test_common_marker_set_used_refuses_an_already_used_marker() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local m
  m="$TEST_TMPDIR/marker-single-use.json"
  printf '{"branch":"b","pr_head_sha":"a","created_at":"x","used":false,"quote":"q"}\n' >"$m"
  marker_set_used "$m" || fail "the first flip should have succeeded"
  assert_contains "$(cat "$m")" '"used":true'
  if marker_set_used "$m"; then fail "flipping an already-used marker reported success"; fi
}

# Regression: same silent-no-op, other rewriter. A marker whose layout sed cannot find
# was copied through byte-for-byte and reported REFRESHED, so the merge went on to stop
# at "PR head moved since approval" with nothing tying that back to the refresh.
test_common_marker_refresh_reports_a_rewrite_that_changed_nothing() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local m
  m="$TEST_TMPDIR/marker-unrecognisable.json"
  printf '{"nothing":"recognisable"}\n' >"$m"
  if marker_refresh "$m" "newsha" "2026-01-01T00:00:00Z"; then
    fail "marker_refresh reported success after changing nothing"
  fi
}

# resolve_under is what keeps two cwd-sensitive paths honest: preflight's config file and
# worktree.sh's --salvage-to destination. A Windows form it fails to recognise as absolute
# gets silently buried under the repo root, where neither of them is ever found again.
# Every value is built from one unambiguous backslash rather than written as a literal:
# counting backslashes through layers of quoting is how the first version of this test
# came to assert something other than what it meant.
test_common_resolve_under_keeps_absolute_paths() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local bs drive unc
  bs=$(printf '\\')
  drive="C:${bs}x.md"                 # C:\x.md
  unc="$bs$bs""nas${bs}team${bs}x.md" # \\nas\team\x.md
  assert_eq '/etc/x.md' "$(resolve_under /ROOT /etc/x.md)" 'POSIX absolute'
  assert_eq 'C:/x.md' "$(resolve_under /ROOT C:/x.md)" 'drive letter, forward slash'
  assert_eq "$drive" "$(resolve_under /ROOT "$drive")" 'drive letter, backslash'
  assert_eq "$unc" "$(resolve_under /ROOT "$unc")" 'UNC share'
  assert_eq '//nas/team/x.md' "$(resolve_under /ROOT //nas/team/x.md)" 'UNC, forward slashes'
}

test_common_resolve_under_roots_a_relative_path() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local bs
  bs=$(printf '\\')
  assert_eq '/ROOT/.claude/c.md' "$(resolve_under /ROOT .claude/c.md)"
  assert_eq '/ROOT/C:not-a-drive/c.md' "$(resolve_under /ROOT C:not-a-drive/c.md)" 'drive-relative is not absolute'
  # ONE leading backslash is not a UNC share, so it still gets rooted.
  assert_eq "/ROOT/${bs}single" "$(resolve_under /ROOT "${bs}single")" 'single backslash'
}

# ensure_state_dir is what keeps this plugin out of a repository it is a guest in: the
# state directory carries its own ignore rule, so a teammate without the plugin never
# sees a file they cannot place, and the project's own .gitignore is never touched.
test_common_ensure_state_dir_writes_a_self_ignoring_gitignore() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local d first
  d="$TEST_TMPDIR/state"
  ensure_state_dir "$d" || fail "ensure_state_dir reported a failure on a writable path"
  [ -f "$d/.gitignore" ] || fail "no .gitignore was written"
  # `*` must be the FIRST rule: gitignore lets the last match win, so a `!keep` someone
  # adds below still works. A `*` at the bottom would override it.
  first=$(grep -v '^#' "$d/.gitignore" | grep -v '^[[:space:]]*$' | head -1)
  assert_eq '*' "$first" 'the first rule must be *'
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

# The caller has to be able to refuse: the files that land here carry the board URL, the
# pinned gate commands and live approvals, and without the rule they are ordinary
# untracked files that the next `git add -A` commits.
test_common_ensure_state_dir_reports_a_failure() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local blocked
  blocked="$TEST_TMPDIR/not-a-dir"
  printf 'i am a file\n' >"$blocked"
  if ensure_state_dir "$blocked/state"; then
    fail "ensure_state_dir reported success with a file in the way"
  fi
}

# A zero-byte .gitignore is the wreckage of an interrupted write, not a rule. Treating it
# as "already set up" left the directory unignored forever while every caller read the 0
# return as proof the rule was there.
test_common_ensure_state_dir_repairs_an_empty_gitignore() {
  source "$ITP_SCRIPTS/lib/common.sh"
  local d first
  d="$TEST_TMPDIR/state-empty"
  mkdir -p "$d"
  : >"$d/.gitignore"
  ensure_state_dir "$d" || fail "ensure_state_dir reported a failure"
  first=$(grep -v '^#' "$d/.gitignore" | grep -v '^[[:space:]]*$' | head -1)
  assert_eq '*' "$first" 'the rule was not restored'
}
