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
argument-hint: "[issue-number | \"free text\"] [--tier trivial|standard|complex] [--grill]"
---

# issue-to-pr — issue → merge-ready PR pipeline

Ten steps from an issue to a merged PR: the gates block, the depth between them scales to the
tier. Use the current host's tools following `R/companions.md`; the workflow is shared across
Claude Code and Codex. Resolve `S/` to `../../scripts/` relative to this installed `SKILL.md`'s
directory, and `R/` to its `references/`. Use absolute, quoted paths in shell calls, never paths
relative to the project or a plugin environment variable. Run scripts with Bash (Git Bash on
Windows), keeping the working directory on the checkout named by the step. One todo per step.
A script prints `KEY=value` lines. Exit `2` is a stop: `STOP_REASON` on stdout, the
instruction on stderr — do what it says, report any `PUSH_ERROR`, `MERGE_ERROR` or `DIRTY_FILES`
verbatim, never work around it, and the same stop a third time is a livelock: hand back. Exit
`4` means the call itself was wrong: fix the call and re-run. A red gate exits `1`, with the
gate's own code in `GATE_<NAME>_EXIT`.

## Hard rules (never violate)

- **Merge is gated on explicit in-session approval**, runs ONLY in the main session, via
  `S/finish.sh merge` — never a bare `gh pr merge`, never `--admin`, never on the turn the PR
  opens. Force-push only with `--force-with-lease`.
- **Ask contract:** three moments, `--grill` reshapes the first (`R/judgment.md`) — (1) Step 3:
  ONE batched question if the ledger has open items, or the grill in its place, (2) the
  merge gate, (3) a hard stop. Decide everything else yourself and log it, and never ask what a
  script or the code can answer.
- Stage with **explicit paths** (`git add path1 path2`); never `git add -A`/`.`, which sweeps in
  whatever the project keeps untracked. Use the host's file-editing tools for multi-line code.
  Give PR and issue bodies to `gh` with `--body-file`, not interpolated shell strings.
- **Evidence before assertion:** no "green/passing" without the command output; look up any claim
  about the world outside this repo before building on it, ledgered either way (`R/judgment.md`).
- **Humanize** all human-facing text (report, PR body, UI strings > 1–2 words) at every tier,
  using the companion or its fallback — not code, logs or commit subjects.

## Steps

**0. Resolve.** Turn the request
into an issue. Free text with no issue number → draft one that
restates the request and nothing more, `gh issue create`, and immediately report
`Drafted issue #<N>: <title>`. Ambiguous
scope → ONE batched question BEFORE creating it, recording checkpoint use in the ledger as
`R/judgment.md` describes (`--grill` opens that same checkpoint with the scope question).
Then work out the ground the run stands on, **in
the main checkout**, never a worktree, following `R/configuration.md`: `gh auth status` (no auth →
stop), then the repo, the config, `<BASE>` and `<START_POINT>`, the gate commands, and the issue
you claim. Carry those values with you: the worktree has no copy of the config.

