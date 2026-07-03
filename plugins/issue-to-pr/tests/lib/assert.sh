#!/usr/bin/env bash
# tests/lib/assert.sh - plain-bash assertion + fixture helpers.
#
# No bats, no jq: every contract test is a `test_*` function in a file under
# tests/contract/. run-tests.sh runs each in an isolated subshell with cwd set
# to a fresh $TEST_TMPDIR. An assertion prints a diagnostic to stderr and exits
# the test subshell non-zero on failure, so the first failure ends that test.
#
# Exported by run-tests.sh before tests run: ITP_SCRIPTS (scripts/ dir),
# FAKE_GH_DIR (fake-gh/ dir), TEST_TMPDIR (per-test scratch dir).

# -- Assertions --------------------------------------------------------------

assert_eq() { # expected actual [msg]
  if [ "$1" != "$2" ]; then
    printf '  ASSERT FAILED: %s\n    expected: [%s]\n    actual:   [%s]\n' \
      "${3:-assert_eq}" "$1" "$2" >&2
    exit 1
  fi
}

assert_contains() { # haystack needle [msg]
  case "$1" in
    *"$2"*) : ;;
    *)
      printf '  ASSERT FAILED: %s\n    string:  [%s]\n    missing: [%s]\n' \
        "${3:-assert_contains}" "$1" "$2" >&2
      exit 1
      ;;
  esac
}

assert_not_contains() { # haystack needle [msg]
  case "$1" in
    *"$2"*)
      printf '  ASSERT FAILED: %s\n    string:      [%s]\n    should lack: [%s]\n' \
        "${3:-assert_not_contains}" "$1" "$2" >&2
      exit 1
      ;;
    *) : ;;
  esac
}

# assert_key OUTPUT KEY EXPECTED [msg] - assert a `KEY=EXPECTED` line is present.
assert_key() {
  local out=$1 key=$2 exp=$3 msg=${4:-assert_key}
  local line val
  line=$(printf '%s\n' "$out" | grep -m1 "^${key}=") || {
    printf '  ASSERT FAILED: %s\n    key not found: %s\n    output:\n%s\n' "$msg" "$key" "$out" >&2
    exit 1
  }
  val=${line#*=}
  if [ "$val" != "$exp" ]; then
    printf '  ASSERT FAILED: %s\n    key: %s\n    expected: [%s]\n    actual:   [%s]\n' \
      "$msg" "$key" "$exp" "$val" >&2
    exit 1
  fi
}

# assert_key_present OUTPUT KEY [msg]
assert_key_present() {
  if ! printf '%s\n' "$1" | grep -q "^${2}="; then
    printf '  ASSERT FAILED: %s\n    key not present: %s\n    output:\n%s\n' \
      "${3:-assert_key_present}" "$2" "$1" >&2
    exit 1
  fi
}

# assert_rc EXPECTED [msg] - assert last run_script exit code (in $RC).
assert_rc() {
  if [ "${RC:-unset}" != "$1" ]; then
    printf '  ASSERT FAILED: %s\n    expected rc: %s\n    actual rc:   %s\n    stdout:\n%s\n    stderr:\n%s\n' \
      "${2:-assert_rc}" "$1" "${RC:-unset}" "${OUT:-}" "${ERR:-}" >&2
    exit 1
  fi
}

fail() { # msg
  printf '  FAIL: %s\n' "$*" >&2
  exit 1
}

# -- Running scripts under test ----------------------------------------------

# run_script SCRIPT ARGS... - run scripts/SCRIPT, capture stdout->OUT, stderr->ERR,
# exit code->RC. Never aborts the test on a non-zero exit (that is the assertion's
# job). SCRIPT is a path relative to $ITP_SCRIPTS (e.g. "preflight.sh").
run_script() {
  local script=$1
  shift
  local errf
  errf=$(mktemp)
  OUT=$(bash "$ITP_SCRIPTS/$script" "$@" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
  export OUT ERR RC
}

# run_guard STDIN_JSON - feed hook JSON to merge-guard.sh on stdin; sets OUT/RC.
run_guard() {
  local errf
  errf=$(mktemp)
  OUT=$(printf '%s' "$1" | bash "$ITP_SCRIPTS/merge-guard.sh" 2>"$errf")
  RC=$?
  ERR=$(cat "$errf")
  rm -f "$errf"
  export OUT ERR RC
}

# -- fake-gh control ---------------------------------------------------------

# use_fake_gh SCENARIO - put the fake gh first on PATH, select a scenario, and
# start a fresh invocation log.
use_fake_gh() {
  export PATH="$FAKE_GH_DIR:$PATH"
  export FAKE_GH_SCENARIO="$1"
  export FAKE_GH_LOG="$TEST_TMPDIR/gh-invocations.log"
  : >"$FAKE_GH_LOG"
}

# gh_log - the recorded gh invocations (one per line).
gh_log() {
  cat "$FAKE_GH_LOG" 2>/dev/null || true
}

# assert_gh_called SUBSTR [msg] - assert some gh invocation contained SUBSTR.
assert_gh_called() {
  assert_contains "$(gh_log)" "$1" "${2:-gh should have been called with: $1}"
}

# assert_gh_not_called SUBSTR [msg]
assert_gh_not_called() {
  assert_not_contains "$(gh_log)" "$1" "${2:-gh should NOT have been called with: $1}"
}

# -- git fixtures ------------------------------------------------------------

# init_repo [DIR] - create a git repo with one commit on `main`. Echoes its path.
init_repo() {
  local dir=${1:-$TEST_TMPDIR/repo}
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf 'seed\n' >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm "seed"
  printf '%s' "$dir"
}
