#!/usr/bin/env bash
# Run Codex CLI as reviewer in the collaborative loop.
# Evaluates the driver's output and produces a structured verdict.
#
# Usage: run-codex-review.sh <artifact_type> <round> <output_dir> <project_dir> [base_branch] [target_files...]
#
#   artifact_type  : code | plan | architecture | design
#   round          : round number (1, 2, 3...)
#   output_dir     : directory for review output (e.g., docs/plans/collaborative-loop)
#   project_dir    : project root directory
#   base_branch    : (code only, default: main) git base branch for diff
#   target_files   : (non-code only) space-separated list of files to review

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_DIR="$PLUGIN_DIR/prompts"

ARTIFACT_TYPE="${1:?Usage: $0 <artifact_type> <round> <output_dir> <project_dir> [base_branch|target_files...]}"
ROUND="${2:?Missing round number}"
OUTPUT_DIR="${3:?Missing output directory}"
PROJECT_DIR="${4:?Missing project directory}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/loop-review-round-${ROUND}.md"

cd "$PROJECT_DIR"

# Load verdict format template
VERDICT_FORMAT=""
if [[ -f "$PROMPT_DIR/verdict-format.txt" ]]; then
    VERDICT_FORMAT="$(cat "$PROMPT_DIR/verdict-format.txt")"
fi

if [[ "$ARTIFACT_TYPE" == "code" ]]; then
    BASE_BRANCH="${5:-main}"

    if [[ "$ROUND" -eq 1 ]]; then
        # Round 1: use codex review --base for full branch diff review
        # IMPORTANT: --base and [PROMPT] are mutually exclusive in Codex CLI
        codex review --base "$BASE_BRANCH" 2>&1 | tee "$OUTPUT_FILE"
    else
        # Round N>1: use codex exec with diff context for delta review
        DIFF="$(git diff HEAD~1 2>/dev/null || git diff "$BASE_BRANCH"...HEAD)"

        PROMPT="$(cat "$PROMPT_DIR/codex-review-base.txt")"
        PROMPT+=$'\n\n'

        ARTIFACT_FILE="$PROMPT_DIR/codex-review-code.txt"
        if [[ -f "$ARTIFACT_FILE" ]]; then
            PROMPT+="$(cat "$ARTIFACT_FILE")"
            PROMPT+=$'\n\n'
        fi

        PROMPT+="Round: ${ROUND}"$'\n'
        PROMPT+="Only review changes since the last round. Do not re-report fixed issues."$'\n\n'
        PROMPT+="## Recent changes (git diff):"$'\n'
        PROMPT+="$DIFF"$'\n\n'
        PROMPT+="$VERDICT_FORMAT"

        codex exec --full-auto "$PROMPT" 2>&1 | tee "$OUTPUT_FILE"
    fi
else
    # Non-code artifacts: assemble review prompt
    shift 4
    TARGET_FILES="$*"

    PROMPT="$(cat "$PROMPT_DIR/codex-review-base.txt")"
    PROMPT+=$'\n\n'

    ARTIFACT_FILE="$PROMPT_DIR/codex-review-${ARTIFACT_TYPE}.txt"
    if [[ -f "$ARTIFACT_FILE" ]]; then
        PROMPT+="$(cat "$ARTIFACT_FILE")"
        PROMPT+=$'\n\n'
    else
        echo "Warning: no prompt fragment found at $ARTIFACT_FILE" >&2
    fi

    PROMPT+="Files to review: ${TARGET_FILES}"$'\n'
    PROMPT+="Round: ${ROUND}"$'\n'
    if [[ "$ROUND" -gt 1 ]]; then
        PROMPT+="Only review changes since Round $((ROUND - 1)). Do not re-report fixed issues."$'\n'
    fi

    PROMPT+=$'\n'"$VERDICT_FORMAT"

    codex exec --full-auto "$PROMPT" 2>&1 | tee "$OUTPUT_FILE"
fi

echo "Codex review complete: $OUTPUT_FILE"
