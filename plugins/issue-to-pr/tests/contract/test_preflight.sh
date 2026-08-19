#!/usr/bin/env bash
# Contract tests for scripts/preflight.sh (spec §4.1).

test_preflight_missing_issue_degrades() {
  use_fake_gh happy
  run_script preflight.sh
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-issue
}

test_preflight_auth_fail_stops() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh auth-fail
  run_script preflight.sh 6
  assert_rc 2
  assert_key "$OUT" GH_OK false
  assert_key "$OUT" STOP_REASON gh-auth-failed
}

test_preflight_happy_basics() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" GH_OK true
  assert_key "$OUT" OWNER octo-owner
  assert_key "$OUT" REPO demo-repo
  assert_key "$OUT" DEFAULT_BRANCH main
  assert_key "$OUT" BASE main
  assert_key "$OUT" START_POINT main
  assert_key "$OUT" ISSUE_STATE OPEN
  assert_key "$OUT" ISSUE_TITLE "Demo issue"
  assert_key "$OUT" WORKTREE_STATE absent
  assert_key "$OUT" BOARD_CONFIGURED false
}

test_preflight_scopes_parsed() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" SCOPES "gist,project,read:org,repo,workflow"
}

test_preflight_config_overrides_and_base() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  cat >.claude/issue-to-pr.local.md <<'EOF'
---
base_branch: dev
test_cmd: pnpm test
typecheck_cmd: pnpm typecheck
---
Human notes below the frontmatter, ignored by the parser.
EOF
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" BASE dev
  assert_key "$OUT" CMD_TEST "pnpm test"
  assert_key "$OUT" CMD_TYPECHECK "pnpm typecheck"
  assert_key "$OUT" CMD_SOURCE_TEST config
  assert_key "$OUT" CONFIG_PRESENT true
}

test_preflight_config_nested_commands_alias() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  cat >.claude/issue-to-pr.local.md <<'EOF'
---
commands:
  test: yarn test
  typecheck: yarn tsc
---
EOF
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" CMD_TEST "yarn test"
  assert_key "$OUT" CMD_TYPECHECK "yarn tsc"
}

test_preflight_crlf_config_is_parsed() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  # Write the config with CRLF line endings (Windows editor default).
  printf -- '---\r\nbase_branch: dev\r\ntest_cmd: pnpm test\r\n---\r\n' >.claude/issue-to-pr.local.md
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" BASE dev
  assert_key "$OUT" CMD_TEST "pnpm test"
}

test_preflight_status_map_is_parsed() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  cat >.claude/issue-to-pr.local.md <<'EOF'
---
board:
  url: https://github.com/orgs/x/projects/1
  status_map:
    in_progress: Dev In Progress
    in_review: Ready For Review
---
EOF
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" STATUS_MAP_IN_PROGRESS "Dev In Progress"
  assert_key "$OUT" STATUS_MAP_IN_REVIEW "Ready For Review"
}

test_preflight_malformed_config_degrades() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  cat >.claude/issue-to-pr.local.md <<'EOF'
---
this line has no key and is not valid frontmatter !!!
---
EOF
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON config-parse-failed
}

test_preflight_autodetect_package_json() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  cat >package.json <<'EOF'
{ "scripts": { "test": "jest", "typecheck": "tsc --noEmit", "test:visual": "playwright test" } }
EOF
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" CMD_TEST "npm test"
  assert_key "$OUT" CMD_TYPECHECK "npm run typecheck"
  assert_key "$OUT" CMD_VISUAL "npm run test:visual"
  assert_key "$OUT" CMD_SOURCE_TEST package.json
}

test_preflight_base_auto_detects_remote_dev() {
  local repo
  repo=$(init_repo_with_remote dev)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE dev
  assert_key "$OUT" START_POINT origin/dev
}

# Regression: `ls-remote --heads origin dev` fnmatches the TAIL of a ref name on
# slash boundaries, so a repo with only `release/dev` answered yes and the whole
# run was cut from a branch that does not exist.
test_preflight_base_auto_ignores_a_branch_merely_ending_in_dev() {
  local repo
  repo=$(init_repo_with_remote release/dev)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE main
}

# The remote answered and has no dev: that is evidence, and the default branch wins.
test_preflight_base_auto_uses_default_when_remote_has_no_dev() {
  local repo
  repo=$(init_repo_with_remote)
  cd "$repo"
  git branch dev
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE main
  assert_contains "$OUT" "local 'dev' exists but origin has no 'dev'"
}

