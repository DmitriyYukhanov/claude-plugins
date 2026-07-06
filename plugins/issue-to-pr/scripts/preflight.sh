#!/usr/bin/env bash
# preflight.sh - one Step-0 probe that replaces ~8 separate model tool calls
# (spec sec 4.1). Run once from the MAIN checkout. Reports auth/scopes, repo
# identity, resolved base + start-point, auto-detected gate commands (overridden
# by config), issue state/assignees, the issue-<N> worktree state, and board
# membership. Never mutates anything except `--claim` (assign issue to @me).
#
#   preflight.sh <issue-number> [--claim] [--json] [--config <path>]
#
# Exit 0 with the machine block on success; 2 (STOP) only when gh is not
# authenticated; 4 (degraded) when the config file cannot be parsed.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

issue=""
claim=0
config_path=".claude/issue-to-pr.local.md"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --claim) claim=1; shift ;;
    --json) enable_json; shift ;;
    --config) config_path=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    -*) warn "preflight: ignoring unknown flag: $1"; shift ;;
    *) [ -z "$issue" ] && issue=$1; shift ;;
  esac
done

[ -n "$issue" ] || degrade missing-issue "preflight: issue number required"

warnings=()
add_warning() { warnings+=("$1"); }

# -- Config (line-based YAML subset: top-level scalars + one nesting level) ----
CFG_BASE=""
CFG_BOARD_URL=""
CFG_BOARD_STATUS_FIELD=""
CFG_STATUS_MAP_IN_PROGRESS=""
CFG_STATUS_MAP_IN_REVIEW=""
CFG_TYPECHECK=""
CFG_TEST=""
CFG_VISUAL=""
CFG_SMOKE=""
CFG_CHECKS_TIMEOUT=""

set_cfg() { # top sub value
  local top=$1 sub=$2 val=$3
  case "$top:$sub" in
    # Documented schema: top-level scalars.
    base_branch:) CFG_BASE=$val ;;
    typecheck_cmd:) CFG_TYPECHECK=$val ;;
    test_cmd:) CFG_TEST=$val ;;
    visual_cmd:) CFG_VISUAL=$val ;;
    smoke_cmd:) CFG_SMOKE=$val ;;
    checks_timeout:) CFG_CHECKS_TIMEOUT=$val ;;
    board:url) CFG_BOARD_URL=$val ;;
    board:status_field) CFG_BOARD_STATUS_FIELD=$val ;;
    # board.status_map.{in_progress,in_review}: these are the only board sub-keys
    # named this way, so a one-level parser can still capture the explicit column map.
    board:in_progress) CFG_STATUS_MAP_IN_PROGRESS=$val ;;
    board:in_review) CFG_STATUS_MAP_IN_REVIEW=$val ;;
    # Also accept a nested commands: block as an alias.
    commands:typecheck) CFG_TYPECHECK=$val ;;
    commands:test) CFG_TEST=$val ;;
    commands:visual) CFG_VISUAL=$val ;;
    commands:smoke) CFG_SMOKE=$val ;;
    *) : ;; # unknown keys ignored (forward-compatible)
  esac
}

# trim_quotes + parse_frontmatter now live in lib/common.sh (shared with pin-config.sh).

config_present=false
if [ -f "$config_path" ]; then
  config_present=true
  if ! parse_frontmatter "$config_path" set_cfg; then
    degrade config-parse-failed "preflight: could not parse $config_path - read it yourself"
  fi
fi

# -- gh auth + scopes ---------------------------------------------------------
if ! auth_out=$(gh auth status 2>&1); then
  emit GH_OK false
  stop gh-auth-failed "preflight: gh is not authenticated - run 'gh auth login'"
fi
scopes=$(printf '%s\n' "$auth_out" | grep -i 'token scopes' | grep -oE "'[^']+'" | tr -d "'" | paste -sd, - || printf '')
has_project_scope=false
case ",$scopes," in *,project,*) has_project_scope=true ;; esac

# -- repo identity ------------------------------------------------------------
owner=$(gh repo view --json owner --jq .owner.login 2>/dev/null || printf '')
repo=$(gh repo view --json name --jq .name 2>/dev/null || printf '')
default_branch=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || printf 'main')

# -- base + start-point -------------------------------------------------------
git fetch origin --quiet 2>/dev/null || true
if [ -z "$CFG_BASE" ] || [ "$CFG_BASE" = auto ]; then
  if [ -n "$(git branch --list dev 2>/dev/null)" ] || [ -n "$(git branch -r --list origin/dev 2>/dev/null)" ]; then
    base=dev
  else
    base=main
  fi
else
  base=$CFG_BASE
fi
if git show-ref --verify --quiet "refs/remotes/origin/$base"; then
  start_point="origin/$base"
else
  start_point="$base"
fi

# -- gate command auto-detect (config overrides) ------------------------------
det_test="" det_typecheck="" det_visual="" det_smoke="" det_source="none"
detect_from_package_json() {
  det_source="package.json"
  grep -qE '"test"[[:space:]]*:' package.json && det_test='npm test'
  local k
  for k in typecheck tsc type-check; do
    if grep -qE "\"$k\"[[:space:]]*:" package.json; then det_typecheck="npm run $k"; break; fi
  done
  for k in 'test:visual' visual e2e playwright; do
    if grep -qE "\"$k\"[[:space:]]*:" package.json; then det_visual="npm run $k"; break; fi
  done
  grep -qE '"smoke"[[:space:]]*:' package.json && det_smoke='npm run smoke'
}
if [ -f package.json ]; then
  detect_from_package_json
