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

# The spine is one file, so a bare assert_contains on it passes when the string it wants has
# drifted into some other step. Tests about one step read that step's own block.
#
# Steps come in two shapes: `**7. Review loop.**` inline, and `## Step 11 — ...` as a heading.
# Both start and end a block. The terminator matches a NUMBERED heading only, never any bold run
# that happens to lead with a digit: `**2+ confirmed bugs**` mid-paragraph used to end the slice
# early and silently shrink whatever the test was checking.
#
# An empty slice is NOT self-announcing: assert_contains fails on it, assert_not_contains passes.
# So the caller gets a hard failure instead, and no assertion ever runs against nothing.
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
  assert_contains "$(skill_step 4)" '/ponytail:ponytail full' \
    "Step 4's own block must be where ponytail's mode is set"
  assert_not_contains "$c" "ponytail:ponytail ultra" \
    "the final gate must not switch modes; ponytail-review ignores the session mode"
}

# `git diff <BASE>...HEAD` compares two commits, and Step 8 runs before Step 9 commits, so on a
# fresh branch it showed the ponytail gate an empty diff while the whole run sat uncommitted in
# the worktree. The gate reviewed nothing and reported clean.
test_skill_final_review_reads_the_uncommitted_worktree() {
  local c
  c=$(skill_step 8)
  assert_contains "$c" 'over `git diff <BASE>`' \
    "the final review diffs the base against the working tree, not one commit against another"
  # Two dots still miss a file git has never seen, and a run that adds one is the common case.
  # Step 7 names the same script for the security overlay, which is why this reads Step 8 alone.
  assert_contains "$c" 'untracked file `S/changed-paths.sh --base "<BASE>"` names' \
    "the final review is handed the untracked files too"
}

# Step 8 ran `ponytail-review` once. One pass only hunts what to delete, never what to make
# simpler in place, and nothing re-reads the diff after its own cuts land, so a cut that broke a
# neighbouring path reached the gates at best and nobody at worst. The gate is now two lenses
# over two passes, capped at two: pass 2 pays for itself by reading what pass 1 edited, a third
# would spend tokens on a diff that has stopped moving.
test_skill_simplification_gate_is_two_passes() {
  local c
  c=$(skill_step 8)
  assert_contains "$c" "at most two passes" \
    "Step 8 must state the cap out loud; an uncapped loop is what the cap exists to prevent"
  assert_contains "$c" 'built-in `simplify`' \
    "the simplification lens is the skill Claude Code ships, not a hand-rolled pass"
  # Both lenses, and the deletion one keeps its plugin namespace. A bare `ponytail-review` does
  # not resolve, so the gate would quietly run on one lens while still claiming two.
  assert_contains "$c" '/ponytail:ponytail-review' \
    "the deletion lens needs its plugin prefix or the call finds no such skill"
}

# companions.md claimed `/code-review` was unreachable from a skill run because most copies ship
# `disable-model-invocation`. True of plugin commands by that name, false of the skill Claude Code
# registers itself, and acting on it sent Step 7 to an inline fallback for several releases while
# the real reviewer sat one call away. The built-in does take `--fix`; the pipeline declines it,
# because one sweep of applied fixes lands past the per-fix re-gate and past the bug count the
# escalation ratchet reads. The tier table is where `--fix` used to live, so guard it there too.
test_skill_review_loop_uses_the_builtin_code_review() {
  local c tiers
  c=$(skill_step 7)
  assert_contains "$c" 'built-in `code-review` skill' \
    "Step 7 must reach for the reviewer Claude Code ships instead of defaulting to a fallback"
  assert_contains "$c" 'without `--fix`' \
    "Step 7 must say it declines the reviewer's own fix sweep, and why"
  tiers=$(cat "$ITP_SCRIPTS/../skills/run/references/tier-matrix.md")
  assert_not_contains "$tiers" '--fix' \
    "the tier table sets the review level; it must not hand the reviewer a fix sweep"
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
  blk=$(skill_step 4.5)
  d=$(printf '%s\n' "$blk" | grep -n '/drill:me' | head -1 | cut -d: -f1)
  a=$(printf '%s\n' "$blk" | grep -n 'AskUserQuestion' | head -1 | cut -d: -f1)
  [ -n "$d" ] || fail "Step 4.5 must run /drill:me when the flag asked for it"
  [ -n "$a" ] || fail "Step 4.5 lost its batched AskUserQuestion"
  [ "$d" -le "$a" ] ||
    fail "the drill must come before the batched question, not after it"
  # The flag was inert on the two commonest tiers until Step 4 wrote the design unconditionally:
  # standard keeps its mini-design in the PR body, which does not exist yet at 4.5, and trivial
  # designs nothing. Both branches of 4.5 hand over a file, so that file has to be produced.
  assert_contains "$(skill_step 4)" '`<RUN_DIR>/design.md` whatever the tier' \
    "a --drill run must write the design at every tier, or there is nothing to drill"
  # And the fallback needs a slot to collect objections in. Step 4.5 skips the question on an
  # empty ledger, which is exactly the state a no-plugin drill run is in.
  assert_contains "$blk" 'even on an empty ledger' \
    "a --drill run must ask even when nothing else queued a question"
}

# The ask contract says "three moments only". A drill the user opted into is a fourth, and a
# contract that contradicts the step it governs is worse than no contract.
test_autonomy_accounts_for_the_drill() {
  local a
  a=$(cat "$ITP_SCRIPTS/../skills/run/references/autonomy.md")
  assert_contains "$a" '--drill' \
    "autonomy.md must name the opt-in fourth contact moment it now allows"
  # And no copy of the contract may still state the old absolute. The spine carried
  # "contact the user at exactly three moments" under **Hard rules (never violate)** while the
  # step below it described a fourth: a rule the pipeline breaks by design is worse than none.
  assert_not_contains "$a" 'exactly three' \
    "autonomy.md still asserts the three-moment absolute a --drill run breaks"
  assert_not_contains "$(cat "$(skill_md)")" 'exactly three' \
    "the spine's hard rules still assert the three-moment absolute a --drill run breaks"
}