# Regression: when origin cannot be reached, a stale remote-tracking ref is a guess.
# Using it is fine; reporting it as remote-confirmed re-armed the deleted-dev trap.
test_preflight_base_auto_marks_an_unreachable_remote_as_unverified() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  git update-ref refs/remotes/origin/dev HEAD
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE dev
  assert_contains "$OUT" "could not reach origin"
}

# Regression: a `dev` that exists only locally is what is left behind after its
# remote is deleted post-merge. It looks like a trunk and is arbitrarily stale, so
# `auto` must ignore it and fall back to the repository's real default branch.
test_preflight_base_auto_ignores_local_only_dev() {
  local repo
  repo=$(init_repo_with_remote)
  cd "$repo"
  git branch dev
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE main
}

test_preflight_detects_shell_test_harness() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p tests
  printf '#!/usr/bin/env bash\n' >tests/run-tests.sh
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST "bash tests/run-tests.sh"
  assert_key "$OUT" CMD_SOURCE_TEST tests/run-tests.sh
}

# Regression: every gate-command probe ran against the caller's cwd while repo
# identity, the config and the worktree state all resolved against the repository
# root, so a run from any subdirectory reported no test command for a project that
# has one - and Step 6 then had nothing to verify the work with.
test_preflight_detects_the_harness_from_a_subdirectory() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p tests sub/deeper
  printf '#!/usr/bin/env bash\n' >tests/run-tests.sh
  cd sub/deeper
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST "bash tests/run-tests.sh"
}

test_preflight_detects_package_json_from_a_subdirectory() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  printf '%s\n' '{ "scripts": { "test": "jest" } }' >package.json
  mkdir -p sub
  cd sub
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST "npm test"
  assert_key "$OUT" CMD_SOURCE_TEST package.json
}

# A plugin or package monorepo keeps its runner under the project, not at the top. The
# path is emitted bare, and only when nothing in it could change how a shell reads it.
test_preflight_finds_a_nested_harness() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p plugins/foo/tests
  printf '#!/usr/bin/env bash\n' >plugins/foo/tests/run-tests.sh
  git add plugins/foo/tests/run-tests.sh
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST "bash plugins/foo/tests/run-tests.sh"
  assert_key "$OUT" CMD_SOURCE_TEST plugins/foo/tests/run-tests.sh
}

# Two runners are ambiguous ON PURPOSE. Assembling a command from both cannot be honest
# here: Step 0 probes this checkout while the gates run in a worktree cut from
# origin/$base afterwards, so an enumeration can disagree with the tree under test, and
# one stale link either hides a red suite or kills the whole command. No command means
# Step 6 degrades loudly and pin-config names the right one (#23).
test_preflight_two_nested_harnesses_stay_ambiguous() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p plugins/a/tests plugins/b/tests
  printf '#!/usr/bin/env bash\n' >plugins/a/tests/run-tests.sh
  printf '#!/usr/bin/env bash\n' >plugins/b/tests/run-tests.sh
  git add plugins/a/tests/run-tests.sh plugins/b/tests/run-tests.sh
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST ""
  assert_key "$OUT" CMD_SOURCE_TEST none
}

# An untracked runner is not in the worktree the gates run in, so a command naming it
# would die there at 127 on a repository whose own suite is fine.
test_preflight_untracked_nested_harness_is_not_used() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p plugins/foo/tests
  printf '#!/usr/bin/env bash\n' >plugins/foo/tests/run-tests.sh
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST ""
}

# A runner at the top is the repository's entry point, so it wins outright and the search
# below it never happens - not even for a tracked one.
test_preflight_root_harness_wins_over_nested_ones() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p tests plugins/foo/tests
  printf '#!/usr/bin/env bash\n' >tests/run-tests.sh
  printf '#!/usr/bin/env bash\n' >plugins/foo/tests/run-tests.sh
  git add plugins/foo/tests/run-tests.sh
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST "bash tests/run-tests.sh"
}

