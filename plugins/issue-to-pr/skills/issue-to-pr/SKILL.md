---
name: issue-to-pr
description: >-
  Drive a GitHub issue — bare or tracked on a Project board — from triage to a
  merge-ready PR through a gated pipeline (design cross-review, tests green,
  code-review loop). Auto-links the issue to close on merge and advances the
  board card's status as work progresses, then merges and cleans up once you
  approve the PR in-session. Triggers: "take task N", "work on issue #N",
  "do the next task", "start issue 7", and — for the merge gate on a follow-up
  turn — "merge it", "approve the PR", "ship it", "lgtm merge".
user-invocable: true
argument-hint: "[issue-number | next]"
---

# issue-to-pr — issue → merge-ready PR pipeline

One repeatable flow for taking a single GitHub issue from triage and shipping it as a
pull request. The shape is the same every time so nothing gets skipped. The **gates**
(design cross-review, tests green, code-review clean) block forward progress. Create one
todo per step.

The input can be a **bare issue** or a **card on a GitHub Projects (v2) board** — the
pipeline is identical. The PR always links the issue (`Closes #N`) so it auto-closes when the
PR merges into the default branch; when the issue is tracked on a board, the card's status is
advanced as work progresses (Step 0 decides which mode applies).

This skill authorizes branching, committing, and opening a PR — all inside an isolated
worktree so concurrent local runs never clash. It **merges only after you approve the PR in
this session** (squash), then cleans up the branch, worktree, and temp artifacts. The squash
writes to the base branch, so that merge is the one irreversible step — it happens on nothing
less than an explicit, unambiguous go-ahead (Step 11), and even then never force-pushes or
bypasses branch protection.

## Configuration (optional)

Per-project settings live in `.claude/issue-to-pr.local.md` (YAML frontmatter): the board
URL, base branch, and the typecheck/test/visual commands. Everything is optional — with no
file the skill auto-detects commands and runs by issue argument. `preflight.sh` (Step 0) parses
this file and resolves the commands + base for you (`CMD_TEST`, `CMD_TYPECHECK`, `BASE`, ...).
Schema: `${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/configuration.md`. This guide refers
to the resolved commands as `<typecheck_cmd>`, `<test_cmd>`, `<visual_cmd>`.

**Resolve config in the main checkout, up front.** This file is gitignored, so it does not
exist inside the worktree — read it (and the resolved commands + base) in `<original-root>`
before entering the worktree, and carry the resolved values; never re-read config from inside
the worktree, or the pinned commands are silently lost to auto-detect.

## Companion skills (optional, graceful)

The pipeline is sharper with a few companions but never breaks without them — it runs the
inline equivalent and names what would have improved the result. Capability → preferred
skill → fallback map: `${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/companions.md`.
Short form: `superpowers:brainstorming`/`writing-plans`/`test-driven-development`/
`systematic-debugging`/`verification-before-completion`, `/deep-research`, `/cross-review`
(from `codex-collaboration`), `humanizer`, and `/code-review` — used **if available**,
otherwise the inline equivalent.

## Hard rules (never violate)

- **New task = new branch, in its own worktree.** Determine the integration base FIRST (from
  config `base_branch`; `auto` = `dev` if a `dev` branch exists locally or on the remote, else
  `main`), then cut the branch from THAT same ref: `feat/issue-<N>-<slug>` or
  `fix/issue-<N>-<slug>` (the issue number is baked in so the branch can't collide across
  issues), inside a dedicated `../<repo>-worktrees/issue-<N>` worktree (see
  `${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/contracts.md`). All work
  happens there; never run two tasks in the same working tree. The branch you start from and
  the PR target must be the same base, or commits living only on `dev` go missing and surface
  as conflicts at merge.
- **Merge is gated on explicit in-session approval.** Open the PR and stop. Only merge
  (squash) after the user approves *this* PR in the session — never on the same turn the PR
  opens. After a successful merge, clean up (Step 12).
- Stage with **explicit paths** (`git add path1 path2`). Never `git add -A` / `git add .`.
- Human-facing text (UI strings >1–2 words, the report, the PR body) passes through
  `humanizer` if installed. Code identifiers, dev comments, log lines, and
  conventional-commit subjects do not.
- Conventional Commits. TDD (failing test first) for any logic.
- Don't ask the user a question you can answer yourself — see Step 3.
- Don't claim "done / green / passing" without showing the command output
  (`verification-before-completion`, or just paste the output).

