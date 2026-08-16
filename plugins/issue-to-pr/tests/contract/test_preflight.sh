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
