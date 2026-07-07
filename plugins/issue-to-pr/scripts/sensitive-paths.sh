#!/usr/bin/env bash
# sensitive-paths.sh - flag a changed-file list that touches security-sensitive
# areas, so the SKILL adds a /security-review pass (spec sec 5.2 security overlay).
# Reads one path per line on stdin (e.g. `git diff --name-only "$BASE"...HEAD`).
#
# Matching is case-insensitive on whole path SEGMENTS and the filename STEM (last
# extension stripped), NOT raw substring - so auth/, db/migrations/001.sql and .env
# trip, while authors.py, thesaurus.md and payment_ui_copy.md do not (design D2).
#
#   git diff --name-only "$BASE"...HEAD | sensitive-paths.sh [--json]
#
# Emits SENSITIVE=true|false and MATCHED=<comma-list of matching paths>.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json) enable_json; shift ;;
    *) shift ;;
  esac
done

# A whole path segment or filename stem that names a sensitive area.
sensitive_word() {
  case "$1" in
    auth | authz | authn | authentication | authorization | oauth | jwt | iam | sso) return 0 ;;
    crypto | cryptography | keys | kms | keystore) return 0 ;;
    secret | secrets | credential | credentials | password | passwords | session | sessions) return 0 ;;
    payment | payments | billing | checkout) return 0 ;;
    migration | migrations) return 0 ;;
    *) return 1 ;;
  esac
}

# A filename that is sensitive by pattern (dotenv, sql, key material).
sensitive_filename() {
  case "$1" in
    .env | .env.*) return 0 ;;
    *.sql | *.pem | *.key | *.p12 | *.pfx) return 0 ;;
    id_rsa | id_dsa | id_ecdsa | id_ed25519) return 0 ;;
    *) return 1 ;;
  esac
}

matched=()
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  lc=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  hit=0
  # Filename patterns.
  fname=${lc##*/}
  if sensitive_filename "$fname"; then hit=1; fi
  # Whole-segment matches (each '/'-delimited segment, and the filename stem).
  if [ "$hit" = 0 ]; then
    stem=${fname%.*} # strip the last extension only
    local_ifs=$IFS
    IFS=/
    for seg in $lc; do
      [ -n "$seg" ] || continue
      if sensitive_word "$seg"; then hit=1; break; fi
    done
    IFS=$local_ifs
    if [ "$hit" = 0 ] && sensitive_word "$stem"; then hit=1; fi
  fi
  [ "$hit" = 1 ] && matched+=("$path")
done

if [ "${#matched[@]}" -gt 0 ]; then
  emit SENSITIVE true
  emit MATCHED "$(join_by , "${matched[@]}")"
else
  emit SENSITIVE false
  emit MATCHED ""
fi
done_ok
