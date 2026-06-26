# issue-to-pr

A Claude Code plugin that drives a single GitHub issue from triage to a merge-ready pull
request through a gated pipeline. The input can be a **bare issue** or a **card
on a GitHub Projects (v2) board** — both run the same flow. The PR always links the issue so
it auto-closes on merge; when the issue is tracked on a board, the card's status advances as
work progresses.

## Installation

```bash
/plugin install issue-to-pr@DmitriyYukhanov/claude-plugins
```

## Features

### Skill: `issue-to-pr`

Invoked by the model or by you (`/issue-to-pr [issue-number | next]`) — a pipeline with hard
gates that block forward progress:

- **Triage → design → implement → review → PR**, scaled to complexity (simple edits skip
  straight to TDD; complex work goes through brainstorming and a design cross-review gate).
- **Gates:** design hardening (cross-review or a multi-agent fallback), tests green
  (typecheck + tests, plus visual checks for UI), and a code-review loop that runs until
  clean or five passes.
- **Issue ↔ board, one pipeline.** Step 0 resolves the input to an issue and decides whether
  board-status sync applies. Board cards advance to *in-progress* at branch cut and
  *in-review* at PR open; `Done` is left to merge-time automation.
- **Graceful by default.** Missing the `project` token scope degrades to link-only with a
  one-line fix hint; a failed status write never blocks the PR.

### Configuration (optional)

`.claude/issue-to-pr.local.md` (YAML frontmatter) sets the board URL, base branch, and
typecheck/test/visual commands. Everything is optional — with no file the skill auto-detects
commands from the project and runs by the issue argument.

### Companion skills (optional)

Optional companions that sharpen specific steps: `superpowers:*`, `/deep-research`, `/cross-review` (from
`codex-collaboration`), `humanizer`, and `/code-review`. Each is used if installed, with an
inline fallback otherwise.

## Usage

The skill activates when you ask to pick up a task — "take task 4", "work on issue #7", "do
the next task", "start issue 12" — or via the slash command:

```text
/issue-to-pr 4

/issue-to-pr next
```

## License

MIT
