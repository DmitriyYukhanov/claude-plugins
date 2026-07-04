#!/usr/bin/env bash
# Contract tests for scripts/worktree.sh (spec sec 4.2). SAFETY-CRITICAL.
# Real git fixtures (a bare remote + a repo) exercise every exit path.

# ── fixtures ────────────────────────────────────────────────────────────────
mk_repo() { # -> repo path; also creates $TEST_TMPDIR/remote.git as origin
  local remote="$TEST_TMPDIR/remote.git" repo="$TEST_TMPDIR/repo"
  git init -q --bare "$remote"
  git init -q -b main "$repo"
  git -C "$repo" config user.email t@e.com
  git -C "$repo" config user.name T
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm seed
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -q -u origin main
  printf '%s' "$repo"
}

mk_worktree() { # repo branch -> worktree path at repo-worktrees/issue-6, pushed
  local repo=$1 branch=$2 wt="$TEST_TMPDIR/repo-worktrees/issue-6"
  git -C "$repo" worktree add "$wt" -b "$branch" main >/dev/null 2>&1
  printf 'work\n' >"$wt/work.txt"
  git -C "$wt" add work.txt
  git -C "$wt" commit -qm work
  git -C "$wt" push -q -u origin "$branch" 2>/dev/null || true
  printf '%s' "$wt"
}

write_marker() { # root branch sha used created_iso
  local root=$1 branch=$2 sha=$3 used=$4 created=$5 slug
  slug=${branch//\//-}
  mkdir -p "$root/.claude/issue-to-pr"
  printf '{"branch":"%s","pr_head_sha":"%s","created_at":"%s","used":%s,"quote":"ship it"}\n' \
    "$branch" "$sha" "$created" "$used" >"$root/.claude/issue-to-pr/approval-$slug.json"
}

SHA_OK="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# ── ensure ──────────────────────────────────────────────────────────────────
test_wt_ensure_creates() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-new --start-point main
  assert_rc 0
  assert_key "$OUT" STATE CREATED
  assert_key "$OUT" BRANCH feat/issue-6-new
  assert_key "$OUT" DEPS_MANIFEST none
  assert_key_present "$OUT" WT_PATH
}

test_wt_ensure_reattaches_existing_branch() {
  local repo; repo=$(mk_repo); cd "$repo"
  git -C "$repo" branch feat/issue-6-x main
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 0
  assert_key "$OUT" STATE REATTACHED
}

test_wt_ensure_resumes() {
  local repo; repo=$(mk_repo); mk_worktree "$repo" feat/issue-6-x >/dev/null; cd "$repo"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 0
  assert_key "$OUT" STATE RESUMED
  assert_key "$OUT" PR_STATE none
}

test_wt_ensure_resume_pr_merged_stops() {
  local repo; repo=$(mk_repo); mk_worktree "$repo" feat/issue-6-x >/dev/null; cd "$repo"
  use_fake_gh pr-merged
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 2
  assert_key "$OUT" STOP_REASON pr-already-merged
}

test_wt_ensure_detached_is_bad_checkout() {
  local repo; repo=$(mk_repo); cd "$repo"
  git worktree add --detach "$TEST_TMPDIR/repo-worktrees/issue-6" main >/dev/null 2>&1
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 2
  assert_key "$OUT" STOP_REASON bad-checkout-state
}

test_wt_ensure_stale_unregistered_dir_stops() {
  local repo; repo=$(mk_repo); cd "$repo"
  mkdir -p "$TEST_TMPDIR/repo-worktrees/issue-6"
  printf 'x\n' >"$TEST_TMPDIR/repo-worktrees/issue-6/leftover"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point main
  assert_rc 2
  assert_key "$OUT" STOP_REASON stale-unregistered-dir
}

test_wt_ensure_invalid_start_point_stops() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-x --start-point no-such-ref
  assert_rc 2
  assert_key "$OUT" STOP_REASON invalid-start-point
}

