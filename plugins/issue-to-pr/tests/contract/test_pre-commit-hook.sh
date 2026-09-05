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

  git init -q .
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
  git log --oneline | grep -q agreed || fail "commit reported success but nothing landed"
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