elif [ -f Cargo.toml ]; then
  det_source="Cargo.toml"; det_test='cargo test'; det_typecheck='cargo check'
elif [ -f go.mod ]; then
  det_source="go.mod"; det_test='go test ./...'; det_typecheck='go vet ./...'
elif [ -f pyproject.toml ] || [ -f setup.py ]; then
  det_source="python"; det_test='pytest'
elif [ -f Makefile ]; then
  det_source="Makefile"
  grep -qE '^test:' Makefile && det_test='make test'
  grep -qE '^(typecheck|check):' Makefile && det_typecheck='make typecheck'
fi

# Config wins over auto-detect; track the source per command.
cmd_test=${CFG_TEST:-$det_test}
cmd_typecheck=${CFG_TYPECHECK:-$det_typecheck}
cmd_visual=${CFG_VISUAL:-$det_visual}
cmd_smoke=${CFG_SMOKE:-$det_smoke}
pick_source() { if [ -n "$1" ]; then echo config; else echo "$2"; fi; }
src_test=$(pick_source "$CFG_TEST" "$det_source")
src_typecheck=$(pick_source "$CFG_TYPECHECK" "$det_source")

# -- issue state / assignees / title ------------------------------------------
issue_state=$(gh issue view "$issue" --json state --jq .state 2>/dev/null || printf '')
issue_title=$(gh issue view "$issue" --json title --jq .title 2>/dev/null || printf '')
assignees=$(gh issue view "$issue" --json assignees --jq '.assignees[].login' 2>/dev/null | paste -sd, - || printf '')

# -- claim (assign to @me), guarding against stealing someone else's issue -----
if [ "$claim" = 1 ]; then
  me=$(gh api user --jq .login 2>/dev/null || printf '')
  claimed_by_other=""
  if [ -n "$assignees" ]; then
    local_ifs=$IFS; IFS=,
    for a in $assignees; do
      [ -n "$a" ] || continue
      [ "$a" = "$me" ] && { claimed_by_other=""; break; }
      claimed_by_other=$a
    done
    IFS=$local_ifs
  fi
  if [ -n "$claimed_by_other" ]; then
    emit WARN_CLAIMED_BY "$claimed_by_other"
    add_warning "issue already assigned to $claimed_by_other - not claimed"
  else
    gh issue edit "$issue" --add-assignee @me >/dev/null 2>&1 || add_warning "could not assign issue to @me"
  fi
fi

# -- worktree state for issue-<N> ---------------------------------------------
root=$(git rev-parse --show-toplevel 2>/dev/null || printf '')
wt_state="absent"
wt_path=""
if [ -n "$root" ]; then
  parent=$(dirname "$root")
  repo_name=$(basename "$root")
  computed_path="$parent/${repo_name}-worktrees/issue-$issue"
  registered_path=$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep -E "/issue-$issue\$" | head -1 || printf '')
  if [ -n "$registered_path" ]; then
    wt_path=$registered_path
    if [ -d "$registered_path" ]; then
      wt_state="resumable"
      # pr-merged override: a resumable worktree whose branch already merged.
      wt_branch=$(git -C "$registered_path" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
      if [ -n "$wt_branch" ]; then
        pr_state=$(gh pr view "$wt_branch" --json state --jq .state 2>/dev/null || printf '')
        [ "$pr_state" = MERGED ] && wt_state="pr-merged"
      fi
    else
      wt_state="registered-missing-dir"
    fi
  elif [ -d "$computed_path" ]; then
    wt_path=$computed_path
    wt_state="stale-dir"
  else
    wt_path=$computed_path
  fi
fi

# -- board membership ---------------------------------------------------------
board_configured=false
board_member=false
if [ -n "$CFG_BOARD_URL" ]; then
  board_configured=true
  if [ "$has_project_scope" = true ]; then
    count=$(gh issue view "$issue" --json projectItems --jq '.projectItems | length' 2>/dev/null || printf '0')
    if printf '%s' "$count" | grep -qE '^[0-9]+$' && [ "$count" -gt 0 ]; then
      board_member=true
    fi
  else
    add_warning "board configured but 'project' scope missing - run: gh auth refresh -s project"
  fi
fi

# -- emit ---------------------------------------------------------------------
emit GH_OK true
emit SCOPES "$scopes"
emit OWNER "$owner"
emit REPO "$repo"
emit DEFAULT_BRANCH "$default_branch"
emit BASE "$base"
emit START_POINT "$start_point"
emit CMD_TYPECHECK "$cmd_typecheck"
emit CMD_TEST "$cmd_test"
emit CMD_VISUAL "$cmd_visual"
emit CMD_SMOKE "$cmd_smoke"
emit CMD_SOURCE_TYPECHECK "$src_typecheck"
emit CMD_SOURCE_TEST "$src_test"
emit CONFIG_PRESENT "$config_present"
emit ISSUE_STATE "$issue_state"
emit ISSUE_TITLE "$issue_title"
emit ISSUE_ASSIGNEES "$assignees"
emit WORKTREE_STATE "$wt_state"
emit WORKTREE_PATH "$wt_path"
emit BOARD_CONFIGURED "$board_configured"
emit BOARD_MEMBER "$board_member"
emit BOARD_STATUS_FIELD "$CFG_BOARD_STATUS_FIELD"
emit STATUS_MAP_IN_PROGRESS "$CFG_STATUS_MAP_IN_PROGRESS"
emit STATUS_MAP_IN_REVIEW "$CFG_STATUS_MAP_IN_REVIEW"
emit CHECKS_TIMEOUT "$CFG_CHECKS_TIMEOUT"
emit WARNINGS "$(join_by '; ' "${warnings[@]:-}")"
done_ok
