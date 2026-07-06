#!/usr/bin/env bash
# Contract tests for scripts/stage-guard.sh (design D2 finding 15).

sg() { # command -> sets OUT
  OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | bash "$ITP_SCRIPTS/stage-guard.sh" 2>/dev/null)
  export OUT
}

test_sg_denies_add_dash_A() {
  sg 'git add -A'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_sg_denies_add_all_long() {
  sg 'git add --all'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_sg_denies_add_dot() {
  sg 'git add .'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_sg_allows_explicit_paths() {
  sg 'git add src/foo.ts src/bar.ts'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}

test_sg_allows_dot_slash_path() {
  # ./src is an explicit path, not `git add .`
  sg 'git add ./src/foo.ts'
  assert_not_contains "$OUT" 'permissionDecision'
}

test_sg_denies_add_dashdash_dot() {
  # `git add -- .` still stages everything and must be denied.
  sg 'git add -- .'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_sg_denies_add_pathspec_root() {
  # `git add :/` is a magic pathspec for the repo root - denied.
  sg 'git add :/'
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_sg_passthrough_non_add_command() {
  sg 'ls -la'
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}
