#!/usr/bin/env bash
# run-gates.sh - run one or more gates (typecheck/test/visual/install/smoke),
# capture each gate's output to a log, and print a compact machine block. The
# printed block is the verification-before-completion proof: a green run is ~2-3
# lines per gate, and only a failing gate's last 40 lines are surfaced (on
# stderr) so gate output never floods the model's context.
#
#   run-gates.sh --log-dir <dir> --gate name='<cmd>' [--gate name2='<cmd2>'] [--json]
#
# Gates run sequentially in the current directory and STOP at the first failure
# (fail-fast). Unlike the rest of the pipeline, this script's exit code is the
# first failing gate's own exit code (0 when all pass) - the model reads it as
# "a gate failed" and looks at the surfaced tail, not as the 0/2/3/4 contract.
# Argument misuse still exits 4 (degraded).
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
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
    --json)
      enable_json
      shift
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

# An empty gate command (e.g. an unresolved '<test_cmd>') must NOT report green:
# `bash -c ""` exits 0, which would ship unverified code past the gate.
for ((gi = 0; gi < ${#gate_cmds[@]}; gi++)); do
  if [ -z "${gate_cmds[$gi]//[[:space:]]/}" ]; then
    degrade empty-gate-command "run-gates: gate '${gate_names[$gi]}' has an empty command - resolve it before running the gate"
  fi
done

mkdir -p "$log_dir" 2>/dev/null || degrade log-dir-unwritable "run-gates: cannot create $log_dir"

# Uppercase + underscore a gate name for use in KEY names.
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
flush_output

if [ "$overall_rc" -ne 0 ]; then
  {
    printf '\n--- gate %s failed (exit %d): last 40 lines of %s ---\n' "$fail_name" "$overall_rc" "$fail_log"
    tail -n 40 "$fail_log" 2>/dev/null || true
  } >&2
fi

exit "$overall_rc"
