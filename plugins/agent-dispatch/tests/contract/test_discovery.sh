#!/usr/bin/env bash
# Exercise the runner with a broken suite beside a valid one, without recursive discovery.
# shellcheck disable=SC2034,SC2317,SC2329

test_discovery_rejects_partial_and_failed_sources() {
  local mini="$TEST_TMPDIR/mini" broken out rc
  mkdir -p "$mini/agent-dispatch/tests/contract" "$mini/issue-to-pr/tests/lib"
  cp "$AD_SCRIPTS/../tests/run-tests.sh" "$mini/agent-dispatch/tests/run-tests.sh"
  cp "$AD_SCRIPTS/../../issue-to-pr/tests/lib/assert.sh" "$mini/issue-to-pr/tests/lib/assert.sh"
  printf 'test_valid() { :; }\n' >"$mini/agent-dispatch/tests/contract/test_good.sh"
  # Lint would detect the deliberate syntax error before discovery. Isolate discovery itself.
  shellcheck() { return 0; }
  export -f shellcheck
  for broken in 'test_partial() { :; }; if' 'test_partial() { :; }; return 7' \
    'test_partial() { :; }; source ./missing-test-file'; do
    printf '%s\n' "$broken" >"$mini/agent-dispatch/tests/contract/test_broken.sh"
    out=$("$BASH" "$mini/agent-dispatch/tests/run-tests.sh" 2>&1)
    rc=$?
    [ "$rc" -ne 0 ] || fail "runner accepted a failed source: $broken"
    assert_contains "$out" test_broken.sh "discovery must identify the failing file"
    assert_contains "$out" discovery "runner must report the discovery failure"
  done
}
