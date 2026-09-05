#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

log_dir=""
gate_names=()
gate_cmds=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --log-dir)
      log_dir=${2:-}
      shift 2 2>/dev/null || shift "$#"
      ;;
    --gate)
      spec=${2:-}
      shift 2 2>/dev/null || shift "$#"
      gate_names+=("${spec%%=*}")
      gate_cmds+=("${spec#*=}")
      ;;
    *)
      warn "run-gates: ignoring unknown argument: $1"
      shift
      ;;
  esac
done

[ -n "$log_dir" ] || degrade missing-log-dir "run-gates: --log-dir is required"
[ "${#gate_names[@]}" -gt 0 ] || degrade no-gates "run-gates: at least one --gate is required"

for ((gi = 0; gi < ${#gate_cmds[@]}; gi++)); do
  if [ -z "${gate_cmds[$gi]//[[:space:]]/}" ]; then
    degrade empty-gate-command "run-gates: gate '${gate_names[$gi]}' has an empty command - resolve it before running the gate"
  fi
done

mkdir -p "$log_dir" 2>/dev/null || degrade log-dir-unwritable "run-gates: cannot create $log_dir"

key_of() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_' | sed 's/_*$//'
}

ts=$(date +%Y%m%d-%H%M%S)
overall_rc=0
fail_name=""
fail_log=""
n=${#gate_names[@]}

for ((i = 0; i < n; i++)); do
  name=${gate_names[$i]}
  cmd=${gate_cmds[$i]}
  key=$(key_of "$name")
  logf="$log_dir/${name}-${ts}.log"

  start=$(date +%s)
  bash -c "$cmd" >"$logf" 2>&1
  rc=$?
  end=$(date +%s)

  emit "GATE_${key}_EXIT" "$rc"
  emit "GATE_${key}_TIME" "$((end - start))"
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
  receipt_root=$(repo_root)
  receipt_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
  receipt_head=$(git rev-parse HEAD 2>/dev/null || printf '')
  if [ -n "$receipt_root" ] && [ -n "$receipt_branch" ] && [ -n "$receipt_head" ]; then
    if receipt_write "$(receipt_path "$receipt_root" "$receipt_branch")"       "$receipt_branch" "$receipt_head" "$(IFS=,; printf %s "${gate_names[*]}")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; then
      emit GATES_RECEIPT "$receipt_head"
    fi
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
