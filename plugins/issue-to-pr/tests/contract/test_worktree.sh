#!/usr/bin/env bash
# Contract tests for scripts/worktree.sh (spec sec 4.2). SAFETY-CRITICAL.
# Real git fixtures (a bare remote + a repo) exercise every exit path.

# ── fixtures ────────────────────────────────────────────────────────────────
# The shared fixture in assert.sh builds exactly this: bare origin + repo + seed
# commit + pushed main. Kept as a name because every test in this file uses it.
mk_repo() { init_repo_with_remote; }

mk_worktree() { # repo branch -> worktree path at repo-worktrees/issue-6, pushed
  local repo=$1 branch=$2 wt="$TEST_TMPDIR/repo-worktrees/issue-6"
  git -C "$repo" worktree add "$wt" -b "$branch" main >/dev/null 2>&1
  printf 'work\n' >"$wt/work.txt"
  git -C "$wt" add work.txt
  git -C "$wt" commit -qm work
  git -C "$wt" push -q -u origin "$branch" 2>/dev/null || true
  printf '%s' "$wt"
}

# write_marker lives in tests/lib/assert.sh - test_approve.sh needs the identical shape.

SHA_OK="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
NL=$'\n' # a real newline, for building a multi-line approval reply

# ── ensure ──────────────────────────────────────────────────────────────────
test_wt_ensure_creates() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh ensure 6 --branch feat/issue-6-new --start-point main
  assert_rc 0
  assert_key "$OUT" STATE CREATED
  assert_key "$OUT" BRANCH feat/issue-6-new
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
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_used_marker_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" true "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_stale_marker_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(stale_iso)"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_head_moved_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh head-moved
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON no-valid-approval
}

test_wt_merge_happy_consumes_marker() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD squash
  # A merged approval is deleted, not merely flagged: cleanup used to be the only
  # thing that removed it, and cleanup never runs for an abandoned or hand-merged PR.
  if [ -f "$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json" ]; then fail "marker survived the merge"; fi
  assert_gh_called "pr merge feat/issue-6-x --squash"
}

# Regression: cmd_merge keyed the marker off the raw --branch value while approve.sh
# and merge-guard.sh both canonicalize a PR number first, so `--branch 13` looked for
# a marker nobody had written and the merge stopped on an approval that existed.
test_wt_merge_resolves_pr_number_to_marker() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch 13
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_gh_called "pr merge feat/issue-6-x --squash"
}

test_wt_merge_squash_disallowed_falls_back_to_merge() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh squash-disallowed
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
  assert_key "$OUT" MERGE_METHOD merge
}

test_wt_merge_rebase_only_fallback() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh rebase-only
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
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
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON checks-pending
}

test_wt_merge_push_rejected_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git -C "$wt" remote set-url origin "$TEST_TMPDIR/does-not-exist.git"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
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

# Regression: cleanup keyed the branch off the raw --branch too. `gh pr view 13` still
# reported MERGED, then every git step missed - the merged branch survived local and
# remote, the marker stayed behind, and the script exited 0 as if it had cleaned up.
test_wt_cleanup_resolves_pr_number_to_the_branch() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch 13
  assert_rc 0
  assert_key "$OUT" DELETED_LOCAL true
  if git -C "$repo" show-ref --verify --quiet refs/heads/feat/issue-6-x; then
    fail "cleanup by PR number left the merged branch behind"
  fi
  if [ -f "$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json" ]; then
    fail "cleanup by PR number left the approval marker behind"
  fi
}

# Regression: a relative --salvage-to was resolved against cwd, so a cleanup run from
# inside the worktree copied the artifacts into the directory it was about to remove.
test_wt_cleanup_relative_salvage_resolves_against_the_main_checkout() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x)
  mkdir -p "$wt/tmp/task-6"
  printf '# design\n' >"$wt/tmp/task-6/design.md"
  cd "$wt"
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x --salvage-to salvaged
  assert_rc 0
  if [ ! -f "$repo/salvaged/design.md" ]; then fail "relative salvage did not land in the main checkout"; fi
  if [ -f "$wt/salvaged/design.md" ]; then fail "salvage landed in the worktree being removed"; fi
}

