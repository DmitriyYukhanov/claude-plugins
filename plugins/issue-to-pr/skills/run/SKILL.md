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
argument-hint: "[issue-number | \"free text\"] [--tier trivial|standard|complex] [--grill]"
---

# issue-to-pr — issue → merge-ready PR pipeline

Ten steps from an issue to a merged PR: the gates block, the depth between them scales to the
tier. Scripts own the mechanics (`S/` = `${CLAUDE_PLUGIN_ROOT}/scripts/`, `R/` = `references/`),
you own judgment. One todo per step. Any non-zero script exit → `R/contracts.md` before you act:
some are stops, some are fallbacks.

## Hard rules (never violate)

- **Merge is gated on explicit in-session approval**, runs ONLY in the main session, via
  `S/worktree.sh merge` — never a bare `gh pr merge`, which no hook denies, and never on the turn
  the PR opens.
- **Ask contract:** three moments, `--grill` reshapes the first (`R/judgment.md`) — (1) Step 3:
  ONE batched `AskUserQuestion` if the ledger has open items, or the grill in its place, (2) the
  merge gate, (3) a hard stop. Decide everything else yourself and log it, and never ask what a
  script or the code can answer.
- Stage with **explicit paths** (`git add path1 path2`); never `git add -A`/`.`, which sweeps in
  whatever the project keeps untracked. Write multi-line code with the Write tool — a Bash heredoc
  breaks on an apostrophe inside the body.
- **Evidence before assertion:** no "green/passing" without the command output; look up any claim
  about the world outside this repo before building on it, ledgered either way (`R/judgment.md`).
- **Humanizer** runs on 100% of human-facing text (report, PR body, UI strings > 1–2 words)
  regardless of tier — not code, logs or commit subjects.

## Steps

**0. Resolve.** Turn the request into an issue. Free text with no issue number → draft one that
restates the request and nothing more, `gh issue create`, and make `Drafted issue #<N>: <title>`
the **first output line of the turn** — that echo is the only guard against issue spam; ambiguous
scope → ONE `AskUserQuestion` BEFORE creating it, spending the checkpoint early, unless `--grill`
is on, which keeps that question for the grill. Then work out the ground the run stands on, **in
the main checkout**, never a worktree, following `R/configuration.md`: `gh auth status` (no auth →
stop), then the repo, the config, `<BASE>` and `<START_POINT>`, the gate commands, and the issue
you claim.

**1. Worktree.** Pick `TIER` against `R/judgment.md`: `standard` unless the issue's signals say
otherwise, `--tier` pins it; too large for one PR → split into issues first, each its own run.
Then `S/worktree.sh ensure <N> --branch feat|fix/issue-<N>-<slug> --start-point <START_POINT>`
and `cd WT_PATH`, where all the work then happens: one task per tree, never two. Install deps: work the command out from that
tree's manifests as a **literal** (Step 5's rule) and run it through `run-gates.sh --log-dir
"<RUN_DIR>/logs"`, which every gate call needs. Board-mode (the config named one): move the card
to *in progress* with the chain in `R/board.md`.

**2. Design** (tier routes it). Unknowns first, on `complex`: an `Explore` subagent handed an
explicit question list returns a ≤150-line summary citing `path:line`. `/deep-research` is the
user's own command, never yours to start. **Ponytail installed → `/ponytail:ponytail full` first**
(`R/companions.md`), ledgered: design and implementation then run under the ladder. Complex: author
a `Workflow` **inline** — 3 proposers from distinct angles reading the actual code, 1 judge — with
the issue number, title and context paths written into the script text as literals, never passed
through `args`. It returns the design (→ `<RUN_DIR>/design.md`) and rejected alternatives; a throw
or an empty design → design inline. `/cross-review` critiques the result. Preference-bound
questions → ledger. Standard: a mini-design in the PR body. **`--grill` needs a design at any
tier**, trivial included and in context rather than on disk: there is nothing to grill otherwise.

**3. Checkpoint (unconditional slot).** `--grill` → `mattpocock-skills:grilling` over the design
you just built (absent: hand it over in the question itself), ledgering each decision as its round
closes, never at the end — a grill is long enough to compact. It ends on the user's confirmation
and **replaces** the batched question, so every open `asked` item goes into its first round; a
second ask after it is the fourth moment coming back. No flag → those items in ONE batched
`AskUserQuestion`. Either way, the only mid-run question.

**4. Build.** Turn the design into a plan (`superpowers:writing-plans` for complex); TDD: failing
test → implement → passing. UI/layout work is verified with `<visual_cmd>` or a browser test,
never eyeballing.