# Regression: the config path was the last cwd-relative read left in the script, and it
# outranks auto-detect - so a run from a subdirectory found no config, silently swapped
# the pinned test command for a guess, and lost the pinned base branch with it. The
# package.json is here so a regression shows up as `npm test`, not as an empty value.
test_preflight_reads_the_config_from_a_subdirectory() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude sub
  printf -- '---\nbase_branch: dev\ntest_cmd: make ci\n---\n' >.claude/issue-to-pr.local.md
  printf '%s\n' '{ "scripts": { "test": "jest" } }' >package.json
  cd sub
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CONFIG_PRESENT true
  assert_key "$OUT" CMD_TEST "make ci"
  assert_key "$OUT" CMD_SOURCE_TEST config
  assert_key "$OUT" BASE dev
}

# SECURITY. The detected command is evaluated by `bash -c` in run-gates.sh, so a tracked
# directory named `$(...)` used to execute at gate time on any repository merely cloned
# and taken through Step 0. Reproduced against the double-quoted form this replaced.
test_preflight_nested_harness_path_cannot_inject_a_command() {
  local repo cmd
  repo=$(init_repo)
  cd "$repo"
  mkdir -p 'plugins/$(touch PWNED)/tests'
  printf '#!/usr/bin/env bash\n' >'plugins/$(touch PWNED)/tests/run-tests.sh'
  git add 'plugins/$(touch PWNED)/tests/run-tests.sh'
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST ""
  cmd=$(printf '%s\n' "$OUT" | grep -m1 '^CMD_TEST=' | sed 's/^CMD_TEST=//')
  bash -c "$cmd" >/dev/null 2>&1
  if [ -e PWNED ]; then fail "the detected command executed a substitution from a path"; fi
}

# A path that needs quoting to be one argument is left undetected instead. The value is
# evaluated twice (bash -c, and Step 6's --gate test='<cmd>' wrapper), so no quoting
# scheme survives both; not detecting is the honest outcome and pin-config names it.
test_preflight_nested_harness_with_a_space_is_not_used() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p "my proj/tests"
  printf '#!/usr/bin/env bash\n' >"my proj/tests/run-tests.sh"
  git add "my proj/tests/run-tests.sh"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST ""
}

# An explicit --config is the caller's instruction and stays relative to the caller; only
# the default path is re-rooted. Re-rooting both would hand a caller standing in a
# subdirectory with a real ./custom.md the auto-detected commands instead of their own.
test_preflight_explicit_relative_config_stays_relative_to_the_caller() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p sub
  printf -- '---\ntest_cmd: from sub\n---\n' >sub/custom.md
  printf -- '---\ntest_cmd: from root\n---\n' >custom.md
  cd sub
  use_fake_gh happy
  run_script preflight.sh 6 --config custom.md
  assert_key "$OUT" CMD_TEST "from sub"
}

# Regression: a `check:`-only Makefile (the GNU spelling) reported `make typecheck`,
# which make refuses for want of such a rule - a red gate on a healthy repository, with
# nothing to tell the model the command had been invented rather than read.
test_preflight_makefile_check_target_is_reported_as_itself() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  printf 'check:\n\t@true\n' >Makefile
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TYPECHECK "make check"
}

# Regression: the search read the working tree, so a gitignored scratch project's runner
# was taken as a suite of this repository. It is absent from the worktree the gates run
# in, so the gate died at 127 - and sorting first, it also kept the real suite from
# running. It is not tracked, so it is not a candidate now, and the real one still is.
test_preflight_ignores_a_gitignored_project() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  printf 'aaa-sandbox/\n' >.gitignore
  mkdir -p aaa-sandbox/tests plugins/real/tests
  printf '#!/usr/bin/env bash\n' >aaa-sandbox/tests/run-tests.sh
  printf '#!/usr/bin/env bash\n' >plugins/real/tests/run-tests.sh
  git add plugins/real/tests/run-tests.sh
  use_fake_gh happy
  run_script preflight.sh 6
  assert_not_contains "$OUT" aaa-sandbox
  assert_key "$OUT" CMD_TEST "bash plugins/real/tests/run-tests.sh"
}

# Regression: anchoring the probes to "whatever tree cwd is in" meant that starting a run
# for issue 9 from issue 5's worktree gated issue 9 on a project that exists only on
# issue 5's branch - while the same script reported issue 9's own worktree as absent.
test_preflight_never_probes_a_foreign_worktree() {
  local repo other
  repo=$(init_repo)
  cd "$repo"
  mkdir -p tests
  printf '#!/usr/bin/env bash\n' >tests/run-tests.sh
  git -C "$repo" worktree add "$TEST_TMPDIR/repo-worktrees/issue-5" -b feat/issue-5-x HEAD >/dev/null 2>&1
  other="$TEST_TMPDIR/repo-worktrees/issue-5"
  mkdir -p "$other/newpkg/tests"
  printf '#!/usr/bin/env bash\n' >"$other/newpkg/tests/run-tests.sh"
  cd "$other"
  use_fake_gh happy
  run_script preflight.sh 9
  assert_key "$OUT" CMD_TEST "bash tests/run-tests.sh"
  assert_not_contains "$OUT" newpkg
}

