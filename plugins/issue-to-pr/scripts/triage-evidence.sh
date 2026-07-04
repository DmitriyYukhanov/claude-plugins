#!/usr/bin/env bash
# triage-evidence.sh - emit objective, tier-agnostic triage signals for an issue
# (spec sec 4.6). It makes NO tier decision: the model maps these signals to a tier
# via the rubric in references/tier-matrix.md (v1.3.0). Referenced paths are
# checked for existence relative to the current directory (run it in the repo).
#
#   triage-evidence.sh <issue-number> [--json]
#
# Keys: LABELS (comma-joined), BODY_LENGTH, CHECKLIST_ITEMS, REF_PATHS_EXIST,
# REF_PATHS_MISSING, NEW_THING_HITS, LINKED_ISSUES, TITLE.
# Exit 0 on success; 4 (degraded) if the issue cannot be read.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

issue=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      enable_json
      shift
      ;;
    --repo)
      shift 2 2>/dev/null || shift "$#"
      ;;
    -*)
      warn "triage-evidence: ignoring unknown flag: $1"
      shift
      ;;
    *)
      [ -z "$issue" ] && issue=$1
      shift
      ;;
  esac
done

[ -n "$issue" ] || degrade missing-issue "triage-evidence: issue number required"

# Fetch title + body + labels. A failed title fetch means the issue is unreachable.
if ! title=$(gh issue view "$issue" --json title --jq .title 2>/dev/null); then
  degrade issue-unreachable "triage-evidence: could not read issue #$issue via gh"
fi
body=$(gh issue view "$issue" --json body --jq .body 2>/dev/null || printf '')
labels=$(gh issue view "$issue" --json labels --jq '.labels[].name' 2>/dev/null | paste -sd, - || printf '')

combined="$title"$'\n'"$body"

# Body length (characters).
body_length=${#body}

# Markdown checklist items: `- [ ]` / `- [x]`.
checklist=$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*[-*][[:space:]]*\[[ xX]\]' || true)

# Referenced source/doc paths that exist vs. do not (relative to cwd).
exist=0
missing=0
mapfile -t refs < <(
  printf '%s\n' "$body" |
    grep -oE '[A-Za-z0-9_./-]+\.(ts|tsx|js|jsx|mjs|cjs|py|rs|go|md|json|sh|ya?ml|toml|c|cc|cpp|h|hpp|java|rb|php|css|html)' |
    sort -u || true
)
for p in "${refs[@]:-}"; do
  [ -n "$p" ] || continue
  if [ -e "$p" ]; then
    exist=$((exist + 1))
  else
    missing=$((missing + 1))
  fi
done

# "New thing" keyword hits (create/new/scaffold/from scratch/greenfield/...).
new_hits=$(
  printf '%s\n' "$combined" |
    grep -oiE 'from scratch|greenfield|scaffold|creat(e|ing)|new (service|app|application|plugin|project|feature|module|system|microservice)|build (a|an|the) ' |
    wc -l | tr -d '[:space:]'
)

# Distinct linked issues (#123 references).
linked=$(
  printf '%s\n' "$combined" |
    grep -oE '#[0-9]+' | sort -u | wc -l | tr -d '[:space:]'
)

emit TITLE "$title"
emit LABELS "$labels"
emit BODY_LENGTH "$body_length"
emit CHECKLIST_ITEMS "$checklist"
emit REF_PATHS_EXIST "$exist"
emit REF_PATHS_MISSING "$missing"
emit NEW_THING_HITS "$new_hits"
emit LINKED_ISSUES "$linked"
done_ok
