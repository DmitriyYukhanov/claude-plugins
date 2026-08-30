#!/usr/bin/env bash
# Contract tests for .githooks/pre-commit.
#
# The hook is the repo's only guard that fires before a bad commit exists, and the only one
# covering every plugin rather than this one. Nothing exercised it until now: the suite
# shellchecks `scripts/*.sh` and the fake gh, and no test ran the hook at all. That gap shipped
# a description-sync check whose sed had been mangled into a no-op, which guarded nothing.
#
# Each test builds a throwaway repo in its own TEST_TMPDIR and drives real `git commit`: what is
# under test is the hook's behaviour against a real index, not a function in isolation.
#
# The fixture carries TWO plugins, with the one under test second, and gives each an
# `"author": {"name": ...}` the way the real marketplace does. Both details are load-bearing.
# The hook selects an entry with an awk `found` flag that re-arms on every line containing
# `"name"`, so a single-plugin fixture with no nested name lets an awk that ignores the plugin
# name entirely pass every test here while comparing the wrong entry against the real file.

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

# A repo with two registered plugins, `foo` committed at 1.0.0, hook installed. Leaves cwd in it.
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

# Stage a version bump for `foo` with its changelog entry, so only the field under test can fail.
stage_bump() { # plugin_description marketplace_description
  plugin_json 1.1.0 "$1" > plugins/foo/.claude-plugin/plugin.json
  marketplace_json "$2" 1.1.0 > .claude-plugin/marketplace.json
  printf '# Changelog\n\n## [1.1.0] - 2026-01-02\n\n### Changed\n- second\n\n## [1.0.0] - 2026-01-01\n\n### Added\n- first\n' \
    > plugins/foo/CHANGELOG.md
  git add -A
}

# `git commit` must fail, and fail for the stated reason. Asserting only that it exited non-zero
# passes on any unrelated hook error, which is how a guard ends up proving nothing.
# The trailing `case` also gives the function its exit status: the harness runs tests without
# `set -e`, so whatever runs last decides, and an `&&` list must never be that last thing.
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

# Fail closed. A renamed entry used to take the version check down with it, so a commit could
# change both fields and report nothing at all.
test_hook_rejects_a_marketplace_entry_that_no_longer_answers_to_the_name() {
  fixture_repo "Does the original thing."
  stage_bump "Does the NEW thing." "Does the NEW thing."
  sed -i 's/"name": "foo"/"name": "foo-renamed"/' .claude-plugin/marketplace.json
  git add -A
  refuse_commit renamed "no entry in"
}

# Both sides empty compare equal, which is the one path that would sail through in silence.
test_hook_rejects_a_plugin_manifest_with_no_description_at_all() {
  fixture_repo "Does the original thing."
  stage_bump "Does the NEW thing." "Does the NEW thing."
  printf '{\n  "name": "foo",\n  "version": "1.1.0",\n  "author": { "name": "Test" }\n}\n' \
    > plugins/foo/.claude-plugin/plugin.json
  sed -i '/"description": "Does the NEW thing."/d' .claude-plugin/marketplace.json
  git add -A
  refuse_commit stripped "no description found"
}

# The guard has to let real work through, or it gets bypassed with --no-verify and guards nothing.
# This is also the test that kills an entry-selection bug: with `foo` second in the marketplace,
# an extraction that ignores the name compares aaa-decoy's description here and goes red.
test_hook_accepts_a_bump_whose_manifests_agree() {
  local out
  fixture_repo "Does the original thing."
  stage_bump "Does the NEW thing." "Does the NEW thing."

  out=$(git commit -m agreed 2>&1) || fail "the hook blocked a correct commit:
$out"
  git log --oneline | grep -q agreed || fail "commit reported success but nothing landed"
}

# A brand-new plugin has no marketplace entry yet and no manifest in HEAD. Check 4 owns that and
# says the right thing; the sync check must stay quiet rather than report a rename of something
# that never existed. This branch shipped once already saying exactly that.
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
  # Demand Check 4's own words. "It exited non-zero" also describes the hook dying on an
  # unguarded `set -e`, which is exactly how the first cut of this branch failed: every
  # new-plugin commit was rejected with no message at all, and a laxer assertion passed on it.
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