test_preflight_worktree_resumable() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  git -C "$repo" worktree add "$TEST_TMPDIR/repo-worktrees/issue-6" -b feat/issue-6-x HEAD >/dev/null 2>&1
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" WORKTREE_STATE resumable
}

test_preflight_claim_assigns_when_free() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6 --claim
  assert_rc 0
  assert_gh_called "issue edit 6 --add-assignee @me"
}

test_preflight_claim_warns_when_assigned_other() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh assigned-other
  run_script preflight.sh 6 --claim
  assert_rc 0
  assert_key "$OUT" WARN_CLAIMED_BY someone-else
  assert_gh_not_called "add-assignee"
}

test_preflight_board_scope_missing_warns() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  cat >.claude/issue-to-pr.local.md <<'EOF'
---
board:
  url: https://github.com/orgs/x/projects/1
  status_field: Status
---
EOF
  use_fake_gh scope-missing
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" BOARD_CONFIGURED true
  assert_contains "$OUT" "project"
}

test_preflight_non_numeric_issue_degrades() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh '6/../../evil'
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON invalid-issue
}






test_preflight_worktree_state_uses_the_main_checkout() {
  local repo wt
  repo=$(init_repo)
  cd "$repo"
  git -C "$repo" worktree add "$TEST_TMPDIR/repo-worktrees/issue-6" -b feat/issue-6-x HEAD >/dev/null 2>&1
  wt="$TEST_TMPDIR/repo-worktrees/issue-6"
  cd "$wt"
  use_fake_gh happy
  run_script preflight.sh 6
  # From inside the worktree, `git rev-parse --show-toplevel` would return the
  # worktree itself and report its own worktree as absent.
  assert_key "$OUT" WORKTREE_STATE resumable
}



# Regression: a Step-0 probe the model runs on every task must not delete the
# user's remote-tracking refs as a side effect.
test_preflight_does_not_prune_remote_refs() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  git update-ref refs/remotes/origin/some-old-branch HEAD
  use_fake_gh happy
  run_script preflight.sh 6
  if git show-ref --verify --quiet refs/remotes/origin/some-old-branch; then :; else
    fail "preflight pruned a remote-tracking ref"
  fi
}





# Regression: batching state/title/assignees into one gh call with `--jq '...|@tsv'`
# ran the values through jq's TSV encoder, which doubles a backslash and turns a tab
# into the two characters `\t`. `read -r` is raw by definition and never undoes it,
# so an issue titled `Fix C:\Users\foo path bug` arrived as `C:\\Users\\foo` - and
# that string is what names the branch, the PR and the design panel's prompt. One
# field per line carries the value through untouched.
test_preflight_issue_title_survives_a_backslash() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh backslash-title
  run_script preflight.sh 6
  assert_key "$OUT" ISSUE_TITLE 'Fix C:\Users\foo path bug'
}

# Regression: the probe fetches only the base ref, so on a single-branch clone the
# default branch has no local ref — and cmd_cleanup's in-place path runs
# `git switch <default>` to get off the feature branch before deleting it. Without
# the ref that switch fails and cleanup silently ends on a detached HEAD. Both
# refspecs ride the same connection, so this costs no extra round trip.
test_preflight_fetches_the_default_branch_too() {
  local repo
  repo=$(init_repo_with_remote dev)
  cd "$repo"
  git update-ref -d refs/remotes/origin/main 2>/dev/null || true
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE dev
  if git show-ref --verify --quiet refs/remotes/origin/main; then :; else
    fail "the default branch was not fetched; in-place cleanup would end detached"
  fi
}