# ── merge ───────────────────────────────────────────────────────────────────
test_wt_merge_no_marker_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_used_marker_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" true "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_stale_marker_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_head_moved_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh head-moved
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_happy_consumes_marker() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD squash
  assert_contains "$(cat "$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json")" '"used":true'
  assert_gh_called "pr merge feat/issue-6-x --squash"
}

test_wt_merge_squash_disallowed_falls_back_to_merge() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh squash-disallowed
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD merge
}

test_wt_merge_rebase_only_fallback() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh rebase-only
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD rebase
}

test_wt_missing_branch_value_does_not_hang() {
  # A value-flag with no value must degrade, not spin forever.
  local out rc
  out=$(timeout 15 bash "$ITP_SCRIPTS/worktree.sh" merge 6 --branch 2>/dev/null)
  rc=$?
  if [ "$rc" = 124 ]; then fail "worktree.sh hung on --branch with no value"; fi
  assert_eq 4 "$rc" "should degrade (missing-branch), not hang"
}

test_wt_merge_pending_checks_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh pending-checks
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON checks-pending
}

test_wt_merge_push_rejected_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git -C "$wt" remote set-url origin "$TEST_TMPDIR/does-not-exist.git"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON push-rejected
}

# ── cleanup ─────────────────────────────────────────────────────────────────
test_wt_cleanup_pr_not_merged_stops() {
  local repo; repo=$(mk_repo); mk_worktree "$repo" feat/issue-6-x >/dev/null; cd "$repo"
  use_fake_gh pr-open
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON pr-not-merged
}

test_wt_cleanup_happy_removes_and_deletes() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REMOVED true
  assert_key "$OUT" DELETED_LOCAL true
  if [ -d "$wt" ]; then fail "worktree dir still exists after cleanup"; fi
}

test_wt_cleanup_dirty_tracked_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  printf 'changed\n' >>"$wt/README.md" # tracked modification
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON dirty-tracked-files
}

test_wt_cleanup_salvages_then_removes() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  mkdir -p "$wt/tmp/task-6"
  printf '# design\n' >"$wt/tmp/task-6/design.md"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x --salvage-to "$TEST_TMPDIR/salvage"
  assert_rc 0
  assert_key "$OUT" REMOVED true
  if [ ! -f "$TEST_TMPDIR/salvage/design.md" ]; then fail "design.md not salvaged"; fi
}

test_wt_cleanup_in_place_deletes_checked_out_branch() {
  # In-place mode: branch checked out in root, no worktree registered.
  local repo; repo=$(mk_repo); cd "$repo"
  git -C "$repo" switch -c feat/issue-6-x main >/dev/null 2>&1
  git -C "$repo" push -q -u origin feat/issue-6-x 2>/dev/null || true
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" DELETED_LOCAL true
  if git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "in-place cleanup did not delete the checked-out branch"
  fi
}

test_wt_cleanup_reports_unregistered_leftover_dir() {
  # A directory at the worktree path that git no longer tracks (a prior
  # partial-success remnant on Windows, or a folder parked there) must be REPORTED,
  # not silently deleted, while branch + marker cleanup still proceeds.
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  git -C "$repo" worktree remove "$wt"
  mkdir -p "$wt"
  printf 'stale\n' >"$wt/leftover"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x
  assert_rc 0
  # LEFTOVER_DIR is emitted (exact path format is git's, not the test's cygwin form).
  assert_key_present "$OUT" LEFTOVER_DIR
  assert_contains "$OUT" "issue-6"
  assert_key "$OUT" DELETED_LOCAL true # branch cleanup still runs
  if [ ! -d "$wt" ]; then fail "unregistered dir must be reported, not deleted"; fi
}

# ── teardown ────────────────────────────────────────────────────────────────
test_wt_teardown_removes_but_keeps_branch() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh teardown 6
  assert_rc 0
  assert_key "$OUT" REMOVED true
  assert_key "$OUT" KEPT branch-and-pr
  if ! git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "teardown must not delete the branch"
  fi
}

test_wt_teardown_in_place_when_no_worktree() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh teardown 6
  assert_rc 0
  assert_key "$OUT" KEPT in-place
}
