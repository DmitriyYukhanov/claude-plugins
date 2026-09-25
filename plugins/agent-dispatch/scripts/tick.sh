#!/usr/bin/env bash
# The scheduler's command: copy it once to ~/.agent-dispatch/tick.sh. Every call finds the
# agent-dispatch version the named host has active now, so an update needs no re-registration.
# Usage: tick.sh claude|codex. Output goes to ~/.agent-dispatch/logs/tick.log.
set -uo pipefail

host=${1:-}
mkdir -p "$HOME/.agent-dispatch/logs"
exec >>"$HOME/.agent-dispatch/logs/tick.log" 2>&1
printf '== %s ==\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

d=
case "$host" in
  claude)
    # installed_plugins.json is pretty-printed JSON; Windows paths arrive with doubled backslashes.
    # The range runs from the agent-dispatch key to the next plugin key at the same indent (or
    # EOF), so every installPath in that key's own array is counted, never one from a different
    # plugin's entry below it.
    paths=$(sed -n '/"agent-dispatch@[^"]*":/,/^    "/{/"installPath"/s/.*"installPath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p;}' \
      "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null)
    if [ "$(printf '%s\n' "$paths" | grep -c .)" -eq 1 ]; then
      d=$(printf '%s' "$paths" | sed 's|\\\\|/|g')
    fi
    ;;
  codex)
    if grep -q '^\[plugins\."agent-dispatch@' "$HOME/.codex/config.toml" 2>/dev/null; then
      set -- "$HOME"/.codex/plugins/cache/*/agent-dispatch/*/
      if [ "$#" -eq 1 ] && [ -d "$1" ]; then d=${1%/}; fi
    fi
    ;;
  *)
    printf 'usage: tick.sh claude|codex\n'
    exit 4
    ;;
esac

if [ -z "$d" ] || [ ! -f "$d/scripts/dispatch.sh" ]; then
  printf 'agent-dispatch is not installed in %s, or several versions are cached: reinstall it and run its setup again.\n' "$host"
  exit 1
fi
exec "$BASH" "$d/scripts/dispatch.sh"
