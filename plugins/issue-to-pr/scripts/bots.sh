#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# bots.sh wait    <PR> [--request-codex]   wait for the review bots on the PR head, one slice per call
# bots.sh threads <PR>                     the PR's unresolved review threads
# bots.sh reply   <thread-id> --body-file <f>   answer a thread, then resolve it
# Nothing here is irreversible; the merge gate in finish.sh is what holds.
subcmd=${1:-}
shift || true
target="" body_file="" request_codex=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --request-codex) request_codex=1; shift ;;
    --body-file) body_file=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    -*) degrade unknown-flag "bots: unknown flag '$1'" ;;
    *) [ -z "$target" ] && target=$1; shift ;;
  esac
done
[ -n "$target" ] || degrade missing-target "bots: $subcmd needs a PR number or a thread id"

readonly MARKER='<!-- issue-to-pr -->'
readonly CR='coderabbitai[bot]' CX='chatgpt-codex-connector[bot]'
# a slice ends inside a default two-minute tool call; the model calls again on WAIT_MORE
POLL=${ITP_BOTS_POLL:-30} SLICE=${ITP_BOTS_SLICE:-90}
readonly GRACE=240 LIMIT=1200 RETRY_MAX=15

now() { date +%s; }

pr_ctx() { # -> head, branch, owner, name of PR $target, or stop
  local pr url
  assert_numeric_issue "$target" bots
  pr=$(gh pr view "$target" --json headRefOid,headRefName,url --jq '"\(.headRefOid)\t\(.headRefName)\t\(.url)"' 2>/dev/null) || pr=""
  head=$(printf '%s' "$pr" | cut -f1)
  pr_branch=$(printf '%s' "$pr" | cut -f2)
  url=$(printf '%s' "$pr" | cut -f3)
  IFS=$'\t' read -r owner name < <(pr_slug "$url")
  if [ -z "$head" ] || [ -z "$owner" ] || [ -z "$name" ]; then
    stop pr-unreadable "issue-to-pr: could not read PR #$target. Check it exists and gh is authenticated."
  fi
}

say() { # body -> the new comment's id, the marker appended so headless never takes it for the owner
  gh api "repos/$owner/$name/issues/$target/comments" -f body="$1"$'\n\n'"$MARKER" --jq .id 2>/dev/null
}

cmd_threads() {
  local threads
  pr_ctx
  threads=$(open_threads "$owner" "$name" "$target" 2>/dev/null) ||
    stop threads-unprovable "issue-to-pr: could not read the review threads of PR #$target."
  while IFS= read -r t; do [ -n "$t" ] && emit THREAD "$t"; done <<<"$threads"
  emit THREADS_OPEN "$(printf '%s' "$threads" | grep -c .)"
  done_ok
}

cmd_reply() {
  local body url
  [ -f "$body_file" ] || degrade missing-body "bots: reply needs --body-file <file>"
  body=$(cat "$body_file")
  case "$body" in *"$MARKER"*) : ;; *) body="$body"$'\n\n'"$MARKER" ;; esac
  # shellcheck disable=SC2016 # $t and $b are GraphQL variables
  url=$(gh api graphql -f t="$target" -f b="$body" \
    -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{url}}}' \
    --jq '.data.addPullRequestReviewThreadReply.comment.url // empty' 2>/dev/null)
  # resolving without the answer would clear the merge gate with nothing said
  [ -n "$url" ] || stop reply-failed "issue-to-pr: the reply to $target did not post, so the thread stays open. Check gh auth and the thread id."
  emit REPLIED "$url"
  # shellcheck disable=SC2016 # $t is a GraphQL variable
  gh api graphql -f t="$target" -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
    --jq '.data.resolveReviewThread.thread.isResolved' 2>/dev/null | grep -qx true ||
    stop resolve-failed "issue-to-pr: replied to $target but could not resolve it. Resolve it on GitHub."
  emit RESOLVED true
  done_ok
}

