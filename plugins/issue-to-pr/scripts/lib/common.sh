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
# config/marker parsing is hand-rolled bash, so the scripts run on any Git Bash.

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
# slugs and the approval-marker filename (branch '/' -> '-').
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
# approval marker lives under this root, so it is shared across worktrees.
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
# with no PID, so two concurrent runs on one marker clobbered each other's temp.
# Every writer of a file this plugin owns goes through here now: marker_set_used,
# marker_refresh and the state-dir ignore rule.
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
now_epoch() { date +%s; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# epoch_of ISO8601 - epoch seconds, or empty if the timestamp cannot be parsed.
#
# Two dialects, because the merge gate treats an unparseable timestamp as fatal:
# GNU (Linux, Git Bash) and BSD `date -j -f` (macOS). With only the GNU form, every
# approval on macOS would be undatable and Step 11 would refuse every merge forever,
# re-approving into the identical stop.
#
# `--date=` and not `-d`, which is why the fallback can be trusted to fire: BSD's `-d`
# is the daylight-saving flag, so `date -d <iso> +%s` there does not reliably fail - it
# can consume the timestamp as a DST value and print the CURRENT epoch, which would date
# every marker to "now" (approvals that never expire and are never swept). BSD has no
# `--date` at all, so the long form errors out cleanly and the BSD branch below runs.
# GNU accepts both spellings, so this costs nothing on the platform that runs it most.
#
# The empty string is rejected up front: `date --date=''` does NOT fail, it returns
# today's midnight, so a marker whose created_at could not be read would be handed
# a plausible-looking epoch - old enough to be swept as stale for most of the day,
# and fresh enough to pass the merge gate just after midnight.
epoch_of() {
  [ -n "${1:-}" ] || return 0
  date --date="$1" +%s 2>/dev/null && return 0
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null && return 0
  printf ''
}

# -- Approval marker (shared by approve.sh, merge-guard.sh, worktree.sh merge) -
# How long an approval stays valid. One definition: the sweeper that deletes markers
# and the two gates that validate them have to agree, or preflight deletes approvals
# the merge gate would still honour (or dead ones pile up).
# shellcheck disable=SC2034  # read by merge-guard.sh and worktree.sh, which source this file
APPROVAL_TTL=1800
# One file per branch under the state dir, branch '/' -> '-'. The marker is
# single-use and short-lived: a successful merge deletes it (marker_consume) and
# preflight sweeps anything past the validity window, so none of them pile up.
# JSON is hand-written/parsed (no jq): quote is escaped and placed last so a
# hostile quote cannot spoof the scalar fields parsed before it.

# canonical_branch REF - the branch a gh ref names: a PR number resolves to that PR's
# head branch, a branch name resolves to itself. An unresolvable ref (no such PR,
# offline, old gh) comes back UNCHANGED so the caller's own error path still fires.
# All three gates key the marker through here - approve.sh writing it, merge-guard.sh
# and worktree.sh merge reading it - because `gh pr merge 42` must find the approval
# that `approve.sh 42` wrote under the branch name, not miss it and re-ask.
canonical_branch() {
  local resolved
  resolved=$(gh pr view "$1" --json headRefName --jq .headRefName 2>/dev/null) || resolved=""
  printf '%s' "${resolved:-$1}"
}

# state_dir ROOT - where everything this plugin writes into a repository lives: the
# pinned config, approval markers, the friction log. One definition, because the path
# is spliced into a marker name, a config path and an ignore rule that must agree.
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
    '# issue-to-pr keeps its runtime state here: pinned config, approval markers, logs.' \
    '# The star is first so anything you add below can still be un-ignored with a ! rule.' \
    '*' || return 1
  return 0
}

marker_path() { # root branch
  printf '%s/approval-%s.json' "$(state_dir "$1")" "$(printf '%s' "$2" | tr '/' '-')"
}

marker_write() { # file branch sha quote created_at used(true|false)
  local file=$1
  # Not a bare mkdir: an approval is often the first thing written into the state dir,
  # and the directory has to ignore itself from its first file onward.
  ensure_state_dir "$(dirname "$file")" || return 1
  printf '{"branch":"%s","pr_head_sha":"%s","created_at":"%s","used":%s,"quote":"%s"}\n' \
    "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$5")" "$6" "$(json_escape "$4")" >"$file"
}

