#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR=${BASH_SOURCE[0]%/*}
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# gates.sh <name> <command> [<name> <command> ...]
# Each command is its own argument, so nothing here has to split or unquote a packed value.
# Runs them in order in the current checkout, logs each under the branch's run directory in
# the main checkout, stops at the first red one, and on all green writes the receipt the merge
# checks (branch, HEAD sha, gate names).
if [ "$#" -eq 0 ] || [ $(($# % 2)) -ne 0 ]; then
  degrade bad-arguments "gates: expected name/command pairs, got $# arguments"
fi
args=("$@")
for ((i = 1; i < ${#args[@]}; i += 2)); do
  [ -n "${args[$i]//[[:space:]]/}" ] ||
    degrade empty-gate-command "gates: gate '${args[$((i - 1))]}' has an empty command, and bash -c on nothing exits 0: a green gate over no command"
  # shellcheck disable=SC2016  # a literal dollar sign is what this arm looks for
  case "${args[$i]}" in
    '$('*) : ;;
    '$'*) degrade unexpanded-gate-command "gates: gate '${args[$((i - 1))]}' arrived as the literal text ${args[$i]}, so a variable name was passed instead of the command, and bash -c on that runs nothing and exits 0. Substitute the command itself." ;;
  esac
done

root=$(repo_root)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
if [ -z "$root" ] || [ -z "$branch" ]; then
  degrade not-a-git-repo "gates: not inside a git checkout"
fi
[ "$branch" != HEAD ] ||
  degrade detached-head "gates: this checkout is detached, so there is no branch to key the receipt to. Check the feature branch out first."
log_dir="$(branch_dir "$root" "$branch")/logs"
if ! ensure_state_dir "$(state_dir "$root")" || ! mkdir -p "$log_dir" 2>/dev/null; then
  degrade log-dir-unwritable "gates: cannot create $log_dir"
fi

ts=$(date +%Y%m%d-%H%M%S)
names=""
while [ "$#" -gt 0 ]; do
  name=$1
  cmd=$2
  shift 2
  key=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_' | sed 's/_*$//')
  slug=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
  logf="$log_dir/$slug-$ts.log"
  bash -c "$cmd" >"$logf" 2>&1
  rc=$?
  emit "GATE_${key}_EXIT" "$rc"
  emit "GATE_${key}_LOG" "$logf"
  if [ "$rc" -ne 0 ]; then
    flush_output
    {
      printf '\n--- gate %s failed (exit %d): last 40 lines of %s ---\n' "$name" "$rc" "$logf"
      tail -n 40 "$logf"
    } >&2
    exit 1
  fi
  # the receipt lists the sanitized key, not the name: a comma cannot survive it, so no gate
  # name can forge a second entry the merge would read as the test gate
  names="$names${names:+,}$slug"
done

head_sha=$(git rev-parse HEAD 2>/dev/null || printf '')
if [ -n "$head_sha" ] && receipt_write "$root" "$branch" "$head_sha" "$names"; then
  emit GATES_RECEIPT "$head_sha"
else
  warn "gates: all green, but the receipt under $(branch_dir "$root" "$branch") could not be written, so the merge will refuse this head"
fi
done_ok
