#!/usr/bin/env bash
# agent-dispatch: one tick. Recover a dead tick's run, then start at most one headless
# issue-to-pr run: an owner reply first, else the oldest issue the owner labelled `agent`.
# Prints KEY=value lines, TICK= last; exit 1 when the tick could not do its job.
# Bash 3.2 and up. gh --jq only projects fields; every decision is made here.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=marker.sh
. "$HERE/marker.sh"

AD_HOME="$HOME/.agent-dispatch"
LOCK="$AD_HOME/lock"
DEADLINE_SECONDS=14400 # a hang guard: a trivial run takes minutes, a complex one a few hours at most
POLL_SECONDS=20
GRACE_SECONDS=10
RUN_LABELS="agent,agent:waiting,agent:review,agent:failed"
OWNER= # Ruling R2: recover() may reconcile before main sets this; reconcile resolves it itself.

JQ_ISSUES='.[] | [.number, ([.labels[].name] | join(","))] | @tsv'
JQ_LABEL_ACTORS='.[] | select(.event == "labeled" and .label.name == "%LABEL%") | .actor.login'

# ponytail: one global lock; per-repo locks if parallel runs ever matter.

say() { printf '%s\n' "$*"; }
die() { # reason message -> TICK=error, exit 1
  printf 'agent-dispatch: %s\n' "$2" >&2
  say "REASON=$1"
  say "TICK=error"
  exit 1
}
on_windows() {
  case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) return 0 ;; esac
  return 1
}
now() { date +%s; }
trim() {
  local s=${1%$'\r'}
  s=${s#"${s%%[![:space:]]*}"}
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}
has_label() { # csv label
  case ",$1," in *",$2,"*) return 0 ;; esac
  return 1
}

# Ruling R1: split a MARKER_JQ row by parameter expansion, never `IFS=$'\t' read`, which
# collapses a plain reply's consecutive marker/body tabs. Mirrors finish.sh's row().
# shellcheck disable=SC2034 # R_BODY completes the row() contract; no caller here needs the body.
row() { # comment TSV line -> R_ID R_LOGIN R_MARKER R_BODY; rc 1 on a row with no numeric id
  local l=${1%$'\r'}
  R_ID=${l%%$'\t'*}
  l=${l#*$'\t'}
  R_LOGIN=${l%%$'\t'*}
  l=${l#*$'\t'}
  R_MARKER=${l%%$'\t'*}
  R_BODY=${l#*$'\t'}
  case "$R_ID" in '' | *[!0-9]*) return 1 ;; esac
}

valid_line() { # path host tier rest
  if [ -n "$4" ] || [ ! -d "$1" ]; then return 1; fi
  case "$2" in claude | codex) ;; *) return 1 ;; esac
  case "$3" in trivial | standard | complex | none) ;; *) return 1 ;; esac
}

read_config() { # -> CONF_PATH CONF_HOST CONF_TIER CONF_REPO; dies on a malformed line
  local f="$AD_HOME/repos.conf" line p h t rest repo
  CONF_PATH=() CONF_HOST=() CONF_TIER=() CONF_REPO=()
  [ -f "$f" ] || die config "no $f: run the agent-dispatch setup skill"
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(trim "$line")
    case "$line" in '' | '#'*) continue ;; esac
    IFS='|' read -r p h t rest <<<"$line"
    p=$(trim "$p")
    h=$(trim "${h:-}")
    t=$(trim "${t:-}")
    if ! valid_line "$p" "$h" "$t" "${rest:-}"; then
      die config "malformed line in $f (want: <checkout path> | claude|codex | trivial|standard|complex|none): $line"
    fi
    repo=$(cd "$p" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
    [ -n "$repo" ] || die config "gh cannot name the GitHub repo of $p (line: $line)"
    CONF_PATH+=("$p")
    CONF_HOST+=("$h")
    CONF_TIER+=("$t")
    CONF_REPO+=("$(trim "$repo")")
  done <"$f"
}

