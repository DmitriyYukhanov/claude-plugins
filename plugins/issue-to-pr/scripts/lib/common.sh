#!/usr/bin/env bash

[ -n "${_ITP_COMMON_SOURCED:-}" ] && return 0
_ITP_COMMON_SOURCED=1

_ITP_OUT_KEYS=()
_ITP_OUT_VALS=()

emit() {
  _ITP_OUT_KEYS+=("$1")
  _ITP_OUT_VALS+=("${2-}")
}

json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

flush_output() {
  local n=${#_ITP_OUT_KEYS[@]}
  local i
  for ((i = 0; i < n; i++)); do
    printf '%s=%s\n' "${_ITP_OUT_KEYS[$i]}" "${_ITP_OUT_VALS[$i]}"
  done
}

stop() {
  local reason=$1
  shift
  emit STOP_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 2
}

fallback() {
  local reason=$1
  shift
  emit FALLBACK_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 3
}

degrade() {
  local reason=$1
  shift
  emit DEGRADED_REASON "$reason"
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 4
}

done_ok() {
  flush_output
  exit 0
}

warn() {
  printf '%s\n' "$*" >&2
}

repo_root() {
  local r
  r=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)
  if [ -n "$r" ] && [ -e "$r/.git" ]; then printf '%s' "$r"; return 0; fi
  git rev-parse --show-toplevel 2>/dev/null || printf ''
}

assert_numeric_issue() {
  case "$1" in
    '' | *[!0-9]*) degrade invalid-issue "${2:-script}: issue must be a number, got '$1'" ;;
  esac
}

canonical_branch() {
  local resolved
  resolved=$(gh pr view "$1" --json headRefName --jq .headRefName 2>/dev/null) || resolved=""
  printf '%s' "${resolved:-$1}"
}

state_dir() { printf '%s/.claude/issue-to-pr' "$1"; }

ensure_state_dir() {
  local dir=$1 gi="$1/.gitignore"
  mkdir -p "$dir" 2>/dev/null || return 1
  [ -s "$gi" ] && return 0
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

json_str_field() {
  grep -oE "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"
}

hook_decision() {
  local r
  r=$(json_escape "$2")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"},"systemMessage":"%s"}\n' \
    "$1" "$r" "$r"
}
hook_deny() { hook_decision deny "$1"; exit 0; }
hook_ask() { hook_decision ask "$1"; exit 0; }
hook_passthrough() { printf '{"continue":true,"suppressOutput":true}\n'; exit 0; }

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
