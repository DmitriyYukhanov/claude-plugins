#!/usr/bin/env bash
# board-sync.sh - move a GitHub Projects (v2) card's Status field, wrapping the
# whole GraphQL chain (membership -> field/option resolution with a smart alias
# table -> mutation). Best-effort by construction: it ALWAYS exits 0 and reports
# outcome as JSON, so a board hiccup never blocks the pipeline. The SKILL runs it
# with run_in_background, so there is zero main-context wait.
#
#   board-sync.sh <owner/repo> <issue> <in_progress|in_review|done> \
#                 [--board-url U] [--status-field F] [--state S]
#   board-sync.sh <owner/repo> --create-card <title> [--board-url U]
#   board-sync.sh <owner/repo> --convert-draft <itemId>
#
# Always JSON: OK plus optional SKIPPED_REASON / ERROR / HINT. The create-card /
# convert-draft modes have no Layer-1 caller (they are used by epic mode, sec 6.1);
# they report OK=false SKIPPED_REASON=mode-deferred until v2.0.
#
# The GraphQL queries and some jq filters below intentionally hold literal
# $-tokens (GraphQL variables like $owner, jq bindings like $f) inside single
# quotes - they are NOT shell expansions. Every real shell-var interpolation in
# this file is double-quoted, so disabling SC2016 file-wide is safe here.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

enable_json # board-sync always speaks JSON

repo_slug=""
issue=""
status=""
board_url=""
status_field="Status"
explicit_option="" # explicit column name (restores the board.status_map escape hatch)
mode="transition"
card_title="" # --create-card value (epic mode, sec 6.1)
draft_item=""  # --convert-draft value

positionals=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --board-url) board_url=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --status-field) status_field=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --option) explicit_option=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --state) shift 2 2>/dev/null || shift "$#" ;; # state.json caching lands in v1.3.0 (sec 5.5)
    --create-card) mode="create-card"; card_title=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --convert-draft) mode="convert-draft"; draft_item=${2:-}; shift 2 2>/dev/null || shift "$#" ;;
    --json) shift ;; # already JSON
    -*) warn "board-sync: ignoring unknown flag: $1"; shift ;;
    *) positionals+=("$1"); shift ;;
  esac
done

repo_slug=${positionals[0]:-}
[ -n "$repo_slug" ] || { emit OK false; emit SKIPPED_REASON missing-repo; done_ok; }
owner=${repo_slug%%/*}
repo=${repo_slug#*/}

has_project_scope() {
  local scopes
  scopes=$(gh auth status 2>&1 | grep -i 'token scopes' | grep -oE "'[^']+'" | tr -d "'" | paste -sd, - || printf '')
  case ",$scopes," in *,project,*) return 0 ;; *) return 1 ;; esac
}

# -- epic-mode card ops (sec 6.1). Board-mode only and best-effort: any missing
# piece reports a SKIPPED_REASON and still exits 0, so materialize never hard-stops.
if [ "$mode" = "create-card" ]; then
  [ -n "$card_title" ] || { emit OK false; emit SKIPPED_REASON missing-title; done_ok; }
  [ -n "$board_url" ] || { emit OK false; emit SKIPPED_REASON missing-board-url; emit HINT "epic --create-card needs --board-url"; done_ok; }
  has_project_scope || { emit OK false; emit SKIPPED_REASON missing-scope; emit HINT "gh auth refresh -s project"; done_ok; }
  board_num=${board_url##*/projects/}; board_num=${board_num%%/*}
  board_rest=${board_url%/projects/*}; board_login=${board_rest##*/}
  proj_id=$(gh project view "$board_num" --owner "$board_login" --format json --jq '.id' 2>/dev/null || printf '')
  [ -n "$proj_id" ] || { emit OK false; emit SKIPPED_REASON project-not-found; done_ok; }
  card_id=$(gh api graphql \
    -f query='mutation($p:ID!,$t:String!){addProjectV2DraftIssue(input:{projectId:$p,title:$t}){projectItem{id}}}' \
    -F p="$proj_id" -F t="$card_title" \
    --jq '.data.addProjectV2DraftIssue.projectItem.id' 2>/dev/null || printf '')
  if [ -n "$card_id" ]; then emit OK true; emit CARD_ID "$card_id"; else emit OK false; emit ERROR create-failed; fi
  done_ok
fi

if [ "$mode" = "convert-draft" ]; then
  [ -n "$draft_item" ] || { emit OK false; emit SKIPPED_REASON missing-item; done_ok; }
  has_project_scope || { emit OK false; emit SKIPPED_REASON missing-scope; emit HINT "gh auth refresh -s project"; done_ok; }
  draft=$(gh api graphql \
    -f query='query($item:ID!){node(id:$item){... on ProjectV2Item{content{... on DraftIssue{title body}}}}}' \
    -F item="$draft_item" \
    --jq '.data.node.content | "\(.title)\t\(.body // "")"' 2>/dev/null || printf '')
  d_title=${draft%%$'\t'*}
  d_body=${draft#*$'\t'}
  [ -n "$d_title" ] || { emit OK false; emit SKIPPED_REASON draft-not-found; done_ok; }
  new_url=$(gh issue create --title "$d_title" --body "$d_body" 2>/dev/null || printf '')
  if [ -n "$new_url" ]; then emit OK true; emit ISSUE_URL "$new_url"; else emit OK false; emit ERROR convert-failed; fi
  done_ok
fi

issue=${positionals[1]:-}
status=${positionals[2]:-}
if [ -z "$issue" ] || [ -z "$status" ]; then
  emit OK false
  emit SKIPPED_REASON missing-args
  done_ok
fi

# -- project scope gate -------------------------------------------------------
scopes=$(gh auth status 2>&1 | grep -i 'token scopes' | grep -oE "'[^']+'" | tr -d "'" | paste -sd, - || printf '')
case ",$scopes," in
  *,project,*) : ;;
  *)
    emit OK false
    emit SKIPPED_REASON missing-scope
    emit HINT "gh auth refresh -s project"
    done_ok
    ;;
