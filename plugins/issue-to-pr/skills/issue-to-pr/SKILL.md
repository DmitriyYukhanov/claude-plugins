---
name: issue-to-pr
description: >-
  Drive a GitHub issue — bare or tracked on a Project board — from triage to a
  merge-ready PR through a gated pipeline (design cross-review, tests green,
  code-review loop). Auto-links the issue to close on merge and advances the
  board card's status as work progresses. Triggers: "take task N",
  "work on issue #N", "do the next task", "start issue 7".
user-invocable: true
argument-hint: "[issue-number | next]"
---

# issue-to-pr — issue → merge-ready PR pipeline

One repeatable flow for taking a single GitHub issue from triage and shipping it as a
pull request. The shape is the same every time so nothing gets skipped. The **gates**
(design cross-review, tests green, code-review clean) block forward progress. Create one
todo per step.

The input can be a **bare issue** or a **card on a GitHub Projects (v2) board** — the
pipeline is identical. The PR always links the issue so it auto-closes on merge; when the
issue is tracked on a board, the card's status is advanced as work progresses (Step 0
decides which mode applies).

This skill authorizes branching, committing, and opening a PR. It does **not** merge,
deploy, or push to a protected base branch — those are separate, explicit actions.

## Configuration (optional)

Per-project settings live in `.claude/issue-to-pr.local.md` (YAML frontmatter): the board
URL, base branch, and the typecheck/test/visual commands. Everything is optional — with no
file the skill auto-detects commands and runs by issue argument. Schema and auto-detect
rules: `${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/configuration.md`. This guide
refers to the resolved commands as `<typecheck_cmd>`, `<test_cmd>`, `<visual_cmd>`.

## Companion skills (optional, graceful)

The pipeline is sharper with a few companions but never breaks without them — it runs the
inline equivalent and names what would have improved the result. Capability → preferred
skill → fallback map: `${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/companions.md`.
Short form: `superpowers:brainstorming`/`writing-plans`/`test-driven-development`/
`systematic-debugging`/`verification-before-completion`, `/deep-research`, `/cross-review`
(from `codex-collaboration`), `humanizer`, and `/code-review` — used **if available**,
otherwise the inline equivalent.

## Hard rules (never violate)

- **New task = new branch.** Determine the integration base FIRST (from config
  `base_branch`; `auto` = `dev` if it exists, else `main`), then cut the branch from THAT
  same ref: `feat/<slug>` or `fix/<slug>`. The branch you start from and the PR target must
  be the same base, or commits living only on `dev` go missing and surface as conflicts at
  merge.
- Stage with **explicit paths** (`git add path1 path2`). Never `git add -A` / `git add .`.
- Human-facing text (UI strings >1–2 words, the report, the PR body) passes through
  `humanizer` if installed. Code identifiers, dev comments, log lines, and
  conventional-commit subjects do not.
- Conventional Commits. TDD (failing test first) for any logic.
- Don't ask the user a question you can answer yourself — see Step 3.
- Don't claim "done / green / passing" without showing the command output
  (`verification-before-completion`, or just paste the output).

## Step 0 — Resolve the input + detect mode

Turn the request into a concrete issue and decide whether board-status sync applies. Full
mechanics (verified `gh` commands, token scope, draft handling):
`${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/board-sync.md`.

| Input | Mode |
|---|---|
| `#N` / issue URL, no board configured | **issue-mode** — link `Closes #N` only |
| `#N`, and the issue is on the configured board | **board-mode** — link + advance the card |
| `next` / top card of `board.url` | **board-mode** |
| board card with no backing issue (draft) | convert draft → issue, then proceed |

- Derive the repo owner from `gh repo view --json owner,name`.
- Detect board membership: query the issue's `projectItems`. Empty (and no board arg) →
  issue-mode. Otherwise board-mode for the project in `board.url` (or the first, with a
  note).
- Board-mode needs the `project` token scope. If it's missing, **do not fail** — run
  link-only and tell the user `gh auth refresh -s project`.

## Step 1 — Read the task + context

- `gh issue view <N>` for the issue. Skim siblings (`gh issue list --state all`) so the
  change fits the roadmap.
- Open the files the issue points at; map the real code (functions, wiring, existing tests,
  any visual harness).
- Confirm the base branch (Hard rules + `git branch -a`).
- **Board-mode:** once the branch is cut and work begins, set the card's status to
  `in_progress` (see board-sync). A failed status write is logged and never blocks progress.

## Step 2 — Triage complexity (decides the path)

- **Simple** (one obvious edit, no design choices): skip to Step 5, implement directly with
  TDD.