**1. Worktree.** Pick `TIER` against `R/judgment.md`: `standard` unless the issue's signals say
otherwise, `--tier` pins it; too large for one PR → split into issues first, each its own run.
Then, from the main checkout, with `<prefix>` either `feat` or `fix`, `git worktree add
"../<repo>-worktrees/issue-<N>" -b <prefix>/issue-<N>-<slug> <START_POINT>` — drop `-b` if the
branch already exists, and if that path is already a registered worktree verify its branch and
ownership before resuming it. Inspect `git status --short` and `git worktree list` first; never
reuse another task's tree. Permission denied → use the in-place `git switch -c <branch>
<START_POINT>` fallback only when the main checkout is clean and not owned by another task;
otherwise stop and report the conflict. `cd` into the tree: all the work
happens there, one task per tree, never two. Install deps: work the command out from that tree's
manifests as a **literal** (Step 5's rule) and run it as `S/gates.sh install "<install_cmd>"`.
Board-mode (the config named one): move the card to *in progress* with the chain in `R/board.md`.

**2. Design** (tier routes it). Unknowns first, on `complex`: a research subagent handed an
explicit question list returns a ≤150-line summary citing `path:line`. Apply Ponytail before
design when available, preserving an already active level (`R/companions.md`). Complex: three
independent proposers read the code from distinct angles; the parent judges their proposals.
Give each the issue, question and context paths. Keep the chosen design and rejected alternatives
for the PR body. Use the host's subagents within its concurrency limit; if unavailable, perform
the research and those perspectives sequentially and disclose that they were not independent.
Critique the design using `R/companions.md`; unresolved decisions go to the ledger for Step 3.
Standard: a mini-design in the PR body. **`--grill` needs a design at
any tier**, trivial included: there is nothing to grill otherwise.

**3. Checkpoint.** `R/judgment.md` says whether it is still owed: skip it once spent, wait rather
than re-ask while a question is out, and treat a user decision surfacing after it as a hard stop
rather than a second routine question. Otherwise, `--grill` starts or continues
`mattpocock-skills:grilling` over the design (absent: discuss it directly). It **replaces** the
batched question; include open `asked` items in the next round and record decisions as each round
closes, never at the end — a grill is long enough to compact. It ends on the user's confirmation.
Without the flag, those items go into ONE batched question. Either way, the only mid-run question.

**4. Build.** Turn the design into a plan (`superpowers:writing-plans` for complex); TDD: failing
test → implement → passing. UI/layout work is verified with `<visual_cmd>` or a browser test,
never eyeballing.

**5. Gates.** Config commands are authoritative; each one the config left empty you work out **in
the worktree**, the tree the gates run in, from its manifests and CI workflow — as a **literal**
(`npm test`, `bash tests/run-tests.sh`), never a string assembled from repository filenames,
because `gates.sh` runs it through `bash -c`. Unresolvable ⇒ use the checkpoint or hard stop in
`R/judgment.md`. Then
`S/gates.sh typecheck "<typecheck_cmd>" test "<test_cmd>"` (+ `visual "<visual_cmd>"` for UI):
each command is one double-quoted argument with the value substituted in. It stops at the first
red gate and prints that gate's last 40 lines; never judge a gate from an ad-hoc command, only this
one surfaces the real failure. Red ⇒ STOP and fix.

**6. Review and harden.** Review the complete diff and callers at the tier's depth and pass cap,
using `R/companions.md`. Reviewers report findings with `path:line`, impact and evidence; only
the parent applies confirmed fixes. Never let a reviewer apply its own fixes in bulk (Claude
Code's `--fix`, or any equivalent): that sweeps findings in past the per-fix re-gate and past the
count the ratchet reads. Add independent adversarial reviewers when the diff warrants it;
wait for them before editing or running gates. **Security overlay:** run
`git rev-parse --verify "<BASE>^{commit}"` first, every
time — an unresolved base still prints a plausible list — then the surface is `git diff
--name-only <BASE>` plus `git ls-files --others --exclude-standard`. Decide from the diff, not the
filename, whether it reaches auth, crypto, secrets, sessions, payments or migrations, and add one
security review if it does. `auth`, `crypto`, `secrets`, `migrations`, `.env*`, `*.sql`,
`*.pem` and `*.key` are a floor you may escalate from and never argue down. Re-run the gates after
each fix and again when the loop closes, all green. For any gate command you worked out yourself,
**print** (never write) the config frontmatter block in the report, naming
`.claude/issue-to-pr/config.md`. Then the **simplification gate**, at most two passes:
use the deletion and simplification capabilities in `R/companions.md` over `git diff <BASE>`
plus the untracked files. Apply the cuts you agree with,
re-run the gates, stop as soon as a pass finds nothing; the rest gets one line each in the report.
Then **verify the result**, `standard`+ and **last**: build the change and drive it at its own
surface, past the happy path. A FAIL is stop-and-fix and re-gate.

**7. PR and report.** `git add <explicit paths>`, conventional subjects; `git push -u origin
<branch>`. **Re-run `S/gates.sh` on the commit** — the receipt names the HEAD it ran against, so
the pre-commit run does not cover it. Then `gh pr list --head <branch> --state open --json
number,baseRefName,url`: exactly one open PR on `<BASE>` → reuse it, `gh pr edit <number>
--body-file <file>`, preserving unrelated body content and its URL; none → `gh pr create` against
`<BASE>`; anything else — a failed lookup, another base, several matches — is a stop, never
permission to open a second PR. Either way the body carries `Closes #<N>` and the humanized
design, autonomous decisions and rejected alternatives. Board-mode: move the card to
*in review* the same way. Then report, length per tier (3 lines → full): what was built and why,
test status with the green proof, the autonomous decisions, the PR link, and how much machinery
ran (gate runs, review passes and level). Ask when to merge, and **stop** — merging is the next
step.