esac

# -- resolve the project item + project id for this issue ---------------------
item_line=$(gh api graphql \
  -f query='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){projectItems(first:20){nodes{id project{id number url title}}}}}}' \
  -F owner="$owner" -F repo="$repo" -F num="$issue" \
  --jq ".data.repository.issue.projectItems.nodes[] | select(\"$board_url\"==\"\" or .project.url==\"$board_url\") | \"\(.id)\t\(.project.id)\"" \
  2>/dev/null | head -1 || printf '')

if [ -z "$item_line" ]; then
  emit OK false
  emit SKIPPED_REASON not-a-member
  done_ok
fi
item_id=${item_line%%$'\t'*}
project_id=${item_line#*$'\t'}

# -- resolve the status field + its options -----------------------------------
opts=$(gh api graphql \
  -f query='query($proj:ID!,$field:String!){node(id:$proj){... on ProjectV2 {field(name:$field){... on ProjectV2SingleSelectField {id options{id name}}}}}}' \
  -F proj="$project_id" -F field="$status_field" \
  --jq '.data.node.field as $f | $f.options[] | "\($f.id)\t\(.name)\t\(.id)"' \
  2>/dev/null || printf '')

if [ -z "$opts" ]; then
  emit OK false
  emit SKIPPED_REASON status-field-not-found
  done_ok
fi

# -- pick the option whose name matches the target (alias table) --------------
norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'; }
aliases_for() {
  case "$1" in
    in_progress) printf 'in progress\ndoing\nstarted\nwip\nin development\ndevelopment\n' ;;
    in_review) printf 'in review\nreview\nreviewing\ncode review\npr open\nready for review\n' ;;
    done) printf 'done\nclosed\ncomplete\ncompleted\nmerged\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Build the normalized set of acceptable option names for the target status. An
# explicit column name (board.status_map, passed as --option) is authoritative:
# match only it. Otherwise fall back to the built-in alias table.
alias_norms=""
if [ -n "$explicit_option" ]; then
  alias_norms=$(norm "$explicit_option")
else
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    alias_norms="$alias_norms $(norm "$a")"
  done <<EOF
$(aliases_for "$status")
$status
EOF
fi

field_id=""
option_id=""
while IFS=$'\t' read -r fid oname oid; do
  [ -n "$oname" ] || continue
  field_id=$fid
  on=$(norm "$oname")
  case " $alias_norms " in
    *" $on "*)
      option_id=$oid
      break
      ;;
  esac
done <<EOF
$opts
EOF

if [ -z "$option_id" ]; then
  emit OK false
  emit SKIPPED_REASON option-not-found
  emit HINT "no option on the '$status_field' field matches '$status'"
  done_ok
fi

# -- mutate -------------------------------------------------------------------
result=$(gh api graphql \
  -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$opt}}){projectV2Item{id}}}' \
  -F proj="$project_id" -F item="$item_id" -F field="$field_id" -F opt="$option_id" \
  --jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id' \
  2>/dev/null || printf '')

if [ -n "$result" ]; then
  emit OK true
  emit STATUS_SET "$status"
else
  emit OK false
  emit ERROR mutation-failed
fi
done_ok
