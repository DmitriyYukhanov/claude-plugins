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

test_preflight_base_auto_detects_dev() {
  local repo
  repo=$(init_repo)
  cd "$repo"
  git branch dev
  use_fake_gh happy
  run_script preflight.sh 6
  assert_key "$OUT" BASE dev
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