# One tick reads what the bots left on the head. CodeRabbit reports as a commit status; Codex only
# answers our own request comment, so everything about it is keyed to that comment's id.
# -> cr_state, cr_desc, cr_until, cx_seen, cx_verdict; rc 1 when GitHub could not be read.
snapshot() {
  local st comments
  st=$(gh api "repos/$owner/$name/commits/$head/status" \
    --jq '.statuses[] | select(.context == "CodeRabbit") | "\(.state)\t\(.description // "")"' 2>/dev/null) || return 1
  cr_state=$(printf '%s' "$st" | head -1 | cut -f1)
  cr_desc=$(printf '%s' "$st" | head -1 | cut -f2)
  comments=$(gh api "repos/$owner/$name/issues/$target/comments" --paginate \
    --jq '.[] | "\(.id)\t\(.user.login)\t\(.updated_at | fromdateiso8601)\t\(.body | gsub("[[:space:]]+"; " "))"' 2>/dev/null) || return 1
  # when the most recently updated CodeRabbit limit notice (often its edited summary) says the
  # next review opens
  cr_until=$(printf '%s\n' "$comments" | awk -F'\t' -v u="$CR" '
    $2 == u && $3 + 0 >= at && match($4, /available in [0-9]+ minute/) {
      at = $3 + 0; t = at + substr($4, RSTART + 13, RLENGTH - 20) * 60 }
    END { print t }')
  cx_seen="" cx_verdict=""
  [ -n "$rid" ] || return 0
  cx_verdict=$(printf '%s\n' "$comments" | awk -F'\t' -v u="$CX" -v r="$rid" '$2 == u && $1 + 0 > r + 0' | tail -1 | cut -f4)
  reviews=$(gh api "repos/$owner/$name/pulls/$target/reviews" --paginate \
    --jq '.[] | select(.user.login == "'"$CX"'" and .commit_id == "'"$head"'") | .id' 2>/dev/null) || return 1
  [ -z "$reviews" ] || cx_verdict=reviewed
  cx_seen=$(gh api "repos/$owner/$name/issues/comments/$rid/reactions" \
    --jq '.[] | select(.user.login == "'"$CX"'") | .content' 2>/dev/null) || return 1
}

save() { # the per-head budget and what was already asked, so no call repeats a request
  printf '%s %s %s %s %s %s %s\n' "$head" "$since" "$retry" "$cr_asked" "${rid:--}" "$asked_at" "${cr_final:--}" >"$state"
}

cmd_wait() {
  local state since retry=0 cr_asked=0 rid="" asked_at=0 cr_final="" t tx x fails slice_end deadline cr cx
  local cr_state cr_desc cr_until cx_seen cx_verdict reviews h s r a i q f left
  pr_ctx
  root=$(repo_root)
  [ -n "$root" ] || degrade not-a-git-repo "bots: not inside a git repository"
  state="$(branch_dir "$root" "$pr_branch")/bots"
  if ! ensure_state_dir "$(state_dir "$root")" || ! mkdir -p "${state%/*}" 2>/dev/null; then
    degrade state-unwritable "bots: cannot write $state"
  fi
  since=$(now)
  # one budget per head, shared by every call and every re-run
  if [ -f "$state" ] && read -r h s r a i q f <"$state" && [ "$h" = "$head" ]; then
    since=$s retry=$r cr_asked=$a asked_at=${q:-0}
    [ "${i:--}" = - ] || rid=$i
    [ "${f:--}" = - ] || cr_final=$f # an earlier call's outcome holds until this one has its own
  fi
  if [ "$request_codex" = 1 ] && [ -z "$rid" ]; then
    rid=$(say '@codex review') || stop request-failed "issue-to-pr: could not post '@codex review' on PR #$target."
    asked_at=$(now)
    save
  fi
  slice_end=$(($(now) + SLICE)) fails=0
  while :; do
    save
    if ! snapshot; then
      fails=$((fails + 1))
      [ "$fails" -lt 3 ] || stop bots-unreadable "issue-to-pr: could not read PR #$target from GitHub three times running. Report the bots as unchecked; the merge gate still reads the threads."
      sleep "$POLL"
      continue
    fi
    fails=0 t=$(($(now) - since)) tx=$(($(now) - asked_at)) cr="" cx=""
    case "$cr_desc" in
      '') if [ "$cr_state" = pending ] || [ "$t" -lt "$GRACE" ]; then cr="wait"; fi ;;
      'Review queued'* | 'Review in progress'*) cr="wait" ;;
      'Review completed'*) cr="done" ;;
      'Review skipped'*) cr="unavailable:skipped" ;;
      'Review paused'*) cr="unavailable:paused" ;; # pause is the owner's switch; resuming is theirs too
      'Review rate limited'*)
        left=$((${cr_until:-0} - $(now)))
        if [ "$cr_asked" != 0 ]; then
          # the status keeps its old text for a moment after the re-request
          if [ "$(now)" -lt $((cr_asked + 120)) ]; then cr="wait"; else cr="unavailable:rate-limited"; fi
        elif [ -z "$cr_until" ] || [ "$left" -gt $((RETRY_MAX * 60)) ]; then
          cr="unavailable:rate-limited${cr_until:+-$(((left + 59) / 60))m}"
        else
          [ "$retry" != 0 ] || retry=$((cr_until + 30))
          cr="wait"
          if [ "$(now)" -ge "$retry" ]; then
            say '@coderabbitai review' >/dev/null || stop request-failed "issue-to-pr: could not post '@coderabbitai review' on PR #$target."
            cr_asked=$(now)
            save
          fi
        fi ;;
      *) if [ "$cr_state" = pending ]; then cr="wait"; else cr="unknown"; fi ;;
    esac
    if [ -n "$rid" ]; then
      case "$cx_verdict" in
        reviewed | *'major issues'*) cx="done" ;;
        *'Codex account'* | *'connect to github'*) cx="unavailable:no-account" ;;
        *limit*) cx="unavailable:usage-limit" ;;
        *)
          case "$cx_seen" in
            *+1*) cx="done" ;;
            *eyes*) cx="wait" ;;
            *) if [ "$tx" -ge "$GRACE" ]; then cx="unavailable:not-connected"; else cx="wait"; fi ;;
          esac ;;
      esac
    fi
    # a short rate limit stretches the budget to ten minutes past its re-request
    deadline=$LIMIT
    x=$((cr_asked > 0 ? cr_asked : retry))
    [ "$x" = 0 ] || [ $((x - since + 600)) -le "$deadline" ] || deadline=$((x - since + 600))
    if [ "$cr" = wait ] && [ "$t" -ge "$deadline" ]; then cr=timeout; fi
    if [ "$cx" = wait ] && [ "$tx" -ge "$LIMIT" ]; then cx=timeout; fi
    if [ "$cr" != wait ] && [ "$cx" != wait ]; then break; fi
    if [ $(($(now) + POLL)) -gt "$slice_end" ]; then
      save
      emit WAIT_MORE true
      done_ok
    fi
    sleep "$POLL"
  done
  # finish.sh reads this: a wait that ran out on this head lets a stuck CodeRabbit status through
  cr_final=${cr:-none}
  save
  [ -z "$cr" ] || emit BOT_coderabbit "$cr"
  [ -z "$cx" ] || emit BOT_codex "$cx"
  [ -n "$cr$cx" ] || emit BOTS none
  done_ok
}

case "$subcmd" in
  wait) cmd_wait ;;
  threads) cmd_threads ;;
  reply) cmd_reply ;;
  *) degrade unknown-subcommand "bots: expected wait, threads or reply, got '$subcmd'" ;;
esac
