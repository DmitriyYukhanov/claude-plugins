---
name: issue-to-pr
description: >-
  Drive a GitHub issue — bare or tracked on a Project board — from triage to a
  merge-ready PR through a gated pipeline (design hardening, tests green,
  code-review clean), scaling the machinery to the task's tier and asking at most one
  batched question. Auto-links the issue to close on merge, advances the board card,
  then merges and cleans up once you approve the PR in-session. Triggers: "take task
  N", "work on issue #N", "do the next task", "build/fix X" when no issue exists yet, and —
  for the merge gate later — "merge it", "approve the PR", "ship it", "lgtm merge".
user-invocable: true
argument-hint: "[issue-number | next | \"free text\"] [--tier trivial|standard|complex|epic]"
---

# issue-to-pr — issue → merge-ready PR pipeline

One repeatable, gated flow: the **gates** (design hardening, tests green, review clean,
approval-gated merge) block progress; the depth between them scales to the tier. Mechanics
live in tested scripts (`S/` = `${CLAUDE_PLUGIN_ROOT}/scripts/`, `R/` = `references/`); you
own judgment. One todo per step.

## Hard rules (never violate)

- **New task = new branch in its own worktree** (`S/worktree.sh ensure`), cut from the
  resolved base. All work happens there; never two tasks in one tree.
- **Merge is gated on explicit in-session approval**, runs ONLY in the main session
  (plugin agents ignore the hook), via `S/approve.sh` + `S/worktree.sh merge` — never a
  bare `gh pr merge`, never on the turn the PR opens.
- **Ask contract:** contact the user at exactly three moments — (1) ONE batched
  `AskUserQuestion` at Step 4.5 (only if the ledger has open items), (2) the merge gate,
  (3) a hard stop. Decide everything else yourself and log it (see below).
- Stage with **explicit paths** (`git add path1 path2`); never `git add -A`/`.` (a hook
  denies it). Conventional Commits. TDD (failing test first) for any logic. Write multi-line
  code with the Write tool — a Bash heredoc breaks on an apostrophe inside the body.
- **Humanizer** runs on 100% of human-facing text (report, PR body, UI strings > 1–2 words)
  regardless of tier — not code/logs/commit subjects. Don't claim "green/passing" without the
  command output. Don't ask what a script or the code can answer.

## Config, tier, ask contract, state

- **Config** (`.claude/issue-to-pr/config.md`, optional): `preflight.sh` parses it and
  resolves the base (schema `R/configuration.md`); read it in the main checkout up front
  (gitignored, absent in the worktree). Gate commands come from it, or from you at Step 6. **Companions** (if installed,
  else inline): `superpowers:*`, `/deep-research`, `/cross-review`, `humanizer`,
  `/code-review` (`R/companions.md`).
- **Tier** (`R/tier-matrix.md`): you pick it at Step 2, `standard` unless the issue argues
  otherwise; it routes research, design, review level/passes, security overlay, report length.
- **Autonomy** (`R/autonomy.md`, read once at Step 0): the ask contract (three contact
  moments; log every judgment call to `state.json.ledger[]` before the next tool call;
  auto-decisions rendered in the report + PR body), the `state.json` schema + the append-only
  `step.log` you write beside it, and the resume path (log wins over stale state).

## Steps