current_state() { # comments-tsv -> M_* of the newest well-formed owner state comment; rc 1 when none
  local line s='' p='' i='' r=''
  while IFS= read -r line; do
    row "$line" || continue
    [ "$R_LOGIN" = "$OWNER" ] || continue
    parse_marker "$R_MARKER" || continue
    s=$M_STATE p=$M_PR i=$M_IREAD r=$M_PREAD
  done <<<"$1"
  [ -n "$s" ] || return 1
  M_STATE=$s M_PR=$p M_IREAD=$i M_PREAD=$r
}

reply_in() { # comments-tsv cursor -> rc 0 on an unmarked owner comment above the cursor
  local line
  while IFS= read -r line; do
    row "$line" || continue
    if [ "$R_LOGIN" != "$OWNER" ] || [ -n "$R_MARKER" ]; then continue; fi
    if [ "$R_ID" -gt "${2:-0}" ] 2>/dev/null; then return 0; fi
  done <<<"$1"
  return 1
}

owner_replied() { # repo issue -> rc 0 when the issue's current state has an owner reply
  local c
  c=$(gh api "repos/$1/issues/$2/comments" --paginate --jq "$MARKER_JQ" 2>/dev/null) || return 1
  current_state "$c" || return 1
  case "$M_STATE" in waiting | review) ;; *) return 1 ;; esac
  reply_in "$c" "$M_IREAD" && return 0
  [ -n "$M_PR" ] || return 1
  c=$(gh api "repos/$1/issues/$M_PR/comments" --paginate --jq "$MARKER_JQ" 2>/dev/null) || return 1
  reply_in "$c" "$M_PREAD"
}

label_actors_jq() { printf '%s' "${JQ_LABEL_ACTORS//%LABEL%/$1}"; } # bash 3.2: pattern substitution, not templating printf (SC2059)

owner_labelled() { # repo issue label -> rc 0 when the latest application of that label was the owner's
  local actors
  actors=$(gh api "repos/$1/issues/$2/events" --paginate --jq "$(label_actors_jq "$3")" 2>/dev/null) || return 1
  [ "$(printf '%s\n' "$actors" | tr -d '\r' | grep . | tail -1)" = "$OWNER" ]
}

pick() { # -> PICK_I PICK_N PICK_WHY; rc 1 when nothing is due
  local i=0 n labels why parked out
  local -a issues
  issues=()
  while [ "$i" -lt "${#CONF_REPO[@]}" ]; do
    out=$(gh issue list -R "${CONF_REPO[$i]}" --state open --search 'label:agent,agent:waiting,agent:review' \
      --limit 500 --json number,labels --jq "$JQ_ISSUES" 2>/dev/null) ||
      die github "could not list the open issues of ${CONF_REPO[$i]}"
    issues+=("$(printf '%s\n' "$out" | tr -d '\r' | sort -n)")
    i=$((i + 1))
  done
  for why in reply queue; do
    i=0
    while [ "$i" -lt "${#CONF_REPO[@]}" ]; do
      while IFS=$'\t' read -r n labels; do
        [ -n "$n" ] || continue
        if [ "$why" = reply ]; then
          if has_label "$labels" agent:waiting; then parked=agent:waiting
          elif has_label "$labels" agent:review; then parked=agent:review
          else continue; fi
          owner_labelled "${CONF_REPO[$i]}" "$n" "$parked" || continue
          owner_replied "${CONF_REPO[$i]}" "$n" || continue
        else
          has_label "$labels" agent || continue
          if has_label "$labels" agent:running || has_label "$labels" agent:waiting ||
            has_label "$labels" agent:review; then continue; fi
          owner_labelled "${CONF_REPO[$i]}" "$n" agent || continue
        fi
        PICK_I=$i PICK_N=$n PICK_WHY=$why
        return 0
      done <<<"${issues[$i]}"
      i=$((i + 1))
    done
  done
  return 1
}

