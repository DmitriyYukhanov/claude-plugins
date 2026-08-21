#!/usr/bin/env bash
# preflight.sh - one Step-0 probe that replaces ~8 separate model tool calls
# (spec sec 4.1). Run once, from anywhere in the repository: the config, the gate
# commands and the worktree state all resolve against the main checkout, so the
# answer does not depend on the directory you started in. The commands it reports
# are relative to the repository root, which is where the gates run. Reports
# auth/scopes, repo
# identity, resolved base + start-point, the gate commands the config names,
# issue state/assignees, the issue-<N> worktree state, and board
# membership. Never mutates anything except `--claim` (assign issue to @me).
#
#   preflight.sh <issue-number> [--claim] [--config <path>]
#
# Exit 0 with the machine block on success; 2 (STOP) only when gh is not
# authenticated; 4 (degraded) when the config file cannot be parsed.
#
# The only things it writes are its own state directory (which ignores itself: see
# ensure_state_dir) and - with --claim - the issue assignee. It fetches, but never prunes: a probe the model runs on every task must
# not delete the user's remote-tracking refs.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

issue=""
claim=0
config_path=".claude/issue-to-pr/config.md"
config_from_flag=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --claim) claim=1; shift ;;
    --config) config_path=${2:-}; config_from_flag=1; shift 2 2>/dev/null || shift "$#" ;;
    -*) warn "preflight: ignoring unknown flag: $1"; shift ;;
    *) [ -z "$issue" ] && issue=$1; shift ;;
  esac
done

[ -n "$issue" ] || degrade missing-issue "preflight: issue number required"
assert_numeric_issue "$issue" preflight

warnings=()
add_warning() { warnings+=("$1"); }
# A queued warning is part of the answer, and `degrade`/`stop` flush the buffer and leave.
# Both early exits sit after warnings have already been queued, so without this the notice
# that a config is sitting at a path nothing reads was dropped on exactly the runs that
# also could not authenticate. Emitted even when empty: the contract lists WARNINGS as
# always present, and a reader keying off it should never see the key vanish.
emit_warnings() {
  emit WARNINGS "$(join_by '; ' "${warnings[@]:-}")"
  return 0
}

# The config lives inside the self-ignoring state dir, so a repository gains no tracked
# file from this plugin.
#
# Resolved against the MAIN checkout, never the cwd: on a resume the caller is already
# inside the worktree, which has no state dir at all. A relative path would find nothing
# there, report CONFIG_PRESENT=false, and let the run proceed with the pinned base branch
# and board silently missing.
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


# The config is read from the MAIN checkout, resolved before anything reads it. It was
# the one cwd-relative path left in this script: a run started from a subdirectory found
# no config at all and lost the pinned test command, base branch and board with it.
#
# The main checkout and not the current tree, because the file is usually untracked
# (the user keeps it there and nothing commits it), so a worktree simply has no
# copy. A repository that DOES commit it is read from the main checkout too, which means
# a branch changing the config is gated by the version on the base - a wart, not a
# hazard, and one the pinned values being explicit makes visible.
root=$(repo_root)
# `git worktree list` puts a BARE repository first, and a bare directory holds neither
# the config nor a project to probe: `.git` (a dir in a checkout, a file in a linked
# worktree) is missing there, so fall back to the tree we are standing in.
[ -e "${root:-.}/.git" ] || root=$(git rev-parse --show-toplevel 2>/dev/null || printf '')
# Only the DEFAULT path is re-rooted; an explicit --config is a caller's instruction and
# is taken as given.
#
# There is no legacy path and no migration. Reading a second location, deciding whether it
# was a team's file, copying it, and choosing which copy wins came to about forty lines
# that produced five confirmed defects across two review passes - a malformed file copied
# before it was parsed and then shadowing the original forever, an ordering hole where a
# machine that migrated first never saw a config the team committed later, and a pin that
# edited a tracked shared file. A file nobody reads is mentioned once and left alone;
# whoever owns it can move what they want to keep.
if [ "$config_from_flag" = 0 ] && [ -n "$root" ]; then
  config_path=$(resolve_under "$root" "$config_path")
  legacy="$root/.claude/issue-to-pr.local.md"
  if [ -f "$legacy" ] && [ ! -f "$config_path" ]; then
    add_warning "$legacy is not read any more; move what you want to keep into $config_path"
  fi
fi