- **Complex** (real design/UX choices, multiple files, new behavior): brainstorm (Step 3+).
- **Very complex** (unfamiliar domain, external systems, security/perf unknowns): gather
  context first (`/deep-research` if available, else a focused web-search pass), then
  brainstorm.

When in doubt, treat it as one level harder.

## Step 2.5 — Decide on state tracking

- If the task is complex+ and will likely outlive a context compaction, keep a short
  progress file in a **gitignored** location (`tmp/task-<N>/progress.md` or the session
  scratchpad): branch, decisions, plan checklist, current step.
- Put the **design doc there too** (`tmp/task-<N>/design.md`) unless your project commits
  design docs under `docs/`. Treat it as a working artifact.
- **Delete `tmp/task-<N>/` when the task is done.** It never lands in git.

## Step 3 — Brainstorm (complex+ only)

Use `superpowers:brainstorming` if installed; otherwise run the same loop inline. Before
asking the user anything:
1. Investigate the code + existing issues; form the best answer yourself.
2. Still unsure? Use web search / docs lookup to settle it.
3. Only a genuine, still-open judgment call after that goes to the user. Auto-decide
   everything you reasonably can.

When writing the design doc, **plan the tests explicitly**. Anything that needs external or
visual inspection (UI, layout, browser behavior) must be verifiable with `<visual_cmd>` or
a dedicated browser test — not eyeballing alone. Logic gets unit/integration tests.

## Step 4 — Harden the design (GATE)

- Self-review the design doc.
- Run `/cross-review` on it for cross-agent critique (needs `codex-collaboration` + Codex
  authenticated, `/codex:setup`). If unavailable and you can't fix it yourself, **don't
  stall** — run an equivalent multi-agent review via `Workflow` (several independent
  reviewers with distinct lenses → adversarial synthesis). Resolve every finding — accept,
  reject (with reason), or fix.
- Gate: the doc meets a high bar (clear problem, chosen approach with rejected
  alternatives, explicit test plan, risks) before any code. Bugs caught here are far cheaper
  than after implementation.

## Step 5 — Plan + implement

- Turn the design into a written plan (`superpowers:writing-plans` if available), then
  execute.
- **Execution mode:** if the work parallelizes and you're in a multi-agent mode, run it
  through a `Workflow` (fan-out + adversarial verify). Otherwise use
  `superpowers:subagent-driven-development`, or just implement directly with TDD for a
  single tightly-coupled file.
- Write the test first, watch it fail, implement, watch it pass.

## Step 6 — Tests green (GATE)

- `<typecheck_cmd>` (clean) AND `<test_cmd>` (all green). For UI work also run `<visual_cmd>`
  and inspect its output.
- Anything red ⇒ STOP and fix (`superpowers:systematic-debugging` or a disciplined inline
  pass). Never proceed red.

## Step 7 — Code review loop (GATE)

- Run `/code-review` (e.g. `max --fix` if your setup supports it). Apply real findings;
  record skipped ones (false positives / out-of-scope) with a one-line reason.
- **Each pass reviews the updated diff** — your own fixes can introduce new regressions
  (normal; expect ~1 real follow-up per pass for a while). Re-run typecheck + tests (+ visual
  for UI) after every fix pass, and feed the next pass a summary of what changed.
- Repeat until a pass yields no actionable findings, or 5 passes total — whichever comes
  first. Say how many passes ran and what converged.

## Step 8 — Re-run all tests

- `<typecheck_cmd>` + `<test_cmd>` (+ `<visual_cmd>` for UI) once more after the review
  edits. All green before the PR.

## Step 9 — Commit + PR

- `git add <explicit paths>`, conventional-commit subjects (separate unrelated concerns).
- Push the branch; open a PR against the base from Step 1 with `gh pr create`. Link the
  issue (`Closes #<N>`) so it auto-closes on merge. PR body is human-facing → humanize it.
- **Board-mode:** set the card's status to `in_review` (see board-sync). `Done` is left to
  merge-time — GitHub's built-in project automation moves the card when the issue closes;
  this skill does not merge.
- Do **not** merge or deploy unless the user asks.

## Step 10 — Report (plain language)

Short, human, no jargon — understandable by a 3rd-year student:
- What was built and why, how it works, what was tricky, what was decided.
- Test status (with the green proof) and anything the user must do by hand (manual setup,
  secrets, follow-up).
- The PR link.

## Step 11 — Improve this skill

After shipping, reflect: did any step bite, stay unclear, or get skipped? If so, refine this
SKILL.md. Leave it sharper than you found it.