# Regression: SALVAGED was emitted after remove_worktree, which flushes the buffer on
# its way out when the tree is dirty - so a caller whose salvage HAD happened was never
# told, and had no reason to trust the copies it could not see reported.
test_wt_cleanup_reports_salvage_even_when_removal_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  mkdir -p "$wt/tmp/task-6"
  printf '# design\n' >"$wt/tmp/task-6/design.md"
  printf 'changed\n' >>"$wt/README.md" # tracked modification -> removal stops
  use_fake_gh pr-merged
  run_script worktree.sh cleanup 6 --branch feat/issue-6-x --salvage-to "$TEST_TMPDIR/salvage"
  assert_rc 2
  assert_key "$OUT" STOP_REASON dirty-tracked-files
  assert_key "$OUT" SALVAGED "$TEST_TMPDIR/salvage"
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

# -- merge-failure ladder (sec 6.3) ------------------------------------------
fresh_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

test_wt_merge_ladder_exhausted_caps_before_anything() {
  # The cap check is first: no marker, no gh needed - just the counter.
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x --ladder-attempt 4
  assert_rc 2
  assert_key "$OUT" STOP_REASON merge-ladder-exhausted
  assert_gh_not_called "pr" # the cap must fire before ANY GitHub interaction
}

test_wt_merge_checks_failed_stops_before_merge() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh checks-failing
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON checks-failed
  assert_key_present "$OUT" FAILING_CHECKS
  assert_gh_not_called "pr merge" # a doomed check must never blind-merge
}

test_wt_merge_conflict_stops_without_update() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh merge-conflict-state
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON merge-conflict
  assert_gh_not_called "pr update-branch"
  assert_gh_not_called "pr merge"
}

test_wt_merge_update_branch_failure_is_distinct() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh behind-update-fail
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON update-branch-failed
  assert_gh_called "pr update-branch"
  assert_gh_not_called "pr merge"
}

test_wt_merge_behind_clean_refreshes_then_asks_for_gates() {
  # Base advances with an UNRELATED file; the update (simulated by fake-gh) merges
  # it into the branch. is_pure_base_merge must see the PR's own diff unchanged
  # (this FAILS if the unsound two-dot check is used) -> the approval carries over.
  # The gates do not: they never ran against base+diff, and a receipt a base update
  # could walk past would not be a gate. So the run stops for one more gate pass.
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  printf 'unrelated\n' >"$repo/unrelated.txt"
  git -C "$repo" add unrelated.txt
  git -C "$repo" commit -qm base-advance
  git -C "$repo" push -q origin main
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh behind-clean
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" LADDER_STEP base-merged-refreshed
  assert_key "$OUT" STOP_REASON gates-unverified
  assert_gh_called "pr update-branch"
  if printf '%s' "$(gh_log)" | grep -q 'pr merge'; then fail "merged a head no receipt covers"; fi
}

test_wt_merge_behind_unverified_stops() {
  # update-branch succeeds but the branch head could not be observed to advance
  # (stale/failed fetch) — never assume the base merge is pure; stop for re-approval.
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh behind-noadvance
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON base-update-unverified
  assert_gh_called "pr update-branch"
  assert_gh_not_called "pr merge"
}

test_wt_merge_behind_content_changed_needs_reapproval() {
  # The update also touches the PR's own file -> the PR's diff changed -> the old
  # approval no longer covers it. Never merges; asks for fresh approval.
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  printf 'unrelated\n' >"$repo/unrelated.txt"
  git -C "$repo" add unrelated.txt
  git -C "$repo" commit -qm base-advance
  git -C "$repo" push -q origin main
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh behind-content
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON content-changed-needs-reapproval
  assert_gh_not_called "pr merge"
}

test_wt_merge_clean_passes_precheck() {
  # Regression: a CLEAN mergeability read must not disturb the normal merge.
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" MERGED true
}

# -- draft revert (sec 6.5) --------------------------------------------------
test_wt_revert_opens_draft_pr_never_merges() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  # Land the PR's change as a SQUASH (single-parent) commit on main so there is a
  # normal commit to revert (a real squash-merge is never a 2-parent merge commit).
  git -C "$repo" merge -q --squash feat/issue-6-x
  git -C "$repo" commit -qm 'squash: feat/issue-6-x'
  git -C "$repo" push -q origin main
  use_fake_gh happy
  run_script worktree.sh revert 6 --branch feat/issue-6-x
  assert_rc 0
  assert_key_present "$OUT" REVERT_PR_URL
  assert_key_present "$OUT" REVERT_BRANCH
  assert_gh_called "pr create --draft"
  assert_gh_not_called "pr merge"
}

test_wt_revert_no_merge_commit_degrades() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$repo"
  use_fake_gh revert-no-merge-commit
  run_script worktree.sh revert 6 --branch feat/issue-6-x
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON no-merge-commit
}