# Both only inside a repository. `${root:-.}` would otherwise point at the caller's cwd,
# and a probe run outside a checkout has no business creating `./.claude/issue-to-pr/`
# in whatever directory someone happened to be standing in.
if [ -n "$root" ]; then
  # Unconditionally, not only when something is written here: the model itself writes the
  # friction log and epic ledgers into this directory with a plain mkdir, and whichever of
  # those lands first would otherwise be an ordinary untracked file until some later
  # approval created the rule. Step 0 runs before all of them, so the promise that nothing
  # from this plugin reaches `git status` holds from the very first write.
  ensure_state_dir "$(state_dir "$root")" ||
    add_warning "could not create $(state_dir "$root") with its ignore rule - files this plugin writes there will show up as untracked"
fi

config_present=false
if [ -f "$config_path" ]; then
  config_present=true
  if ! parse_frontmatter "$config_path" set_cfg; then
    emit_warnings
    degrade config-parse-failed "preflight: could not parse $config_path - read it yourself"
  fi
fi

# -- gh auth + scopes ---------------------------------------------------------
if ! auth_out=$(gh auth status 2>&1); then
  emit GH_OK false
  emit_warnings
  stop gh-auth-failed "preflight: gh is not authenticated - run 'gh auth login'"
fi
scopes=$(printf '%s\n' "$auth_out" | grep -i 'token scopes' | grep -oE "'[^']+'" | tr -d "'" | paste -sd, - || printf '')
has_project_scope=false
case ",$scopes," in *,project,*) has_project_scope=true ;; esac

# -- repo identity ------------------------------------------------------------
# One call, three fields. Three separate `gh repo view` invocations cost three
# process spawns and three API round trips on a probe that runs for every task.
#
# One field per LINE, never `@tsv`: jq's TSV encoder escapes the value it emits, so
# a backslash comes back doubled and a tab comes back as the two characters `\t`,
# and `read -r` - raw by definition - never undoes either. Raw lines round-trip the
# value verbatim, and none of these three fields can contain a newline.
mapfile -t _repo_fields < <(
  gh repo view --json owner,name,defaultBranchRef \
    --jq '.owner.login, .name, (.defaultBranchRef.name // "main")' 2>/dev/null
)
owner=${_repo_fields[0]:-}
repo=${_repo_fields[1]:-}
default_branch=${_repo_fields[2]:-main}

# -- base + start-point -------------------------------------------------------
# `auto` trusts the remote and nothing else. A local `dev` left behind after its
# remote counterpart was deleted post-merge is a trap: it still looks like a
# trunk, is arbitrarily stale, and would silently become the branch point for
# everything downstream.
#
# The question is asked with `ls-remote` rather than by pruning: a Step-0 probe the
# model runs on every task must not delete the user's remote-tracking refs as a
# side effect, and the stale local ref is exactly what a non-pruned fetch leaves
# behind. ls-remote reads the remote directly, so it is both read-only and correct.
if [ -z "$CFG_BASE" ] || [ "$CFG_BASE" = auto ]; then
  # Three outcomes, three different answers - conflating any two of them is how
  # this resolution went wrong before:
  #
  #   asked, and dev is there   -> dev, confirmed
  #   asked, and dev is gone    -> the repo's real default branch
  #   could not ask (offline)   -> a remote-tracking ref is a guess, not evidence;
  #                                use it, but say the source is unverified
  #
  # The ref is spelled in full: `ls-remote --heads origin dev` fnmatches the tail of
  # a ref name on slash boundaries, so it also answers yes for `release/dev`.
  if ls_out=$(git ls-remote origin refs/heads/dev 2>/dev/null); then
    if [ -n "$ls_out" ]; then
      base=dev
    else
      base=$default_branch
      # Name the discrepancy rather than resolve it silently: on a repo that really
      # does integrate on a local-only `dev`, this is the line that says so.
      [ -n "$(git branch --list dev 2>/dev/null)" ] &&
        add_warning "a local 'dev' exists but origin has no 'dev' - using '$base'; pin base_branch in the config if that is wrong"
    fi
  elif git show-ref --verify --quiet refs/remotes/origin/dev; then
    base=dev
    add_warning "could not reach origin; using 'dev' from a stale remote-tracking ref, which may name a branch that was deleted upstream - verify before the PR is opened"
  else
    base=$default_branch
    add_warning "could not reach origin; falling back to '$base' without confirming it"
    [ -n "$(git branch --list dev 2>/dev/null)" ] &&
      add_warning "a local 'dev' exists but could not be confirmed against origin - pin base_branch in the config if that is your integration branch"
  fi
