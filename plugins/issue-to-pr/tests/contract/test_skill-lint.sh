#!/usr/bin/env bash
# Contract tests for the SKILL.md spine (design D8, spec sec 5.7).
# Enforces the <=140-line budget and that the spine still wires its mechanical
# scripts (so a future edit can't silently drop the substrate the SKILL relies on).

skill_md() { printf '%s' "$ITP_SCRIPTS/../skills/issue-to-pr/SKILL.md"; }

test_skill_within_line_budget() {
  local n
  n=$(wc -l <"$(skill_md)")
  n=${n// /}
  if [ "$n" -gt 140 ]; then fail "SKILL.md is $n lines; the budget is <=140 (sec 5.7)"; fi
}

test_skill_names_spine_scripts() {
  local c
  c=$(cat "$(skill_md)")
  local s
  for s in preflight.sh worktree.sh run-gates.sh triage-evidence.sh tier-select.sh approve.sh; do
    assert_contains "$c" "$s" "SKILL spine must invoke $s"
  done
}

test_skill_keeps_merge_gate_rule() {
  # The merge-in-main-session-only safety rule must survive the squeeze.
  local c
  c=$(cat "$(skill_md)")
  assert_contains "$c" "main session"
}
