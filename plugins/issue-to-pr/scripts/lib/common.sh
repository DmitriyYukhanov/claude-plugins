#!/usr/bin/env bash

_ITP_OUT_KEYS=()
_ITP_OUT_VALS=()

emit() {
  _ITP_OUT_KEYS+=("$1")
  _ITP_OUT_VALS+=("${2-}")
}

flush_output() {
  local i
  for ((i = 0; i < ${#_ITP_OUT_KEYS[@]}; i++)); do
    printf '%s=%s\n' "${_ITP_OUT_KEYS[$i]}" "${_ITP_OUT_VALS[$i]}"
  done
}

stop() { # reason [hint]: exit 2, nothing irreversible happened
  emit STOP_REASON "$1"
  shift
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 2
}

degrade() { # reason [hint]: exit 4, the call itself was wrong
  emit DEGRADED_REASON "$1"
  shift
  flush_output
  [ "$#" -gt 0 ] && printf '%s\n' "$*" >&2
  exit 4
}

done_ok() {
  flush_output
  exit 0
}

warn() { printf '%s\n' "$*" >&2; }

repo_root() { # the one place every worktree of this clone agrees on
  local r
  r=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | head -1)
  if [ -n "$r" ] && [ -e "$r/.git" ]; then printf '%s' "$r"; return 0; fi
  # a bare clone has no main checkout; its worktrees share the common dir instead
  git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || printf ''
}

assert_numeric_issue() { # the issue number ends up in a path cleanup rm -rf's
  case "$1" in
    '' | *[!0-9]*) degrade invalid-issue "${2:-script}: issue must be a number, got '$1'" ;;
  esac
}

state_dir() { printf '%s/.claude/issue-to-pr' "$1"; }

ensure_state_dir() { # creates it with a .gitignore whose first rule is *, never clobbers one
  local dir=$1 gi="$1/.gitignore" tmp
  mkdir -p "$dir" 2>/dev/null || return 1
  [ -s "$gi" ] && return 0
  tmp="$gi.tmp.$$"
  if ! printf '%s\n' \
    '# issue-to-pr keeps its runtime state here: config, gate receipts, logs.' \
    '# The star is first so anything you add below can still be un-ignored with a ! rule.' \
    '*' 2>/dev/null >"$tmp" || ! mv "$tmp" "$gi" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
    return 1
  fi
  return 0
}

branch_dir() { # root branch -> the directory one run owns (receipt, gate logs)
  # a dash doubles before a slash collapses, so no two branch names share a directory;
  # cleanup rm -rf's this path
  printf '%s/branch-%s' "$(state_dir "$1")" "$(printf '%s' "$2" | sed 's/-/--/g; s|/|-|g')"
}

receipt_path() { printf '%s/receipt.json' "$(branch_dir "$1" "$2")"; }

json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
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

json_str_field() { # file key -> the string value, or empty
  grep -oE "\"$2\":\"[^\"]*\"" "$1" 2>/dev/null | head -1 | sed -E "s/.*\"$2\":\"([^\"]*)\".*/\1/"
}