# Regression: `git fetch` fails the WHOLE invocation the moment any one refspec names
# a ref the remote does not have, so batching the base and the default branch into one
# call let a default branch that is absent on THIS origin (a fork, a mirror, a renamed
# trunk) take the base ref down with it - and Step 1 then hard-stops at
# invalid-start-point on a base that ls-remote had just confirmed is there.
test_preflight_fetches_the_base_when_the_default_branch_is_missing_on_origin() {
  local repo
  repo=$(init_repo_with_remote dev)
  cd "$repo"
  # gh still reports defaultBranchRef=main; this origin no longer has it. update-ref
  # on the bare repo rather than `push --delete`, which refuses to drop remote HEAD.
  git -C "$TEST_TMPDIR/remote.git" update-ref -d refs/heads/main
  git update-ref -d refs/remotes/origin/dev 2>/dev/null || true
  git update-ref -d refs/remotes/origin/main 2>/dev/null || true
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE dev
  assert_key "$OUT" START_POINT origin/dev
  if git show-ref --verify --quiet refs/remotes/origin/dev; then :; else
    fail "a missing default branch took the base ref down with it"
  fi
}

# -- state directory: config location, migration, marker sweep (issue #18) ----

test_preflight_reads_the_canonical_config() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude/issue-to-pr
  printf -- '---\nbase_branch: dev\ntest_cmd: make ci\n---\n' >.claude/issue-to-pr/config.md
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" CONFIG_PRESENT true
  assert_key "$OUT" CMD_TEST "make ci"
  assert_key "$OUT" BASE dev
}

# A project that pinned its config before the state directory existed keeps working: the
# old sibling file is copied in on the first run and LEFT where it is, so nothing breaks
# if the user rolls the plugin back. Deleting it is their call, and the warning says so.
test_preflight_migrates_the_legacy_config() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  printf -- '---\ntest_cmd: legacy cmd\n---\n' >.claude/issue-to-pr.local.md
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 0
  assert_key "$OUT" CMD_TEST "legacy cmd"
  [ -f "$repo/.claude/issue-to-pr/config.md" ] || fail "the config was not copied to the state dir"
  [ -f "$repo/.claude/issue-to-pr.local.md" ] || fail "the original was removed instead of left alone"
  assert_contains "$OUT" "issue-to-pr.local.md"
}

test_preflight_canonical_config_wins_over_the_legacy_one() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude/issue-to-pr
  printf -- '---\ntest_cmd: canonical\n---\n' >.claude/issue-to-pr/config.md
  printf -- '---\ntest_cmd: legacy\n---\n' >.claude/issue-to-pr.local.md
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST canonical
}

# Whatever writes into the state directory first has to leave the ignore rule behind, or
# the copied config lands in the repository as an untracked file nobody recognises.
test_preflight_migration_leaves_the_state_dir_ignoring_itself() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  printf -- '---\ntest_cmd: legacy cmd\n---\n' >.claude/issue-to-pr.local.md
  use_fake_gh happy
  run_script preflight.sh 6
  [ -f "$repo/.claude/issue-to-pr/.gitignore" ] || fail "the state dir does not ignore itself"
}

test_preflight_sweeps_an_expired_approval_marker() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  write_marker "$repo" feat/old "aaaa" false "$(stale_iso)"
  use_fake_gh happy
  run_script preflight.sh 6
  if [ -f "$repo/.claude/issue-to-pr/approval-feat-old.json" ]; then
    fail "an expired marker was left behind"
  fi
}

test_preflight_keeps_a_fresh_approval_marker() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  write_marker "$repo" feat/live "aaaa" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_script preflight.sh 6
  [ -f "$repo/.claude/issue-to-pr/approval-feat-live.json" ] || fail "a fresh approval was swept"
}

# Regression the issue names: epoch_of returns EMPTY for a timestamp it cannot read, and
# treating that as "infinitely old" swept every live approval in the repository at once
# on macOS, where the GNU date form fails. Unreadable means leave it alone.
test_preflight_never_sweeps_a_marker_it_cannot_date() {
  local repo m
  repo=$(init_repo)
  cd "$repo"
  # Through the shared fixture, not a third hand-rolled copy of the marker JSON: the
  # helper exists because two independent copies had already drifted apart once.
  write_marker "$repo" feat/undated aaaa false not-a-date
  m="$repo/.claude/issue-to-pr/approval-feat-undated.json"
  use_fake_gh happy
  run_script preflight.sh 6
  [ -f "$m" ] || fail "a marker with an unreadable timestamp was swept"
}

