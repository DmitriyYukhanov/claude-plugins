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
  mkdir -p .claude/issue-to-pr
  cat >.claude/issue-to-pr/config.md <<'EOF'
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
  assert_key "$OUT" CONFIG_PRESENT true
}

test_preflight_config_nested_commands_alias() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude/issue-to-pr
  cat >.claude/issue-to-pr/config.md <<'EOF'
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
  mkdir -p .claude/issue-to-pr
  # Write the config with CRLF line endings (Windows editor default).
  printf -- '---\r\nbase_branch: dev\r\ntest_cmd: pnpm test\r\n---\r\n' >.claude/issue-to-pr/config.md
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
  mkdir -p .claude/issue-to-pr
  cat >.claude/issue-to-pr/config.md <<'EOF'
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
  mkdir -p .claude/issue-to-pr
  cat >.claude/issue-to-pr/config.md <<'EOF'
---
this line has no key and is not valid frontmatter !!!
---
EOF
  use_fake_gh happy
  run_script preflight.sh 6
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON config-parse-failed
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

# Regression: the config path was the last cwd-relative read left in the script, and it
# outranks auto-detect - so a run from a subdirectory found no config, silently swapped
# the pinned test command for a guess, and lost the pinned base branch with it. The
# package.json is here so a regression shows up as `npm test`, not as an empty value.
test_preflight_reads_the_config_from_a_subdirectory() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude/issue-to-pr sub
  printf -- '---\nbase_branch: dev\ntest_cmd: make ci\n---\n' >.claude/issue-to-pr/config.md
  printf '%s\n' '{ "scripts": { "test": "jest" } }' >package.json
  cd sub
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CONFIG_PRESENT true
  assert_key "$OUT" CMD_TEST "make ci"
  assert_key "$OUT" BASE dev
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
  mkdir -p .claude/issue-to-pr
  cat >.claude/issue-to-pr/config.md <<'EOF'
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
# `.claude/issue-to-pr.local.md`, a path nothing reads.
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
test_preflight_warnings_survive_an_early_stop() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  printf -- '---
test_cmd: from the old path
---
' >.claude/issue-to-pr.local.md
  use_fake_gh auth-fail
  run_script preflight.sh 6
  assert_rc 2
  assert_key "$OUT" STOP_REASON gh-auth-failed
  assert_contains "$OUT" "not read any more"
}

# The old sibling path is not read, not copied, and not tidied away. It is mentioned once
# so the pinned base branch and board do not vanish in silence, and moving it is a job for
# whoever owns the file.
test_preflight_says_the_old_config_path_is_not_read() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  mkdir -p .claude
  printf -- '---\nbase_branch: from-the-old-path\ntest_cmd: old cmd\n---\n' >.claude/issue-to-pr.local.md
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CONFIG_PRESENT false
  assert_key "$OUT" BASE main
  assert_contains "$OUT" "not read any more"
  if [ -f "$repo/.claude/issue-to-pr/config.md" ]; then fail "the old config was copied after all"; fi
  [ -f "$repo/.claude/issue-to-pr.local.md" ] || fail "the old config was removed"
}

# The contract lists WARNINGS among the keys that are always present.
test_preflight_always_emits_the_warnings_key() {
  local repo
  repo=$(init_repo_with_remote)
  cd "$repo"
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key_present "$OUT" WARNINGS
}

# 2.8.0: gate-command detection left this script. A repository that plainly declares a suite
# still reports none, because the tree Step 0 sees is not the tree the gates run in - Step 1
# has not cut it yet. The model works the command out there instead, and only as a literal.
test_preflight_never_detects_a_gate_command() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  printf '{"scripts":{"test":"jest","typecheck":"tsc"}}
' >package.json
  mkdir -p tests
  printf '#!/usr/bin/env bash
' >tests/run-tests.sh
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" CMD_TEST ""
  assert_key "$OUT" CMD_TYPECHECK ""
}
