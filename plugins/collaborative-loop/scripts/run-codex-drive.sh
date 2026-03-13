#!/usr/bin/env bash
# Run Codex CLI as driver in the collaborative loop.
# Produces or modifies artifacts based on task description and reviewer feedback.
#
# Usage: run-codex-drive.sh <artifact_type> <round> <output_dir> <project_dir> <feedback_file> [target_files...]
#
#   artifact_type  : code | plan | architecture | design
#   round          : round number (1, 2, 3...)
#   output_dir     : directory for drive output (e.g., docs/plans/collaborative-loop)
#   project_dir    : project root directory
#   feedback_file  : path to reviewer feedback (use "none" for round 1)
#   target_files   : space-separated list of files to work on

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_DIR="$PLUGIN_DIR/prompts"

# Detect environment and validate codex (sets CODEX_ENV, codex_run)
# shellcheck source=check-codex.sh
source "$SCRIPT_DIR/check-codex.sh"

ARTIFACT_TYPE="${1:?Usage: $0 <artifact_type> <round> <output_dir> <project_dir> <feedback_file> [target_files...]}"
ROUND="${2:?Missing round number}"
OUTPUT_DIR="${3:?Missing output directory}"
PROJECT_DIR="${4:?Missing project directory}"
FEEDBACK_FILE="${5:?Missing feedback file (use 'none' for round 1)}"
shift 5
TARGET_FILES="$*"

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/loop-drive-round-${ROUND}.md"

cd "$PROJECT_DIR"

# Assemble prompt: base + artifact-specific focus
BASE_PROMPT="$PROMPT_DIR/codex-drive-base.txt"
if [[ ! -f "$BASE_PROMPT" ]]; then
    echo "FAIL: base prompt not found at $BASE_PROMPT" >&2
    exit 1
fi
PROMPT="$(cat "$BASE_PROMPT")"
PROMPT+=$'\n\n'

ARTIFACT_FILE="$PROMPT_DIR/codex-drive-${ARTIFACT_TYPE}.txt"
if [[ -f "$ARTIFACT_FILE" ]]; then
    PROMPT+="$(cat "$ARTIFACT_FILE")"
    PROMPT+=$'\n\n'
else
    echo "Warning: no prompt fragment found at $ARTIFACT_FILE" >&2
fi

# Add target files context
if [[ -n "$TARGET_FILES" ]]; then
    PROMPT+="Target files: ${TARGET_FILES}"$'\n\n'
fi

PROMPT+="Round: ${ROUND}"$'\n'

# Add feedback from previous review round
if [[ "$FEEDBACK_FILE" == "none" ]]; then
    PROMPT+="This is the first round. Implement the task as described."$'\n'
elif [[ -f "$FEEDBACK_FILE" ]]; then
    PROMPT+=$'\n'"## Reviewer Feedback (apply these changes):"$'\n\n'
    PROMPT+="$(cat "$FEEDBACK_FILE")"
    PROMPT+=$'\n\n'
    PROMPT+="Apply ALL findings above unless they contradict the task. Address in severity order."$'\n'
else
    echo "FAIL: feedback file not found at $FEEDBACK_FILE" >&2
    exit 1
fi

CODEX_EXIT=0
codex_run exec --full-auto "$PROMPT" 2>&1 | tee "$OUTPUT_FILE" || CODEX_EXIT=$?

if [[ "$CODEX_EXIT" -ne 0 ]]; then
    echo "WARNING: codex exited with code $CODEX_EXIT" >&2
    exit "$CODEX_EXIT"
fi

echo "Codex drive complete: $OUTPUT_FILE"