else
  base=$CFG_BASE
fi

# The start point must be a ref that RESOLVES, which is not the same question as
# which branch is the base. Asking the remote can name a branch this clone has no
# ref for at all - a --single-branch or --depth 1 clone fetches only the default
# branch - and handing `git worktree add` a bare name it cannot resolve hard-stops
# the run at invalid-start-point on a base that is perfectly reachable. So fetch
# the one ref we need before giving up on it.
# Fetch exactly the one ref the start point needs, rather than every branch on the
# remote: base identity was already answered by ls-remote, and nothing else in the
# pipeline reads other remote refs. --no-prune is explicit because `fetch.prune` in
# the user's config would otherwise make this probe delete their tracking refs.
#
# Two refspecs, one invocation: the base is what Step 1 cuts from, and the default
# branch is what `cleanup` switches onto before deleting the feature branch in the
# in-place fallback. On a single-branch clone the latter has no local ref, so that
# `git switch` fails and cleanup silently finishes on a detached HEAD. Both refs
# travel over the same connection, so naming the second costs no extra round trip.
#
# The retry is not belt-and-braces: `git fetch` fails the WHOLE invocation the moment
# any one refspec names a ref the remote does not have ("fatal: couldn't find remote
# ref"), so a default branch that is absent on THIS origin - a fork, a mirror, a repo
# whose GitHub default differs from what `origin` actually holds - would take the base
# down with it, and Step 1 would hard-stop at invalid-start-point on a base that is
# perfectly reachable. Retrying one refspec at a time costs an extra round trip only
# on the path that was already broken.
fetch_refs=("+refs/heads/$base:refs/remotes/origin/$base")
[ -n "$default_branch" ] && [ "$default_branch" != "$base" ] &&
  fetch_refs+=("+refs/heads/$default_branch:refs/remotes/origin/$default_branch")
if ! git fetch origin --no-prune --quiet "${fetch_refs[@]}" 2>/dev/null; then
  for _ref in "${fetch_refs[@]}"; do
    git fetch origin --no-prune --quiet "$_ref" 2>/dev/null || true
  done
fi
if git show-ref --verify --quiet "refs/remotes/origin/$base"; then
  start_point="origin/$base"
elif git show-ref --verify --quiet "refs/heads/$base"; then
  start_point="$base"
  add_warning "base '$base' has no origin/ ref - cutting from the local branch, which nothing verifies"
else
  start_point="$base"
  add_warning "base '$base' resolves to no ref in this clone - Step 1 will stop at invalid-start-point; fetch it or pin a different base_branch"
fi

# -- gate commands (config only) ----------------------------------------------
# The config names them or nothing does. Detection moved to Step 6, in the worktree
# the gates run in - a tree Step 1 has not cut yet when this runs, which is where
# every defect in the old probe came from.
cmd_test=${CFG_TEST:-}
cmd_typecheck=${CFG_TYPECHECK:-}
cmd_visual=${CFG_VISUAL:-}
cmd_smoke=${CFG_SMOKE:-}

# -- issue state / assignees / title ------------------------------------------
# Same again for the issue, and one field per line for the same reason - here it is
# not theoretical: `@tsv` turned a title like `Fix C:\Users\foo` into `C:\\Users\\foo`,
# and that string is what names the branch and the PR. projectItems stays a separate
# call below: it needs the `project` scope, and folding it in would fail the whole
# request for a token without it.
mapfile -t _issue_fields < <(
  gh issue view "$issue" --json state,title,assignees \
    --jq '.state, .title, ([.assignees[].login] | join(","))' 2>/dev/null
)
issue_state=${_issue_fields[0]:-}
issue_title=${_issue_fields[1]:-}
assignees=${_issue_fields[2]:-}

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
# `$root` (resolved once above, for the gate probes too) is the MAIN checkout, the
# same root as the config and the state dir. `git rev-parse --show-toplevel` would
# return the WORKTREE's own root when preflight runs from inside one, which would
# compute `<repo>-worktrees/issue-N-worktrees/issue-N` and report `absent` for a
# worktree the caller is standing in.
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
emit CONFIG_PRESENT "$config_present"
emit CONFIG_PATH "$config_path"
emit RUN_DIR "$(run_dir "${root:-.}" "$issue")"
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
emit_warnings
done_ok
