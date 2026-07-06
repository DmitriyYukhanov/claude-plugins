#!/usr/bin/env bash
# pin-config.sh - self-writing config (spec sec 5.6). After a run whose auto-detected
# gate commands passed, pin them to .claude/issue-to-pr.local.md so later runs skip
# detection. NEVER overwrites a human-set value: idempotency is checked with the SAME
# shared frontmatter parser preflight uses, so a nested `commands:` value counts as
# already-set (design D6). Base branch is never auto-pinned.
#
#   pin-config.sh --config <path> [--test <cmd>] [--typecheck <cmd>] [--visual <cmd>] [--smoke <cmd>]
#
# Emits PINNED=<comma-list of keys added> and CONFIG=<path>. Exit 0; 4 (degraded) if
# an existing config's frontmatter cannot be parsed (never corrupt a hand-edited file).
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

config=""
val_test="" val_typecheck="" val_visual="" val_smoke=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) config=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --test) val_test=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --typecheck) val_typecheck=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --visual) val_visual=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --smoke) val_smoke=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --json) enable_json; shift ;;
    -*) warn "pin-config: ignoring unknown flag: $1"; shift ;;
    *) shift ;;
  esac
done

[ -n "$config" ] || degrade missing-config "pin-config: --config <path> required"

# Record which command keys are already set, in EITHER the top-level *_cmd form or
# the nested commands: form (both are what preflight accepts).
has_test=0 has_typecheck=0 has_visual=0 has_smoke=0
record() {
  case "$1:$2" in
    test_cmd: | commands:test) has_test=1 ;;
    typecheck_cmd: | commands:typecheck) has_typecheck=1 ;;
    visual_cmd: | commands:visual) has_visual=1 ;;
    smoke_cmd: | commands:smoke) has_smoke=1 ;;
  esac
}
if [ -f "$config" ]; then
  parse_frontmatter "$config" record || degrade config-parse-failed "pin-config: cannot parse $config frontmatter - refusing to edit it"
fi

# Build the lines to append for each requested, unset command.
block=""
pinned=()
maybe_pin() { # key has-flag value
  local key=$1 already=$2 value=$3
  [ -n "$value" ] || return 0
  [ "$already" = 0 ] || return 0
  block="${block}${key}_cmd: ${value}"$'\n'
  pinned+=("$key")
}
maybe_pin test "$has_test" "$val_test"
maybe_pin typecheck "$has_typecheck" "$val_typecheck"
maybe_pin visual "$has_visual" "$val_visual"
maybe_pin smoke "$has_smoke" "$val_smoke"

if [ -z "$block" ]; then
  emit PINNED ""
  emit CONFIG "$config"
  done_ok
fi

mkdir -p "$(dirname "$config")" 2>/dev/null || true

# Persist the block. Both paths write to a temp first and are STATUS-CHECKED: if
# the write cannot land (parent is a file, or a read-only/full filesystem),
# degrade (exit 4) rather than falsely emitting PINNED - a could-not-persist must
# never report success (exit-code contract), and a bad temp never clobbers a
# hand-edited config.
if [ -f "$config" ] && [ "$(grep -c '^---[[:space:]]*$' "$config")" -ge 1 ]; then
  # Insert the new keys right after the OPENING fence (top of the frontmatter).
  # Keying on >=1 fence matches parse_frontmatter, which accepts a single
  # unterminated fence (EOF closes it) - so a hand-edited one-fence config is
  # amended in place, never wrapped/orphaned. ENVIRON (not awk -v) carries the
  # block so a backslash in a gate command is written verbatim, not escape-processed.
  tmp="$config.tmp.$$"
  if ADD_BLOCK="$block" awk '
      { print }
      /^---[[:space:]]*$/ && !inserted { printf "%s", ENVIRON["ADD_BLOCK"]; inserted = 1 }
    ' "$config" >"$tmp" && mv "$tmp" "$config"; then :; else
    rm -f "$tmp" 2>/dev/null || true
    degrade config-write-failed "pin-config: could not write $config"
  fi
else
  # No frontmatter yet: create one, preserving any existing notes below it.
  existing=""
  [ -f "$config" ] && existing=$(cat "$config")
  suffix=""
  [ -n "$existing" ] && suffix=$'\n'"$existing"$'\n'
  tmp="$config.tmp.$$"
  if printf -- '---\n%s---\n%s' "$block" "$suffix" >"$tmp" && mv "$tmp" "$config"; then :; else
    rm -f "$tmp" 2>/dev/null || true
    degrade config-write-failed "pin-config: could not write $config"
  fi
fi

emit PINNED "$(join_by , "${pinned[@]}")"
emit CONFIG "$config"
done_ok
