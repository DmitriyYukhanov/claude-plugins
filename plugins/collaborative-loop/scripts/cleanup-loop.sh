#!/usr/bin/env bash
# Clean up intermediate collaborative-loop files.
# MANDATORY after every loop exit, regardless of exit reason.
#
# Usage: cleanup-loop.sh <output_dir>

set -euo pipefail

OUTPUT_DIR="${1:?Usage: $0 <output_dir>}"

# Single glob list used for both counting and deletion
PATTERNS=(
    "$OUTPUT_DIR"/loop-drive-round-*.md
    "$OUTPUT_DIR"/loop-review-round-*.md
    "$OUTPUT_DIR"/loop-analysis.md
    "$OUTPUT_DIR"/loop-validation.md
)

# Collect matching files (nullglob-safe)
FILES=()
for pattern in "${PATTERNS[@]}"; do
    for f in $pattern; do
        [[ -f "$f" ]] && FILES+=("$f")
    done
done

# Delete collected files
if [[ ${#FILES[@]} -gt 0 ]]; then
    rm -f "${FILES[@]}"
fi

# Remove empty directories (output_dir, then its parent)
rmdir "$OUTPUT_DIR" 2>/dev/null || true
parent_dir="$(dirname "$OUTPUT_DIR")"
rmdir "$parent_dir" 2>/dev/null || true

echo "Collaborative-loop cleanup complete. Removed ${#FILES[@]} intermediate file(s)."
