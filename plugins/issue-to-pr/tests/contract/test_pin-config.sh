#!/usr/bin/env bash
# Contract tests for scripts/pin-config.sh (design D6, spec sec 5.6).

test_pin_missing_config_degrades() {
  run_script pin-config.sh --test "npm test"
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-config
}

test_pin_creates_frontmatter() {
  local cfg="$TEST_TMPDIR/cfg.md"
  run_script pin-config.sh --config "$cfg" --test "npm test" --typecheck "tsc --noEmit"
  assert_rc 0
  assert_key "$OUT" PINNED "test,typecheck"
  local c; c=$(cat "$cfg")
  assert_contains "$c" "test_cmd: npm test"
  assert_contains "$c" "typecheck_cmd: tsc --noEmit"
}

test_pin_idempotent_toplevel_never_overwrites() {
  local cfg="$TEST_TMPDIR/cfg.md"
  printf -- '---\ntest_cmd: my own test\n---\nnotes\n' >"$cfg"
  run_script pin-config.sh --config "$cfg" --test "npm test"
  assert_rc 0
  assert_key "$OUT" PINNED ""
  local c; c=$(cat "$cfg")
  assert_contains "$c" "my own test"
  assert_not_contains "$c" "npm test"
}

test_pin_respects_nested_commands_form() {
  local cfg="$TEST_TMPDIR/cfg.md"
  printf -- '---\ncommands:\n  test: my nested test\n---\n' >"$cfg"
  run_script pin-config.sh --config "$cfg" --test "npm test" --typecheck "tsc"
  assert_rc 0
  assert_key "$OUT" PINNED "typecheck" # test already set (nested), only typecheck added
  local c; c=$(cat "$cfg")
  assert_not_contains "$c" "test_cmd: npm test"
  assert_contains "$c" "typecheck_cmd: tsc"
}

test_pin_crlf_config_idempotent() {
  local cfg="$TEST_TMPDIR/cfg.md"
  printf -- '---\r\ntest_cmd: existing\r\n---\r\n' >"$cfg"
  run_script pin-config.sh --config "$cfg" --test "npm test"
  assert_rc 0
  assert_key "$OUT" PINNED "" # CRLF-parsed, test seen as already set
}

test_pin_malformed_config_degrades() {
  local cfg="$TEST_TMPDIR/cfg.md"
  printf -- '---\nthis line has no colon\n---\n' >"$cfg"
  run_script pin-config.sh --config "$cfg" --test "npm test"
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON config-parse-failed
}

test_pin_inserts_into_existing_frontmatter_preserving_notes() {
  local cfg="$TEST_TMPDIR/cfg.md"
  printf -- '---\nbase_branch: dev\n---\n\nHuman notes here\n' >"$cfg"
  run_script pin-config.sh --config "$cfg" --test "npm test"
  assert_rc 0
  local c; c=$(cat "$cfg")
  assert_contains "$c" "base_branch: dev"
  assert_contains "$c" "test_cmd: npm test"
  assert_contains "$c" "Human notes here"
}

test_pin_single_fence_amended_in_place() {
  # A hand-edited config with ONE unterminated fence must be amended after that
  # fence, not wrapped in a second frontmatter (regression: keyed on >=2 fences
  # would orphan the original). Exactly one fence line must remain.
  local cfg="$TEST_TMPDIR/cfg.md"
  printf -- '---\nbase_branch: dev\n' >"$cfg"
  run_script pin-config.sh --config "$cfg" --test "npm test"
  assert_rc 0
  assert_key "$OUT" PINNED "test"
  local c; c=$(cat "$cfg")
  assert_contains "$c" "test_cmd: npm test"
  assert_contains "$c" "base_branch: dev"
  local fences; fences=$(grep -c '^---' "$cfg")
  assert_eq 1 "$fences" "single-fence config must not gain a wrapping frontmatter"
}

test_pin_preserves_backslash_in_command() {
  # A backslash in a gate command must be written verbatim (regression: awk -v
  # escape-processes \t into a tab; ENVIRON does not).
  local cfg="$TEST_TMPDIR/cfg.md"
  printf -- '---\nbase_branch: dev\n---\n' >"$cfg"
  run_script pin-config.sh --config "$cfg" --test 'grep -P \t file'
  assert_rc 0
  local c; c=$(cat "$cfg")
  assert_contains "$c" 'test_cmd: grep -P \t file'
}

test_pin_unwritable_config_degrades() {
  # A write that cannot land (the parent path is a file, not a dir) must degrade
  # with exit 4 - never falsely emit PINNED and exit 0 (exit-code contract).
  local blocker="$TEST_TMPDIR/blocker"
  printf 'x\n' >"$blocker" # a regular file where a directory is needed
  run_script pin-config.sh --config "$blocker/issue-to-pr.local.md" --test "npm test"
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON config-write-failed
  assert_not_contains "$OUT" "PINNED=test"
}
