#!/usr/bin/env bash
# lib/common.sh - shared helpers. Sourced, never executed.
#
# Output: emit() buffers KEY=VALUE, flush_output() prints it; hints go to stderr via
# warn() so the machine block stays clean.
# Exit codes: 0 proceed | 2 stop-and-ask (STOP_REASON=) | 3 sandbox fallback
# | 4 degraded (do it by hand) | anything else = bug.
#
# No system `jq`: gh JSON goes through gh's bundled --jq, so these run on any Git Bash.

# Source-once guard: re-sourcing must not re-run readonly declarations.
[ -n "${_ITP_COMMON_SOURCED:-}" ] && return 0
_ITP_COMMON_SOURCED=1

# -- Output buffer -----------------------------------------------------------
# Parallel indexed arrays preserve insertion order (associative arrays do not).
_ITP_OUT_KEYS=()
_ITP_OUT_VALS=()

# emit KEY VALUE - buffer one machine-block pair.
emit() {
  _ITP_OUT_KEYS+=("$1")
  _ITP_OUT_VALS+=("${2-}")
}

# json_escape STRING - minimal JSON string escaping (backslash, quote, control).
json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# flush_output - print the buffered pairs once, in the selected format.
flush_output() {
  local n=${#_ITP_OUT_KEYS[@]}
  local i
  for ((i = 0; i < n; i++)); do
    printf '%s=%s\n' "${_ITP_OUT_KEYS[$i]}" "${_ITP_OUT_VALS[$i]}"
  done
}

# -- Structured exits (each flushes the buffer, then exits with its code) ------

# stop REASON [hint...] - human-judgment stop. REASON is machine-readable.
stop() {
  local reason=$1
  shift
  emit STOP_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 2
}

# fallback REASON [hint...] - sandbox/permission denial; caller does it in place.
fallback() {
  local reason=$1
  shift
  emit FALLBACK_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 3
}

# degrade REASON [hint...] - could not parse/reach something; model does it by hand.
degrade() {
  local reason=$1
  shift
  emit DEGRADED_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 4
}

# done_ok - flush and exit 0. (Named done_ok to avoid clobbering shell builtins.)
done_ok() {
  flush_output
  exit 0
}

# -- Small utilities ---------------------------------------------------------

# warn MESSAGE... - human hint to stderr (never pollutes the machine block).
warn() {
  printf '%s\n' "$*" >&2
}

# repo_root - the main working tree (first `git worktree list` entry), falling
# back to the toplevel of cwd. Empty string if not inside a git repository. The
# gate receipt lives under this root, so it is shared across worktrees.
repo_root() {
  local r
  r=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)
  # `git worktree list` puts a BARE main worktree first, and a bare directory holds no
  # project to work in: `.git` (a dir in a checkout, a file in a linked one) is absent there.
  if [ -n "$r" ] && [ -e "$r/.git" ]; then printf '%s' "$r"; return 0; fi
  git rev-parse --show-toplevel 2>/dev/null || printf ''
}

# assert_numeric_issue VALUE SCRIPT - the issue number is the only caller-supplied
# value that gets spliced into a state-dir or worktree path, and those paths are
# later handed to `rm -rf`. A token carrying `..` (a fabricated number, a fragment
# copied out of a URL) would escape the directory it is meant to stay inside, so
# anything non-numeric stops the script before a path is ever built from it.
assert_numeric_issue() {
  case "$1" in
    '' | *[!0-9]*) degrade invalid-issue "${2:-script}: issue must be a number, got '$1'" ;;
  esac
}

# canonical_branch REF - the branch a gh ref names: a PR number resolves to that PR's
# head branch, a branch name resolves to itself. An unresolvable ref (no such PR,
# offline, old gh) comes back UNCHANGED so the caller's own error path still fires.
# The merge keys its gate receipt through here, because `merge --branch 42` must find
# the receipt run-gates.sh wrote under the branch name, not miss it and refuse a head
# whose gates were green.
canonical_branch() {
  local resolved
  resolved=$(gh pr view "$1" --json headRefName --jq .headRefName 2>/dev/null) || resolved=""
  printf '%s' "${resolved:-$1}"
}

# state_dir ROOT - where everything this plugin writes into a repository lives: the
# the config, gate receipts, the friction log. One definition, because the path is
# spliced into a receipt name, a config path and an ignore rule that must agree.
state_dir() { printf '%s/.claude/issue-to-pr' "$1"; }

# ensure_state_dir DIR - create it and make it hide itself. `*` is the FIRST rule
# because gitignore lets the LAST match decide, so a `!keep-this` added below still wins.
# The project's own .gitignore is never touched.
#
# Returns non-zero when the rule could not be written, and callers MUST check: what lands
# here is otherwise ordinary untracked files.
# `-s` not `-e`: a zero-byte .gitignore is wreckage, not a rule, and treating it as
# "already set up" left the directory unignored forever. A non-empty file is left alone.
ensure_state_dir() {
  local dir=$1 gi="$1/.gitignore"
  mkdir -p "$dir" 2>/dev/null || return 1
  [ -s "$gi" ] && return 0
  # Written beside the target and moved into place, so a failed write leaves no
  # half-file. `2>` comes first: bash reports a failed redirect on stderr, and with
  # `>` first an unwritable state dir printed a raw internal path.
  local tmp="$gi.tmp.$$"
  if ! printf '%s\n' \
    '# issue-to-pr keeps its runtime state here: config, gate receipts, logs.' \
    '# The star is first so anything you add below can still be un-ignored with a ! rule.' \
    '*' 2>/dev/null >"$tmp" || ! mv "$tmp" "$gi" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
  return 0
}

