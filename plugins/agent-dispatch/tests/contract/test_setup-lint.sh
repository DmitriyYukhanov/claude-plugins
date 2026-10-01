#!/usr/bin/env bash
# The setup skill applies what a tick needs after one confirmation; these pin the parts a tick depends on.

setup_md() { printf '%s' "$AD_SCRIPTS/../skills/setup/SKILL.md"; }

test_setup_applies_everything_a_tick_needs_after_one_confirmation() {
  local s label
  s=$(cat "$(setup_md)") || fail "skills/setup/SKILL.md missing"
  [ -n "$s" ] || fail "SKILL.md came back empty; this check would be vacuous"
  assert_contains "$s" 'issue-to-pr' "setup must check the issue-to-pr it launches"
  assert_contains "$s" '9.4.0' "setup must check issue-to-pr's version: the manifest cannot"
  for label in agent agent:running agent:waiting agent:review agent:failed; do
    assert_contains "$s" "gh label create $label" "setup must create the $label label"
  done
  assert_contains "$s" 'label:agent:waiting,agent:review,agent:failed' "setup must print the saved search"
  assert_contains "$s" 'tick.sh' "the scheduler runs the copied tick.sh"
  assert_contains "$s" 'conhost.exe --headless' "Windows: the hidden launch the spike proved"
  assert_contains "$s" 'IgnoreNew' "Windows: never a second instance"
  assert_contains "$s" 'StartInterval' "macOS: a LaunchAgent"
  assert_contains "$s" 'OnUnitActiveSec' "Linux: a systemd user timer"
  assert_contains "$s" 'WindowsApps' "Windows: warn about the Store pwsh that leaks out of the job"
  assert_contains "$s" '--installer-type wix --scope machine' "Windows: the MSI pwsh a job can stop"
  assert_contains "$s" "-Settings \$s -Force" "Windows: a second setup replaces the task instead of failing on it"
  assert_contains "$s" 'launchctl bootout' "macOS: a second setup reloads the LaunchAgent instead of failing on it"
  assert_contains "$s" 'Auto-merge threshold' "the threshold is its own step"
  assert_contains "$s" 'human_paths' "the threshold question says what merges without the owner"
  assert_contains "$s" 'Apply all of this?' "one confirmation before anything changes"
  assert_contains "$s" '.agent-dispatch/notify.sh' "setup must show the optional notification hook"
  assert_contains "$s" 'Do not run the hook unless' "setup must not send an unsolicited test message"
  assert_not_contains "$s" 'Never run' "setup applies now; the old print-only rule is gone"
}

test_nothing_shipped_names_a_real_project() {
  local hits
  hits=$(grep -r -n -i -E 'agent-sandbox|yarrtifacts|relationship|n8n' --exclude-dir=tests "$AD_SCRIPTS/.." || true)
  [ -z "$hits" ] || fail "shipped files name a real project:
$hits"
}
