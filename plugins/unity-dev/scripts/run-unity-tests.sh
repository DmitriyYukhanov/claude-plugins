#!/usr/bin/env bash
# run-unity-tests.sh — Run Unity Test Framework tests via CLI batchmode.
#
# Usage: run-unity-tests.sh --project-path <path> [OPTIONS]
#
# Options:
#   --project-path <path>   Path to Unity project root (required)
#   --platform <platform>   EditMode | PlayMode (default: EditMode)
#   --category <cats>        Semicolon-separated test categories
#   --filter <filter>        Semicolon-separated test name filter / regex
#   --results-file <path>    Path for NUnit XML results (default: $TEMP/MaintainerTestResults.xml)
#   --unity-path <path>      Path to Unity.exe (default: auto-detect via find-unity.sh)
#   --log-file <path>        Path for Unity log file (default: auto-generated in project Temp/)
#   --extra-args <args>      Additional arguments to pass to Unity CLI
#
# Exit codes: 0 = all tests passed, 2 = some tests failed, 3 = Unity error, 1 = script error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse arguments ---
PROJECT_PATH=""
PLATFORM="EditMode"
CATEGORY=""
FILTER=""
RESULTS_FILE=""
RESULTS_FILE_PROVIDED=false
UNITY_PATH=""
LOG_FILE=""
EXTRA_ARGS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-path) PROJECT_PATH="$2"; shift 2 ;;
    --platform)     PLATFORM="$2"; shift 2 ;;
    --category)     CATEGORY="$2"; shift 2 ;;
    --filter)       FILTER="$2"; shift 2 ;;
    --results-file) RESULTS_FILE="$2"; RESULTS_FILE_PROVIDED=true; shift 2 ;;
    --unity-path)   UNITY_PATH="$2"; shift 2 ;;
    --log-file)     LOG_FILE="$2"; shift 2 ;;
    --extra-args)   EXTRA_ARGS="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROJECT_PATH" ]]; then
  echo "ERROR: --project-path is required" >&2
  exit 1
fi

case "$PLATFORM" in
  EditMode|PlayMode) ;;
  *) echo "ERROR: --platform must be EditMode or PlayMode, got: $PLATFORM" >&2; exit 1 ;;
esac

# Resolve to absolute path
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# --- Detect Unity if not provided ---
if [[ -z "$UNITY_PATH" ]]; then
  UNITY_PATH=$("$SCRIPT_DIR/find-unity.sh" "$PROJECT_PATH")
fi

if [[ ! -f "$UNITY_PATH" ]]; then
  echo "ERROR: Unity not found at: $UNITY_PATH" >&2
  exit 1
fi
echo "Using Unity: $UNITY_PATH" >&2

# --- Set defaults for results and log paths ---
SYS_TEMP="${TMPDIR:-${TEMP:-/tmp}}"

if [[ -z "$RESULTS_FILE" ]]; then
  RESULTS_FILE="$SYS_TEMP/MaintainerTestResults.xml"
fi

if [[ -z "$LOG_FILE" ]]; then
  PROJECT_TEMP_DIR="$PROJECT_PATH/Temp"
  mkdir -p "$PROJECT_TEMP_DIR"
  LOG_FILE="$PROJECT_TEMP_DIR/unity-test-$(date +%Y%m%d-%H%M%S).log"
fi

# Remove stale results to avoid parsing outdated data
rm -f "$RESULTS_FILE"

# --- Build Unity CLI command ---
CMD=("$UNITY_PATH"
  -batchmode
  -nographics
  -projectPath "$PROJECT_PATH"
  -runTests
  -testPlatform "$PLATFORM"
  -testResults "$RESULTS_FILE"
  -logFile "$LOG_FILE"
  -forgetProjectPath
)

if [[ -n "$CATEGORY" ]]; then
  CMD+=(-testCategory "$CATEGORY")
fi

if [[ -n "$FILTER" ]]; then
  CMD+=(-testFilter "$FILTER")
fi

if [[ -n "$EXTRA_ARGS" ]]; then
  extra_arr=()
  read -ra extra_arr <<< "$EXTRA_ARGS"
  CMD+=("${extra_arr[@]}")
fi

echo "--- Running Unity Tests ---" >&2
echo "Project:  $PROJECT_PATH" >&2
echo "Platform: $PLATFORM" >&2
echo "Category: ${CATEGORY:-<all>}" >&2
echo "Filter:   ${FILTER:-<all>}" >&2
echo "Results:  $RESULTS_FILE" >&2
echo "Log:      $LOG_FILE" >&2
echo "Command:  ${CMD[*]}" >&2
echo "---" >&2

# --- Execute Unity ---
set +e
"${CMD[@]}"
UNITY_EXIT=$?
set -e

echo "" >&2
echo "Unity exited with code: $UNITY_EXIT" >&2

# --- Parse NUnit XML results ---
if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "ERROR: Results file not generated at $RESULTS_FILE" >&2
  echo "Check Unity log at: $LOG_FILE" >&2
  exit 3
fi

# Extract summary attributes from <test-run> element in a single pass
# Format: <test-run ... total="N" passed="N" failed="N" skipped="N" ...>
read -r TOTAL PASSED FAILED SKIPPED DURATION < <(
  awk -F'"' '/<test-run/{
    for(i=1;i<NF;i++){
      if($i~/total=/)t=$(i+1)
      if($i~/passed=/)p=$(i+1)
      if($i~/failed=/)f=$(i+1)
      if($i~/skipped=/ || $i~/inconclusive=/)s=$(i+1)
      if($i~/duration=/)d=$(i+1)
    }
    print t,p,f,s,d; exit
  }' "$RESULTS_FILE"
) || true
TOTAL="${TOTAL:-0}"; PASSED="${PASSED:-0}"; FAILED="${FAILED:-0}"; SKIPPED="${SKIPPED:-0}"; DURATION="${DURATION:-?}"

echo ""
echo "=============================="
echo "  Unity Test Results Summary"
echo "=============================="
echo "  Total:   $TOTAL"
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo "  Duration: ${DURATION}s"
echo "=============================="

# --- Show failure details ---
if [[ "$FAILED" -gt 0 ]]; then
  echo ""
  echo "--- Failed Tests ---"
  # Extract failed test names paired with their failure messages in a single pass
  awk '
    /<test-case[^>]*result="Failed"/ {
      s = $0
      sub(/.*fullname="/, "", s)
      sub(/".*/, "", s)
      name = s
    }
    name && /<message>/ {
      msg = $0
      sub(/.*<message><!\[CDATA\[/, "", msg)
      sub(/\]\]><\/message>.*/, "", msg)
      printf "  FAIL: %s\n    -> %s\n", name, msg
      name = ""
    }
  ' "$RESULTS_FILE"
  echo "---"
fi

echo ""
echo "Unity log: $LOG_FILE"

# --- Clean up results files ---
if [[ "$RESULTS_FILE_PROVIDED" == false ]]; then
  rm -f "$RESULTS_FILE"
fi
# Also remove Unity's default TestResults.xml from the project root (left by GUI or direct CLI runs)
rm -f "$PROJECT_PATH/TestResults.xml"

# --- Exit with appropriate code ---
if [[ "$FAILED" -gt 0 ]]; then
  exit 2
elif [[ "$UNITY_EXIT" -ne 0 ]]; then
  exit 3
else
  exit 0
fi
