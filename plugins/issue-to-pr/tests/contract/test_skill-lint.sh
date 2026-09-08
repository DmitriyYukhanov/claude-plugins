#!/usr/bin/env bash

BUILT_IN_SKILLS='code-review simplify verify deep-research'

skill_md() { printf '%s' "$ITP_SCRIPTS/../skills/run/SKILL.md"; }
setup_md() { printf '%s' "$ITP_SCRIPTS/../skills/setup/SKILL.md"; }
references_dir() { printf '%s' "$ITP_SCRIPTS/../skills/run/references"; }
companions_md() { printf '%s' "$(references_dir)/companions.md"; }
plugin_readme() { printf '%s' "$ITP_SCRIPTS/../README.md"; }
repo_readme() { printf '%s' "$ITP_SCRIPTS/../../../README.md"; }
plugin_manifest() { printf '%s' "$ITP_SCRIPTS/../.claude-plugin/plugin.json"; }
marketplace_manifest() { printf '%s' "$ITP_SCRIPTS/../../../.claude-plugin/marketplace.json"; }

skill_step() { # word-in-the-heading
  local heads head='^([*][*][0-9]+([.][0-9]+)?[.] |## Step [0-9])'
  heads=$(grep -cE "$head.*$1" "$(skill_md)")
  [ "$heads" -eq 1 ] || fail "SKILL.md has $heads step headings naming $1; there must be exactly one.
    Zero means it was renamed or removed. Two is how one step becomes two, which is how a single
    contact moment becomes a pair that each still reads like the original."
  awk -v w="$1" -v h="$head" '$0 ~ h {f = index($0, w) > 0} f' "$(skill_md)"
}

install_table() { sed -n '/^| Companion | Install |/,/^$/p' "$(setup_md)"; }
companions_table() { sed -n '/^| Capability | Preferred/,/^$/p' "$(companions_md)"; }

description_in() { # manifest [anchor-line]
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

test_every_reference_is_cited_and_every_citation_exists() {
  local on_disk cited
  on_disk=$(basename -a "$(references_dir)"/*.md | sort -u)
  cited=$(grep -o 'R/[A-Za-z0-9._-]*\.md' "$(skill_md)" | cut -d/ -f2 | sort -u)
  [ -n "$on_disk" ] || fail "no references on disk; this check would be vacuous"
  [ "$on_disk" = "$cited" ] || fail "the reference files on disk and the R/*.md the spine cites disagree.
    on disk: $(printf '%s' "$on_disk" | tr '\n' ' ')
    cited:   $(printf '%s' "$cited" | tr '\n' ' ')"
}

test_skill_names_every_script_that_ships() {
  local spine script found=0
  spine=$(cat "$(skill_md)")
  for script in "$ITP_SCRIPTS"/*.sh; do
    assert_contains "$spine" "${script##*/}" "SKILL spine must invoke ${script##*/}, or the script should not ship"
    found=$((found + 1))
  done
  [ "$found" -gt 0 ] || fail "no scripts found under $ITP_SCRIPTS; the glob did not expand"
}

test_skill_never_writes_a_resolved_value_as_a_shell_variable() {
  local hits
  hits=$(grep -n '\$[A-Z][A-Z_]\{2,\}' "$(skill_md)" || true)
  [ -z "$hits" ] || fail "SKILL.md names a shell variable where it must substitute the value.
    Every Bash call is a fresh shell, so the name expands to nothing. Use <ANGLE_BRACKETS>.
$hits"
}

test_skill_grill_reshapes_the_checkpoint_without_adding_a_moment() {
  local spine checkpoint ask_contract file content
  spine=$(cat "$(skill_md)")
  [ -n "$spine" ] || fail "SKILL.md came back empty; this check would be vacuous"
  grep -q 'argument-hint:.*--grill' "$(skill_md)" || fail "argument-hint must advertise --grill"

  for file in "$(skill_md)" "$(setup_md)" "$(references_dir)"/*.md \
              "$(plugin_readme)" "$(repo_readme)"; do
    content=$(cat "$file")
    [ -n "$content" ] || fail "$file came back empty; this check would be vacuous"
    assert_not_contains "$content" 'drill' "$file still mentions drill, which the plugin no longer has"
  done

  checkpoint=$(skill_step Checkpoint)
  assert_contains "$checkpoint" 'grilling' "the checkpoint must run the grill when --grill asked for it"
  assert_contains "$checkpoint" 'AskUserQuestion' "the checkpoint lost its batched question"
  assert_contains "$checkpoint" 'replaces' \
    "the checkpoint must say the grill REPLACES the batched question; one that grills and THEN asks spends two contacts"

  ask_contract=$(printf '%s\n' "$spine" | grep -A3 -i 'ask contract:')
  [ -n "$ask_contract" ] || fail "the spine no longer states the ask contract"
  case "$ask_contract" in
    *four*) fail "the ask contract promises a fourth moment again: $ask_contract" ;;
  esac
}

test_builtins_are_never_listed_as_installable() {
  local table skill
  table=$(install_table)
  [ -n "$table" ] || fail "setup's install table came back empty; this check would be vacuous"
  for skill in $BUILT_IN_SKILLS; do
    assert_not_contains "$table" "$skill" "setup's install table offers $skill, which Claude Code already registers"
  done
  table=$(companions_table)
  [ -n "$table" ] || fail "the companions table is gone; this check would be vacuous"
  assert_not_contains "$table" "deep-research" \
    "companions.md gives deep-research a row, but the run can never start it"
}

test_setup_checks_the_hard_requirements_and_installs_nothing() {
  local setup
  setup=$(cat "$(setup_md)")
  assert_contains "$setup" 'gh auth status' "setup must verify the one hard dependency the run has"
  assert_contains "$setup" 'gh auth refresh -s project' \
    "board mode needs the project scope; setup must print the command that adds it"
  assert_contains "$setup" 'never run' \
    "setup prints install commands for a human to run; it must say it installs nothing itself"
}

test_manifests_agree_on_what_the_plugin_does() {
  local plugin market
  plugin=$(description_in "$(plugin_manifest)")
  market=$(description_in "$(marketplace_manifest)" '"name": "issue-to-pr"')
  [ -n "$plugin" ] || fail "no description found in plugin.json; this check would be vacuous"
  [ -n "$market" ] || fail "no issue-to-pr description found in marketplace.json; check vacuous"
  case "$plugin$market" in
    *'"description"'*) fail "the key survived the strip, so both sides are raw lines; check vacuous" ;;
  esac
  [ "$plugin" = "$market" ] || fail "the manifests describe the plugin differently.
    plugin.json is the only copy Claude Code reads, so byte equality is the rule.
    plugin.json:      $plugin
    marketplace.json: $market"
}
