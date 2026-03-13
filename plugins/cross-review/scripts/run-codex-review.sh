#!/usr/bin/env bash
# Run Codex CLI review for cross-review workflow.
# Handles both code artifacts (codex review --base) and non-code (codex exec).
#
# Usage: run-codex-review.sh <artifact_type> <round> <output_dir> <project_dir> [base_branch] [target_files...]
#
#   artifact_type  : code | plan | architecture | design
#   round          : round number (1, 2, 3...)
#   output_dir     : directory for review output (e.g., docs/plans)
#   project_dir    : project root directory
#   base_branch    : (code only, default: main) git base branch for diff
#   target_files   : (non-code only) space-separated list of files to review

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_DIR="$PLUGIN_DIR/prompts"

# Detect environment and validate codex (sets CODEX_ENV, codex_run)
# shellcheck source=check-codex.sh
source "$SCRIPT_DIR/check-codex.sh"

ARTIFACT_TYPE="${1:?Usage: $0 <artifact_type> <round> <output_dir> <project_dir> [base_branch|target_files...]}"
ROUND="${2:?Missing round number}"
OUTPUT_DIR="${3:?Missing output directory}"
PROJECT_DIR="${4:?Missing project directory}"

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/review-codex-round-${ROUND}.md"

cd "$PROJECT_DIR"

if [[ "$ARTIFACT_TYPE" == "code" ]]; then
    # codex review --base is purpose-built for code review.
    # IMPORTANT: --base and [PROMPT] are mutually exclusive — no prompt argument allowed.
    # Multi-agent behavior depends on ~/.codex/config.toml [features] multi_agent = true.
    BASE_BRANCH="${5:-main}"
    codex_run review --base "$BASE_BRANCH" 2>&1 | tee "$OUTPUT_FILE"
else
    # Non-code artifacts use codex exec with an assembled prompt.
    shift 4
    TARGET_FILES="$*"

    # Assemble prompt: base + artifact-specific focus + round context
    PROMPT="$(cat "$PROMPT_DIR/codex-base.txt")"
    PROMPT+=$'\n\n'

    ARTIFACT_FILE="$PROMPT_DIR/codex-${ARTIFACT_TYPE}.txt"
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
    codex_run exec --full-auto "$PROMPT" 2>&1 | tee "$OUTPUT_FILE"
fi

echo "Codex review complete: $OUTPUT_FILE"
