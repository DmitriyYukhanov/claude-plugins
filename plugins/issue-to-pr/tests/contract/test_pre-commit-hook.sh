#!/usr/bin/env bash

hook_src() { printf '%s' "$ITP_SCRIPTS/../../../.githooks/pre-commit"; }

marketplace_json() { # foo_description
  cat <<EOF
{
  "plugins": [
    {
      "name": "aaa-decoy",
      "description": "A different plugin that sorts first and must never be the one compared.",
      "version": "9.9.9",
      "author": { "name": "Someone Else" }
    },
    {
      "name": "foo",
      "description": "$1",
      "version": "$2",
      "author": { "name": "Test" }
    }
  ]
}
EOF
}

plugin_json() { # version description
  cat <<EOF
{
  "name": "foo",
  "version": "$1",
  "description": "$2",
  "author": { "name": "Test" }
}
EOF
}

fixture_repo() { # foo_description
  local desc=${1:?description}
  [ -f "$(hook_src)" ] || fail "the hook is missing at $(hook_src)"

  git init -q -b main .
  git config user.email t@example.com
  git config user.name Test
  git config core.hooksPath .githooks
  git config commit.gpgsign false

  mkdir -p .githooks .claude-plugin plugins/foo/.claude-plugin plugins/aaa-decoy/.claude-plugin
  cp "$(hook_src)" .githooks/pre-commit
  chmod +x .githooks/pre-commit

  plugin_json 1.0.0 "$desc" > plugins/foo/.claude-plugin/plugin.json
  printf '# Changelog\n\n## [1.0.0] - 2026-01-01\n\n### Added\n- first\n' > plugins/foo/CHANGELOG.md
  printf '{\n  "name": "aaa-decoy",\n  "version": "9.9.9",\n  "description": "A different plugin that sorts first and must never be the one compared.",\n  "author": { "name": "Someone Else" }\n}\n' \
    > plugins/aaa-decoy/.claude-plugin/plugin.json
  printf '# Changelog\n\n## [9.9.9] - 2026-01-01\n\n### Added\n- decoy\n' > plugins/aaa-decoy/CHANGELOG.md
  marketplace_json "$desc" 1.0.0 > .claude-plugin/marketplace.json
  printf '# Repo\n\nfoo, aaa-decoy\n' > README.md

  git add -A
  git commit -q --no-verify -m seed
}

stage_bump() { # plugin_description marketplace_description
  plugin_json 1.1.0 "$1" > plugins/foo/.claude-plugin/plugin.json
  marketplace_json "$2" 1.1.0 > .claude-plugin/marketplace.json
  printf '# Changelog\n\n## [1.1.0] - 2026-01-02\n\n### Changed\n- second\n\n## [1.0.0] - 2026-01-01\n\n### Added\n- first\n' \
    > plugins/foo/CHANGELOG.md
  git add -A
}

refuse_commit() { # message reason_substring
  local out
  if out=$(git commit -m "${1}" 2>&1); then
    fail "the hook allowed the commit it had to stop:
$out"
  fi
  case "$out" in
    *"$2"*) : ;;
    *) fail "rejected, but not for '$2'. Got:
$out" ;;
  esac
}

test_hook_rejects_a_description_that_drifted_from_the_marketplace() {
  fixture_repo "Does the original thing."
  stage_bump "Does the NEW thing." "Does the original thing."
  refuse_commit drift "descriptions differ"
}

test_hook_rejects_a_marketplace_entry_that_no_longer_answers_to_the_name() {
  fixture_repo "Does the original thing."
  stage_bump "Does the NEW thing." "Does the NEW thing."
  sed -i 's/"name": "foo"/"name": "foo-renamed"/' .claude-plugin/marketplace.json
  git add -A
  refuse_commit renamed "no entry in"
}

test_hook_rejects_a_plugin_manifest_with_no_description_at_all() {
  fixture_repo "Does the original thing."
  stage_bump "Does the NEW thing." "Does the NEW thing."
  printf '{\n  "name": "foo",\n  "version": "1.1.0",\n  "author": { "name": "Test" }\n}\n' \
    > plugins/foo/.claude-plugin/plugin.json
  sed -i '/"description": "Does the NEW thing."/d' .claude-plugin/marketplace.json
  git add -A
  refuse_commit stripped "no description found"
}

