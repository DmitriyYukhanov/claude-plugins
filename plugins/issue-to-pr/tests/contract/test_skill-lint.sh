#!/usr/bin/env bash

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
  assert_contains "$checkpoint" 'batched question' "the checkpoint lost its batched question"
  assert_contains "$checkpoint" 'replaces' \
    "the checkpoint must say the grill REPLACES the batched question; one that grills and THEN asks spends two contacts"

  ask_contract=$(printf '%s\n' "$spine" | grep -A3 -i 'ask contract:')
  [ -n "$ask_contract" ] || fail "the spine no longer states the ask contract"
  case "$ask_contract" in
    *four*) fail "the ask contract promises a fourth moment again: $ask_contract" ;;
  esac
}

test_the_second_model_review_names_its_own_target() {
  local row step
  row=$(grep -i 'second-model review' "$(companions_md)")
  [ -n "$row" ] || fail "companions.md lost the Step 6 second-model review row"
  assert_contains "$row" 'cross-review' "the second-model row must name the capability it prefers"
  assert_contains "$row" '<CHANGED>'     "the second model must be handed the file list: its own target is a three-dot diff, empty
    until Step 7 commits, and an empty diff is where it stops to ask the user what to review"
  assert_contains "$row" '--max-rounds 1'     "one round only, so what it applies lands inside a single pass the ratchet counts"
  step=$(skill_step Review)
  assert_contains "$step" 'second' "the spine must say when the second model runs"
}

test_a_host_builtin_is_never_offered_as_an_install() {
  local setup companions offenders
  setup=$(cat "$(setup_md)")
  companions=$(cat "$(companions_md)")
  assert_contains "$setup" 'gh auth status' "setup.md did not load; this check would be vacuous"
  assert_contains "$companions" 'Inline fallback'     "companions.md did not load; this check would be vacuous"
  offenders=$(printf '%s
%s
' "$setup" "$companions" |
    grep -nE '(plugin (install|add)|marketplace add)' |
    grep -E 'code-review|simplify|verify|deep-research' || true)
  [ -z "$offenders" ] || fail "an install command is offered for a capability the host ships:
$offenders"
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

test_headless_is_one_flag_that_reshapes_two_contacts_and_adds_none() {
  local hl merge
  grep -q 'argument-hint:.*--headless' "$(skill_md)" || fail "argument-hint must advertise --headless"
  grep -q 'argument-hint:.*--auto-merge' "$(skill_md)" || fail "argument-hint must advertise --auto-merge"
  hl=$(cat "$(references_dir)/headless.md") || fail "R/headless.md missing"
  assert_contains "$hl" 'agent:waiting' "headless.md must name the label a posted question sets"
  assert_contains "$hl" 'agent:review'  "headless.md must name the label an unmerged PR sets"
  assert_contains "$hl" 'An **owner reply** is a comment by the owner' \
    "headless.md must say only the owner's comment continues a run"
  assert_contains "$hl" 'finish.sh merge <N> --branch <b> --auto' \
    "the self-merge must pass --auto so the script checks the tier and human paths"
  assert_contains "$hl" 'git status --porcelain' "a headless deploy must refuse a dirty main checkout"
  merge=$(skill_step Merge)
  assert_contains "$merge" 'Approval is never inferred' "the attended merge gate lost its closing rule"
  case "$hl" in *"fourth"* | *"four moments"*) fail "headless.md adds a contact moment" ;; esac
  case "$hl" in *"gh pr merge"*) fail "headless.md names a merge path other than finish.sh" ;; esac
}

