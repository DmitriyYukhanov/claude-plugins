#!/usr/bin/env bash
# Contract tests for scripts/approve.sh + scripts/merge-guard.sh (spec sec 4.5).
# SAFETY-CRITICAL: these encode the merge gate.

SHA_OK="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_MOVED="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

write_marker() { # root branch sha used created_iso
  local root=$1 branch=$2 sha=$3 used=$4 created=$5 slug
  slug=${branch//\//-}
  mkdir -p "$root/.claude/issue-to-pr"
  printf '{"branch":"%s","pr_head_sha":"%s","created_at":"%s","used":%s,"quote":"ship it"}\n' \
    "$branch" "$sha" "$created" "$used" >"$root/.claude/issue-to-pr/approval-$slug.json"
}

hook_json() { # command -> hook stdin JSON
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}

# ── approve.sh ──────────────────────────────────────────────────────────────
test_approve_writes_marker() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_script approve.sh feat/issue-6-x --quote "lgtm, ship it"
  assert_rc 0
  assert_key "$OUT" APPROVED true
  local m="$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json"
  if [ ! -f "$m" ]; then fail "marker not written"; fi
  assert_contains "$(cat "$m")" "\"pr_head_sha\":\"$SHA_OK\""
  assert_contains "$(cat "$m")" '"used":false'
}

test_approve_missing_quote_degrades() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_script approve.sh feat/issue-6-x
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-quote
}

test_approve_missing_branch_degrades() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_script approve.sh --quote "ship it"
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON missing-branch
}

test_approve_no_pr_head_degrades() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh head-empty
  run_script approve.sh feat/issue-6-x --quote "ship it"
  assert_rc 4
  assert_key "$OUT" DEGRADED_REASON no-pr-head
}

test_approve_resolves_pr_number_to_branch() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_script approve.sh 13 --quote "lgtm, ship it"
  assert_rc 0
  assert_key "$OUT" APPROVED true
  local m="$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json"
  if [ ! -f "$m" ]; then fail "marker not written under the resolved branch name"; fi
  if [ -f "$repo/.claude/issue-to-pr/approval-13.json" ]; then fail "marker wrongly keyed by the raw PR number"; fi
}

test_approve_unresolvable_ref_falls_back_to_raw() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh head-name-missing
  run_script approve.sh feat/issue-6-x --quote "ship it"
  assert_rc 0
  assert_key "$OUT" APPROVED true
  local m="$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json"
  if [ ! -f "$m" ]; then fail "marker not written when branch resolution is unavailable"; fi
}

test_approve_refresh_updates_sha() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_script approve.sh feat/issue-6-x --quote "ship it"
  use_fake_gh head-moved
  run_script approve.sh --refresh feat/issue-6-x
  assert_rc 0
  assert_key "$OUT" REFRESHED true
  local m="$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json"
  assert_contains "$(cat "$m")" "\"pr_head_sha\":\"$SHA_MOVED\""
  assert_contains "$(cat "$m")" '"used":false'
}

# ── merge-guard.sh ──────────────────────────────────────────────────────────
test_guard_valid_marker_allows() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash')"
  assert_rc 0
  assert_contains "$OUT" '"permissionDecision":"allow"'
}

test_guard_worktree_merge_command_allows() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_guard "$(hook_json 'bash worktree.sh merge 6 --branch feat/issue-6-x')"
  assert_contains "$OUT" '"permissionDecision":"allow"'
}

test_guard_no_marker_denies() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash')"
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_guard_used_marker_denies() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" true "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash')"
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_guard_stale_marker_denies() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u -d '-2 hours' +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash')"
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_guard_head_moved_denies() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh head-moved
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash')"
  assert_contains "$OUT" '"permissionDecision":"deny"'
}

test_guard_admin_always_denies() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash --admin')"
  assert_contains "$OUT" '"permissionDecision":"deny"'
  assert_contains "$OUT" "admin"
}

test_guard_force_push_asks() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard "$(hook_json 'git push --force origin feat/issue-6-x')"
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

test_guard_normalizes_odd_spacing() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard "$(hook_json 'gh  pr   merge  feat/issue-6-x   --squash')"
  assert_contains "$OUT" '"permissionDecision":"deny"' # no marker -> still caught despite spacing
}

test_guard_passthrough_non_merge_command() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard "$(hook_json 'ls -la')"
  assert_rc 0
  assert_contains "$OUT" '"continue":true'
  assert_not_contains "$OUT" 'permissionDecision'
}

# Regression: a quoted script path (author's spaced Windows path) must NOT bypass
# the gate. The command has escaped quotes around the path.
test_guard_quoted_path_worktree_merge_is_gated() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard '{"tool_name":"Bash","tool_input":{"command":"bash \"D:/Code Stage/x/worktree.sh\" merge 6 --branch feat/issue-6-x"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"' # no marker -> denied, not passthrough
}

test_guard_chained_admin_is_denied() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard '{"tool_name":"Bash","tool_input":{"command":"echo \"hi\" && gh pr merge feat/x --admin"}}'
  assert_contains "$OUT" '"permissionDecision":"deny"'
  assert_contains "$OUT" "admin"
}

test_guard_refspec_force_push_asks() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard "$(hook_json 'git push origin +main')"
  assert_contains "$OUT" '"permissionDecision":"ask"'
}

test_guard_flag_first_branch_is_parsed() {
  local repo; repo=$(init_repo); cd "$repo"
  use_fake_gh happy
  run_guard "$(hook_json 'gh pr merge --squash feat/issue-6-x')"
  # Correctly parsed branch -> deny names it (not "--squash").
  assert_contains "$OUT" 'feat/issue-6-x'
  assert_not_contains "$OUT" 'no approval marker for --squash'
}

test_guard_resolves_pr_number_to_marker() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  # No marker filed under "13" -- the guard must resolve it to feat/issue-6-x and find
  # the one approve.sh actually wrote, exactly the mismatch a real `gh pr merge <N>`
  # produced before this fix.
  run_guard "$(hook_json 'gh pr merge 13 --merge --delete-branch=false')"
  assert_contains "$OUT" '"permissionDecision":"allow"'
}

test_guard_direct_gh_merge_consumes_marker() {
  local repo; repo=$(init_repo); cd "$repo"
  write_marker "$repo" feat/issue-6-x "$SHA_OK" false "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  use_fake_gh happy
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash')"
  assert_contains "$OUT" '"permissionDecision":"allow"'
  # Marker is now consumed, so a second direct merge is denied.
  assert_contains "$(cat "$repo/.claude/issue-to-pr/approval-feat-issue-6-x.json")" '"used":true'
  run_guard "$(hook_json 'gh pr merge feat/issue-6-x --squash')"
  assert_contains "$OUT" '"permissionDecision":"deny"'
}
