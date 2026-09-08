#!/usr/bin/env bash

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

repo_root() { # the one place every worktree of this clone agrees on
  local r
  r=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)
  if [ -n "$r" ] && [ -e "$r/.git" ]; then printf '%s' "$r"; return 0; fi
  # a bare clone has no main checkout; its worktrees share the common dir instead
  git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || printf ''
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

branch_dir() { # root branch -> everything one run owns: receipt, gate logs, design
  # a dash doubles before a slash collapses, so no two branch names can name one directory -
  # which matters because cleanup rm -rf's this path
  printf '%s/branch-%s' "$(state_dir "$1")" "$(printf '%s' "$2" | sed 's/-/--/g; s|/|-|g')"
}

receipt_path() { # root branch
  printf '%s/receipt.json' "$(branch_dir "$1" "$2")"
}

receipt_write() { # root branch head_sha gates
  local dir
  dir=$(branch_dir "$1" "$2")
  ensure_state_dir "$(state_dir "$1")" || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '{"branch":"%s","head_sha":"%s","gates":"%s","created_at":"%s"}\n' \
    "$(json_escape "$2")" "$(json_escape "$3")" "$(json_escape "$4")" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$dir/receipt.json"
}

review_state() { # branch -> clear | changes_requested | unresolved_threads | unreadable
  local meta decision requested url owner repo num threads unresolved total
  meta=$(gh pr view "$1" --json reviewDecision,latestReviews,url --jq \
    '"\(.reviewDecision // "")\t\([ .latestReviews[]? | select(.state == "CHANGES_REQUESTED") ] | length)\t\(.url)"' \
    2>/dev/null) || meta=""
  if [ -z "$meta" ]; then printf 'unreadable'; return 0; fi
  decision=$(printf '%s' "$meta" | cut -f1)
  requested=$(printf '%s' "$meta" | cut -f2)
  url=$(printf '%s' "$meta" | cut -f3)
  if [ "$decision" = CHANGES_REQUESTED ] || [ "${requested:-0}" != 0 ]; then
    printf 'changes_requested'; return 0
  fi

  num=${url##*/}
  repo=${url%/pull/*}; repo=${repo##*/}
  owner=${url%/*/pull/*}; owner=${owner##*/}
  case "$num" in '' | *[!0-9]*) printf 'unreadable'; return 0 ;; esac

  # shellcheck disable=SC2016  # $o/$r/$n are GraphQL variables, not shell expansions
  threads=$(gh api graphql \
    -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){totalCount nodes{isResolved}}}}}' \
    -f o="$owner" -f r="$repo" -F n="$num" \
    --jq '.data.repository.pullRequest.reviewThreads | "\([.nodes[] | select(.isResolved == false)] | length)\t\(.totalCount)"' \
    2>/dev/null) || threads=""
  unresolved=$(printf '%s' "$threads" | cut -f1)
  total=$(printf '%s' "$threads" | cut -f2)
  case "$unresolved$total" in '' | *[!0-9]*) printf 'unreadable'; return 0 ;; esac
  if [ "$unresolved" -ne 0 ]; then printf 'unresolved_threads'; return 0; fi
  # one page is all the query asks for; past it, "none unresolved" would be a guess
  if [ "$total" -gt 100 ]; then printf 'unreadable'; return 0; fi
  printf 'clear'
}

json_str_field() {
  grep -oE "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"
}
