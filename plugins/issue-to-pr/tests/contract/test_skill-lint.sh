#!/usr/bin/env bash
# Contract tests for the SKILL.md spine: the line budget, and that the spine still
# wires its mechanical scripts.
#
# The budget counts LINES, not width, so it can be gamed by cramming. Headroom is for
# reflowing a crammed sentence, never for moving DETAIL back out of `references/`.
#
# What this file deliberately does NOT do is pin the spine's English. Assertions on exact
# wording went red on every rewrite of a step whose meaning had not changed, and a test
# that fights the edit instead of the defect gets edited to agree, not consulted.

skill_md() { printf '%s' "$ITP_SCRIPTS/../skills/run/SKILL.md"; }

# The spine is one file, so a bare assert_contains passes when the string it wants drifted
# into another step. Tests about one step read that step's own block.
#
# Steps come in two shapes, `**7. Review loop.**` and `## Step 10 — ...`. The terminator
# matches a NUMBERED heading only, never a bold run that merely leads with a digit.
# An empty slice is not self-announcing (assert_not_contains passes on it), so it is a
# hard failure here rather than a silently empty assertion.
skill_step() { # step-number
  local out
  out=$(awk -v n="$1" '
    index($0, "**" n ". ")==1 || index($0, "## Step " n " ")==1 {f=1; print; next}
    /^\*\*[0-9]+(\.[0-9]+)?\. / || /^## Step [0-9]/ {f=0}
    f' "$(skill_md)")
  [ -n "$out" ] || fail "SKILL.md has no Step $1 block; the heading was renamed or removed"
  printf '%s\n' "$out"
}

test_skill_within_line_budget() {
  local n
  n=$(wc -l <"$(skill_md)")
  n=${n// /}
  # 180 since v2.8.0. The number buys shell back: every rebalance that moved a probe out of
  # a script and into the spine paid for its prose many times over in deleted bash.
  if [ "$n" -gt 180 ]; then fail "SKILL.md is $n lines; the budget is <=180"; fi
}

# Derived from what actually ships, not a hard-coded list: a script the spine stopped calling
# and a script that was deleted look identical to a fixed list, and only one of them is a bug.
# merge-guard.sh is the exception - hooks.json runs it, so the spine never names it.
test_skill_names_spine_scripts() {
  local c s base n=0
  c=$(cat "$(skill_md)")
  for s in "$ITP_SCRIPTS"/*.sh; do
    base=${s##*/}
    [ "$base" = merge-guard.sh ] && continue
    assert_contains "$c" "$base" "SKILL spine must invoke $base, or the script should not ship"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || fail "no scripts found under $ITP_SCRIPTS; the glob did not expand"
}

# Values the model resolves at one step and uses at another are placeholders, not shell
# variables: every Bash call starts a fresh shell. The spine once wrote
# `--option "$STATUS_MAP_IN_PROGRESS"`, which expands to nothing, and the board update
# silently went out without its column. Placeholders are `<ANGLE_BRACKETS>`.
test_skill_never_writes_a_resolved_value_as_a_shell_variable() {
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
  bad=$(grep -nE '\-\-(log-dir|config) [^"]' "$(skill_md)" || true)
  if [ -n "$bad" ]; then
    fail "SKILL.md passes an unquoted path to a path flag: $bad"
  fi
}

# `run-gates.sh` degrades on a missing --log-dir before it runs anything, so the
# post-merge smoke call without one meant the safety net never fired in any released
# version: a merge that broke the base was never caught and the draft revert PR never
# opened.
test_skill_smoke_gate_passes_a_log_dir_before_cleanup() {
  local c smoke_line
  c=$(cat "$(skill_md)")
  smoke_line=$(printf '%s\n' "$c" | grep -n "gate smoke=" || true)
  [ -n "$smoke_line" ] || fail "SKILL.md no longer runs the post-merge smoke gate"
  assert_contains "$c" 'run-gates.sh --log-dir "<RUN_DIR>/logs"'
}

# `--drill` is the one way a run spends the human's time on purpose instead of saving it: it
# hands the design to /drill:me at the checkpoint. Ordering is the contract, not decoration —
# the drill runs BEFORE the batched question so an objection it surfaces still fits in that
# same slot rather than needing a second one. A flag nobody can discover is a flag nobody
# passes, so the frontmatter has to advertise it too.
test_skill_drill_is_opt_in_and_precedes_the_batched_question() {
  local blk d a
  grep -q 'argument-hint:.*--drill' "$(skill_md)" ||
    fail "argument-hint must advertise --drill"
  blk=$(skill_step 4)
  d=$(printf '%s\n' "$blk" | grep -n '/drill:me' | head -1 | cut -d: -f1)
  a=$(printf '%s\n' "$blk" | grep -n 'AskUserQuestion' | head -1 | cut -d: -f1)
  [ -n "$d" ] || fail "the checkpoint must run /drill:me when the flag asked for it"
  [ -n "$a" ] || fail "the checkpoint lost its batched AskUserQuestion"
  [ "$d" -le "$a" ] ||
    fail "the drill must come before the batched question, not after it"
}

setup_md() { printf '%s' "$ITP_SCRIPTS/../skills/setup/SKILL.md"; }

# A companion the run knows and `setup` does not is a companion nobody installs. Both files
# are read up front and a short read is a failure, never a skip: a guard that skips on no
# match passed this test against a one-byte setup skill.
test_setup_walks_every_companion_the_run_knows() {
  local s c comps
  [ -f "$(setup_md)" ] || fail "the setup skill is missing"
  s=$(cat "$(setup_md)")
  comps=$(cat "$ITP_SCRIPTS/../skills/run/references/companions.md")
  [ ${#s} -gt 500 ] || fail "the setup skill is too short to be walking anyone through anything"
  [ ${#comps} -gt 500 ] || fail "companions.md came back short; the comparison would be vacuous"
  for c in superpowers ponytail humanizer drill deep-research cross-review code-review simplify; do
    assert_contains "$comps" "$c" "companions.md must still know the $c companion"
    assert_contains "$s" "$c" "setup must account for the $c companion the run relies on"
  done
}

# A missing scope otherwise surfaces mid-run, after the user has asked for work. Setup is where
# that check is cheap and early. Assert the load-bearing strings: a bare `project` was satisfied
# by "changes their environment for every project" elsewhere in the prose.
test_setup_checks_the_hard_requirements_and_installs_nothing() {
  local s
  s=$(cat "$(setup_md)")
  assert_contains "$s" 'gh auth status' "setup must verify the one hard dependency the run has"
  assert_contains "$s" 'gh auth refresh -s project' \
    "board mode needs the project scope; setup must print the command that adds it"
  assert_contains "$s" 'never run' \
    "setup prints install commands for a human to run; it must say it installs nothing itself"
}
