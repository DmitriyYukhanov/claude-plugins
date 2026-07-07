# Non-issue entry -- free-text mode (spec sec 6.2)

The pipeline normally takes an issue number. This mode covers the case where the user
describes work but no issue exists yet, e.g. `/issue-to-pr "add rate limiting to the
public API"`. Keep the frontmatter `description` trigger scoped to "no issue exists yet"
so it does not over-fire on a normal "take issue N".

## When it fires

The request names something to build or fix and carries NO issue number or URL. Any bare
"#N", "issue N", "the next task", or issue link routes to the normal path instead.

## Flow: draft, then create

Draft an issue `{title, body, acceptance_criteria}` that faithfully restates the request.
Never invent scope the user did not ask for; the drafted issue only restates what was
asked, and its acceptance criteria are the user's veto surface.

- **Scope unambiguous** -> create it silently (`gh issue create`) and proceed. The
  drafted-issue link MUST be the FIRST output line of the turn
  (`Drafted issue #<N>: <title>`), so a misfire is caught the same turn. This first-line
  echo is the sole guard against auto-created-issue spam.
- **Scope ambiguous** -> this is the pipeline's single sanctioned pre-design question,
  relocated to BEFORE `gh issue create`. Ask ONE batched `AskUserQuestion` to settle
  scope, then create + proceed. Never ask a second time.

## Why the ask must precede creation

`triage-evidence.sh` and `preflight.sh` both take an issue number; with none they degrade
(`missing-issue`). So an ambiguous free-text scope cannot defer to the normal Step 4.5
question slot -- it must be settled before the issue exists. Relocating that one question
keeps the three-contact-moments contract intact (`R/autonomy.md`): it is the SAME single
design question, moved earlier for entry-mode, not a fourth contact.

## After the issue exists

The flow is byte-identical to `take issue N`: `preflight.sh <N>`, worktree, triage, gates,
the merge gate. Downstream code paths never learn the issue was model-drafted, so nothing
below Step 0 changes.

Large free text that triages to `epic` routes into the epic decompose flow (`R/epic.md`),
not a single pipeline run.