# marker_quote FILE - the recorded verbatim reply, made readable. Read separately
# from marker_str_field because a quote is the one field that legitimately CONTAINS
# escaped double quotes, and that helper's `"[^"]*"` match stops at the first one.
# The quote is written last precisely so everything after the opening `"` up to the
# final `"}` is the value, however many quotes it contains.
#
# Escaped whitespace becomes a SPACE, not the character it stands for: the machine
# block is one KEY=VALUE per line, so restoring a newline here would split the value
# across two lines and corrupt every key a reader parses after it. A multi-line
# approval is reported on one line; the words are what matter.
marker_quote() {
  local line s
  line=$(head -1 "$1" 2>/dev/null) || return 0
  line=${line%$'\r'}
  case "$line" in *'"quote":"'*) : ;; *) return 0 ;; esac
  s=${line#*\"quote\":\"}
  s=${s%\"\}}
  # json_escape only escapes backslash, quote, \n, \r and \t, so any OTHER control
  # byte the user's reply happened to carry is still sitting in the value raw - and
  # a raw \001 would be indistinguishable from the sentinel below, handing back a
  # spurious backslash and miscounting any real one next to it. Fold them to spaces
  # first, on the same principle as \n: this is a one-line report of what was said.
  s=${s//$'\001'/ }
  # Escaped backslashes are parked on the (now unambiguous) sentinel BEFORE anything
  # else is decoded. Substituting escape by escape is not the inverse of escaping
  # them: json_escape doubles backslashes first, so `C:\notes` is stored `C:\\notes`,
  # and decoding `\n` first would match the second backslash plus the n and eat both.
  s=${s//\\\\/$'\001'}
  s=${s//\\n/ }
  s=${s//\\r/ }
  s=${s//\\t/ }
  s=${s//\\\"/\"}
  s=${s//$'\001'/\\}
  printf '%s' "$s"
}

# marker_str_field FILE FIELD - value of a string field (branch|pr_head_sha|created_at).
marker_str_field() {
  grep -oE "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"
}

# marker_used FILE - the boolean `used` value (true|false), empty if absent.
marker_used() {
  grep -oE '"used":(true|false)' "$1" 2>/dev/null | head -1 | sed -E 's/.*"used"://'
}

# marker_set_used FILE - flip used:false -> used:true in place (single-use consume).
# Returns non-zero unless THIS call performed the transition. Callers MUST check: an
# approval that cannot be spent is one that authorises every later merge attempt
# for the rest of its freshness window, which is the opposite of single-use.
#
# Both the before and after are read, because a status check alone cannot see either
# failure. `sed` exits 0 when its pattern matched nothing, so flipping a marker that
# already said `true` reported success just like a real flip - and the whole point of
# the caller's `|| hook_deny` is to distinguish "I spent this approval" from "somebody
# else already did". The read-back also keeps this honest if marker_used's regex and
# the substitution above ever drift apart; they are two spellings of one field.
#
# This narrows the window rather than closing it: two hook processes can still both
# read `false` before either writes. Truly concurrent merges of one branch need an
# atomic test-and-set, which this file has no primitive for; the sequential retry -
# far and away the likelier shape - is now refused.
marker_set_used() {
  [ "$(marker_used "$1")" = false ] || return 1
  atomic_replace "$1" sed 's/"used":false/"used":true/' "$1" || return 1
  [ "$(marker_used "$1")" = true ]
}

# sed_repl STRING - STRING made safe to splice into the right-hand side of a `s///`.
# `&` there means "the whole match" and `\` starts a backreference, so an unescaped
# value does not fail, it silently writes something else - the one outcome a
# status-checked writer cannot catch.
sed_repl() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//&/\\&}
  s=${s//\//\\/}
  printf '%s' "$s"
}

# marker_refresh FILE SHA CREATED - re-stamp the head-SHA and timestamp after a pure
# base merge. Lives here so approve.sh does not become a second place that knows the
# marker's on-disk JSON layout; marker_write's format and this rewriter cannot drift.
#
# The result is READ BACK, because a status check alone cannot catch the failure that
# matters here: `sed` exits 0 when its pattern matched nothing, so a marker whose layout
# differs at all (hand-edited, truncated, written by an older version) would be rewritten
# to itself and reported REFRESHED. The merge would then stop at "PR head moved since
# approval" with nothing connecting that to a refresh it was told had worked.
marker_refresh() {
  atomic_replace "$1" sed -E \
    "s/\"pr_head_sha\":\"[^\"]*\"/\"pr_head_sha\":\"$(sed_repl "$2")\"/; s/\"created_at\":\"[^\"]*\"/\"created_at\":\"$(sed_repl "$3")\"/" \
    "$1" || return 1
  [ "$(marker_str_field "$1" pr_head_sha)" = "$2" ] &&
    [ "$(marker_str_field "$1" created_at)" = "$3" ]
}

# marker_consume FILE - a merge succeeded, so the approval has done its whole job:
# delete it. Flipping `used` first keeps the single-use check correct for anything
# already holding the path if the unlink loses a race.
#
# Returns non-zero when the approval is still usable afterwards - neither flagged
# nor removed. The caller cannot undo the merge that already happened, but it must
# say so: an approval left unused and fresh authorises every further merge attempt
# in its window, which is the single-use guarantee failing open.
marker_consume() {
  local file=$1 flagged=0
  marker_set_used "$file" && flagged=1
  rm -f "$file" 2>/dev/null
  [ ! -e "$file" ] || [ "$flagged" = 1 ]
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
