#!/usr/bin/env bash
# pin-config.sh - self-writing config (spec sec 5.6). After a run whose auto-detected
# gate commands passed, pin them to .claude/issue-to-pr/config.md so later runs skip
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

# Not a bare mkdir: pin-config can be the first thing to write into the state dir
# (a resumed run whose Step 0 ran in an earlier session), and that directory has
# to ignore itself from its first file onward, not from whenever preflight lands.
#
# A refusal is honoured, not swallowed: the file about to be written carries the
# project's board URL and gate commands, and without the ignore rule it lands in the
# repository as an ordinary untracked file that the next `git add -A` commits.
# The ignore rule is written ONLY into the plugin's own directory. `--config` can name
# anywhere, and dropping a `*` into a directory the caller chose would hide their files
# from git - a far worse outcome than the untracked config this is meant to prevent.
# A directory is not a file to write into, and `--config .claude/issue-to-pr` names the
# state dir itself: dirname would then strip the wrong segment, the check below would miss,
# and pin-config would try to create a plain file exactly where the state directory goes.
[ -d "$config" ] && degrade invalid-config "pin-config: --config must name a file, not the directory $config"

# Recognised through the shared predicate rather than re-derived here: this file already
# shipped one hand-rolled version of that match which missed the relative form.
# `dirname`, not ${config%/*}: on Git Bash dirname splits backslashes too, and the
# parameter expansion silently turned a Windows-native --config into "." - pinning nothing.
config_dir=$(dirname "$config")
if is_state_dir_path "$config_dir"; then
  ensure_state_dir "$config_dir" ||
    degrade state-dir-failed "pin-config: could not create $config_dir with its ignore rule - refusing to write a config the repository would pick up"
else
  mkdir -p "$config_dir" 2>/dev/null ||
    degrade config-write-failed "pin-config: could not create $config_dir"
fi

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
  ADD_BLOCK="$block" atomic_replace "$config" awk '
      { print }
      /^---[[:space:]]*$/ && !inserted { printf "%s", ENVIRON["ADD_BLOCK"]; inserted = 1 }
    ' "$config" ||
    degrade config-write-failed "pin-config: could not write $config"
else
  # No frontmatter yet: create one, preserving any existing notes below it.
  existing=""
  [ -f "$config" ] && existing=$(cat "$config")
  suffix=""
  [ -n "$existing" ] && suffix=$'\n'"$existing"$'\n'
  atomic_replace "$config" printf -- '---\n%s---\n%s' "$block" "$suffix" ||
    degrade config-write-failed "pin-config: could not write $config"
fi

emit PINNED "$(join_by , "${pinned[@]}")"
emit CONFIG "$config"
done_ok