## Step 0 — Resolve the input + detect mode

Turn the request into a concrete issue and decide whether board-status sync applies. **Run
`${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh <N>` first** (from the main checkout) — one call
returns auth/scopes, repo owner/name, resolved `BASE`/`START_POINT`, auto-detected gate commands,
issue state, `WORKTREE_STATE`, and `BOARD_CONFIGURED`/`BOARD_MEMBER`. Then apply the mode table.
Script keys and exit codes: `${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/contracts.md`.

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
- **Cut the branch inside an isolated worktree** with `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh
  ensure <N> --branch <branch> --start-point <START_POINT>` (from the main checkout). It
  creates / resumes / reattaches and reports `WT_PATH`, `STATE`, and `INSTALL_HINT`. `cd` into
  `WT_PATH`, then **install dependencies** — a fresh worktree has only tracked files (no
  `node_modules`/`.venv`/etc), so run `INSTALL_HINT` through `run-gates.sh` (keeps output out of
  context) before touching any file. Exit-code handling (bad-checkout, stale dir, invalid
  start-point, permission → in-place fallback) is in
  `${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/contracts.md` → "worktree.sh". Everything
  downstream runs there.
- **Board-mode:** once work begins, `${CLAUDE_PLUGIN_ROOT}/scripts/board-sync.sh <owner/repo> <N>
  in_progress` (run it in the background; it always exits 0 and never blocks progress). If
  preflight reported `STATUS_MAP_IN_PROGRESS`, append `--option "<that value>"`.

## Step 2 — Triage complexity (decides the path)

Run `${CLAUDE_PLUGIN_ROOT}/scripts/triage-evidence.sh <N>` for objective signals (labels,
checklist items, referenced-paths-that-exist, new-thing keywords, linked issues), then map them
to a level yourself:

- **Simple** (one obvious edit, no design choices): skip to Step 5, implement directly with
  TDD.
- **Complex** (real design/UX choices, multiple files, new behavior): brainstorm (Step 3+).
- **Very complex** (unfamiliar domain, external systems, security/perf unknowns): gather
  context first (`/deep-research` if available, else a focused web-search pass), then
  brainstorm.

When in doubt, treat it as one level harder.

## Step 2.5 — Decide on state tracking

- If the task is complex+ and will likely outlive a context compaction, keep a short progress
  file at **`tmp/task-<N>/progress.md` inside the worktree** (gitignored): branch,
  `<original-root>`, decisions, plan checklist, current step.
- Put the **design doc there too** (`tmp/task-<N>/design.md`) unless your project commits design
  docs under `docs/`. Treat it as a working artifact.
- Keep these *inside* the worktree so a resume restores them and Step 12 removes them for free
  when the worktree is torn down. Write with an absolute path (or `cd` into the worktree first) —
  don't assume a bare relative path lands there. Only in the sandbox-fallback (in-place) case is
  there no worktree; then use the session scratchpad, and Step 12 sweeps it explicitly (see its
  keep-list).

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

- Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-gates.sh --log-dir tmp/task-<N>/logs --gate
  typecheck='<typecheck_cmd>' --gate test='<test_cmd>'` (add `--gate visual='<visual_cmd>'` for
  UI). The printed `GATES_OK=true` + `GATE_*_EXIT` block is the green proof; a failing gate
  surfaces only its last 40 lines.
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

- Re-run the same `run-gates.sh` invocation (typecheck + test, + visual for UI) once more after
  the review edits. All green before the PR.

## Step 9 — Commit + PR

- `git add <explicit paths>`, conventional-commit subjects (separate unrelated concerns).
- Push the branch **with upstream tracking** — `git push -u origin <branch>` (Step 11's merge
  precondition relies on it). Open a PR against the base from Step 1 with `gh pr create`. Link the
  issue (`Closes #<N>`) so it auto-closes when the PR merges into the default branch. PR body is
  human-facing → humanize it.
- **Board-mode:** `${CLAUDE_PLUGIN_ROOT}/scripts/board-sync.sh <owner/repo> <N> in_review`
  (background, best-effort). `Done` is left to merge-time — GitHub's automation moves the card
  when the issue closes (on a default-branch merge).
- The PR opens here and the skill **stops**. Merging is Step 11, gated on the user's approval
  — do **not** merge or deploy on this turn.

