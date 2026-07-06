#!/usr/bin/env bash
# tier-select.sh - map triage-evidence.sh signals to a machinery tier (spec sec 5.2).
# Reads triage-evidence.sh's KEY=VALUE block on stdin and emits TIER + TIER_REASON.
# The rubric is a deterministic function so cost-scaling is CI-verifiable and cannot
# silently drift (design D2). `--tier <t>` always overrides. Borderline picks higher.
#
#   triage-evidence.sh <N> | tier-select.sh [--tier trivial|standard|complex|epic] [--json]
#
# Tiers: trivial | standard | complex | epic. (Epic MODE - decompose - is v2.0; here
# epic is just the detected tier and the SKILL treats it as complex+ for now.)
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

override=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tier) override=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --json) enable_json; shift ;;
    -*) warn "tier-select: ignoring unknown flag: $1"; shift ;;
    *) shift ;;
  esac
done

new_hits=0 checklist=0 ref_exist=0 body_len=0 labels=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    NEW_THING_HITS=*) new_hits=${line#*=} ;;
    CHECKLIST_ITEMS=*) checklist=${line#*=} ;;
    REF_PATHS_EXIST=*) ref_exist=${line#*=} ;;
    BODY_LENGTH=*) body_len=${line#*=} ;;
    LABELS=*) labels=${line#*=} ;;
  esac
done

# Coerce anything non-numeric to 0 so a malformed line can't crash the arithmetic.
num() { case "$1" in '' | *[!0-9]*) printf '0' ;; *) printf '%s' "$1" ;; esac; }
new_hits=$(num "$new_hits")
checklist=$(num "$checklist")
ref_exist=$(num "$ref_exist")
body_len=$(num "$body_len")

has_label() { # label -> 0 if present (case-insensitive, comma-list)
  case ",$(printf '%s' "$labels" | tr '[:upper:]' '[:lower:]')," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

tier="" reason=""
if [ -n "$override" ]; then
  tier=$override
  reason="--tier override"
elif [ "$new_hits" -ge 3 ] && [ "$ref_exist" -eq 0 ]; then
  tier=epic
  reason="new-system signal (new-thing hits >=3, references no existing paths)"
elif [ "$new_hits" -ge 1 ] || [ "$checklist" -ge 3 ] || [ "$ref_exist" -ge 3 ] \
  || has_label design || has_label ux || has_label breaking; then
  tier=complex
  reason="design/new-behavior signal (new-thing hits, checklist, refs, or label)"
elif [ "$new_hits" -eq 0 ] && [ "$ref_exist" -le 1 ] && [ "$checklist" -le 1 ] \
  && [ "$body_len" -lt 400 ] && ! has_label feature && ! has_label design && ! has_label epic; then
  tier=trivial
  reason="minimal signal (no new-thing, <=1 ref, <=1 checklist, short body)"
else
  tier=standard
  reason="default (known-code change)"
fi

emit TIER "$tier"
emit TIER_REASON "$reason"
done_ok