write_run_script() { # path host issue tier log -> $LOCK/run.sh
  local prompt="issue-to-pr:run $3 --headless --auto-merge $4"
  {
    printf 'cd %q || exit 97\n' "$1"
    if [ "$2" = claude ]; then
      printf 'exec claude -p --dangerously-skip-permissions --output-format stream-json --verbose %q' "/$prompt"
    else
      printf 'exec codex exec --dangerously-bypass-approvals-and-sandbox --json -C %q %q' "$1" "\$$prompt"
    fi
    printf ' </dev/null >%q 2>&1\n' "$5"
  } >"$LOCK/run.sh"
}

winpid_of() { # cygpid deadline -> the launcher's confirmed powershell.exe winpid; empty once it
  # has exited, or once the deadline passes, without ever being confirmed. MSYS's fork-then-exec
  # of a native target briefly reports a placeholder image (its own bash.exe) at this cygpid
  # before /proc/<cygpid>/winpid settles on the real target, and that placeholder can itself sit
  # still across two immediate reads; only the image name tells them apart, so a candidate is
  # trusted once confirmed, never handed out unconfirmed. Bounded by the launcher's own life and
  # by the deadline the caller must still enforce: a fixed iteration cap can run out while the
  # launcher is simply slow to settle, which is exactly the case where the caller must not lose
  # the ability to stop it; the deadline is what keeps a broken tasklist from spinning this past
  # the run's own time budget. No `sleep` here: tests replay it through a fake clock, which would
  # corrupt a caller's deadline math; the read (and, on a changed candidate, tasklist) calls
  # provide their own pacing.
  local v seen=''
  while kill -0 "$1" 2>/dev/null && [ "$(now)" -lt "$2" ]; do
    v=$(cat "/proc/$1/winpid" 2>/dev/null)
    if [ -n "$v" ] && [ "$v" != "$seen" ]; then
      seen=$v
      if tasklist //FI "PID eq $v" //FI "IMAGENAME eq powershell.exe" //NH 2>/dev/null | grep -qi powershell; then
        printf '%s' "$v"
        return 0
      fi
    fi
  done
  printf ''
}

launch() { # deadline; runs $LOCK/run.sh -> RUN_PID (to wait on), RUN_ID (to stop, maybe empty
  # when winpid_of never confirmed it), recorded in the lock
  if on_windows; then
    # job.ps1 holds the run in a job object: stopping it stops every process the run started,
    # Git Bash grandchildren and orphans included, which taskkill //T misses.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/job.ps1")" \
      "$(cygpath -w "$BASH")" "$(cygpath -w "$LOCK/run.sh")" </dev/null >/dev/null 2>&1 &
    RUN_PID=$!
    RUN_ID=$(winpid_of "$RUN_PID" "$1")
    say "LAUNCHER=job"
  else
    set -m
    "$BASH" "$LOCK/run.sh" </dev/null >/dev/null 2>&1 &
    RUN_PID=$!
    set +m
    RUN_ID=$RUN_PID
    say "LAUNCHER=group"
  fi
  printf '%s\n' "$RUN_ID" >"$LOCK/run"
}

stop_run() { # run-id: the job launcher's Windows pid, or the run's process group
  if on_windows; then
    taskkill //F //FI "PID eq $1" //FI "IMAGENAME eq powershell.exe" >/dev/null 2>&1
  else
    kill -TERM -- "-$1" 2>/dev/null && sleep "$GRACE_SECONDS"
    kill -KILL -- "-$1" 2>/dev/null
  fi
  return 0
}

gone() { # run-id -> rc 0 once nothing of the run is left
  local _
  for _ in 1 2 3 4 5; do
    if on_windows; then
      tasklist //FI "PID eq $1" //FI "IMAGENAME eq powershell.exe" //NH 2>/dev/null | grep -qi powershell || return 0
    else
      kill -0 -- "-$1" 2>/dev/null || return 0
    fi
    sleep 1
  done
  return 1
}

