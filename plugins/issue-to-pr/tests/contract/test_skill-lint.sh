#!/usr/bin/env bash
# Contract tests for the SKILL.md spine (design D8, spec sec 5.7).
# Enforces the line budget and that the spine still wires its mechanical scripts
# (so a future edit can't silently drop the substrate the SKILL relies on). The
# budget was 140 through v1.3.0; v2.0.0 (sec 6) added epic/entry/ladder/smoke
# pointers, raising it to 155; v2.2.0 added the substitution rule, the panel
# acceptance test and the widened security overlay, so it is 170.
#
# The budget counts LINES, and a line has no upper width, so squeezing four
# instructions onto one 200-character line scores better than writing them on four
# readable ones. It kept scoring better until the spine's own reader was the thing
# paying for it. The headroom is for reflowing crammed sentences, not for moving
# detail back out of the references: a new paragraph of DETAIL still belongs in
# `references/`, and that is what this number is here to force.

skill_md() { printf '%s' "$ITP_SCRIPTS/../skills/run/SKILL.md"; }

test_skill_within_line_budget() {
  local n
  n=$(wc -l <"$(skill_md)")
  n=${n// /}
  # 180 since v2.8.0: the rebalance moves gate-command detection out of preflight.sh and
  # into the spine, so a few lines of prose here buy back ~90 lines of shell.
  if [ "$n" -gt 180 ]; then fail "SKILL.md is $n lines; the budget is <=180"; fi
}

test_skill_names_spine_scripts() {
  local c
  c=$(cat "$(skill_md)")
  local s
  for s in preflight.sh worktree.sh run-gates.sh changed-paths.sh; do
    assert_contains "$c" "$s" "SKILL spine must invoke $s"
  done
}

# Step 0 tells the model that preflight's keys are values to substitute, not shell
# variables. The spine then wrote `--option "$STATUS_MAP_IN_PROGRESS"` itself, which
# expands to nothing in the fresh Bash call the model actually makes - so the board
# update silently went out without its column. Placeholders are `<ANGLE_BRACKETS>`.
test_skill_never_writes_a_preflight_key_as_a_shell_variable() {
  local hits
  hits=$(grep -n '\$[A-Z][A-Z_]\{2,\}' "$(skill_md)" || true)
  if [ -n "$hits" ]; then
    fail "SKILL.md names a shell variable instead of substituting the value: $hits"
  fi
}

# A checkout path with a space in it turned an unquoted placeholder into two
# arguments, which sent gate logs and the pinned config somewhere else entirely.
test_skill_quotes_its_path_placeholders() {
  local bad
  bad=$(grep -nE '\-\-(log-dir|config|salvage-to) [^"]' "$(skill_md)" || true)
  if [ -n "$bad" ]; then
    fail "SKILL.md passes an unquoted path to a path flag: $bad"
  fi
}

# `run-gates.sh` degrades on a missing --log-dir before it runs anything, so the
# Step 12 smoke call without one meant the post-merge safety net never fired in any
# released version: a merge that broke the base was never caught and the draft revert
# PR never opened. Cleanup deletes that log dir, hence the ordering rule too.
test_skill_smoke_gate_passes_a_log_dir_before_cleanup() {
  local c smoke_line
  c=$(cat "$(skill_md)")
  smoke_line=$(printf '%s\n' "$c" | grep -n "gate smoke=" || true)
  [ -n "$smoke_line" ] || fail "SKILL.md no longer runs the post-merge smoke gate"
  assert_contains "$c" 'run-gates.sh --log-dir "<RUN_DIR>/logs"'
  assert_contains "$c" "Smoke runs BEFORE cleanup"
}

test_skill_keeps_merge_gate_rule() {
  # The merge-in-main-session-only safety rule must survive the squeeze.
  local c
  c=$(cat "$(skill_md)")
  assert_contains "$c" "main session"
}

# Ponytail used to enter at Step 8, after the code was written, and its first act was to
# switch the session to `ultra`. Both halves were wrong: the over-engineering it hunts was
# designed in at Step 4 and typed at Step 5, and `ponytail-review` is a separate skill that
# never reads the session mode, so the switch changed nothing. The mode now goes on at Step 4,
# and ponytail's own SubagentStart hook carries it into every implementation subagent.
test_skill_sets_ponytail_mode_at_design_not_at_the_final_gate() {
  local c
  c=$(cat "$(skill_md)")
  # Placement, not just presence: a `full` that drifted down to Step 8 would still satisfy a
  # bare "contains" check while setting the mode after the design it was meant to shape.
  printf '%s\n' "$c" | grep '^\*\*4\. Design\*\*' | grep -q '/ponytail:ponytail full' ||
    fail "Step 4's own line must be where ponytail's mode is set"
  assert_not_contains "$c" "ponytail:ponytail ultra" \
    "the final gate must not switch modes; ponytail-review ignores the session mode"
}

# `git diff <BASE>...HEAD` compares two commits, and Step 8 runs before Step 9 commits, so on a
# fresh branch it showed the ponytail gate an empty diff while the whole run sat uncommitted in
# the worktree. The gate reviewed nothing and reported clean.
test_skill_final_review_reads_the_uncommitted_worktree() {
  local c
  c=$(cat "$(skill_md)")
  assert_contains "$c" 'ponytail-review` over `git diff <BASE>`' \
    "the final review diffs the base against the working tree, not one commit against another"
  # Two dots still miss a file git has never seen, and a run that adds one is the common case.
  # Anchored on "untracked file" because the bare command string also appears in Step 7, where
  # it would satisfy a looser assertion no matter what Step 8 said.
  assert_contains "$c" 'untracked file `S/changed-paths.sh --base "<BASE>"` names' \
    "the final review is handed the untracked files too"
}
