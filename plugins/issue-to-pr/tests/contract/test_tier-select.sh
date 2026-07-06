#!/usr/bin/env bash
# Contract tests for scripts/tier-select.sh (design D2, spec sec 5.2 rubric).

tier_run() { # keys-block [args...] -> sets OUT/RC
  local block=$1; shift
  OUT=$(printf '%s\n' "$block" | bash "$ITP_SCRIPTS/tier-select.sh" "$@" 2>/dev/null)
  RC=$?
  export OUT RC
}

test_tier_trivial() {
  tier_run "NEW_THING_HITS=0
REF_PATHS_EXIST=0
CHECKLIST_ITEMS=0
BODY_LENGTH=100
LABELS="
  assert_key "$OUT" TIER trivial
}

test_tier_standard_default() {
  tier_run "NEW_THING_HITS=0
REF_PATHS_EXIST=2
CHECKLIST_ITEMS=2
BODY_LENGTH=600
LABELS=bug"
  assert_key "$OUT" TIER standard
}

test_tier_borderline_picks_higher() {
  # Fails one trivial condition (ref>1) -> not trivial -> standard (higher).
  tier_run "NEW_THING_HITS=0
REF_PATHS_EXIST=2
CHECKLIST_ITEMS=0
BODY_LENGTH=100
LABELS="
  assert_key "$OUT" TIER standard
}

test_tier_complex_via_new_thing() {
  tier_run "NEW_THING_HITS=1
REF_PATHS_EXIST=1
CHECKLIST_ITEMS=0
BODY_LENGTH=200"
  assert_key "$OUT" TIER complex
}

test_tier_complex_via_checklist() {
  tier_run "NEW_THING_HITS=0
CHECKLIST_ITEMS=3
REF_PATHS_EXIST=1
BODY_LENGTH=200"
  assert_key "$OUT" TIER complex
}

test_tier_complex_via_refs() {
  tier_run "NEW_THING_HITS=0
CHECKLIST_ITEMS=0
REF_PATHS_EXIST=3
BODY_LENGTH=200"
  assert_key "$OUT" TIER complex
}

test_tier_complex_via_label() {
  tier_run "NEW_THING_HITS=0
CHECKLIST_ITEMS=0
REF_PATHS_EXIST=1
BODY_LENGTH=200
LABELS=bug,design"
  assert_key "$OUT" TIER complex
}

test_tier_epic() {
  tier_run "NEW_THING_HITS=3
REF_PATHS_EXIST=0
CHECKLIST_ITEMS=0
BODY_LENGTH=200"
  assert_key "$OUT" TIER epic
}

test_tier_override_wins() {
  tier_run "NEW_THING_HITS=5
REF_PATHS_EXIST=0" --tier trivial
  assert_key "$OUT" TIER trivial
  assert_key "$OUT" TIER_REASON "--tier override"
}

test_tier_malformed_numeric_coerced() {
  tier_run "NEW_THING_HITS=abc
REF_PATHS_EXIST=
CHECKLIST_ITEMS=x
BODY_LENGTH=100
LABELS="
  assert_rc 0
  assert_key "$OUT" TIER trivial # all coerced to 0
}

test_tier_json_output() {
  tier_run "NEW_THING_HITS=1" --json
  assert_contains "$OUT" '"TIER":"complex"'
}

test_tier_unterminated_last_line() {
  # The decisive signal on the final line with NO trailing newline must still be
  # read - otherwise the tier silently falls to trivial (read-loop regression).
  OUT=$(printf 'BODY_LENGTH=100\nNEW_THING_HITS=1' | bash "$ITP_SCRIPTS/tier-select.sh" 2>/dev/null)
  RC=$?
  export OUT RC
  assert_rc 0
  assert_key "$OUT" TIER complex
}
