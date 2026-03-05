#!/usr/bin/env bash
# Clean up intermediate cross-review files.
# MANDATORY after every review loop exit, regardless of exit reason.
#
# Usage: cleanup-reviews.sh <output_dir>

set -euo pipefail

OUTPUT_DIR="${1:?Usage: $0 <output_dir>}"

# Delete review round files
rm -f "$OUTPUT_DIR"/review-claude-round-*.md \
      "$OUTPUT_DIR"/review-codex-round-*.md \
      "$OUTPUT_DIR"/combined-review-round-*.md

# Remove empty directories (output_dir, then its parent)
rmdir "$OUTPUT_DIR" 2>/dev/null || true
parent_dir="$(dirname "$OUTPUT_DIR")"
rmdir "$parent_dir" 2>/dev/null || true

echo "Cross-review cleanup complete."
