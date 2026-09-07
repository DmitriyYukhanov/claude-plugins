#!/usr/bin/env bash
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR=$(cd "$HERE/.." && pwd)
export ITP_SCRIPTS="$PLUGIN_DIR/scripts"
export FAKE_GH_DIR="$HERE/fake-gh"
ASSERT_LIB="$HERE/lib/assert.sh"

red="" grn="" ylw="" rst=""
if [ -t 1 ]; then
  red=$'\033[31m' grn=$'\033[32m' ylw=$'\033[33m' rst=$'\033[0m'
fi

SHELLCHECK_BIN=${SHELLCHECK:-shellcheck}
lint_rc=0
if command -v "$SHELLCHECK_BIN" >/dev/null 2>&1; then
  printf '== shellcheck ==\n'
  mapfile -t sh_files < <(
    find "$PLUGIN_DIR/scripts" -name '*.sh' -type f
    printf '%s\n' "$FAKE_GH_DIR/gh"
  )
  if "$SHELLCHECK_BIN" -x -e SC1091 "${sh_files[@]}"; then
    printf '%sshellcheck clean (%d files)%s\n' "$grn" "${#sh_files[@]}" "$rst"
  else
    lint_rc=1
    printf '%sshellcheck reported problems%s\n' "$red" "$rst"
  fi
else
  printf '%s== shellcheck skipped (not installed) ==%s\n' "$ylw" "$rst"
fi

printf '== contract tests ==\n'
total=0 pass=0 fail=0
failures=""

for tf in "$HERE"/contract/test_*.sh; do
  [ -e "$tf" ] || continue
  name=$(basename "$tf")
  mapfile -t fns < <(
    bash --norc -c '
      set -uo pipefail
      source "$1" >/dev/null 2>&1
      source "$2" >/dev/null 2>&1
      declare -F | awk "{print \$3}" | grep "^test_" | sort
    ' _ "$ASSERT_LIB" "$tf" 2>/dev/null || true
  )
  if [ "${#fns[@]}" -eq 0 ] || [ -z "${fns[0]:-}" ]; then
    fail=$((fail + 1))
    failures="$failures"$'\n'"  $name :: NO TESTS DISCOVERED (parse error?)"
    continue
  fi
  for fn in "${fns[@]:-}"; do
    [ -n "${fn:-}" ] || continue
    total=$((total + 1))
    out=$(
      bash --norc -c '
        set -uo pipefail
        TEST_TMPDIR=$(mktemp -d)
        export TEST_TMPDIR
        trap "cd / 2>/dev/null; rm -rf \"$TEST_TMPDIR\"" EXIT
        source "$1"
        source "$2"
        cd "$TEST_TMPDIR"
        "$3"
      ' _ "$ASSERT_LIB" "$tf" "$fn" 2>&1
    )
    rc=$?
    if [ "$rc" -eq 0 ]; then
      pass=$((pass + 1))
      printf '  %sok%s   %s :: %s\n' "$grn" "$rst" "$name" "$fn"
    else
      fail=$((fail + 1))
      failures="$failures"$'\n'"  $name :: $fn"
      printf '  %sFAIL%s %s :: %s\n%s\n' "$red" "$rst" "$name" "$fn" "$out"
    fi
  done
done

printf '\n== summary ==\n'
printf 'tests: %d  passed: %d  failed: %d\n' "$total" "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  printf '%sFAILURES:%s%s\n' "$red" "$rst" "$failures"
fi

if [ "$fail" -gt 0 ] || [ "$lint_rc" -ne 0 ]; then
  exit 1
fi
printf '%sALL GREEN%s\n' "$grn" "$rst"
exit 0
