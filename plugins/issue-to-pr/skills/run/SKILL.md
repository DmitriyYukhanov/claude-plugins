---
name: run
description: >-
  Drive a GitHub issue — bare or tracked on a Project board — from triage to a
  merge-ready PR through a gated pipeline (design hardening, tests green,
  code-review clean), scaling the machinery to the task's tier and asking at most one
  batched question. Auto-links the issue to close on merge, advances the board card,
  then merges and cleans up once you approve the PR in-session. Triggers: "take task
  N", "work on issue #N", "build/fix X" when no issue exists yet, and —
  for the merge gate later — "merge it", "approve the PR", "ship it", "lgtm merge".
user-invocable: true
argument-hint: "[issue-number | \"free text\"] [--tier trivial|standard|complex] [--drill]"
---

# issue-to-pr — issue → merge-ready PR pipeline

Gated flow: the gates block, the depth between them scales to the tier. Scripts own the
mechanics (`S/` = `${CLAUDE_PLUGIN_ROOT}/scripts/`, `R/` = `references/`), you own judgment.
One todo per step.

## Hard rules (never violate)

- **New task = new branch in its own worktree** (`S/worktree.sh ensure`), cut from the
  resolved base. All work happens there; never two tasks in one tree.
- **Merge is gated on explicit in-session approval**, runs ONLY in the main session, via
  `S/worktree.sh merge` — never a bare `gh pr merge`, never on the turn the PR opens.
- **Ask contract:** three moments, four with `--drill` (`R/autonomy.md`) — (1) ONE batched
  `AskUserQuestion` at Step 4 (only if the ledger has open items), (2) the merge gate,
  (3) a hard stop. Decide everything else yourself and log it (see below).
- Stage with **explicit paths** (`git add path1 path2`); never `git add -A`/`.`, which
  sweeps in whatever the project keeps untracked. Conventional Commits. TDD (failing test first) for any logic. Write multi-line
  code with the Write tool — a Bash heredoc breaks on an apostrophe inside the body.
- **Humanizer** runs on 100% of human-facing text (report, PR body, UI strings > 1–2 words)
  regardless of tier — not code/logs/commit subjects. Don't claim "green/passing" without the
  command output. Don't ask what a script or the code can answer.
- **Check before you lean on it:** a claim about anything outside this repo gets looked up before you build on it, and ledgered either way (`R/autonomy.md`).

## Config, tier, ask contract

- **Config** (`.claude/issue-to-pr/config.md`, optional): you read it at Step 0 and resolve the
  base from it (`R/configuration.md`), in the main checkout — it is gitignored and absent in the
  worktree. Gate commands come from it, or from you at Step 6.
  **Built in:** `code-review` (Step 7), `simplify` (Step 8). **Companions** (if installed,
  else inline): `superpowers:*`, `/cross-review`, `humanizer`, `ponytail:*` — `R/companions.md`.
- **Tier** (`R/tier-matrix.md`): you pick it at Step 1, `standard` unless the issue argues
  otherwise; it routes research depth, design, review level/passes and report length.
- **Autonomy** (`R/autonomy.md`, read once at Step 0): the ask contract (three contact moments,
  a fourth only with `--drill`), and the ledger of judgment calls you keep in context and render
  into the report + PR body.

## Steps

**0. Resolve.** Turn the request into an issue. Free text with no issue number → draft one that
restates the request and nothing more, `gh issue create`, and make `Drafted issue #<N>: <title>`
the **first output line of the turn** — that echo is the only guard against issue spam; ambiguous
scope → ONE `AskUserQuestion` BEFORE creating it (the run's single question, moved earlier, not a
fourth). Then work out the ground the run stands on, **in the main checkout**, never a worktree,
following `R/configuration.md`: `gh auth status` (no auth → stop), `gh repo view`, the config file,
`<BASE>` and `<START_POINT>`, the gate commands the config names, `gh issue view`, and claim the
issue. **Report every warning that page tells you to raise** — an unresolved base surfaces there
and nowhere else. An issue already assigned to someone else is a **hard stop**: ask first.
`<RUN_DIR>` is `.claude/issue-to-pr/runs/task-<N>/` under the main checkout.