## Step 8 — Merge on approval (GATE)

Return to your working tree first: `cd` into the worktree (in-place fallback: stay in the main
checkout on `<branch>`). Read the reply against *this* PR. **Merge only on an unambiguous
go-ahead to merge THIS PR.**
Approval covers the reported commit. If new commits arrived locally or on the PR, review their
diff and repeat Steps 5–7 as a new review cycle with the tier's pass cap, then obtain approval
for that head. A stale receipt requires this same cycle, not just another test run.
- **Go-ahead** ("merge it", "lgtm, ship it", "approved", "go ahead and merge") → `S/finish.sh
  merge <N> --branch <branch>`, the only sanctioned merge path. It refuses a head no green receipt
  covers and a review requesting changes, pushes, then squashes with `--match-head-commit`, so a
  commit landing after the diff you showed stops the merge rather than shipping unseen. Any
  refusal after that is gh's own, quoted in `MERGE_ERROR` with the next move on stderr. On exit
  2, **skip cleanup**.
- **Change requests** → build them the way Step 4 builds anything, then **re-run the tier gates**
  (Steps 5–6 on the new diff) until clean, push, re-report, wait again. Never merge unverified.
- **Anything else** → do **not** merge. A vague ack ("ok", "looks fine") or a question → ask for
  explicit confirmation. If they'll self-merge/abandon, offer `S/finish.sh cleanup <N> --branch
  <branch> --keep-branch`, which removes the worktree and touches nothing else. Approval is never
  inferred.

## Step 9 — Cleanup (after a successful merge)

Only after Step 8 merges. **`cd` into the main checkout first** (a shell whose cwd is the worktree
locks it on Windows). Smoke first if `smoke_cmd` is set: pull the base and run
`S/gates.sh smoke "<smoke_cmd>"`. Red → on a fresh branch cut from the refreshed base, `git revert`
what landed (one commit after a squash, `-m 1` after a merge commit), open a **draft** PR, never
merge it, and report it loudly. Then `S/finish.sh cleanup <N> --branch <branch>`: it refuses
unless the PR is merged and no open PR is based on the branch, removes the worktree (never forced:
anything dirty in it is a stop), deletes the local and remote branch and the run's state. Report
from its keys: a `LEFTOVER_DIR` is a locked directory to remove by hand once the lock clears,
`DELETED_LOCAL=false` means the local branch is still there, and `DELETED_REMOTE=false` is normal
when GitHub deletes head branches itself — check before calling it a failure. In-place fallback: switch off `<branch>` and delete
it local and remote yourself. **`BASE_IS_DEFAULT`** is the one thing cleanup cannot answer:
`false` means the work landed on `<MERGED_INTO>` and the issue is still open, `unknown` means the
landing branch was never confirmed, so claim neither. Finish with one line: what merged, what
went, what was kept.