# shellcheck disable=SC2016,SC2088 # the backticks are Markdown; the tilde is shown, not expanded
reconcile() { # repo issue cause log cli-error -> OUTCOME [PAUSED]; rc 1 when GitHub failed
  local labels body="$AD_HOME/.comment.md" shown=$4 comments prmark=
  if [ -z "$OWNER" ]; then # Ruling R2: recover() may call us before main() resolves OWNER
    OWNER=$(gh api user --jq .login 2>/dev/null | tr -d '\r')
    [ -n "$OWNER" ] || return 1
  fi
  labels=$(gh issue view "$2" -R "$1" --json labels --jq '.labels[].name' 2>/dev/null) || return 1
  labels=$(printf '%s\n' "$labels" | tr -d '\r')
  if ! printf '%s\n' "$labels" | grep -qx 'agent:running'; then
    say "OUTCOME=$(printf '%s\n' "$labels" | grep '^agent' | head -1)"
    return 0
  fi
  # Amendment #2: carry the run's PR, if the issue's own current state already named one, so a
  # retry (or a human) can still find it from the failure comment alone.
  comments=$(gh api "repos/$1/issues/$2/comments" --paginate --jq "$MARKER_JQ" 2>/dev/null) || return 1
  if current_state "$comments" && [ -n "$M_PR" ]; then prmark=" pr=$M_PR"; fi
  case "$shown" in "$HOME"/*) shown="~${shown#"$HOME"}" ;; esac
  if [ "$5" = 1 ]; then
    : >"$AD_HOME/paused"
    say "PAUSED=true"
  fi
  {
    printf 'The dispatcher marked this run failed: %s. Its log stays on the machine that ran it, at `%s`.\n' "$3" "$shown"
    if [ "$5" = 1 ]; then
      printf '\nDispatching is paused for every repo until `~/.agent-dispatch/paused` is deleted. An error like this usually means the CLI is logged out or out of allowance, and the next issue would fail the same way.\n'
    fi
    printf '\nTo retry, label the issue `agent` again.\n\n<!-- issue-to-pr state=failed%s -->\n' "$prmark"
  } >"$body"
  gh issue comment "$2" -R "$1" --body-file "$body" >/dev/null 2>&1 || return 1
  gh issue edit "$2" -R "$1" --add-label agent:failed --remove-label agent:running >/dev/null 2>&1 || return 1
  say "OUTCOME=agent:failed"
}

recover() { # a lock at tick start: a live tick (busy), or a dead one's run to stop and reconcile
  [ -d "$LOCK" ] || return 0
  local tick repo n run cause clierr
  tick=$(cat "$LOCK/tick" 2>/dev/null)
  if [ -n "$tick" ] && kill -0 "$tick" 2>/dev/null; then
    say "TICK=busy"
    exit 0
  fi
  repo=$(cat "$LOCK/repo" 2>/dev/null)
  n=$(cat "$LOCK/issue" 2>/dev/null)
  run=$(cat "$LOCK/run" 2>/dev/null)
  if [ -n "$run" ]; then
    stop_run "$run"
    gone "$run" || die recover "the run of a dead tick ($repo#$n, id $run) is still alive; the next tick retries"
  fi
  if [ -n "$repo" ] && [ -n "$n" ]; then
    cause=$(cat "$LOCK/cause" 2>/dev/null)
    clierr=$(cat "$LOCK/clierr" 2>/dev/null)
    reconcile "$repo" "$n" "${cause:-the dispatcher stopped before the run finished}" \
      "$(cat "$LOCK/log" 2>/dev/null)" "${clierr:-0}" ||
      die recover "could not reach GitHub to reconcile $repo#$n; the next tick retries"
    say "RECOVERED=$repo#$n"
  fi
  rm -rf "$LOCK"
}

run_issue() { # the picked issue: lock, flip, launch, wait, reconcile
  local repo=${CONF_REPO[$PICK_I]} path=${CONF_PATH[$PICK_I]} host=${CONF_HOST[$PICK_I]}
  local tier=${CONF_TIER[$PICK_I]} n=$PICK_N log rc cause='' clierr=0 deadline
  say "ISSUE=$repo#$n"
  say "PICK=$PICK_WHY"
  mkdir "$LOCK" 2>/dev/null || {
    say "TICK=busy"
    exit 0
  }
  log="$AD_HOME/logs/${repo//\//_}_${n}_$(date -u +%Y%m%dT%H%M%SZ).log"
  printf '%s\n' "$$" >"$LOCK/tick"
  printf '%s\n' "$repo" >"$LOCK/repo"
  printf '%s\n' "$n" >"$LOCK/issue"
  printf '%s\n' "$log" >"$LOCK/log"
  if ! gh issue edit "$n" -R "$repo" --add-label agent:running --remove-label "$RUN_LABELS" >/dev/null 2>&1; then
    rm -rf "$LOCK"
    die flip "could not label $repo#$n agent:running; nothing was launched"
  fi
  write_run_script "$path" "$host" "$n" "$tier" "$log"
  deadline=$(($(now) + DEADLINE_SECONDS))
  launch "$deadline"
  while kill -0 "$RUN_PID" 2>/dev/null; do
    if [ "$(now)" -ge "$deadline" ]; then
      if [ -n "$RUN_ID" ]; then
        stop_run "$RUN_ID"
        cause="it ran past the $((DEADLINE_SECONDS / 3600))-hour deadline"
        break
      fi
      # winpid_of never confirmed an id (e.g. a broken tasklist): stop what we launched by its
      # MSYS pid instead. This only reaches the launcher itself, and can miss grandchildren a job
      # object would have taken with it, which is why the RUN_ID path above is the preferred one.
      kill "$RUN_PID" 2>/dev/null
      die recover "$repo#$n's run id was never confirmed before the deadline; the next tick retries"
    fi
    sleep "$POLL_SECONDS"
  done
  wait "$RUN_PID"
  rc=$?
  if [ -z "$cause" ]; then
    if [ "$rc" -ne 0 ]; then
      cause="the $host CLI exited with code $rc"
      clierr=1
    elif [ "$host" = claude ] && grep '"type":"result"' "$log" 2>/dev/null | tail -1 | grep -q '"is_error":true'; then
      cause="the claude CLI reported an error"
      clierr=1
    else
      cause="it ended without leaving a state"
    fi
  fi
  printf '%s\n' "$cause" >"$LOCK/cause"
  printf '%s\n' "$clierr" >"$LOCK/clierr"
  if [ -n "$RUN_ID" ]; then
    on_windows || kill -KILL -- "-$RUN_ID" 2>/dev/null # whatever the exited run left behind
    gone "$RUN_ID" || die recover "processes of $repo#$n are still alive (id $RUN_ID); the next tick retries"
  fi # else: RUN_ID is only ever empty on Windows, and only once the launcher itself (wait, above)
     # has already exited, which frees its job object and everything still in it.
  reconcile "$repo" "$n" "$cause" "$log" "$clierr" ||
    die github "could not reach GitHub to reconcile $repo#$n; the next tick retries"
  rm -rf "$LOCK"
  say "RC=$rc"
  say "TICK=done"
}

main() {
  mkdir -p "$AD_HOME/logs"
  recover
  if [ -e "$AD_HOME/paused" ]; then
    say "TICK=paused"
    exit 0
  fi
  read_config
  OWNER=$(gh api user --jq .login 2>/dev/null | tr -d '\r')
  [ -n "$OWNER" ] || die github "gh api user failed: check gh auth status and the network"
  if ! pick; then
    say "TICK=idle"
    exit 0
  fi
  run_issue
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main; fi
