#!/usr/bin/env bash
# preflight.sh - one Step-0 probe that replaces ~8 separate model tool calls
# (spec sec 4.1). Run once, from anywhere in the repository: the config, the gate
# commands and the worktree state all resolve against the main checkout, so the
# answer does not depend on the directory you started in. The commands it reports
# are relative to the repository root, which is where the gates run. Reports
# auth/scopes, repo
# identity, resolved base + start-point, auto-detected gate commands (overridden
# by config), issue state/assignees, the issue-<N> worktree state, and board
# membership. Never mutates anything except `--claim` (assign issue to @me).
#
#   preflight.sh <issue-number> [--claim] [--config <path>]
#
# Exit 0 with the machine block on success; 2 (STOP) only when gh is not
# authenticated; 4 (degraded) when the config file cannot be parsed.
#
# The only things it writes are its own state directory (which ignores itself)
# and, with --claim, the issue assignee. It fetches, but never prunes: a probe the
# model runs on every task must not delete the user's remote-tracking refs.
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

issue=""
claim=0
config_path=".claude/issue-to-pr.local.md"
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

# The config now lives inside the self-ignoring state dir, so a repo gains no
# tracked file from this plugin. The pre-v3 sibling path is still read when the
# canonical one is absent, so existing projects keep working untouched.
#
# Both are resolved against the MAIN checkout, never the cwd: on a resume the
# caller is already inside the worktree, which has no state dir at all. A relative
# path would find nothing there, report CONFIG_PRESENT=false, and let the run
# proceed with the pinned base branch and board silently missing.
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

# The config is read from the MAIN checkout, resolved before anything reads it. It was
# the one cwd-relative path left in this script, and it outranks auto-detect: a run
# started from a subdirectory found no config at all and silently swapped the pinned
# test command for whatever auto-detect guessed, taking the pinned base branch and the
# board with it.
#
# The main checkout and not the current tree, because the file is usually untracked
# (`pin-config.sh` writes it there and nothing commits it), so a worktree simply has no
# copy. A repository that DOES commit it is read from the main checkout too, which means
# a branch changing the config is gated by the version on the base - a wart, not a
# hazard, and one the pinned values being explicit makes visible.
root=$(repo_root)
# `git worktree list` puts a BARE repository first, and a bare directory holds neither
# the config nor a project to probe: `.git` (a dir in a checkout, a file in a linked
# worktree) is missing there, so fall back to the tree we are standing in.
[ -e "${root:-.}/.git" ] || root=$(git rev-parse --show-toplevel 2>/dev/null || printf '')
# Only the DEFAULT path is re-rooted. An explicit --config is a caller's instruction and
# stays relative to the caller, which is also how every in-tree caller already passes it
# (SKILL Step 8 hands it an absolute path).
[ "$config_from_flag" = 1 ] || config_path=$(resolve_under "${root:-.}" "$config_path")

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

# -- gate command auto-detect (config overrides) ------------------------------
# Every probe below is anchored to a checkout root, never to cwd: a run started from a
# subdirectory used to report "no test command" for a project that plainly has one, and
# Step 6 then had nothing left to verify the work with.
#
# Probed in the main checkout, never in "whatever tree cwd happens to be in": started
# from issue-5's worktree, a run for issue 9 would otherwise gate issue 9 on a project
# that exists only on issue 5's branch. Anchoring this to the worktree the run will
# actually use is a different job and cannot be done here anyway - Step 0 probes before
# Step 1 has cut that worktree from `origin/$base`, so the tree the gates will run in
# does not exist yet.
det_root=${root:-.}
det_test="" det_typecheck="" det_visual="" det_smoke="" det_source="none"
detect_from_package_json() {
  local pkg="$det_root/package.json"
  det_source="package.json"
  grep -qE '"test"[[:space:]]*:' "$pkg" && det_test='npm test'
  local k
  for k in typecheck tsc type-check; do
    if grep -qE "\"$k\"[[:space:]]*:" "$pkg"; then det_typecheck="npm run $k"; break; fi
  done
  for k in 'test:visual' visual e2e playwright; do
    if grep -qE "\"$k\"[[:space:]]*:" "$pkg"; then det_visual="npm run $k"; break; fi
  done
  grep -qE '"smoke"[[:space:]]*:' "$pkg" && det_smoke='npm run smoke'
}
if [ -f "$det_root/package.json" ]; then
  detect_from_package_json
