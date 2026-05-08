#!/usr/bin/env bash
# dirty-tree-probe.sh <file>...
# Emits one JSON object per line (paths are JSON-escaped via Node):
#   {"path":<abs>,"exists":bool,"dirty":bool,"untracked":bool,"wouldCreate":bool}
set -euo pipefail

emit_json() {
  # Args: path exists dirty untracked wouldCreate
  node -e '
    const [p,e,d,u,w] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({path:p,exists:e==="true",dirty:d==="true",untracked:u==="true",wouldCreate:w==="true"})+"\n");
  ' -- "$1" "$2" "$3" "$4" "$5"
}

for raw in "$@"; do
  abs=$(node -e 'process.stdout.write(require("path").resolve(process.argv[1]))' -- "$raw")
  if [ ! -e "$abs" ]; then
    emit_json "$abs" false false false true
    continue
  fi
  dirty=false; untracked=false
  if ! git diff --quiet HEAD -- "$abs" 2>/dev/null; then dirty=true; fi
  if ! git diff --cached --quiet -- "$abs" 2>/dev/null; then dirty=true; fi
  if git status --porcelain -- "$abs" 2>/dev/null | grep -qE '^\?\? '; then untracked=true; fi
  emit_json "$abs" true "$dirty" "$untracked" false
done
