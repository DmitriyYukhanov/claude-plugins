#!/usr/bin/env bash
# merge-guard.sh - the merge gate as physics (spec sec 4.5). A PreToolUse command
# hook: reads the hook JSON on stdin, finds the target branch of a merge command,
# and ALLOWS it only when a valid approval marker exists (present and unused and
# fresh <30min and its head-SHA still matches the PR head). Otherwise it DENYs
# with the exact remedy. `--admin` is always denied; a force-push asks.
#
# Because plugin agents ignore hooks, merge commands must run only in the MAIN
# session - this guard protects that session.
#
# Output: {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#          "permissionDecision":"allow|deny|ask","permissionDecisionReason":"..."}}
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

emit_decision() { # decision reason
  local r
  r=$(json_escape "$2")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' \
    "$1" "$r" "$r"
}
allow() { emit_decision allow "$1"; exit 0; }
deny() { emit_decision deny "$1"; exit 0; }
ask() { emit_decision ask "$1"; exit 0; }
# passthrough: NOT a guarded command. Emit no permissionDecision so Claude Code's
# normal permission flow handles it -- returning "allow" here would auto-approve
# every Bash command the hook sees (it matches the whole Bash tool).
passthrough() { printf '{"continue":true,"suppressOutput":true}\n'; exit 0; }

# extract_command JSON -> the tool_input.command value, JSON-unescaped. A pure-bash
# scanner (no jq/perl dependency in the hot path) that honours backslash escapes,
# so a quoted script path ("D:/Code Stage/...") or an embedded quote can't truncate
# the command the way a naive "[^"]*" match would.
extract_command() {
  local s=$1 after out="" i n c esc=0 key='"command"'
  case "$s" in *"$key"*) : ;; *) printf ''; return ;; esac
  after=${s#*"$key"}
  after=${after#*:}                              # past the colon
  after=${after#"${after%%[![:space:]]*}"}       # ltrim whitespace
  case "$after" in \"*) after=${after#\"} ;; *) printf ''; return ;; esac
  n=${#after}
  for ((i = 0; i < n; i++)); do
    c=${after:i:1}
    if [ "$esc" = 1 ]; then
      case "$c" in
        n) out+=$'\n' ;;
        t) out+=$'\t' ;;
        r) out+=$'\r' ;;
        *) out+=$c ;;
      esac
      esc=0
    elif [ "$c" = "\\" ]; then
      esc=1
    elif [ "$c" = '"' ]; then
      break
    else
      out+=$c
    fi
  done
  printf '%s' "$out"
}

# merge_branch_of COMMAND -> the branch a `gh pr merge` targets: the first
# non-flag positional (skipping value-taking flags), else the current HEAD.
merge_branch_of() {
  local rest=${1#*gh pr merge} tok skip=0
  for tok in $rest; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$tok" in
      -R | --repo | -b | --body | -t | --subject | --body-file | --match-head-commit | --author-email)
        skip=1; continue ;;
      --repo=* | --body=* | --subject=* | --body-file=*) continue ;;
      -*) continue ;;
      *) printf '%s' "$tok"; return ;;
    esac
  done
  git rev-parse --abbrev-ref HEAD 2>/dev/null || printf ''
}

input=$(cat)
# Fast path: only merge / push commands are guarded; everything else defers to the
# normal permission flow without the char-scan.
case "$input" in
  *merge* | *push*) : ;;
  *) passthrough ;;
esac

cmd=$(extract_command "$input")
# Collapse whitespace runs, then strip quotes, so odd spacing (`gh  pr  merge`) and
# a quoted script path (`"...worktree.sh" merge`, which would otherwise hide the
# `worktree.sh merge` substring) can't slip a merge command past the matchers. A
# branch name never contains a quote, so removing them is safe for extraction.
cmd=$(printf '%s' "$cmd" | tr -s '[:space:]' ' ' | tr -d '\042\047')

# Never allow an admin bypass of branch protection.
case "$cmd" in
  *"gh pr merge"*"--admin"*) deny "gh pr merge --admin is forbidden - never bypass branch protection. Merge normally after approval." ;;
esac

# A force-push is a human call: match --force, -f, or a +refspec.
case "$cmd" in
  *"git push"*"--force"* | *"git push"*" -f"* | *"git push"*" +"*)
    ask "force-push detected - confirm this manually." ;;
esac

# Identify the guarded merge command and its target branch.
branch=""
is_gh_merge=0
case "$cmd" in
  *"worktree.sh merge"*)
    branch=$(printf '%s' "$cmd" | grep -oE -- '--branch[ =]+[^ ]+' | head -1 | sed -E 's/--branch[ =]+//')
    ;;
  *"gh pr merge"*)
    is_gh_merge=1
    branch=$(merge_branch_of "$cmd")
    ;;
esac

# Anything that is not a guarded merge command defers to normal permission flow.
[ -n "$branch" ] || passthrough

root=$(repo_root)
marker=$(marker_path "$root" "$branch")

[ -f "$marker" ] || deny "no approval marker for $branch. The model must run approve.sh after judging the reply an unambiguous go-ahead. You can still merge manually in a terminal."
used=$(marker_used "$marker")
[ "$used" = false ] || deny "the approval for $branch was already used (single-use). Re-approve to merge again."
created=$(marker_str_field "$marker" created_at)
epoch=$(epoch_of "$created")
[ -n "$epoch" ] || deny "the approval marker timestamp is unparseable. Re-approve."
age=$(($(now_epoch) - epoch))
[ "$age" -le 1800 ] || deny "the approval for $branch is stale (>30 min old). Re-approve."
marker_sha=$(marker_str_field "$marker" pr_head_sha)
cur_sha=$(gh pr view "$branch" --json headRefOid --jq .headRefOid 2>/dev/null || printf '')
if [ -z "$cur_sha" ] || [ "$marker_sha" != "$cur_sha" ]; then
  deny "the PR head for $branch moved since approval. Re-approve so the marker matches the new head."
fi

# On the direct `gh pr merge` path, consume the marker now so one approval buys one
# merge even without worktree.sh (which consumes on success for the sanctioned path).
if [ "$is_gh_merge" = 1 ]; then
  marker_set_used "$marker"
fi
allow "approval marker for $branch is valid (present, unused, fresh, head-SHA matches)."
