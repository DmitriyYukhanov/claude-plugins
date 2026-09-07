#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

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
    # a << inside a quoted string is text, not an operator. An odd number of quotes before it
    # means we are inside one, and opening a heredoc there swallows the real command below.
    local before=${line%%<<*} sq dq
    sq=${before//[^\']/}
    dq=${before//[^\"]/}
    if [ $((${#sq} % 2)) -eq 0 ] && [ $((${#dq} % 2)) -eq 0 ] &&
      [[ "$line" =~ \<\<(-)?[[:space:]]*(\'|\")?([A-Za-z_][A-Za-z0-9_]*)(\'|\")? ]]; then
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