# -- Gate receipt --------------------------------------------------------------
# run-gates.sh leaves one on an all-green run; worktree.sh merge refuses without one
# matching the PR head. The binding is the head SHA, not a timestamp: it answers whether
# the gates ran against the content being merged, and nothing can fake it into agreeing.

# run_dir ROOT ISSUE - a run's own files (design, gate logs). Under the self-ignoring
# state directory, NOT in the worktree, where test discovery and bundlers would find it.
run_dir() { # root issue
  printf '%s/runs/task-%s' "$(state_dir "$1")" "$2"
}

receipt_path() { # root branch
  printf '%s/gates-%s.json' "$(state_dir "$1")" "$(printf '%s' "$2" | tr '/' '-')"
}

receipt_write() { # file branch head_sha gates created_at
  ensure_state_dir "$(dirname "$1")" || return 1
  printf '{"branch":"%s","head_sha":"%s","gates":"%s","created_at":"%s"}
'     "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$4")" "$(json_escape "$5")" >"$1"
}

# review_state BRANCH - clear | changes_requested | unresolved_threads | unreadable.
# Fails CLOSED: a read that does not come back is `unreadable`, never `clear`.
#
# reviewDecision alone is unreliable - GitHub leaves it null on repos without a
# required-review rule, so a real "Request changes" would read as clear; the count of
# latest reviews in CHANGES_REQUESTED covers that. Unresolved threads are best-effort:
# the decision read already answered the blocking question.
review_state() { # branch
  local meta decision cr_reviews pr_num slug owner repo unresolved
  meta=$(gh pr view "$1" --json reviewDecision,latestReviews,number --jq     '"\(.reviewDecision // "")	\([ .latestReviews[]? | select(.state == "CHANGES_REQUESTED") ] | length)	\(.number)"'     2>/dev/null || printf '')
  if [ -z "$meta" ]; then printf 'unreadable'; return 0; fi
  decision=$(printf '%s' "$meta" | cut -f1)
  cr_reviews=$(printf '%s' "$meta" | cut -f2)
  pr_num=$(printf '%s' "$meta" | cut -f3)
  [ -n "$cr_reviews" ] || cr_reviews=0
  if [ "$decision" = CHANGES_REQUESTED ] || [ "$cr_reviews" != 0 ]; then
    printf 'changes_requested'; return 0
  fi
  slug=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || printf '/')
  owner=${slug%%/*}
  repo=${slug#*/}
  unresolved=0
  if [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$pr_num" ]; then
    # shellcheck disable=SC2016  # $o/$r/$n are GraphQL variables, not shell expansions
    unresolved=$(gh api graphql       -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{isResolved}}}}}'       -F o="$owner" -F r="$repo" -F n="$pr_num"       --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length'       2>/dev/null || printf '0')
  fi
  [ -n "$unresolved" ] || unresolved=0
  if [ "$unresolved" != 0 ]; then printf 'unresolved_threads'; else printf 'clear'; fi
}

# json_str_field FILE FIELD - value of a string field (branch|head_sha|gates|created_at).
json_str_field() {
  grep -oE "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"
}

# -- PreToolUse hook helpers (merge-guard.sh) ---------------------------------
# hook_decision DECISION REASON - emit a PreToolUse permission decision.
hook_decision() {
  local r
  r=$(json_escape "$2")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' \
    "$1" "$r" "$r"
}
hook_deny() { hook_decision deny "$1"; exit 0; }
hook_ask() { hook_decision ask "$1"; exit 0; }
# hook_passthrough - NOT a guarded command; emit no permissionDecision so Claude
# Code's normal permission flow handles it (returning "allow" would auto-approve
# every Bash command the hook sees, since it matches the whole Bash tool).
hook_passthrough() { printf '{"continue":true,"suppressOutput":true}\n'; exit 0; }

# strip_heredoc_bodies TEXT -> TEXT with every heredoc body blanked out, opener and
# terminator kept. A heredoc body is data, never command syntax, so merge-guard.sh must
# not substring-match inside one: a commit message quoting `gh pr merge` in prose would
# otherwise trip the guard describing it. `<<-DELIM` may tab-indent its terminator.
strip_heredoc_bodies() {
  local text=$1 line delim="" tab_strip=0 in_heredoc=0 out=""
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_heredoc" = 1 ]; then
      local check=$line
      if [ "$tab_strip" = 1 ]; then
        while [ "${check:0:1}" = "$(printf '\t')" ]; do check=${check:1}; done
      fi
      if [ "$check" = "$delim" ]; then
        in_heredoc=0
        out+="$line"$'\n'
      fi
      continue
    fi
    out+="$line"$'\n'
    if [[ "$line" =~ \<\<(-)?[[:space:]]*(\'|\")?([A-Za-z_][A-Za-z0-9_]*)(\'|\")? ]]; then
      tab_strip=0
      [ "${BASH_REMATCH[1]}" = "-" ] && tab_strip=1
      delim=${BASH_REMATCH[3]}
      in_heredoc=1
    fi
  done <<<"$text"
  printf '%s' "$out"
}

# hook_extract_command JSON -> the tool_input.command value, JSON-unescaped. A
# pure-bash scanner (no jq/perl) that honours backslash escapes, so a quoted path
# ("D:/Code Stage/...") or an embedded quote can't truncate the command the way a
# naive "[^"]*" match would.
hook_extract_command() {
  local s=$1 after out="" i n c esc=0 key='"command"'
  case "$s" in *"$key"*) : ;; *) printf ''; return ;; esac
  after=${s#*"$key"}
  after=${after#*:}
  after=${after#"${after%%[![:space:]]*}"}
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
