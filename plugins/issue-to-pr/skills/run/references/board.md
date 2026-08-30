# Board sync — GitHub Projects v2

Read only when the config names `board.url` (`R/configuration.md`). Everything here is
**best-effort at every step**: any failure is one reported line and the run continues. A
board hiccup never blocks the pipeline, and nothing here is worth debugging mid-run.

`gh auth status` must list the `project` scope. Without it, say once that board sync is off
and carry on with plain issues; the fix is `gh auth refresh -s project`. A fine-grained token
prints no scopes line at all — that is unknown, not missing, and board sync is skipped either
way, because `gh` reads the classic line.

Discovery is **one backgrounded command**, so it costs the run no wait, and it prints what it
found because a later Bash call is a new shell in which nothing it assigned survives. The
mutation cannot join it: picking the option needs `opts` in front of you and the matching
below is a judgement, not a pipeline stage.

```bash
item=$(gh api graphql -f query='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){projectItems(first:20){nodes{id project{id url}}}}}}' \
  -F owner=<OWNER> -F repo=<REPO> -F num=<N> \
  --jq '[.data.repository.issue.projectItems.nodes[] | select("<BOARD_URL>"=="" or .project.url=="<BOARD_URL>") | "\(.id)\t\(.project.id)"] | first // ""') \
  || { echo "BOARD=lookup-failed"; exit 0; }
[ -n "$item" ] || { echo "BOARD=not-on-the-board"; exit 0; }
opts=$(gh api graphql -f query='query($proj:ID!,$field:String!){node(id:$proj){... on ProjectV2 {field(name:$field){... on ProjectV2SingleSelectField {id options{id name}}}}}}' \
  -F proj="${item#*$'\t'}" -F field=Status \
  --jq '.data.node.field as $f | $f.options[] | "\($f.id)\t\(.name)\t\(.id)"') \
  || { echo "BOARD=status-unreadable"; exit 0; }
printf 'ITEM=%s\nOPTS=%s\n' "$item" "$opts"
```

A failed call leaves on its own rung, which is what lets the next paragraph read an empty
`opts` as an answer. Twenty items is the whole search: an issue carried on more boards than
that reads as not on this one, and that is the trade, not an oversight.

`opts` empty means the board has no `Status` field at all, which is not the same as a Status
field with no matching column — say which one it was. Otherwise pick the option: `status_map`
pins the exact column name and is authoritative when set; without it match case- and
punctuation-insensitively against the target, where *in progress* also answers to doing,
started, wip, in development, and *in review* to review, reviewing, code review, pr open,
ready for review. Then set it:

```bash
gh api graphql -f query='mutation($proj:ID!,$item:ID!,$field:ID!,$opt:String!){updateProjectV2ItemFieldValue(input:{projectId:$proj,itemId:$item,fieldId:$field,value:{singleSelectOptionId:$opt}}){projectV2Item{id}}}' \
  -F proj=<PROJECT_ID> -F item=<ITEM_ID> -F field=<FIELD_ID> -F opt=<OPTION_ID>
```

`Done` is never set here: GitHub's own automation moves the card when the PR merges into the
default branch.
