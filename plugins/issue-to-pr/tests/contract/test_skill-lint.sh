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

# Twice now a built-in has been advertised as something to install: `code-review` in
# companions.md, then `deep-research` in three places at once. Every one slipped past the
# companion-walk test above, which only checks that the NAME appears somewhere. Hence three
# regions, each a place whose whole meaning is "you have to install this", and all three
# checked: the first cut of this test read the setup table alone and went green while both
# READMEs were still wrong.
#
# companions.md gets a narrower rule of its own, at the bottom. The blanket one cannot apply
# there: its Preferred column legitimately holds `code-review` and `simplify` in their own
# rows, so banning all three would fail on correct prose. `deep-research` is different, and
# per-name, because it has no preferred-versus-fallback shape to occupy a row with. The
# `code-review` incident that opens this comment stays unguarded.
#
# Regions 2 and 3 are prose, so the rule there is blunt: any mention trips it, a correct one
# included. Deliberate. A false red costs a minute; a false green shipped this bug twice.
# Reword the prose or narrow the slice, never delete the check.
#
# `verify` is not guarded yet: absent from the plugin, so the entry would be speculative and
# the substring would go red on prose that merely says "verify". Add it with the Step 8 slot.
no_builtins() { # region label
  local c
  [ -n "$1" ] || fail "$2 came back empty; this check would be vacuous"
  for c in code-review simplify deep-research; do
    assert_not_contains "$1" "$c" "$2 offers $c, which Claude Code already registers"
  done
}

test_builtins_are_never_listed_as_installable() {
  no_builtins "$(sed -n '/^| Companion | Install |/,/^$/p' "$(setup_md)")" \
    "setup's install table"
  no_builtins "$(sed -n '/^Optional companions/,/^$/p' "$ITP_SCRIPTS/../README.md")" \
    "the plugin README's optional-companions paragraph"
  # Slice the repo README by the claim, not a heading. Take neighbouring lines too, or a hard
  # wrap that pushes the companion names off the matched line defeats the check silently:
  # the region stays non-empty, so the vacuity guard above still passes.
  no_builtins "$(grep -B3 -A3 'used if installed' "$ITP_SCRIPTS/../../../README.md")" \
    "the repo README's companion line"

  # And the companions table itself, for `deep-research` alone: a row there would put the run
  # back to choosing between it and the subagent, which is the choice it cannot make.
  local table
  table=$(sed -n '/^| Capability | Preferred/,/^$/p' \
    "$ITP_SCRIPTS/../skills/run/references/companions.md")
  [ -n "$table" ] || fail "the companions table is gone; this check would be vacuous"
  assert_not_contains "$table" "deep-research" \
    "companions.md gives deep-research a row, but the run can never start it"
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

# v5.0.0 corrected one sentence about cleanup in three places and missed the fourth: the plugin
# manifest, which is the only copy Claude Code itself reads. It stayed wrong for two releases
# because the pre-commit hook keeps the two manifests' VERSIONS in step and says nothing about
# what they claim the plugin does. Byte equality is the whole rule. If they ever have to differ,
# change this test and say why in the same commit.
desc_of() { # file [anchor-line]
  local line
  if [ -n "${2:-}" ]; then
    line=$(grep -A1 -F -- "$2" "$1" | grep '"description"' | head -1)
  else
    line=$(grep '"description"' "$1" | head -1)
  fi
  line=${line#*\"description\": \"}
  line=${line%\",}
  printf '%s' "${line%\"}"
}

test_manifests_agree_on_what_the_plugin_does() {
  local plugin market
  plugin=$(desc_of "$ITP_SCRIPTS/../.claude-plugin/plugin.json")
  market=$(desc_of "$ITP_SCRIPTS/../../../.claude-plugin/marketplace.json" '"name": "issue-to-pr"')
  # Guard the extraction, not its length: a byte count is a proxy that goes red on a legitimately
  # shorter description, and gets "fixed" by lowering the number. What must hold is that the
  # prefix strip fired and something came back.
  [ -n "$plugin" ] || fail "no description found in plugin.json; this check would be vacuous"
  [ -n "$market" ] || fail "no issue-to-pr description found in marketplace.json; check vacuous"
  case "$plugin$market" in
    *'"description"'*) fail "the key survived the strip, so both sides are raw lines; check vacuous" ;;
  esac
  [ "$plugin" = "$market" ] || fail "the manifests describe the plugin differently:
    plugin.json:      $plugin
    marketplace.json: $market"
}