# A tracked legacy config is a TEAM's file. Copying it into a directory that ignores
# itself would give every developer a private, frozen snapshot, and a base_branch or
# board change pushed to the tracked file would never be read again on a machine that
# had migrated. So it is left alone and it stays the file in force.
test_preflight_does_not_migrate_a_tracked_legacy_config() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  printf -- '---\ntest_cmd: team cmd\n---\n' >.claude/issue-to-pr.local.md
  git add .claude/issue-to-pr.local.md
  git commit -qm "share the config"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST "team cmd"
  if [ -f "$repo/.claude/issue-to-pr/config.md" ]; then
    fail "a tracked config was copied into the per-developer state dir"
  fi
  assert_contains "$OUT" "is tracked"
}

# Step 8 pins into the file preflight REPORTS, not a hard-coded path: when the migration
# could not copy, the run keeps reading the legacy file, and a pin aimed at the canonical
# path would create a second config that wins next run and drops the base branch and board.
test_preflight_reports_the_config_path_it_read() {
  local repo line
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude/issue-to-pr
  printf -- '---\ntest_cmd: canonical\n---\n' >.claude/issue-to-pr/config.md
  use_fake_gh happy
  run_script preflight.sh 6
  # Compared on the tail: the absolute prefix is git's spelling of the path, not the
  # test's, and on Windows those differ (C:/Users/... against /tmp/...).
  line=$(printf '%s\n' "$OUT" | grep -m1 '^CONFIG_PATH=')
  assert_contains "$line" '.claude/issue-to-pr/config.md'
  assert_not_contains "$line" 'issue-to-pr.local.md'
}

# The model writes the friction log and epic ledgers here itself with a plain mkdir, and
# whichever lands first would be an untracked file until some later approval created the
# rule. Step 0 runs before all of them, so the directory hides itself from the start.
test_preflight_creates_the_state_dir_even_with_nothing_to_write() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6
  [ -f "$repo/.claude/issue-to-pr/.gitignore" ] || fail "the state dir was not prepared"
}

# Regression: with NO config anywhere, the legacy fallback still fired and CONFIG_PATH
# named the old sibling path. Step 8 pins into whatever this reports, so a first run on a
# fresh repository would have written the gate commands into an un-ignored
# `.claude/issue-to-pr.local.md` - and the run after that would offer to migrate a file
# the user never created.
test_preflight_with_no_config_reports_the_canonical_path() {
  local repo line
  repo=$(init_repo)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CONFIG_PRESENT false
  line=$(printf '%s\n' "$OUT" | grep -m1 '^CONFIG_PATH=')
  assert_contains "$line" '.claude/issue-to-pr/config.md'
  assert_not_contains "$line" 'issue-to-pr.local.md'
}

# A probe run outside a checkout stays read-only: `${root:-.}` would otherwise resolve to
# the caller's cwd and create a state directory in whatever folder they stood in.
test_preflight_outside_a_repository_writes_nothing() {
  local outside
  outside="$TEST_TMPDIR/not-a-repo"
  mkdir -p "$outside"
  cd "$outside"
  use_fake_gh happy
  run_script preflight.sh 6
  if [ -e "$outside/.claude" ]; then fail "preflight created a state dir outside a repository"; fi
}

# The outside-a-repo guard has to hold on the path that actually WRITES: a stray legacy
# config in a plain directory used to be copied into a state dir created right there in the
# caller's cwd. Reading it is left alone deliberately - that is what preflight did with a
# cwd-relative config long before this change, there is no repository to read instead, and
# nothing downstream can run outside a checkout anyway.
test_preflight_outside_a_repository_ignores_a_stray_legacy_config() {
  local outside
  outside="$TEST_TMPDIR/not-a-repo"
  mkdir -p "$outside/.claude"
  printf -- '---\ntest_cmd: stray cmd\n---\n' >"$outside/.claude/issue-to-pr.local.md"
  cd "$outside"
  use_fake_gh happy
  run_script preflight.sh 6
  if [ -e "$outside/.claude/issue-to-pr" ]; then fail "a state dir was created outside a repository"; fi
}

# Regression: warnings are queued before the two early exits, and degrade/stop flush the
# buffer and leave. The one saying the config is a shared tracked file was dropped on
# exactly the runs that also failed to parse it.
test_preflight_warnings_survive_an_early_degrade() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  printf -- '---\nnot valid frontmatter at all !!!\n---\n' >.claude/issue-to-pr.local.md
  git add .claude/issue-to-pr.local.md
  git commit -qm "share a broken config"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON config-parse-failed
  assert_contains "$OUT" "is tracked"
}
