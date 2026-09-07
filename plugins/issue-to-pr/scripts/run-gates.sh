#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

gate_names=()
gate_cmds=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --gate)
      spec=${2:-}
      shift 2 2>/dev/null || shift "$#"
      gate_names+=("${spec%%=*}")
      gate_cmds+=("${spec#*=}")
      ;;
    *)
      degrade unknown-argument "run-gates: unrecognised argument '$1'. A gate value carrying a quote of its own closes the wrapper and splits the rest into arguments like this one; pass each value through a shell variable: --gate \"test=\$t\""
      ;;
  esac
done

[ "${#gate_names[@]}" -gt 0 ] || degrade no-gates "run-gates: at least one --gate is required"

key_of() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_' | sed 's/_*$//'
}

seen_keys=""
for ((gi = 0; gi < ${#gate_cmds[@]}; gi++)); do
  gname=${gate_names[$gi]}
  gcmd=${gate_cmds[$gi]}

  if [ -z "${gcmd//[[:space:]]/}" ]; then
    degrade empty-gate-command "run-gates: gate '$gname' has an empty command - resolve it before running the gate"
  fi
  # shellcheck disable=SC2016  # these patterns match a literal dollar sign, they do not expand
  case "$gcmd" in
    '$('*) : ;;
    '$'*)
      degrade unexpanded-gate-command "run-gates: gate '$gname' arrived as the literal text $gcmd, so the value was single-quoted at the call site and the shell never expanded it. Running that expands to nothing and exits 0, which is a green gate over no command. Use double quotes: --gate \"$gname=\$var\"" ;;
  esac

  gkey=$(key_of "$gname")
  [ -n "$gkey" ] || degrade unnamed-gate "run-gates: gate name '$gname' leaves nothing to build an output key from"
  case " $seen_keys " in
    *" $gkey "*) degrade duplicate-gate "run-gates: gate '$gname' keys to GATE_${gkey}_EXIT, which an earlier gate already claimed, so one would report over the other. Rename one." ;;
  esac
  seen_keys="$seen_keys $gkey"
done

root=$(repo_root)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
if [ -z "$root" ] || [ -z "$branch" ]; then
  degrade not-a-git-repo "run-gates: the gate logs are keyed to the checkout and its branch, and neither could be read here"
fi
if [ "$branch" = HEAD ]; then
  degrade detached-head "run-gates: this checkout is detached, so there is no branch to key the receipt to and the merge would look for it under the branch name instead. Check the feature branch out first."
fi
log_dir="$(branch_dir "$root" "$branch")/logs"
if ! ensure_state_dir "$(state_dir "$root")" || ! mkdir -p "$log_dir" 2>/dev/null; then
  degrade log-dir-unwritable "run-gates: cannot create $log_dir"
fi

ts=$(date +%Y%m%d-%H%M%S)
overall_rc=0
fail_name=""
fail_log=""
n=${#gate_names[@]}

for ((i = 0; i < n; i++)); do
  name=${gate_names[$i]}
  key=$(key_of "$name")
  logf="$log_dir/$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')-$ts.log"

  bash -c "${gate_cmds[$i]}" >"$logf" 2>&1
  rc=$?

  emit "GATE_${key}_EXIT" "$rc"
  emit "GATE_${key}_LOG" "$logf"

  if [ "$rc" -ne 0 ]; then
    overall_rc=$rc
    fail_name=$name
    fail_log=$logf
    break
  fi
done

if [ "$overall_rc" -eq 0 ]; then gates_ok=true; else gates_ok=false; fi
emit GATES_RUN "$((i < n ? i + 1 : n))"
emit GATES_OK "$gates_ok"

if [ "$gates_ok" = true ]; then
  head_sha=$(git rev-parse HEAD 2>/dev/null || printf '')
  if [ -z "$head_sha" ]; then
    warn "run-gates: the gates passed but HEAD could not be read, so no receipt was written and the merge will refuse this head"
  elif receipt_write "$root" "$branch" "$head_sha" "$(IFS=,; printf %s "${gate_names[*]}")"; then
    emit GATES_RECEIPT "$head_sha"
  else
    warn "run-gates: the gates passed but the receipt under $(branch_dir "$root" "$branch") could not be written, so the merge will refuse this head"
  fi
fi
flush_output

if [ "$overall_rc" -ne 0 ]; then
  {
    printf '\n--- gate %s failed (exit %d): last 40 lines of %s ---\n' "$fail_name" "$overall_rc" "$fail_log"
    tail -n 40 "$fail_log" 2>/dev/null || true
  } >&2
fi

exit "$overall_rc"