**1. Triage + worktree.** Pick `TIER` against `R/tier-matrix.md`: `standard` unless the issue's
signals say otherwise, `--tier` pins it; too large for one PR → split into issues first, each its
own run. Then `S/worktree.sh ensure <N> --branch feat|fix/issue-<N>-<slug> --start-point
<START_POINT>`; `cd WT_PATH`, then install deps: work the command out from that tree's manifests
as a **literal** (Step 6's rule) and run it through `run-gates.sh` (`--log-dir` on every call).
Exit-code dispatch (bad-checkout, stale dir, invalid start-point, exit-3 in-place fallback):
`R/contracts.md`. Board-mode (the config names one): move the card to *in progress* with the
chain in `R/board.md`; a board failure is one reported line, never a stop.

**2. Research** (tier routes it, complex+ with unknowns): an `Explore` subagent handed an explicit
question list. You get back a ≤150-line summary citing `path:line`; the raw file reads stay in its
context, not yours. `/deep-research` is the user's own command, never yours to start.

**3. Design** (tier routes it). **Ponytail installed → `/ponytail:ponytail full` first**, ledgered:
design and implementation then run under the ladder. Complex: author a `Workflow` **inline**
— 3 proposers from distinct angles reading the actual code, 1 judge — with the issue
number, title and context paths written into the script text as literals, never
passed through `args`. Returns the design (→ `<RUN_DIR>/design.md`) + rejected alternatives; a
throw or an empty design → design inline. `/cross-review` critiques the result. Preference-bound
questions → ledger. Standard: a mini-design in the PR body. **`--drill` → write the design to
`<RUN_DIR>/design.md` whatever the tier**, including trivial: there is nothing to drill otherwise.

**4. Checkpoint (unconditional slot).** `--drill` → hand `<RUN_DIR>/design.md` to `/drill:me`
**first** (no plugin: hand the file over to read), appending each objection to the ledger as it
is raised, never at the end — a drill is long enough to compact
(`R/autonomy.md`). Then ask any open `asked` items in ONE batched `AskUserQuestion`; a `--drill`
run asks even on an empty ledger, or the design goes unanswered. The only mid-run question.

**5. Plan + implement.** Turn the design into a plan (`superpowers:writing-plans` for
complex+); TDD: failing test → implement → passing. UI/layout work is verified with
`<visual_cmd>` or a browser test, never eyeballing.

**6. Gates.** Config commands are authoritative; each one the config left empty you work
out **in the worktree**, the tree the gates run in, from its manifests and CI workflow — as a
**literal** (`npm test`, `bash tests/run-tests.sh`), never a string assembled from repository
filenames, because `run-gates.sh` evaluates it through `bash -c`. Ambiguous ⇒ Step 4 asks.
`S/run-gates.sh --log-dir "<RUN_DIR>/logs" --gate typecheck='<typecheck_cmd>' --gate
test='<test_cmd>'` (+ `--gate visual=…` for UI). A command carrying a quote of its own closes that
wrapper: put it in a shell variable in the same call and pass `--gate "test=$t"`, so the value
reaches the script as one argument. Never judge a gate from an ad-hoc command: only this one
surfaces the real failure. An empty gate command degrades (exit 4), never a false green.
Red ⇒ STOP and fix.

**7. Review loop.** Claude Code's built-in `code-review` skill at the tier's level, ≤ tier's max
passes, and **without `--fix`** — that flag applies findings in one sweep, past the per-fix re-gate
and the bug count the ratchet reads. Add adversarial subagents when the diff earns a second
opinion (`R/companions.md`). Run reviewers in the **foreground**, never while gates run — one
editing the shared worktree mid-gate produces a phantom red.
**Security overlay:** list the surface with `<CHANGED>` = `{ git diff --name-only
"<BASE>...HEAD"; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u`
— committed, uncommitted and untracked. Run `git rev-parse --verify "<BASE>^{commit}"` FIRST,
every time: an unresolved base still prints a plausible list, minus every committed file. Decide
from the diff whether it reaches auth, crypto, secrets, sessions, payments or migrations, add one
`/security-review` if it does — judging the code, not the filename. A floor you may escalate from
and never argue down: anything under `auth`, `crypto`, `secrets` or `migrations`, plus `.env*`,
`*.sql`, `*.pem`, `*.key`.
**Escalate a level** on 2+ confirmed bugs in a pass or a gate failing twice; re-run gates
after each fix.

**8. Re-gates + simplification gate.** Re-run `run-gates.sh` (all green). For any gate command you
worked out yourself, **print** (never write) the `<CONFIG_PATH>` frontmatter block in the report.
Then the **simplification gate**, at most two passes: `/ponytail:ponytail-review` (when installed)
for what to delete, built-in `simplify` for what stays but gets simpler, over `git diff <BASE>` (two dots, never
three) plus any untracked file `<CHANGED>` names. Apply the cuts you
agree with, re-run gates, stop as soon as a pass finds nothing; the rest gets one line each in
the report. Lenses and fallbacks: `R/companions.md`.

**9. Commit + PR + report.** `git add <explicit paths>`, conventional subjects; `git push -u
origin <branch>`. **Re-run `run-gates.sh` on the commit** — the receipt names the HEAD it ran
against, so the pre-commit run does not cover it. Then `gh pr create` against `BASE`,
`Closes #<N>`, humanized body (autonomous-decisions section + rejected alternatives).
Board-mode: move the card to *in review* the same way. Then report, length per tier (3 lines →
full): what was built and why, test status with the green proof, the autonomous decisions, the PR
link, and how much machinery ran (gate runs, review passes and level). Ask when to merge, and
**stop** — merging is the next step.

## Step 10 — Merge on approval (GATE)

Return to your working tree first: `cd` into the `WT_PATH` you recorded at Step 1 (worktree
mode); in the in-place fallback stay in the main checkout on `<branch>`. Read the reply against
*this* PR. A `review-blocked` / `review-unreadable` stop is a real answer, not a hiccup: route it
through change-requests. **Merge only on an unambiguous
go-ahead to merge THIS PR; if the reply (or GitHub review) is anything else, do not merge.**
- **Go-ahead** ("merge it", "lgtm, ship it", "approved", "go ahead and merge") → `S/worktree.sh
  merge <N> --branch <branch>`, the only sanctioned merge path (what it refuses, and why:
  `R/contracts.md`). On a
  `STOP_REASON` rung follow `R/merge-ladder.md`; on exit 2, **skip cleanup**.
- **Change requests** → implement in the worktree, **re-run the tier gates** (Steps 6–7 on the
  new diff) until clean, push, re-report, wait again. Never merge unverified changes.
- **Anything else** → do **not** merge. A vague ack ("ok", "looks fine") or a question → ask for
  explicit confirmation. If they'll self-merge/abandon, offer `S/worktree.sh cleanup <N>
  --branch <branch> --keep-branch` (removes the tree, keeps the PR + branch). Approval is
  never inferred.

## Step 11 — Cleanup (after a successful merge)

Only after Step 10 merges. **Read `BASE_IS_DEFAULT`**; on anything but `true`, do NOT clean up
and say which it is: `false` → it landed on `<MERGED_INTO>`, not the default branch, so the issue
stays open; `unknown` → the landing branch could not be confirmed, so claim neither. **`cd` into the main checkout first** (a shell whose cwd is the worktree
locks it on Windows). **Smoke runs BEFORE cleanup**, which deletes the log dir it writes to:
if `smoke_cmd` is set, pull the base and run `S/run-gates.sh --log-dir "<RUN_DIR>/logs"
--gate smoke='<smoke_cmd>'`; red → revert the squash commit on a fresh branch cut from the
refreshed base and open a **draft** PR from it. Never auto-revert, never merge it; report loudly.
Then `S/worktree.sh cleanup <N> --branch <branch>` (removes the worktree, deletes the merged
local + remote branch, prunes the receipt and run dir). It refuses a branch that is the base of
an open PR. Report from its keys — `DELETED_LOCAL=false` or a `LEFTOVER_DIR` means a locked dir
remains; say so, remove it by hand once the lock clears. In-place fallback (no worktree):
switch off `<branch>`, delete it local+remote, sweep the scratchpad temp (keep committed
`docs/`, PR content, anything you were asked to keep). Details: `R/contracts.md` →
"worktree.sh". Finish with one line: what merged, what was removed, what was kept.

## Friction log

When a step genuinely fought back, append one dated one-line note to
`.claude/issue-to-pr/friction.log`. Mention it in the report only once it is over 10 lines;
it is the maintainer's list, not the run's.