test_hook_accepts_a_bump_whose_manifests_agree() {
  local out
  fixture_repo "Does the original thing."
  stage_bump "Does the NEW thing." "Does the NEW thing."

  out=$(git commit -m agreed 2>&1) || fail "the hook blocked a correct commit:
$out"
  assert_eq agreed "$(git log -1 --format=%s)" "commit reported success but nothing landed"
}

test_hook_holds_main_to_a_version_bump() {
  fixture_repo "Does the original thing."
  printf 'notes\n' > plugins/foo/notes.md
  git add plugins/foo/notes.md
  refuse_commit unbumped "Plugin version bump required"
}

test_hook_rejects_a_version_mismatch_on_a_feature_branch() {
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  plugin_json 1.1.0 "Does the original thing." > plugins/foo/.claude-plugin/plugin.json
  marketplace_json "Does the original thing." 1.2.0 > .claude-plugin/marketplace.json
  git add -A
  refuse_commit mismatch "plugin.json=1.1.0, marketplace.json=1.2.0"
}

test_hook_lets_a_feature_branch_commit_without_a_bump() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  printf 'notes\n' > plugins/foo/notes.md
  git add plugins/foo/notes.md
  out=$(git commit -m wip 2>&1) || fail "the hook held a feature-branch commit to a version bump:
$out"
  assert_eq wip "$(git log -1 --format=%s)" "commit reported success but nothing landed"
}

test_hook_leaves_an_unregistered_new_plugin_to_check_4() {
  local out
  fixture_repo "Does the original thing."

  mkdir -p plugins/newthing/.claude-plugin
  printf '{\n  "name": "newthing",\n  "version": "1.0.0",\n  "description": "Brand new."\n}\n' \
    > plugins/newthing/.claude-plugin/plugin.json
  printf '# Changelog\n\n## [1.0.0] - 2026-01-02\n\n### Added\n- first\n' > plugins/newthing/CHANGELOG.md
  git add -A

  if out=$(git commit -m newplugin 2>&1); then
    fail "an unregistered new plugin was allowed through:
$out"
  fi
  case "$out" in
    *"New plugin missing from marketplace.json"*) : ;;
    *) fail "rejected, but Check 4 never spoke. Got:
$out" ;;
  esac
  case "$out" in
    *"no entry in"*) fail "the sync check reported a rename of a plugin that never had an entry:
$out" ;;
  esac
}


test_ci_checks_committed_feature_changes_without_touching_the_index() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  printf 'notes\n' > plugins/foo/notes.md
  git add plugins/foo/notes.md
  git commit -q --no-verify -m work
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then
    fail "CI allowed a committed PR without a bump: $out"
  fi
  assert_contains "$out" 'Plugin version bump required'
  assert_eq '' "$(git diff --cached --name-only)" "CI must preserve the index"
}

test_ci_checks_changelog_and_sync_across_the_whole_pr() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  stage_bump "Does the NEW thing." "Does the NEW thing."
  git restore --staged --worktree plugins/foo/CHANGELOG.md
  git commit -q --no-verify -m bump
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI allowed no changelog: $out"; fi
  assert_contains "$out" 'CHANGELOG.md update required'
  stage_bump "Does the NEW thing." "Does the NEW thing."
  git commit -q --no-verify -m changelog
  out=$(bash "$(hook_src)" --ci main HEAD 2>&1) || fail "CI rejected split bookkeeping: $out"
  marketplace_json "Does the NEW thing." 1.2.0 > .claude-plugin/marketplace.json
  git add .claude-plugin/marketplace.json
  git commit -q --no-verify -m mismatch
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI allowed drift: $out"; fi
  assert_contains "$out" 'plugin.json=1.1.0, marketplace.json=1.2.0'
}


test_ci_requires_a_dated_heading_for_the_exact_new_version() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  stage_bump "Does the NEW thing." "Does the NEW thing."
  printf '# Changelog\n\n## [1x1x0] - 2026-01-02\n' > plugins/foo/CHANGELOG.md
  git add plugins/foo/CHANGELOG.md
  git commit -q --no-verify -m wrong-heading
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI accepted another heading: $out"; fi
  assert_contains "$out" 'missing entry for [1.1.0]'
  printf '# Changelog\n\nMention [1.1.0] without a release heading.\n' > plugins/foo/CHANGELOG.md
  git add plugins/foo/CHANGELOG.md
  git commit -q --no-verify -m mention
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI accepted a mention as a release: $out"; fi
  assert_contains "$out" 'missing entry for [1.1.0]'
}


