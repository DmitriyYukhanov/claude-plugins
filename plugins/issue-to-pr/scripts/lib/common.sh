#!/usr/bin/env bash
# lib/common.sh - shared helpers for the issue-to-pr scripts.
#
# Sourced, never executed. Provides the uniform output + exit-code contract that
# every script in this directory obeys, plus a few small gh/parse helpers.
#
# Output contract (spec sec 3):
#   - Scripts buffer KEY=VALUE pairs with emit(), then flush_output() prints them
#     as `KEY=VALUE` lines. Lists are comma-joined string values. board-sync.sh is
#     the one exception and prints a JSON object instead (enable_json).
#   - Human-readable hints go to stderr via warn(); the machine block stays clean.
# Exit-code contract (uniform):
#   0 proceed | 2 stop-and-ask (STOP_REASON=) | 3 sandbox/permission fallback
#   | 4 degraded (could not parse/reach X - do it by hand) | anything else = bug.
#
# No system `jq` dependency: gh JSON is read through gh's bundled `--jq`, and
# config/JSON parsing is hand-rolled bash, so the scripts run on any Git Bash.

# Source-once guard: re-sourcing must not re-run readonly declarations.
[ -n "${_ITP_COMMON_SOURCED:-}" ] && return 0
_ITP_COMMON_SOURCED=1

# -- Exit codes --------------------------------------------------------------
readonly EXIT_OK=0
readonly EXIT_STOP=2
readonly EXIT_FALLBACK=3
readonly EXIT_DEGRADED=4

# -- Output buffer -----------------------------------------------------------
# Parallel indexed arrays preserve insertion order (associative arrays do not).
OUTPUT_JSON=0
_ITP_OUT_KEYS=()
_ITP_OUT_VALS=()

# enable_json - switch flush_output to JSON-object mode. board-sync.sh is the only
# caller; every other script speaks KEY=VALUE.
enable_json() { OUTPUT_JSON=1; }

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
  if [ "$OUTPUT_JSON" = "1" ]; then
    printf '{'
    for ((i = 0; i < n; i++)); do
      [ "$i" -gt 0 ] && printf ','
      printf '"%s":"%s"' "$(json_escape "${_ITP_OUT_KEYS[$i]}")" "$(json_escape "${_ITP_OUT_VALS[$i]}")"
    done
    printf '}\n'
  else
    for ((i = 0; i < n; i++)); do
      printf '%s=%s\n' "${_ITP_OUT_KEYS[$i]}" "${_ITP_OUT_VALS[$i]}"
    done
  fi
}

# -- Structured exits (each flushes the buffer, then exits with its code) ------

# stop REASON [hint...] - human-judgment stop. REASON is machine-readable.
stop() {
  local reason=$1
  shift
  emit STOP_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit "$EXIT_STOP"
}

# fallback REASON [hint...] - sandbox/permission denial; caller does it in place.
fallback() {
  local reason=$1
  shift
  emit FALLBACK_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit "$EXIT_FALLBACK"
}

# degrade REASON [hint...] - could not parse/reach something; model does it by hand.
degrade() {
  local reason=$1
  shift
  emit DEGRADED_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit "$EXIT_DEGRADED"
}

# done_ok - flush and exit 0. (Named done_ok to avoid clobbering shell builtins.)
done_ok() {
  flush_output
  exit "$EXIT_OK"
}

# -- Small utilities ---------------------------------------------------------

# warn MESSAGE... - human hint to stderr (never pollutes the machine block).
warn() {
  printf '%s\n' "$*" >&2
}

# join_by SEP ITEM... - join arguments with SEP (empty string for zero items).
join_by() {
  local sep=$1
  shift
  local out="" first=1 x
  for x in "$@"; do
    if [ "$first" = 1 ]; then
      out=$x
      first=0
    else
      out="$out$sep$x"
    fi
  done
  printf '%s' "$out"
}

# slugify STRING - lowercase, non-alnum runs to '-', trimmed. Used for branch
# slugs and the gate-receipt filename (branch '/' -> '-').
slugify() {
  local s=${1-}
  s=$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]')
  s=$(printf '%s' "$s" | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-\+//' -e 's/-\+$//')
  printf '%s' "$s"
}

# gh_field ARGS... - run `gh ARGS...`, print stdout on success, empty on failure.
# Callers pass `--jq` for scalar extraction; failures never abort the caller.
gh_field() {
  gh "$@" 2>/dev/null || printf ''
}

