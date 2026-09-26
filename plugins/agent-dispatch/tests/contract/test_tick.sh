#!/usr/bin/env bash
# Contract tests for tick.sh: the scheduler shim that finds the active install every tick.
# shellcheck disable=SC2016,SC2034
# SC2016: the printf in stub_dispatch writes $0 literally into dispatch.sh, to expand when that
# script runs later, not now. SC2034: RC is read by assert_rc() in the sourced assert.sh.

stub_dispatch() { # dir -> a dispatch.sh there that reports where it ran from
  mkdir -p "$1/scripts"
  printf '#!/usr/bin/env bash\necho "DISPATCH_RAN $0"\n' >"$1/scripts/dispatch.sh"
}

tick_log() { cat "$HOME/.agent-dispatch/logs/tick.log" 2>/dev/null; }
tick() { "$BASH" "$AD_SCRIPTS/tick.sh" "$@"; RC=$?; }

test_tick_runs_the_claude_install_a_windows_shaped_record_names() {
  local inst="$TEST_TMPDIR/cache/agent-dispatch/1.0.0" esc
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/plugins"
  stub_dispatch "$inst"
  esc=$(printf '%s' "$inst" | sed 's|/|\\\\|g')
  cat >"$HOME/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "other@market": [
      {
        "scope": "user",
        "installPath": "C:\\\\elsewhere\\\\other\\\\2.0.0",
        "version": "2.0.0"
      }
    ],
    "agent-dispatch@market": [
      {
        "scope": "user",
        "installPath": "$esc",
        "version": "1.0.0"
      }
    ]
  }
}
EOF
  tick claude
  assert_contains "$(tick_log)" "DISPATCH_RAN $inst/scripts/dispatch.sh" \
    "tick.sh must turn the record's doubled backslashes into a path bash can run"
}

test_tick_refuses_an_ambiguous_claude_install() {
  local proj="$TEST_TMPDIR/repo/.claude/plugins/agent-dispatch/1.0.0" \
    user="$TEST_TMPDIR/home/.claude/plugins/agent-dispatch/1.0.0" \
    other="$TEST_TMPDIR/home/.claude/plugins/other/2.0.0"
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/plugins"
  # Both candidates get a real dispatch.sh: a picker that silently takes one (the bug) would run
  # it and log DISPATCH_RAN, so this only passes if the fix actually refuses instead.
  stub_dispatch "$proj"
  stub_dispatch "$user"
  stub_dispatch "$other"
  cat >"$HOME/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "agent-dispatch@market": [
      {
        "scope": "project",
        "installPath": "$proj",
        "version": "1.0.0"
      },
      {
        "scope": "user",
        "installPath": "$user",
        "version": "1.0.0"
      }
    ],
    "other@market": [
      {
        "scope": "user",
        "installPath": "$other",
        "version": "2.0.0"
      }
    ]
  }
}
EOF
  tick claude
  assert_rc 1 "two scopes registered for the same plugin: which install is active is unknowable, so the tick refuses"
  assert_not_contains "$(tick_log)" "DISPATCH_RAN" "must not silently run either scope's install"
  assert_contains "$(tick_log | tail -1)" "several"
}

test_tick_runs_the_one_codex_version_and_refuses_two() {
  export HOME="$TEST_TMPDIR/home"
  local c="$HOME/.codex/plugins/cache/market/agent-dispatch"
  stub_dispatch "$c/1.0.0"
  printf '[plugins."agent-dispatch@market"]\nenabled = true\n' >"$HOME/.codex/config.toml"
  tick codex
  assert_contains "$(tick_log)" "DISPATCH_RAN $c/1.0.0/scripts/dispatch.sh"
  stub_dispatch "$c/1.1.0"
  tick codex
  assert_rc 1 "two cached versions: which one is active is unknowable, so the tick refuses"
  assert_contains "$(tick_log | tail -1)" "several"
}

test_tick_refuses_an_uninstalled_host() {
  export HOME="$TEST_TMPDIR/home"
  mkdir -p "$HOME"
  tick codex
  assert_rc 1
  tick gpt
  assert_rc 4 "an unknown host is a wrong call"
}

test_tick_refuses_a_disabled_codex_install() {
  export HOME="$TEST_TMPDIR/home"
  stub_dispatch "$HOME/.codex/plugins/cache/market/agent-dispatch/1.0.0"
  printf '[plugins."agent-dispatch@market"]\nenabled = false\n\n[plugins."other@market"]\nenabled = true\n' \
    >"$HOME/.codex/config.toml"
  tick codex
  assert_rc 1 "a disabled Codex install must not dispatch"
  assert_not_contains "$(tick_log)" "DISPATCH_RAN"
}
