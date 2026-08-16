#!/usr/bin/env bash
# sensitive-paths.sh - flag a changed-file list that touches security-sensitive
# areas, so the SKILL adds a /security-review pass (spec sec 5.2 security overlay).
# Reads one path per line on stdin, or collects the list itself with --base.
#
# Matching is case-insensitive on whole path SEGMENTS and the filename STEM (last
# extension stripped), NOT raw substring - so auth/, db/migrations/001.sql and .env
# trip, while authors.py, thesaurus.md and payment_ui_copy.md do not (design D2).
#
#   sensitive-paths.sh --base <ref>      # collects the changed files itself
#   git diff --name-only "$BASE"...HEAD | sensitive-paths.sh
#
# Emits SENSITIVE=true|false and MATCHED=<comma-list of matching paths>.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

base_ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) base_ref=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    *) shift ;;
  esac
done

# The overlay runs at Step 7, BEFORE the Step 9 commit, so three sources have to be
# read together: what is already committed on this branch, what is edited but not yet
# committed, and what is new and untracked. Asking the model to type that as a brace
# group also asks it to remember that the first one is a THREE-dot diff - a two-dot
# diff against a base that moved meanwhile reports files this branch never touched.
# It is one line of git per source; it belongs here, not in the prose.
collect_changed_paths() {
  local base=$1
  {
    git diff --name-only "$base...HEAD" 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u
}

# A whole path segment or filename stem that names a sensitive area.
sensitive_word() {
  case "$1" in
    auth | authz | authn | authentication | authorization | oauth | jwt | iam | sso) return 0 ;;
    crypto | cryptography | keys | kms | keystore) return 0 ;;
    secret | secrets | credential | credentials | password | passwords | session | sessions) return 0 ;;
    payment | payments | billing | checkout) return 0 ;;
    # Schema migrations, by convention name and by tool. Neither of the two most
    # common layouts contains a segment named "migration": Alembic uses
    # alembic/versions/*.py and Rails/goose/dbmate use db/migrate/*, so a schema
    # change in either used to slip past the overlay entirely.
    migration | migrations | migrate | alembic | flyway | liquibase) return 0 ;;
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

paths_in=""
if [ -n "$base_ref" ]; then
  # Degrade rather than report a clean scan. The overlay only ever ADDS a review
  # pass, so an unreachable base that quietly emitted SENSITIVE=false would skip
  # the security review and look exactly like a green result - the same silent
  # failure the pre-2.2.0 overlay had when it diffed an unset variable.
  git rev-parse --git-dir >/dev/null 2>&1 ||
    degrade not-a-git-repo "sensitive-paths: --base needs a git repository - run it from the worktree"
  git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null 2>&1 ||
    degrade base-unresolvable "sensitive-paths: '$base_ref' resolves to no commit - scan the diff yourself"
  paths_in=$(collect_changed_paths "$base_ref")
else
  # No --base and nothing piped in: say so instead of blocking on a terminal read.
  # The caller is a model in a one-shot Bash call, so a hang here reads as the whole
  # step having died. (Not reachable from the test harness, whose stdin is a pipe.)
  [ -t 0 ] && degrade no-input "sensitive-paths: pass --base <ref>, or pipe a path list on stdin"
  paths_in=$(cat)
fi

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
done <<< "$paths_in"

if [ "${#matched[@]}" -gt 0 ]; then
  emit SENSITIVE true
  emit MATCHED "$(join_by , "${matched[@]}")"
else
  emit SENSITIVE false
  emit MATCHED ""
fi
done_ok