**5. Gates.** Config commands are authoritative; each one the config left empty you work out **in
the worktree**, the tree the gates run in, from its manifests and CI workflow — as a **literal**
(`npm test`, `bash tests/run-tests.sh`), never a string assembled from repository filenames,
because `run-gates.sh` evaluates it through `bash -c`. Ambiguous ⇒ Step 3 asks. `S/run-gates.sh
--log-dir "<RUN_DIR>/logs" --gate typecheck='<typecheck_cmd>' --gate test='<test_cmd>'` (+ `--gate
visual=…` for UI). A command carrying a quote of its own closes the wrapper and splits into extra
arguments the script drops with a warning, so the gate runs a truncated command and can report
green: put it in a shell variable in the same call and pass `--gate "test=$t"`. Never judge a gate
from an ad-hoc command; only this one surfaces the real failure. Red ⇒ STOP and fix.

**6. Review and harden.** Built-in `code-review` at the tier's level, ≤ tier's max passes,
**without `--fix`**: that flag sweeps findings in past the per-fix re-gate and the count the
ratchet reads. Add adversarial subagents when the diff earns a second opinion (`R/companions.md`).
Run reviewers in the **foreground**, never while gates run — one editing the tree mid-gate is a
phantom red. **Security overlay:** list the surface with `<CHANGED>` = `{ git diff --name-only
"<BASE>...HEAD"; git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u`
— committed, uncommitted and untracked. Run `git rev-parse --verify "<BASE>^{commit}"` FIRST,
every time: an unresolved base still prints a plausible list, minus every committed file. Decide
from the diff, not the filename, whether it reaches auth, crypto, secrets, sessions, payments or
migrations, and add one `/security-review` if it does. `auth`, `crypto`, `secrets`, `migrations`,
`.env*`, `*.sql`, `*.pem` and `*.key` are a floor you may escalate from and never argue down.
Re-run the gates after each fix and again when the loop closes, all green. For any gate command
you worked out yourself, **print** (never write) the config frontmatter block in the
report, naming `.claude/issue-to-pr/config.md`. Then the **simplification gate**, at most two passes: `/ponytail:ponytail-review` when
installed for what to delete, built-in `simplify` for what stays but gets simpler, over `git diff
<BASE>` (two dots, never three) plus any untracked file `<CHANGED>` names. Apply the cuts you agree
with, re-run the gates, stop as soon as a pass finds nothing; the rest gets one line each in the
report. Then built-in **`verify`**, `standard`+ and **last**: build the change and drive it at its
own surface, past the happy path. A FAIL is stop-and-fix and re-gate.

**7. PR and report.** `git add <explicit paths>`, conventional subjects; `git push -u origin
<branch>`. **Re-run `run-gates.sh` on the commit** — the receipt names the HEAD it ran against, so
the pre-commit run does not cover it. Then `gh pr create` against `BASE`, `Closes #<N>`, humanized
body (autonomous-decisions section + rejected alternatives). Board-mode: move the card to *in
review* the same way. Then report, length per tier (3 lines → full): what was built and why, test
status with the green proof, the autonomous decisions, the PR link, and how much machinery ran
(gate runs, review passes and level). Ask when to merge, and **stop** — merging is the next step.

## Step 8 — Merge on approval (GATE)

Return to your working tree first: `cd` into the `WT_PATH` you recorded at Step 1 (worktree mode);
in the in-place fallback stay in the main checkout on `<branch>`. Read the reply against *this*
PR. **Merge only on an unambiguous go-ahead to merge THIS PR.**
- **Go-ahead** ("merge it", "lgtm, ship it", "approved", "go ahead and merge") → `S/worktree.sh
  merge <N> --branch <branch>`, the only sanctioned merge path (what it refuses, and why:
  `R/contracts.md`). On any `STOP_REASON` follow `R/merge-ladder.md`; on exit 2, **skip cleanup**.
- **Change requests** → build them the way Step 4 builds anything, then **re-run the tier gates**
  (Steps 5–6 on the new diff) until clean, push, re-report, wait again. Never merge unverified.
- **Anything else** → do **not** merge. A vague ack ("ok", "looks fine") or a question → ask for
  explicit confirmation. If they'll self-merge/abandon, offer `S/worktree.sh cleanup <N> --branch
  <branch> --keep-branch`. Approval is never inferred.

## Step 9 — Cleanup (after a successful merge)

Only after Step 8 merges. **Read `BASE_IS_DEFAULT`**; on anything but `true`, do NOT clean up and
say which it is: `false` → it landed on `<MERGED_INTO>`, not the default branch, so the issue
stays open; `unknown` → the landing branch could not be confirmed, so claim neither. **`cd` into
the main checkout first** (a shell whose cwd is the worktree locks it on Windows). **Smoke runs
BEFORE cleanup**, which deletes the log dir it writes to: if `smoke_cmd` is set, pull the base and
run `S/run-gates.sh --log-dir "<RUN_DIR>/logs" --gate smoke='<smoke_cmd>'`; red → revert the squash
commit on a fresh branch cut from the refreshed base and open a **draft** PR from it. Never
auto-revert, never merge it; report loudly. Then `S/worktree.sh cleanup <N> --branch <branch>` and
report from its keys (`R/contracts.md`), which is also where the in-place fallback's hand sweep
lives. Finish with one line: what merged, what was removed, what was kept.