**0. Resolve + preflight.** Turn the request into an issue (free text → draft one, ask only if
ambiguous — `R/entry.md`; a draft card → `S/board-sync.sh --convert-draft`; `next` → top card).
`S/preflight.sh <N> [--claim]` → auth/scopes, repo, `BASE`/`START_POINT`, gate
cmds, issue state, `WORKTREE_STATE`, board membership. **`WARN_CLAIMED_BY` → hard stop and
ask before any further work** (never run an opus design on someone else's issue).
`gh-auth-failed` (2) / config parse (4) → stop. Preflight prints `KEY=value` text:
**substitute the values you read**, they are not shell variables in a later Bash call.
Write the initial state.json.

**1. Worktree.** `S/worktree.sh ensure <N> --branch feat|fix/issue-<N>-<slug> --start-point
<START_POINT>`; `cd WT_PATH`, install deps by running `INSTALL_HINT` through `run-gates.sh`
(with `--log-dir`, as in Step 6 — it is required on every call).
Exit-code dispatch (bad-checkout, stale dir, invalid start-point, exit-3 in-place fallback):
`R/contracts.md`. Board-mode: `S/board-sync.sh <owner/repo> <N> in_progress` in the
background (add `--option "<STATUS_MAP_IN_PROGRESS>"` if preflight reported one).

**2. Triage.** Pick `TIER` from the issue against `R/tier-matrix.md`: `standard` unless its
signals say otherwise, `--tier` pins it. `epic` → decompose first (`R/epic.md`); each child is
a full 0–12 run.

**3. Research** (tier routes it, complex+ with unknowns): `/deep-research` if installed, else an
`Explore` subagent handed an explicit question list. Either way you get back a ≤150-line summary
citing `path:line`; the raw file reads stay in its context, not yours.

**4. Design** (tier routes it). Complex+: `Workflow({scriptPath:
"S/../workflows/design-panel.js", args:{issue,title,contextFiles,constraints,openQuestions}})`
→ `design_md` (→ `tmp/task-<N>/design.md`) + rejected alternatives + open questions. Accept
only if `received_issue` matches `<N>` **and** `design_md` is non-empty **and**
`rejected_alternatives.length >= 1`. Any other outcome (including a thrown panel) → design
inline; on a `received_issue` mismatch the panel never saw its args, so design the **whole**
issue, not just the part a proposer reconstructed. `/cross-review` critiques the result.
Preference-bound questions → ledger. Standard: a mini-design in the PR body.

**4.5. Checkpoint (unconditional slot).** If the ledger has open `asked` items, ask them in
ONE batched `AskUserQuestion`. Empty ledger → no-op. The only mid-run question.

**5. Plan + implement.** Turn the design into a plan (`superpowers:writing-plans` for
complex+); TDD: failing test → implement → passing. UI/layout work is verified with
`<visual_cmd>` or a browser test, never eyeballing.

**6. Gates.** Config commands are authoritative; each one preflight reported empty you work
out **in the worktree**, the tree the gates run in, from its manifests and CI workflow — as a
**literal** (`npm test`, `bash tests/run-tests.sh`), never a string assembled from repository
filenames, because `run-gates.sh` evaluates it through `bash -c`. Ambiguous ⇒ Step 4.5 asks.
`S/run-gates.sh --log-dir "tmp/task-<N>/logs" --gate typecheck='<typecheck_cmd>' --gate
test='<test_cmd>'` (+ `--gate visual=…` for UI). Never judge a gate from an ad-hoc command; only
this one surfaces the real failure instead of a summarised "no tests collected". An empty gate
command degrades (exit 4), never a false green. Red ⇒ STOP and fix.

**7. Review loop.** Default to the inline fallback: independent adversarial review
subagents critique the diff at the tier's level, ≤ tier's max passes. `/code-review
<level> --fix` is preferred only when it's actually callable — most copies ship
`disable-model-invocation`, which blocks a skill run from invoking it at all (`R/companions.md`).
Run them in the **foreground**, never while gates run — a reviewer editing the shared worktree
mid-gate produces a phantom red. **Security overlay:** `S/sensitive-paths.sh --base "<BASE>"` —
it collects committed, uncommitted and untracked work itself; `SENSITIVE=true` → +1
`/security-review`. Track `confirmed_bugs_this_pass`/`gate_fail_streak` in metrics;
**escalate a level** on 2+ confirmed bugs/pass or a gate failing twice; re-run gates
after each fix.

**8. Re-gates + pin config + ponytail.** Re-run `run-gates.sh` (all green). If commands you
worked out yourself passed and config lacks them, `S/pin-config.sh --config "<CONFIG_PATH>" --test '…' …` — the path
preflight reported it READ, so a pin lands in the file that is actually in force, never in a
second one that shadows it. Note it in the report. **Final gate, when ponytail is installed:**
`/ponytail:ponytail ultra`, then `/ponytail:ponytail-review` over `git diff <BASE>...HEAD`. Apply
the cuts you agree with and re-run gates; answer the rest in one line each in the report.

**9. Commit + PR.** `git add <explicit paths>`, conventional subjects; `git push -u origin
<branch>`; `gh pr create` against `BASE`, `Closes #<N>`, humanized body (autonomous-decisions
section + rejected alternatives). Board-mode: `S/board-sync.sh <owner/repo> <N> in_review`.
**Stop** — merging is Step 11.

**10. Report.** Length per tier (3 lines → full). What was built and why, test status with the
green proof, the autonomous decisions, the PR link, and the `metrics` telemetry (gate runs,
review passes/level, which machinery fired). Hand back: ask when to merge, and **stop**.

## Step 11 — Merge on approval (GATE)

Return to your working tree first: `cd` into the `WT_PATH` you recorded at Step 1 (worktree
mode); in the in-place fallback stay in the main checkout on `<branch>`. Read the reply against
*this* PR and run `S/review-check.sh <branch>` — a `changes_requested`/`unresolved_threads`
result routes through change-requests, never a silent merge. **Merge only on an unambiguous
go-ahead to merge THIS PR; if the reply (or GitHub review) is anything else, do not merge.**
- **Go-ahead** ("merge it", "lgtm, ship it", "approved", "go ahead and merge") → `S/approve.sh
  <branch> --quote "<verbatim reply>"`, then `S/worktree.sh merge <N> --branch <branch>`. That
  script is the only sanctioned merge path; the hook + the script both validate the single-use
  marker before `gh pr merge` runs. Run the two as **separate** Bash calls: the hook reads the
  command line before it executes, so chaining them is always denied (no marker yet at check
  time). On a `STOP_REASON` rung follow `R/merge-ladder.md`; on exit 2, **skip cleanup**.
- **Change requests** → implement in the worktree, **re-run the tier gates** (Steps 6–7 on the
  new diff) until clean, push, re-report, wait again. Never merge unverified changes.
- **Anything else** → do **not** merge. A vague ack ("ok", "looks fine") or a question → ask for
  explicit confirmation. If they'll self-merge/abandon, offer `S/worktree.sh teardown <N>` (keeps
  the PR + remote branch; never `cleanup`, which deletes them). Approval is never inferred.

