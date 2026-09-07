#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

input=$(cat)
case "$input" in
  *merge* | *push*) : ;;
  *) hook_passthrough ;;
esac

cmd=$(hook_extract_command "$input")
cmd=$(strip_heredoc_bodies "$cmd")
set -f
# shellcheck disable=SC2086 # deliberate word-splitting: that IS the whitespace squeeze
set -- $cmd
cmd="$*"
set +f
cmd=${cmd//\"/}
cmd=${cmd//\'/}

has_verbs() { # haystack word...
  local rest=" $1 " w
  shift
  for w; do
    case "$rest" in
      *" $w "*) rest=" ${rest#*" $w "}" ;;
      *) return 1 ;;
    esac
  done
}

case "$cmd" in
  *"--admin"*)
    has_verbs "$cmd" gh pr merge &&
      hook_deny "issue-to-pr: gh pr merge --admin is forbidden - never bypass branch protection." ;;
esac

unleased=${cmd//--force-with-lease/}
unleased=${unleased//--force-if-includes/}
if has_verbs "$unleased" git push; then
  case "$unleased" in
    *" --force"* | *" -f"* | *" +"*)
      hook_ask "issue-to-pr: force-push detected - confirm this manually." ;;
  esac
fi

hook_passthrough
