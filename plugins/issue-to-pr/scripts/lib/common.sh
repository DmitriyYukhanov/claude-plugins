#!/usr/bin/env bash
# lib/common.sh - shared helpers for the issue-to-pr scripts.
#
# Sourced, never executed. Provides the uniform output + exit-code contract that
# every script in this directory obeys, plus a few small gh/parse helpers.
#
# Output contract (spec sec 3):
#   - Scripts buffer KEY=VALUE pairs with emit(), then flush_output() prints them
#     as `KEY=VALUE` lines (default) or a single flat JSON object (when --json is
#     set). Lists are comma-joined string values in both modes ("same keys").
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

# enable_json - switch subsequent flush_output to JSON-object mode. Scripts call
# this on --json (keeps the OUTPUT_JSON assignment + read in one file for lint).
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

# has_cmd NAME - true if NAME is on PATH.
has_cmd() {
  command -v "$1" >/dev/null 2>&1
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

# -- Frontmatter parser (shared by preflight.sh + pin-config.sh) --------------
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
# preflight (read config) and pin-config (idempotent append) from diverging.
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

# -- Time helpers ------------------------------------------------------------
now_epoch() { date +%s; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# epoch_of ISO8601 - epoch seconds, or empty if the timestamp cannot be parsed.
epoch_of() { date -d "$1" +%s 2>/dev/null || printf ''; }

# -- Approval marker (shared by approve.sh, merge-guard.sh, worktree.sh merge) -
# One file per branch under <root>/.claude/issue-to-pr/, branch '/' -> '-'. The
# marker is single-use: worktree.sh merge flips used->true on a successful merge.
# JSON is hand-written/parsed (no jq): quote is escaped and placed last so a
# hostile quote cannot spoof the scalar fields parsed before it.
marker_path() { # root branch
  printf '%s/.claude/issue-to-pr/approval-%s.json' "$1" "$(printf '%s' "$2" | tr '/' '-')"
}

marker_write() { # file branch sha quote created_at used(true|false)
  local file=$1
  mkdir -p "$(dirname "$file")"
  printf '{"branch":"%s","pr_head_sha":"%s","created_at":"%s","used":%s,"quote":"%s"}\n' \
    "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$5")" "$6" "$(json_escape "$4")" >"$file"
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
marker_set_used() {
  local file=$1 tmp="$1.tmp"
  sed 's/"used":false/"used":true/' "$file" >"$tmp" && mv "$tmp" "$file"
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
