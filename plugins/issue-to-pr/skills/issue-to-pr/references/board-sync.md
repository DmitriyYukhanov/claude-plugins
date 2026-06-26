# Board sync — GitHub Projects (v2) status

Mechanics for detecting whether an issue is on a Projects (v2) board and advancing its
status. All commands use `gh` (the GraphQL calls use `gh api graphql --jq`, which bundles
gojq — no external `jq` needed, works on Windows/macOS/Linux).

## Prerequisite — token scope

Project mutations need the `project` scope (reads need `read:project`). Check, and if it's
missing **do not fail the pipeline** — run issue-mode (link-only) and tell the user:

```bash
gh auth refresh -s project
```

## 1. Resolve owner + repo

```bash
gh repo view --json owner,name --jq '{owner: .owner.login, repo: .name}'
```

## 2. Detect board membership for an issue

Empty `projectItems` (and no board passed as input) → **issue-mode**, stop here. Otherwise
pick the project matching `board.url`; if none matches, use the first and note it. Treat an
errored or null response (e.g. missing `read:project`) the same as empty — fall back to
link-only and surface the `gh auth refresh -s project` hint.

```bash
gh api graphql -f owner='<owner>' -f repo='<repo>' -F number=<N> --jq '.data.repository.issue.projectItems.nodes[] | {itemId: .id, projectId: .project.id, number: .project.number, title: .project.title}' -f query='
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    issue(number:$number) {
      id
      projectItems(first:10) {
        nodes { id project { id number title } }
      }
    }
  }
}'
```

This yields, per board: `itemId` (the card), `projectId`, the project `number`, and `title`.

## 3. Read the status field + its options

Find the single-select field named by `board.status_field` (default `Status`) and the
option whose name matches the target (see status matching in `configuration.md`).

```bash
gh api graphql -F projectId='<projectId>' --jq '.data.node.fields.nodes[] | select(.name != null) | select(.options != null) | {fieldId: .id, name: .name, options: .options}' -f query='
query($projectId:ID!) {
  node(id:$projectId) {
    ... on ProjectV2 {
      fields(first:50) {
        nodes {
          ... on ProjectV2SingleSelectField { id name options { id name } }
        }
      }
    }
  }
}'
```

From the matching field take its `id` (`fieldId`) and the chosen option's `id` (`optionId`).

## 4. Set the status

Friendly form (flags verified against the gh manual; one line so it copy-pastes into bash
and PowerShell alike):

```bash
gh project item-edit --id '<itemId>' --field-id '<fieldId>' --project-id '<projectId>' --single-select-option-id '<optionId>'
```

Equivalent GraphQL mutation (verified against GitHub docs):

```bash
gh api graphql -F projectId='<projectId>' -F itemId='<itemId>' -F fieldId='<fieldId>' -f optionId='<optionId>' -f query='
mutation($projectId:ID!, $itemId:ID!, $fieldId:ID!, $optionId:String!) {
  updateProjectV2ItemFieldValue(input:{
    projectId:$projectId, itemId:$itemId, fieldId:$fieldId,
    value:{ singleSelectOptionId:$optionId }
  }) { projectV2Item { id } }
}'
```

A status write that fails (scope, renamed field, transient API error) is logged and
**never blocks** the PR.

## 5. Touchpoints in the pipeline

- **Step 1** (branch cut / work starts) → set `in_progress`.
- **Step 9** (PR opened) → set `in_review`.
- **Done** is left to merge-time. GitHub's built-in project workflow moves the card when the
  issue closes (the PR's `Closes #<N>` triggers that on merge); this skill does not merge.

## 6. Draft card with no backing issue

A board "card" can be a draft (no real issue). The pipeline needs an issue to `Closes`-link,
so convert first, then proceed:

```bash
gh api graphql -F itemId='<draftItemId>' -F repoId='<repositoryId>' -f query='
mutation($itemId:ID!, $repoId:ID!) {
  convertProjectV2DraftIssueItemToIssue(input:{ itemId:$itemId, repositoryId:$repoId }) {
    item { id content { ... on Issue { number } } }
  }
}'
```

Get `repositoryId` from `gh repo view --json id --jq .id` (or the GraphQL `repository.id`).
