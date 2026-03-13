#!/usr/bin/env bash
# Clean up intermediate collaborative-loop files.
# MANDATORY after every loop exit, regardless of exit reason.
#
# Usage: cleanup-loop.sh <output_dir>

set -euo pipefail

OUTPUT_DIR="${1:?Usage: $0 <output_dir>}"

# Delete loop round files
rm -f "$OUTPUT_DIR"/loop-drive-round-*.md \
      "$OUTPUT_DIR"/loop-review-round-*.md

# Remove empty directories (output_dir, then its parent)
rmdir "$OUTPUT_DIR" 2>/dev/null || true
parent_dir="$(dirname "$OUTPUT_DIR")"
rmdir "$parent_dir" 2>/dev/null || true

echo "Collaborative-loop cleanup complete."