## Step 12 — Cleanup (after a successful merge)

Only after Step 11 merges. Confirm honestly: GitHub closes the issue / advances the card
**only on a merge into the default branch** — on a non-default base the issue stays open, so
say so. **`cd` your shell into the main checkout first** (a shell whose cwd is the worktree
locks it on Windows). **Smoke runs BEFORE cleanup**, which deletes the log dir it writes to:
if `smoke_cmd` is set, pull the base and run `S/run-gates.sh --log-dir "<WT_PATH>/tmp/task-<N>/logs"
--gate smoke='<smoke_cmd>'`; red → `S/worktree.sh revert <N> --branch <branch>` opens a **draft**
revert PR (never auto-reverts) — report it loudly.
Then `S/worktree.sh cleanup <N> --branch <branch>` (removes the worktree, deletes the merged
local + remote branch + marker). Add `--salvage-to "<dir>"` only when the user named somewhere
to keep a `tmp/task-<N>/` file; the design already lives in the PR body, so the default is not
to salvage. Report from its keys — `DELETED_LOCAL=false` or a `LEFTOVER_DIR` means a locked dir
remains; say so, remove it by hand once the lock clears. In-place fallback (no worktree):
switch off `<branch>`, delete it local+remote, sweep the scratchpad temp (keep committed
`docs/`, PR content, anything you were asked to keep). Details: `R/contracts.md` →
"worktree.sh". Finish with one line: what merged, what was removed, what was kept.

## Friction log

When a step genuinely fought back, append one dated one-line note to
`.claude/issue-to-pr/friction.log`; `/issue-to-pr:tune` batches it into fixes later.
Mention the log in the report only once it is over 10 lines.