# -- Frontmatter parser -------------------------------------------------------
# trim_quotes STRING - strip surrounding whitespace and one layer of matching quotes.
trim_quotes() {
  local v=$1
  v=${v#"${v%%[![:space:]]*}"}
  v=${v%"${v##*[![:space:]]}"}
  case "$v" in
    \"*\") v=${v#\"}; v=${v%\"} ;;
    \'*\') v=${v#\'}; v=${v%\'} ;;
  esac
  printf '%s' "$v"
}

# parse_frontmatter FILE CALLBACK - read a `.local.md` YAML-frontmatter subset
# (top-level scalars + one nesting level; CRLF-tolerant) and invoke
# `CALLBACK <top> <sub> <value>` per key (sub="" for a top-level scalar). Returns
# 1 on a structurally-invalid frontmatter line, 0 otherwise. Sharing this keeps
# the config reader honest about what counts as a set value.
parse_frontmatter() {
  local file=$1 cb=$2 in_fm=0 cur_top="" line val
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    if [ "$in_fm" = 0 ]; then
      [ "$line" = "---" ] && in_fm=1
      continue
    fi
    [ "$line" = "---" ] && return 0
    case "$line" in '' | '#'*) continue ;; esac
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]]; then
      cur_top=${BASH_REMATCH[1]}
      val=$(trim_quotes "${BASH_REMATCH[2]}")
      [ -n "$val" ] && "$cb" "$cur_top" "" "$val"
    elif [[ "$line" =~ ^[[:space:]]+([A-Za-z_][A-Za-z0-9_]*):[[:space:]]*(.*)$ ]]; then
      [ -n "$cur_top" ] || return 1
      "$cb" "$cur_top" "${BASH_REMATCH[1]}" "$(trim_quotes "${BASH_REMATCH[2]}")"
    else
      return 1
    fi
  done <"$file"
  return 0
}

# repo_root - the main working tree (first `git worktree list` entry), falling
# back to the toplevel of cwd. Empty string if not inside a git repository. The
# gate receipt lives under this root, so it is shared across worktrees.
repo_root() {
  local r
  r=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)
  if [ -n "$r" ]; then printf '%s' "$r"; return 0; fi
  git rev-parse --show-toplevel 2>/dev/null || printf ''
}