## Step 10 — Report (plain language)

Short, human, no jargon — understandable by a 3rd-year student:
- What was built and why, how it works, what was tricky, what was decided.
- Test status (with the green proof) and anything the user must do by hand (manual setup,
  secrets, follow-up).
- The PR link.
- End with a clear hand-back: the PR is up and waiting — ask the user to reply when they want
  it merged. Then **stop**; the skill's turn ends here.

## Step 11 — Merge on approval (GATE)

On a later turn your CWD may have reset to the main checkout, so **return to your working tree
first**: in worktree mode `cd` into `../<repo>-worktrees/issue-<N>`; in the sandbox in-place
fallback there's no worktree, so stay in the main checkout on `<branch>` (contracts.md →
"worktree.sh" covers both). Then read the user's reply against *this* PR. **Merge only on an unambiguous go-ahead to merge THIS PR — the burden is on a
clear approval. If the reply is anything else, do not merge.**
- **Go-ahead** — an unmistakable instruction to merge this PR ("merge it", "lgtm, ship it",
  "approved", "go ahead and merge") → run `${CLAUDE_PLUGIN_ROOT}/scripts/approve.sh <branch>
  --quote "<verbatim reply>"`, then `${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh merge <N> --branch
  <branch>`. That script is the only sanctioned merge path; the PreToolUse hook and the script
  both validate the single-use approval marker before `gh pr merge` runs.
- **Change requests** → treat as review feedback: implement in the worktree, then **re-run the
  gates** — Step 6 (typecheck + tests, + visual for UI) and Step 7 (code-review) on the new diff,
  fixing until clean — before pushing to the same branch, re-reporting, and waiting for approval
  again. A change-request edit must clear the same gates as the original work; never merge
  unverified changes.
- **Anything else** → do **not** merge. If the reply is a vague acknowledgment ("ok", "cool",
  "looks fine") or a question about the PR, ask them to confirm the merge explicitly. If the user
  will merge it themselves later or has abandoned the task, ask whether to tear down the local
  worktree now — via the **"Teardown without merging"** section, which removes only the local
  worktree and **keeps the PR and its remote branch intact** (never the section-3 cleanup, which
  deletes the remote branch and would close the open PR). Don't silently leave a stale worktree a
  later run would resume from. There is no timeout; approval is purely explicit — never inferred.

Merge mechanics and failure handling (marker validation, `git push` precondition, squash by head
branch, the single retry for pending checks, when to stop):
`${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/contracts.md` → "worktree.sh". If `merge`
exits 2 (`STOP_REASON=`), **skip cleanup** — the worktree and branch stay put so nothing is lost.

## Step 12 — Cleanup (after a successful merge)

Only after Step 11 merges. First confirm the outcome honestly: GitHub auto-closes the linked
issue (and moves the board card to Done) **only on a merge into the default branch** — if the
base was a non-default branch like `dev`, the issue stays open on purpose; say so rather than
reporting it closed (see the reference's "Merge on approval" outcome check). Then clean up: order
matters — you can't remove a worktree from inside it. **`cd` your shell into `<original-root>`
first** (not just the subprocess — a shell whose current directory is the worktree locks it on
Windows and the removal fails). **Salvage any lasting design doc first**
(`git worktree remove` silently deletes gitignored files), then, from the main checkout, run
`${CLAUDE_PLUGIN_ROOT}/scripts/worktree.sh cleanup <N> --branch <branch> --salvage-to <dir>` (it
salvages design/progress/state, removes the worktree, deletes the merged local + remote branch,
and refuses on tracked dirtiness `STOP_REASON=dirty-tracked-files`). Report from its keys, not from
assumption — if `DELETED_LOCAL=false` or it emits `LEFTOVER_DIR`, a locked directory remains; say so
and remove it by hand once the lock clears. Then sweep temp artifacts outside
the worktree — honoring the keep-list (committed `docs/`, anything already in the PR, anything the
user asked to keep). Keys, the in-place variant, and the teardown (self-merge/abandon) path:
`${CLAUDE_PLUGIN_ROOT}/skills/issue-to-pr/references/contracts.md` → "worktree.sh".
Finish with one line naming what was merged, what was removed, and anything kept.

## Step 13 — Improve this skill

After shipping, reflect: did any step bite, stay unclear, or get skipped? If so, refine this
SKILL.md. Leave it sharper than you found it.
