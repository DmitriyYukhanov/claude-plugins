#!/usr/bin/env bash
# The issue-to-pr state marker. agent-dispatch vendors this file byte for byte; keep it bash 3.2.
# A comment's marker is its last line starting "<!-- issue-to-pr"; a state marker carries
# key=value fields. Unknown keys are ignored, so an older reader survives a newer writer.

# gh --jq over an issue's or PR's comments -> id, author, marker line, trimmed lowercased body
# shellcheck disable=SC2034 # read by the scripts that source this file
MARKER_JQ='.[] | [.id, .user.login, ((.body | split("\n") | map(rtrimstr("\r")) | map(select(startswith("<!-- issue-to-pr"))) | last) // ""), (.body | gsub("^\\s+|\\s+$"; "") | ascii_downcase)] | @tsv'

parse_marker() { # marker-line -> M_STATE M_PR M_HEAD M_IREAD M_PREAD; rc 1 unless a well-formed state marker
  local m=${1%$'\r'} tok k v toks
  M_STATE='' M_PR='' M_HEAD='' M_IREAD='' M_PREAD=''
  case "$m" in '<!-- issue-to-pr '*' -->') ;; *) return 1 ;; esac
  m=${m#'<!-- issue-to-pr '}
  m=${m%' -->'}
  case "$m" in *[![:space:]]*) ;; *) return 1 ;; esac # bash 3.2: never expand an empty array
  read -r -a toks <<<"$m"
  for tok in "${toks[@]}"; do
    k=${tok%%=*}
    v=${tok#*=}
    [ "$k" != "$tok" ] || continue
    case "$k" in
      state) M_STATE=$v ;;
      step) ;; # the resuming model reads it; no script does
      head) M_HEAD=$v ;;
      pr | issue-read | pr-read)
        case "$v" in *[!0-9]*) return 1 ;; esac
        case "$k" in pr) M_PR=$v ;; issue-read) M_IREAD=$v ;; pr-read) M_PREAD=$v ;; esac
        ;;
    esac
  done
  case "$M_STATE" in waiting | review | failed) return 0 ;; esac
  return 1
}