elif [ -f "$det_root/Cargo.toml" ]; then
  det_source="Cargo.toml"; det_test='cargo test'; det_typecheck='cargo check'
elif [ -f "$det_root/go.mod" ]; then
  det_source="go.mod"; det_test='go test ./...'; det_typecheck='go vet ./...'
elif [ -f "$det_root/pyproject.toml" ] || [ -f "$det_root/setup.py" ]; then
  det_source="python"; det_test='pytest'
elif [ -f "$det_root/Makefile" ]; then
  det_source="Makefile"
  grep -qE '^test:' "$det_root/Makefile" && det_test='make test'
  # Emit the target that is actually there. A `check:`-only Makefile (the GNU spelling)
  # used to yield `make typecheck`, which make then refuses for want of such a rule -
  # a red gate on a repository with nothing wrong, and nothing telling the model the
  # command had been invented rather than read.
  for k in typecheck check; do
    if grep -qE "^$k:" "$det_root/Makefile"; then det_typecheck="make $k"; break; fi
  done
fi

# Shell-harness projects - plugin repos, dotfiles, anything where a runner script
# IS the suite. Checked after the manifests so a real one still wins, but it also
# rescues a manifest that declares no test at all; without this the Step 6 gate
# degrades to "no command" and the run proceeds with nothing verifying it.
# A runner at the top wins outright. Failing that, the repository is asked for its
# TRACKED runners and exactly ONE is accepted, so a plugin or package monorepo that
# keeps <project>/tests/run-tests.sh is still found.
#
# Deliberately no command assembled from several runners. Step 0 cannot enumerate
# projects honestly: it probes THIS checkout, while the gates run in a worktree Step 1
# cuts from `origin/$base` afterwards, so any enumeration can disagree with the tree
# under test - and one stale link then either hides a red suite or kills the whole
# command. Two or more runners therefore stay ambiguous on purpose: no test command is
# reported and `pin-config.sh` is the documented way to name the right one. The
# multi-suite case and what it would take is #23.
#
# Tracked, because an ignored scratch project or an untracked leftover is not in the
# worktree the gates run in, so a command naming it dies there at 127. The top-level
# probe below keeps its long-standing behaviour and accepts an untracked runner too.
harness_entry() { # dir relative to det_root ("" = its top) -> the runner path, or nothing
  local d=$1 h p
  for h in tests/run-tests.sh test/run-tests.sh scripts/run-tests.sh run-tests.sh; do
    p=${d:+$d/}$h
    if [ -f "$det_root/$p" ]; then printf '%s' "$p"; return 0; fi
  done
  return 1
}
det_source_test=""
if [ -z "$det_test" ]; then
  if harness=$(harness_entry ""); then
    det_test="bash $harness"
    det_source_test=$harness
  else
    mapfile -t _runners < <(
      git -C "$det_root" ls-files --cached -- '*/run-tests.sh' 2>/dev/null | sort
    )
    if [ "${#_runners[@]}" = 1 ]; then
      # Quoted: run-gates.sh hands the value to `bash -c`, so a project directory with
      # a space in its name would otherwise arrive as two arguments.
      det_test="bash \"${_runners[0]}\""
      det_source_test=${_runners[0]}
    fi
  fi
fi

# Config wins over auto-detect; track the source per command.
cmd_test=${CFG_TEST:-$det_test}
cmd_typecheck=${CFG_TYPECHECK:-$det_typecheck}
cmd_visual=${CFG_VISUAL:-$det_visual}
cmd_smoke=${CFG_SMOKE:-$det_smoke}
pick_source() { if [ -n "$1" ]; then echo config; else echo "$2"; fi; }
src_test=$(pick_source "$CFG_TEST" "${det_source_test:-$det_source}")
src_typecheck=$(pick_source "$CFG_TYPECHECK" "$det_source")

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
