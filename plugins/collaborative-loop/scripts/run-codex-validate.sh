#!/usr/bin/env bash
# Run Codex CLI to validate the driver's analysis/review output.
# The validator confirms, rejects, or augments each finding before the driver acts.
#
# Usage: run-codex-validate.sh <artifact_type> <output_dir> <project_dir> <driver_output_file> [base_branch] [target_files...]
#
#   artifact_type      : code | plan | architecture | design
#   output_dir         : directory for validation output (e.g., docs/plans/collaborative-loop)
#   project_dir        : project root directory
#   driver_output_file : path to the driver's analysis output (loop-analysis.md)
#   base_branch        : (code only, default: main) git base branch for diff
#   target_files       : space-separated list of files the driver analyzed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_DIR="$PLUGIN_DIR/prompts"

# Detect environment and validate codex (sets CODEX_ENV, codex_run)
# shellcheck source=check-codex.sh
source "$SCRIPT_DIR/check-codex.sh"

ARTIFACT_TYPE="${1:?Usage: $0 <artifact_type> <output_dir> <project_dir> <driver_output_file> [base_branch] [target_files...]}"
OUTPUT_DIR="${2:?Missing output directory}"
PROJECT_DIR="${3:?Missing project directory}"
DRIVER_OUTPUT="${4:?Missing driver output file}"
shift 4

# Parse base_branch for code artifacts, default to main
BASE_BRANCH="main"
if [[ "$ARTIFACT_TYPE" == "code" && $# -gt 0 ]]; then
    BASE_BRANCH="$1"
    shift
fi
TARGET_FILES="$*"

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/loop-validation.md"

cd "$PROJECT_DIR"

# Load validation format template
VALIDATION_FORMAT="$(cat "$PROMPT_DIR/validation-format.txt")" || {
    echo "FAIL: validation-format.txt not found at $PROMPT_DIR/validation-format.txt" >&2
    exit 1
}

# Load driver's analysis output
DRIVER_CONTENT="$(cat "$DRIVER_OUTPUT")" || {
    echo "FAIL: driver output file not found at $DRIVER_OUTPUT" >&2
    exit 1
}

# Load base validation prompt
BASE_PROMPT_FILE="$PROMPT_DIR/codex-validate-base.txt"
PROMPT="$(cat "$BASE_PROMPT_FILE")" || {
    echo "FAIL: base validation prompt not found at $BASE_PROMPT_FILE" >&2
    exit 1
}
PROMPT+=$'\n\n'

# Load artifact-specific review focus for domain context
ARTIFACT_FILE="$PROMPT_DIR/codex-review-${ARTIFACT_TYPE}.txt"
if [[ -f "$ARTIFACT_FILE" ]]; then
    PROMPT+="## Domain-Specific Focus"$'\n\n'
    PROMPT+="$(cat "$ARTIFACT_FILE")"
    PROMPT+=$'\n\n'
fi

# Add driver's analysis
PROMPT+="## Driver's Analysis"$'\n\n'
PROMPT+="$DRIVER_CONTENT"

# Add target files context
if [[ -n "$TARGET_FILES" ]]; then
    PROMPT+=$'\n\n'"## Target Files"$'\n'"$TARGET_FILES"
fi

# For code artifacts, include a brief diff summary (not full diff) so the validator
# can cross-reference findings against actual changes
if [[ "$ARTIFACT_TYPE" == "code" ]]; then
    DIFF_STAT="$(git diff "$BASE_BRANCH"...HEAD --stat 2>/dev/null)" || true
    if [[ -n "$DIFF_STAT" ]]; then
        PROMPT+=$'\n\n'"## Changed Files Summary (git diff --stat)"$'\n'"$DIFF_STAT"
        PROMPT+=$'\n'"Note: Use git diff or read the files directly to verify specific findings."
    fi
fi

PROMPT+=$'\n\n'"$VALIDATION_FORMAT"

echo "--- Validating driver analysis ($ARTIFACT_TYPE) ---" >&2

CODEX_EXIT=0
codex_run exec --full-auto "$PROMPT" 2>&1 | tee "$OUTPUT_FILE" || CODEX_EXIT=$?

if [[ "$CODEX_EXIT" -ne 0 ]]; then
    echo "WARNING: codex exec exited with code $CODEX_EXIT" >&2
    exit "$CODEX_EXIT"
fi

echo "Codex validation complete: $OUTPUT_FILE"