test_ci_rejects_downgrades_and_manifest_only_changes_without_a_bump() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  plugin_json 1.0.0 "Does the NEW thing." > plugins/foo/.claude-plugin/plugin.json
  marketplace_json "Does the NEW thing." 1.0.0 > .claude-plugin/marketplace.json
  git add plugins/foo/.claude-plugin/plugin.json .claude-plugin/marketplace.json
  git commit -q --no-verify -m manifest-only
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI allowed no bump: $out"; fi
  assert_contains "$out" 'Plugin version bump required'
  plugin_json 0.9.0 "Does the NEW thing." > plugins/foo/.claude-plugin/plugin.json
  marketplace_json "Does the NEW thing." 0.9.0 > .claude-plugin/marketplace.json
  printf '# Changelog\n\n## [0.9.0] - 2026-01-02\n' > plugins/foo/CHANGELOG.md
  git add plugins/foo/.claude-plugin/plugin.json .claude-plugin/marketplace.json plugins/foo/CHANGELOG.md
  git commit -q --no-verify -m downgrade
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI allowed a downgrade: $out"; fi
  assert_contains "$out" 'Plugin version bump required'
}


test_ci_checks_a_plugin_when_git_quotes_its_changed_path() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  printf 'notes\n' > plugins/foo/café.md
  git add plugins/foo/café.md
  git commit -q --no-verify -m quoted-path
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI missed a quoted path: $out"; fi
  assert_contains "$out" 'Plugin version bump required'
}

test_ci_allows_whole_plugin_removal_but_not_just_its_manifest() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  git rm -q plugins/foo/.claude-plugin/plugin.json
  git commit -q --no-verify -m remove-manifest
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI allowed a missing manifest: $out"; fi
  assert_contains "$out" 'Plugin manifest missing'
  git rm -q plugins/foo/CHANGELOG.md
  git commit -q --no-verify -m remove-plugin
  out=$(bash "$(hook_src)" --ci main HEAD 2>&1) || fail "CI blocked a removed plugin: $out"
}

test_ci_rejects_marketplace_only_drift() {
  local out
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  marketplace_json "Does the original thing." 1.1.0 > .claude-plugin/marketplace.json
  git add .claude-plugin/marketplace.json
  git commit -q --no-verify -m marketplace-only
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI allowed marketplace drift: $out"; fi
  assert_contains "$out" 'plugin.json=1.0.0, marketplace.json=1.1.0'
}


test_ci_rejects_missing_marketplace_metadata() {
  local out mode allowed=''
  fixture_repo "Does the original thing."
  git switch -q -c feat/work
  for mode in version empty deleted; do
    marketplace_json "Does the original thing." 1.0.0 > .claude-plugin/marketplace.json
    case "$mode" in
      version) sed -i '/"version": "1.0.0"/d' .claude-plugin/marketplace.json ;;
      empty) : > .claude-plugin/marketplace.json ;;
      deleted) rm -- .claude-plugin/marketplace.json ;;
    esac
    git add .claude-plugin/marketplace.json
    git commit -q --no-verify -m "missing-$mode"
    if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then allowed="$allowed $mode"
    else assert_contains "$out" 'marketplace.json'; fi
  done
  [ -z "$allowed" ] || fail "CI allowed missing marketplace metadata:$allowed"
}


test_ci_checks_changed_entries_without_blocking_unrelated_baseline_drift() {
  local out
  fixture_repo "Does the original thing."
  sed -i 's/"version": "9.9.9"/"version": "9.9.8"/' .claude-plugin/marketplace.json
  git add .claude-plugin/marketplace.json
  git commit -q --no-verify -m baseline-drift
  git switch -q -c feat/work
  stage_bump "Does the NEW thing." "Does the NEW thing."
  sed -i 's/"version": "9.9.9"/"version": "9.9.8"/' .claude-plugin/marketplace.json
  git add .claude-plugin/marketplace.json
  git commit -q --no-verify -m foo-bump
  out=$(bash "$(hook_src)" --ci main HEAD 2>&1) || fail "CI blocked unrelated baseline drift: $out"
  sed -i 's/"version": "9.9.8"/"version": "9.9.7"/' .claude-plugin/marketplace.json
  git add .claude-plugin/marketplace.json
  git commit -q --no-verify -m changed-decoy
  if out=$(bash "$(hook_src)" --ci main HEAD 2>&1); then fail "CI allowed new drift: $out"; fi
  assert_contains "$out" 'plugin.json=9.9.9, marketplace.json=9.9.7'
}
