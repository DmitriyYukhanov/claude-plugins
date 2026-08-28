#!/usr/bin/env bash
# merge-guard.sh - PreToolUse hook. Two rules a hook can genuinely enforce: never allow
# an admin bypass of branch protection, and make a force-push a human decision.
# Everything else defers to the normal permission flow.
set -uo pipefail

# No fork: every caller invokes this by a path containing a slash.
SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

input=$(cat)
# Fast path: only merge / push commands are inspected at all.
case "$input" in
  *merge* | *push*) : ;;
  *) hook_passthrough ;;
esac

cmd=$(hook_extract_command "$input")
# A heredoc body is data: a commit message discussing this gate is not the command.
cmd=$(strip_heredoc_bodies "$cmd")
# Normalise spacing and quotes so neither can slip a guarded command past the matchers.
# Done in bash, not `printf | tr | tr`: this runs on every Bash call in every session,
# and three processes there cost more than the whole rest of the hook. `set -f` stops a
# `*` in the command from globbing while it is split.
set -f
# shellcheck disable=SC2086 # deliberate word-splitting: that IS the whitespace squeeze
set -- $cmd
cmd="$*"
set +f
cmd=${cmd//\"/}
cmd=${cmd//\'/}

# Match the verb chain IN ORDER, never as one contiguous phrase. Both `gh pr --repo o/r
# merge 7 --admin` and `git -C . push --force` put an option between the words, and that
# alone walked past the old substring matcher - the same shape as the quoted-subcommand
# bypass. Whole tokens only, so `remerge` is not `merge`.
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

# --force, -f, or a +refspec. `--force-with-lease` is exempt: it refuses when the remote
# moved since the last fetch, so it cannot overwrite a push nobody here has seen. Strip the
# lease flags first, so `--force-with-lease --force` still asks.
unleased=${cmd//--force-with-lease/}
unleased=${unleased//--force-if-includes/}
if has_verbs "$unleased" git push; then
  case "$unleased" in
    *" --force"* | *" -f"* | *" +"*)
      hook_ask "issue-to-pr: force-push detected - confirm this manually." ;;
  esac
fi

hook_passthrough