test_attended_steps_read_as_in_the_previous_release() {
  local heads
  heads=$(grep -oE '^\*\*[0-9]+\. [A-Za-z ]+|^## Step [0-9]+ — [A-Za-z ]+' "$(skill_md)" | sed 's/\*\*//; s/ *$//')
  assert_eq "$(printf '%s\n' \
    '0. Resolve' \
    '1. Worktree' \
    '2. Design' \
    '3. Checkpoint' \
    '4. Build' \
    '5. Gates' \
    '6. Review and harden' \
    '7. PR and report' \
    '## Step 8 — Merge on approval' \
    '## Step 9 — Cleanup')" "$heads" \
    "the step names changed; headless was meant to add a path, not reshape a step"

  local ask checkpoint
  ask=$(awk '
    /^- \*\*Ask contract:\*\*/ { f = 1 }
    f && /^- / && !/^- \*\*Ask contract:\*\*/ { exit }
    f { print }
  ' "$(skill_md)")
  assert_contains "$ask" "three moments" \
    "the Hard-rules Ask contract bullet was reshaped away from its three fixed moments"
  assert_contains "$ask" "ONE batched question if the ledger has open items" \
    "the Hard-rules Ask contract bullet no longer names the single batched question"
  checkpoint=$(skill_step Checkpoint)
  assert_contains "$checkpoint" "the only mid-run question" \
    "Step 3 no longer closes on it being the only mid-run question"
}

test_headless_state_lives_in_marked_comments_on_the_issue() {
  local hl hard
  hl=$(cat "$(references_dir)/headless.md") || fail "R/headless.md missing"
  [ -n "$hl" ] || fail "R/headless.md came back empty; this check would be vacuous"
  assert_contains "$hl" '<!-- issue-to-pr state=waiting step=3 tier=standard pr=12 head=<sha> issue-read=<id> pr-read=<id> -->' \
    "the state marker's exact grammar is what agent-dispatch parses"
  assert_contains "$hl" 'gh api user --jq .login' "the owner must be defined by the login gh returns"
  assert_contains "$hl" 'ends with one marker line' "every posted comment must say its marker is the last line"
  assert_contains "$hl" 'a missing cursor counts as 0' "an absent issue-read/pr-read cursor must be pinned to 0"
  assert_contains "$hl" 'without a marker' "an owner reply is an unmarked comment"
  assert_contains "$hl" 'never moves it to a later id' "an edit must never make an old comment count as new"
  assert_contains "$hl" 'authorizes nothing' "a state comment by anyone but the owner must be ignored"
  assert_contains "$hl" '--add-label agent:running --remove-label agent,agent:waiting,agent:review,agent:failed' \
    "a run starts with one label edit, the same one the dispatcher makes"
  assert_contains "$hl" 'Post the state comment first' \
    "the label must move after the comment, or a dispatcher reads an old cursor"
  assert_contains "$hl" '## Re-entry' "headless.md lost its re-entry section"
  assert_contains "$hl" 'never self-merges' "a resumed run must merge only on the owner's word"
  assert_contains "$hl" 're-read both threads' "the run must look for a late reply before it parks"
  assert_not_contains "$hl" 'next prompt' "the reply no longer arrives as a prompt: every run starts fresh from GitHub"
  # shellcheck disable=SC2016 # the backticks are literal Markdown, not a command substitution
  assert_not_contains "$hl" 'flip back to `agent:running`' "a resumed run no longer flips back; its launcher already did"
  assert_not_contains "$hl" 'comment on the PR' "state comments live on the issue, never on the PR"
  assert_contains "$hl" 'no earlier owner state comment' \
    "the self-merge policy must hold back a run on an issue with any earlier state, not just a resumed one"
  assert_contains "$hl" '| Current state |' "re-entry is one transition table; the first matching row decides"
  assert_contains "$hl" 'a change request among the replies' \
    "a change request among several replies must win over a later merge word"
  assert_contains "$hl" 'no rebuild' "a failed state after the merge must not rebuild the merged work"
  assert_contains "$hl" 'step=9 pr=<pr>' "a post-merge failure must name the merged PR so a later run finds it"
  hard=$(awk '/^- \*\*Merge is gated/ { f = 1 } f && /^- / && !/^- \*\*Merge is gated/ { exit } f { print }' "$(skill_md)")
  assert_contains "$hard" 'owner reply' "the merge Hard rule must name the owner reply as the headless go-ahead"
  assert_contains "$hard" 'never self-merges' "the merge Hard rule must hold a resumed run back from self-merging"
}
