#!/usr/bin/env bash
# The setup skill prints what the owner installs; these pin the parts a tick depends on.

setup_md() { printf '%s' "$AD_SCRIPTS/../skills/setup/SKILL.md"; }

test_setup_prints_everything_a_tick_needs_and_runs_none_of_it() {
  local s label
  s=$(cat "$(setup_md)") || fail "skills/setup/SKILL.md missing"
  [ -n "$s" ] || fail "SKILL.md came back empty; this check would be vacuous"
  assert_contains "$s" 'issue-to-pr' "setup must check the issue-to-pr it launches"
  assert_contains "$s" '9.4.0' "setup must check issue-to-pr's version: the manifest cannot"
  for label in agent agent:running agent:waiting agent:review agent:failed; do
    assert_contains "$s" "gh label create $label" "setup must print the $label label"
  done
  assert_contains "$s" 'label:agent:waiting,agent:review,agent:failed' "setup must print the saved search"
  assert_contains "$s" 'tick.sh' "the scheduler runs the copied tick.sh"
  assert_contains "$s" 'conhost.exe --headless' "Windows: the hidden launch the spike proved"
  assert_contains "$s" 'IgnoreNew' "Windows: never a second instance"
  assert_contains "$s" 'StartInterval' "macOS: a LaunchAgent"
  assert_contains "$s" 'OnUnitActiveSec' "Linux: a systemd user timer"
  assert_contains "$s" 'WindowsApps' "Windows: warn about the Store pwsh that leaks out of the job"
  assert_contains "$s" 'Never run' "setup prints; the owner runs"
}

test_nothing_shipped_names_a_real_project() {
  local hits
  hits=$(grep -r -n -i -E 'agent-sandbox|yarrtifacts|relationship|n8n' --exclude-dir=tests "$AD_SCRIPTS/.." || true)
  [ -z "$hits" ] || fail "shipped files name a real project:
$hits"
}
