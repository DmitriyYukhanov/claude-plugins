#!/usr/bin/env bash
# Contract tests for scripts/changed-paths.sh - it enumerates, it never judges.

cp_repo() {
  local dir
  dir=$(init_repo "$TEST_TMPDIR/cp")
  git -C "$dir" switch -qc work
  printf '%s' "$dir"
}

test_cp_sees_a_committed_change() {
  local d
  d=$(cp_repo)
  mkdir -p "$d/src/auth"
  printf 'x\n' >"$d/src/auth/login.py"
  git -C "$d" add src/auth/login.py
  git -C "$d" commit -qm "add auth"
  cd "$d" || fail "cd failed"
  run_script changed-paths.sh --base main
  assert_contains "$OUT" "src/auth/login.py"
}

# The overlay runs at Step 7, before the Step 9 commit, so an edit sitting in the
# working tree is the common case, not the exception.
test_cp_sees_uncommitted_and_untracked_work() {
  local d
  d=$(cp_repo)
  mkdir -p "$d/lib/crypto"
  printf 'v1\n' >"$d/lib/crypto/aes.go"
  git -C "$d" add lib/crypto/aes.go
  git -C "$d" commit -qm "seed crypto"
  printf 'v2\n' >"$d/lib/crypto/aes.go"       # tracked, edited, not committed
  printf 'k\n' >"$d/deploy_id_rsa_backup.pem" # untracked
  cd "$d" || fail "cd failed"
  run_script changed-paths.sh --base main
  assert_contains "$OUT" "lib/crypto/aes.go"
  assert_contains "$OUT" "deploy_id_rsa_backup.pem"
}

# Why the collection stays in a script: a two-dot diff against a base that moved on
# reports files this branch never touched, and the model was being asked to remember
# the difference while typing the command by hand.
test_cp_ignores_work_that_landed_on_the_base() {
  local d
  d=$(cp_repo)
  printf 'note\n' >"$d/notes.md"
  git -C "$d" add notes.md
  git -C "$d" commit -qm "branch work"
  git -C "$d" switch -q main
  mkdir -p "$d/src/auth"
  printf 'base\n' >"$d/src/auth/base_only.py"
  git -C "$d" add src/auth/base_only.py
  git -C "$d" commit -qm "landed on base"
  git -C "$d" switch -q work
  cd "$d" || fail "cd failed"
  run_script changed-paths.sh --base main
  assert_contains "$OUT" "notes.md"
  assert_not_contains "$OUT" "base_only.py"
}

# A base that does not resolve must DEGRADE, never print an empty list: the overlay
# only ever adds a review pass, so an empty list read as "nothing changed" skips the
# security review outright and looks exactly like a clean result.
test_cp_unresolvable_ref_degrades() {
  local d
  d=$(cp_repo)
  cd "$d" || fail "cd failed"
  run_script changed-paths.sh --base no/such/ref
  assert_rc 4 "$RC"
  assert_key "$OUT" DEGRADED_REASON base-unresolvable
}

test_cp_outside_a_repo_degrades() {
  mkdir -p "$TEST_TMPDIR/norepo"
  cd "$TEST_TMPDIR/norepo" || fail "cd failed"
  run_script changed-paths.sh --base main
  assert_rc 4 "$RC"
  assert_key "$OUT" DEGRADED_REASON not-a-git-repo
}

test_cp_without_a_base_degrades() {
  local d
  d=$(cp_repo)
  cd "$d" || fail "cd failed"
  run_script changed-paths.sh
  assert_rc 4 "$RC"
  assert_key "$OUT" DEGRADED_REASON no-base
}
