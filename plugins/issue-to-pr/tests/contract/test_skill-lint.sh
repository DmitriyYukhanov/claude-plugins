#!/usr/bin/env bash

SKILL_LINE_BUDGET=150
ROUTINE_READ_BUDGET=321
ALL_PROSE_BUDGET=583
ROUTINE_READ_REFERENCES='judgment.md configuration.md companions.md'
BUILT_IN_SKILLS='code-review simplify verify deep-research'
HOOK_RUN_SCRIPT=merge-guard.sh

skill_md() { printf '%s' "$ITP_SCRIPTS/../skills/run/SKILL.md"; }
setup_md() { printf '%s' "$ITP_SCRIPTS/../skills/setup/SKILL.md"; }
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

references_dir() { printf '%s' "$ITP_SCRIPTS/../skills/run/references"; }

references_on_disk() { basename -a "$(references_dir)"/*.md | sort -u; }

references_the_spine_cites() {
  grep -o 'R/[A-Za-z0-9._-]*\.md' "$(skill_md)" | cut -d/ -f2 | sort -u
}

install_table() { sed -n '/^| Companion | Install |/,/^$/p' "$(setup_md)"; }
companions_table() { sed -n '/^| Capability | Preferred/,/^$/p' "$(companions_md)"; }
optional_companions_paragraph() { sed -n '/^Optional companions/,/^$/p' "$(plugin_readme)"; }
companion_line_of_repo_readme() { grep 'companion skills (' "$(repo_readme)"; }
companion_region_of_repo_readme() { grep -B3 -A3 'used if installed' "$(repo_readme)"; }

plugins_setup_can_install() {
  install_table | sed -n 's/^| `\([^`]*\)`.*/\1/p' | sort -u
}

companion_paths_in() { # text
  printf '%s\n' "$1" | grep -o '`/\{0,1\}[^`]*:[^`]*`' | tr -d '`/' | cut -d' ' -f1 | sort -u
}

paths_the_run_prefers() { companion_paths_in "$(companions_table | cut -d'|' -f3)"; }
plugins_the_run_prefers() { paths_the_run_prefers | cut -d: -f1 | sort -u; }

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

reject_built_ins_in() { # region region-name
  local skill
  [ -n "$1" ] || fail "$2 came back empty; this check would be vacuous"
  for skill in $BUILT_IN_SKILLS; do
    assert_not_contains "$1" "$skill" "$2 offers $skill, which Claude Code already registers"
  done
}

assert_same_set() { # expected actual expected-name actual-name
  [ -n "$1" ] || fail "nothing parsed from $3; this check would be vacuous"
  [ "$1" = "$2" ] || fail "$3 and $4 disagree.
    $3: $(printf '%s' "$1" | tr '\n' ' ')
    $4: $(printf '%s' "$2" | tr '\n' ' ')"
}

prose_budget() { # what budget file...
  local what=$1 budget=$2 total=0 file count breakdown=''
  shift 2
  for file in "$@"; do
    [ -f "$file" ] || fail "$what counts $file, which is not on disk"
    count=$(wc -l <"$file")
    count=${count// /}
    total=$((total + count))
    breakdown+="${breakdown:+, }${file##*/} $count"
  done
  [ "$total" -le "$budget" ] || fail "$what is $total lines, over the $budget budget.
    $breakdown
    Cut somewhere else, or raise the ceiling in the same PR and say in its body what the extra
    lines bought. A ratchet nobody may ever move is one somebody eventually deletes."
}

test_skill_within_line_budget() {
  prose_budget "the spine" "$SKILL_LINE_BUDGET" "$(skill_md)"
}

test_routine_read_stays_within_budget() {
  local file
  local -a files
  [ -n "$ROUTINE_READ_REFERENCES" ] ||
    fail "ROUTINE_READ_REFERENCES is empty, so this budget counts the spine alone and is vacuous"
  files=("$(skill_md)")
  for file in $ROUTINE_READ_REFERENCES; do files+=("$(references_dir)/$file"); done
  prose_budget "what a run reads before it can work" "$ROUTINE_READ_BUDGET" "${files[@]}"
}

test_all_prose_stays_within_budget() {
  prose_budget "the plugin's prose" "$ALL_PROSE_BUDGET" \
    "$(skill_md)" "$(setup_md)" "$(references_dir)"/*.md
}

test_every_reference_is_cited_and_every_citation_exists() {
  assert_same_set "$(references_on_disk)" "$(references_the_spine_cites)" \
    "the reference files on disk" "the R/*.md the spine cites"
}

test_skill_names_spine_scripts() {
  local spine script name found=0
  spine=$(cat "$(skill_md)")
  for script in "$ITP_SCRIPTS"/*.sh; do
    name=${script##*/}
    [ "$name" = "$HOOK_RUN_SCRIPT" ] && continue
    assert_contains "$spine" "$name" "SKILL spine must invoke $name, or the script should not ship"
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

test_skill_quotes_its_path_placeholders() {
  local unquoted
  unquoted=$(grep -nE '\-\-(log-dir|config) [^"]' "$(skill_md)" || true)
  [ -z "$unquoted" ] || fail "SKILL.md passes an unquoted path to a path flag.
    A checkout path containing a space then arrives as two arguments.
$unquoted"
}

test_skill_smoke_gate_passes_a_log_dir_before_cleanup() {
  local spine
  spine=$(cat "$(skill_md)")
  printf '%s\n' "$spine" | grep -q "gate smoke=" ||
    fail "SKILL.md no longer runs the post-merge smoke gate"
  assert_contains "$spine" 'run-gates.sh --log-dir "<RUN_DIR>/logs"' \
    "the smoke gate needs --log-dir; run-gates.sh degrades before running anything without one"
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

test_setup_names_every_builtin_the_run_leans_on() {
  local setup companions built_in
  setup=$(cat "$(setup_md)")
  companions=$(cat "$(companions_md)")
  [ ${#setup} -gt 500 ] || fail "the setup skill is too short to be walking anyone through anything"
  [ ${#companions} -gt 500 ] || fail "companions.md came back short; the comparison would be vacuous"
  for built_in in $BUILT_IN_SKILLS; do
    assert_contains "$companions" "$built_in" "companions.md must still know the built-in $built_in"
    assert_contains "$setup" "$built_in" "setup must still tell people $built_in needs no install"
  done
}

test_setup_and_companions_name_the_same_plugins() {
  assert_same_set "$(plugins_the_run_prefers)" "$(plugins_setup_can_install)" \
    "the plugins companions.md prefers" "the plugins setup installs"
}

test_both_readmes_name_exactly_the_companions_the_run_prefers() {
  local line
  line=$(companion_line_of_repo_readme)
  [ "$(printf '%s\n' "$line" | grep -c .)" -eq 1 ] ||
    fail "'companion skills (' no longer matches exactly one line of the repo README"
  assert_same_set "$(paths_the_run_prefers)" "$(companion_paths_in "$(optional_companions_paragraph)")" \
    "companions.md" "the plugin README"
  assert_same_set "$(paths_the_run_prefers)" "$(companion_paths_in "$line")" \
    "companions.md" "the repo README"
}

test_builtins_are_never_listed_as_installable() {
  local table
  reject_built_ins_in "$(install_table)" "setup's install table"
  reject_built_ins_in "$(optional_companions_paragraph)" "the plugin README's optional-companions paragraph"
  reject_built_ins_in "$(companion_region_of_repo_readme)" "the repo README's companion line"

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