# resolve_under ROOT PATH - PATH unchanged when it is already absolute (POSIX, or a
# Windows drive letter in either slash), else PATH resolved under ROOT. Every path this
# plugin keys off something other than the caller's cwd goes through here: preflight's
# config file and worktree.sh's --salvage-to destination both used to be cwd-relative,
# and both landed somewhere the caller never meant when the run was not started from
# the repository root.
# A `\\server\share` UNC path is absolute without starting in a slash at all; missing it
# resolved a network path under the root, where nothing is. (`//server/share` needs no
# pattern of its own - `/*` already matches it.)
resolve_under() {
  case "$2" in
    /* | \\\\* | ?:/* | ?:\\*) printf '%s' "$2" ;;
    *) printf '%s/%s' "$1" "$2" ;;
  esac
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

# atomic_replace FILE CMD... - run CMD with stdout to a temp file beside FILE and,
# only if it succeeded, move it into place. Returns non-zero and leaves FILE alone
# otherwise. Five sites hand-rolled this dance and two of them used a `.tmp` name
# with no PID, so two concurrent runs on one file clobbered each other's temp.
# Every writer of a file this plugin owns goes through here now: the gate receipt
# and the state-dir ignore rule.
atomic_replace() {
  local file=$1 tmp="$1.tmp.$$"
  shift
  # `2>` comes FIRST so it is already in place when `>` is opened: bash reports a
  # failure to open a redirect target on stderr, so with the stdout redirect first
  # an unwritable state dir printed a raw internal path on a path built to fail quietly.
  if ! "$@" 2>/dev/null >"$tmp" || ! mv "$tmp" "$file" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
}

# -- Time helpers ------------------------------------------------------------
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

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

# ensure_state_dir DIR - create it and make it hide itself. The `.gitignore` carries `*`
# as its FIRST rule: gitignore lets the LAST match decide, so a `!keep-this` added below
# still wins, where a `*` at the bottom would silently override it. The project's own
# .gitignore is never touched - on a team where one person has the plugin installed, the
# others should never see a file they cannot place, and it is not this plugin's business
# to edit a tracked file to achieve that.
#
# Returns non-zero when the directory or the rule could not be written, and callers MUST
# check: what lands here carries the board URL, the pinned gate commands and live
# approvals. Without the rule those are ordinary untracked files that the next
# `git add -A` sweeps into somebody's commit.
# `-s` and not `-e`: a zero-byte .gitignore is not a rule, it is the wreckage of a write
# that died between the redirect truncating the file and anything landing in it. Treating
# it as "already set up" left the directory permanently unignored while every caller read
# the 0 as proof the rule was in place. A non-empty file is left alone, edits and all.
#
# Written through atomic_replace, like every other file this plugin owns, so the wreckage
# above cannot be produced here in the first place: the temp is moved into place only
# after it is whole.
ensure_state_dir() {
  local dir=$1 gi="$1/.gitignore"
  mkdir -p "$dir" 2>/dev/null || return 1
  [ -s "$gi" ] && return 0
  atomic_replace "$gi" printf '%s\n' \
    '# issue-to-pr keeps its runtime state here: config, gate receipts, logs.' \
    '# The star is first so anything you add below can still be un-ignored with a ! rule.' \
    '*' || return 1
  return 0
}

# -- Gate receipt --------------------------------------------------------------
# run-gates.sh leaves one on an all-green run; worktree.sh merge refuses without one
# matching the PR head. The binding is the head SHA, not a timestamp: it answers the
# only question that matters at the merge, whether the gates ran against the content
# being merged, and nothing else can fake it into agreeing.
receipt_path() { # root branch
  printf '%s/gates-%s.json' "$(state_dir "$1")" "$(printf '%s' "$2" | tr '/' '-')"
}

receipt_write() { # file branch head_sha gates created_at
  ensure_state_dir "$(dirname "$1")" || return 1
  printf '{"branch":"%s","head_sha":"%s","gates":"%s","created_at":"%s"}
'     "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$4")" "$(json_escape "$5")" >"$1"
}

# review_state BRANCH - clear | changes_requested | unresolved_threads | unreadable.
# Fails CLOSED: a read that does not come back is `unreadable`, never `clear`. The
# gate promises no merge lands over a requested change, and a promise that resolves
# to "probably fine" when the API hiccups is not one.
#
# reviewDecision alone is unreliable: GitHub leaves it null on repos WITHOUT a
# required-review rule, so a real "Request changes" would read as clear. The count of
# latest reviews in CHANGES_REQUESTED covers that. Unresolved inline threads are
# GraphQL-only and best-effort - an unreadable thread count is not a blocked merge,
# because the decision read already answered the blocking question.
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

# json_str_field FILE FIELD - value of a string field (branch|pr_head_sha|created_at).
json_str_field() {
  grep -oE "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"
}

# -- PreToolUse hook helpers (shared by merge-guard.sh + stage-guard.sh) -------
# hook_decision DECISION REASON - emit a PreToolUse permission decision.
hook_decision() {
  local r
  r=$(json_escape "$2")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' \
    "$1" "$r" "$r"
}
hook_allow() { hook_decision allow "$1"; exit 0; }
hook_deny() { hook_decision deny "$1"; exit 0; }
hook_ask() { hook_decision ask "$1"; exit 0; }
# hook_passthrough - NOT a guarded command; emit no permissionDecision so Claude
# Code's normal permission flow handles it (returning "allow" would auto-approve
# every Bash command the hook sees, since it matches the whole Bash tool).
hook_passthrough() { printf '{"continue":true,"suppressOutput":true}\n'; exit 0; }

# strip_heredoc_bodies TEXT -> TEXT with every heredoc body (the lines between a
# `<<[-]['"]?DELIM['"]?` opener and its bare DELIM terminator line) blanked out; opener
# and terminator lines are kept. A heredoc body is data handed to whatever reads it
# (cat, a nested shell...) -- the invoking shell never parses it as command syntax --
# so merge-guard.sh / stage-guard.sh must not substring-match inside one (a commit
# message that merely quotes `gh pr merge` or `git add -A` in prose would otherwise
# trip the guard it's describing). `<<-DELIM` may tab-indent its terminator line, so
# that variant's terminator is matched with leading tabs stripped.
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
