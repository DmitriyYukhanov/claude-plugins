#!/usr/bin/env bash
# wait-for-codex.sh <job-id> [poll-interval-seconds]
# Bash 4+ (uses set -euo pipefail).
# Polls codex-companion until phase ∈ {done|failed|cancelled} or 15-min timeout.
# Exits 0 on done, 1 on failed/cancelled, 2 on timeout.
set -euo pipefail

JOB_ID="${1:?usage: wait-for-codex.sh <job-id> [interval]}"
INTERVAL="${2:-30}"
DEADLINE=$(( $(date +%s) + 15*60 ))
COMPANION="${CODEX_COMPANION:-}"

if [ -z "$COMPANION" ]; then
  HOME_DIR="${HOME:-${USERPROFILE:-}}"
  if [ -n "$HOME_DIR" ]; then
    BASE="$HOME_DIR/.claude/plugins/cache/openai-codex/codex"
    [ -d "$BASE" ] && COMPANION=$(find "$BASE" -name codex-companion.mjs 2>/dev/null | sort | tail -1 || true)
  fi
fi

if [ -z "$COMPANION" ] || [ ! -f "$COMPANION" ]; then
  echo "ERROR: codex-companion.mjs not found; set CODEX_COMPANION env var to its absolute path" >&2
  exit 1
fi

NULL_STREAK=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  JSON=$(node "$COMPANION" status "$JOB_ID" --json 2>/dev/null || true)
  if command -v jq >/dev/null 2>&1; then
    PHASE=$(printf '%s' "$JSON" | jq -r '.job.phase // empty' 2>/dev/null || true)
  else
    PHASE=$(printf '%s' "$JSON" \
      | grep -oE '"phase"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | head -1 | grep -oE '"[^"]*"$' | tr -d '"' || true)
  fi
  case "$PHASE" in
    done)      echo "$JOB_ID: done"; exit 0 ;;
    failed)    echo "$JOB_ID: failed" >&2; exit 1 ;;
    cancelled) echo "$JOB_ID: cancelled" >&2; exit 1 ;;
    "")
      NULL_STREAK=$((NULL_STREAK+1))
      [ "$NULL_STREAK" -ge 5 ] && echo "WARN: $NULL_STREAK consecutive empty/unparseable phase reads" >&2
      ;;
    *)
      # Valid non-terminal phase (starting, running, etc.) — reset streak.
      NULL_STREAK=0
      ;;
  esac
  sleep "$INTERVAL"
done
echo "$JOB_ID: timeout after 15min" >&2
exit 2