# ── v3 run-dir + argument safety ────────────────────────────────────────────
# Regression: `run_dir` splices the issue token into a path that cleanup hands to
# `rm -rf`, so a token carrying `..` walked out of the state dir. Reproduced by
# deleting a repository's .git before the guard existed.
test_wt_non_numeric_issue_degrades_before_any_path_is_built() {
  local repo; repo=$(mk_repo); cd "$repo"
  use_fake_gh happy
  run_script worktree.sh cleanup '6/../../../.git' --branch feat/issue-6-x
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON invalid-issue
  if [ ! -d "$repo/.git" ]; then fail "the guard let a traversing issue token delete .git"; fi
}




# Regression: salvage_artifacts set SALVAGED on mkdir alone, so teardown reported a
# salvage that copied nothing — and that report is what makes deleting originals feel safe.
test_wt_salvage_reports_nothing_when_it_copied_nothing() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x)
  cd "$repo"
  use_fake_gh happy
  run_script worktree.sh teardown 6 --salvage-to "$repo/docs/design"
  assert_key "$OUT" SALVAGED ""
}

test_wt_merge_reports_the_approval_quote_before_consuming() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  # Deleting the marker must not also delete the record of what the user said.
  assert_key "$OUT" APPROVAL_QUOTE "ship it"
}


# Regression: marker_str_field's `"[^"]*"` match stops at the first escaped quote,
# so a reply containing one was reported truncated.
test_wt_merge_quote_survives_embedded_quotes() {
  local repo wt m; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  m="$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json"
  mkdir -p "$repo/.claude/issue-to-pr"
  printf '{"branch":"feat/issue-6-x","pr_head_sha":"%s","created_at":"%s","used":false,"quote":"say \\"ship it\\" now"}\n' \
    "$SHA_OK" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$m"
  use_fake_gh happy
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  assert_contains "$OUT" 'say "ship it" now'
}


# Regression: a multi-line approval was reported with a literal backslash-n, and
# the merge deletes the marker, so that mangled copy was the only one left. Written through
# approve.sh so the real escape/unescape pair is exercised, not a hand-built fixture.
# The value must stay on ONE line: the machine block is one KEY=VALUE per line.
test_wt_merge_quote_survives_newlines() {
  local repo wt line; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  run_script approve.sh feat/issue-6-x --quote "ship it${NL}but squash it"
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  line=$(printf '%s
' "$OUT" | grep '^APPROVAL_QUOTE=')
  assert_contains "$line" "ship it"
  assert_contains "$line" "but squash it"
}

# Regression: json_escape doubles backslashes first, so decoding `\n` before `\`
# matched the second backslash plus the n and ate both — corrupting the only
# surviving record of the approval once the marker is deleted.
test_wt_merge_quote_survives_a_backslash() {
  local repo wt line; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  use_fake_gh happy
  run_script approve.sh feat/issue-6-x --quote 'merge it, then update C:\notes.md'
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 0
  line=$(printf '%s\n' "$OUT" | grep '^APPROVAL_QUOTE=')
  assert_contains "$line" 'C:\notes.md'
}

# 2.11.0: the gates were "hard" only because the model ran them. run-gates.sh now
# leaves a receipt naming the HEAD it ran against, and the merge refuses a head no
# receipt covers - including the one case that used to slip through, a green run
# followed by one more commit.
test_wt_merge_without_a_receipt_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON gates-unverified
  if printf '%s' "$(gh_log)" | grep -q 'pr merge'; then fail "merged with no gate receipt"; fi
}

test_wt_merge_with_a_receipt_for_another_head_stops() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  write_receipt "$repo" feat/issue-6-x bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  use_fake_gh happy
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON gates-unverified
}

# The review read used to live in a separate script the model had to remember to
# call, and it reported `clear` when its own read failed. Both halves are gone: the
# merge reads it, and an unreadable review is a stop.
test_wt_merge_stops_on_a_changes_requested_review() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  use_fake_gh review-changes-requested
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON review-blocked
  if printf '%s' "$(gh_log)" | grep -q 'pr merge'; then fail "merged over a requested change"; fi
}

test_wt_merge_stops_when_the_review_cannot_be_read() {
  local repo wt; repo=$(mk_repo); wt=$(mk_worktree "$repo" feat/issue-6-x); cd "$wt"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(fresh_iso)"
  write_receipt "$repo" feat/issue-6-x "$SHA_OK"
  use_fake_gh review-read-fail
  run_script worktree.sh merge 6 --branch feat/issue-6-x
  assert_rc 2
  assert_key "$OUT" STOP_REASON review-unreadable
  if printf '%s' "$(gh_log)" | grep -q 'pr merge'; then fail "merged on an unread review"; fi
}

