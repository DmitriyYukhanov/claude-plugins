# Worktree isolation, merge, and cleanup

Mechanics for running each task in its own git worktree, merging the PR after the user
approves it in-session, and cleaning up afterward. All commands are one line so they
copy-paste into PowerShell and bash alike; paths use forward slashes. (Numbered headers below
are **sections of this file**; the pipeline's numbered "Step N" live in `SKILL.md`.)

Throughout: `<N>` is the issue number, `<branch>` the working branch
(`feat/issue-<N>-<slug>` or `fix/issue-<N>-<slug>` — the issue number is baked in so the branch
shares the worktree path's key and can't collide across issues), `<base>` the resolved
integration base, `<repo>` the repo directory's basename, `<original-root>` the main repo
checkout you started in, and `<wt>` the worktree at `../<repo>-worktrees/issue-<N>` (record its
absolute path — you `cd` in and out of it across turns).

**Resolve config and base in `<original-root>` (the main checkout), before entering the
worktree.** The per-project `.claude/issue-to-pr.local.md` is gitignored, so it is **not** present
in the worktree — re-reading config from inside the worktree would silently lose the pinned
`base_branch` and test/typecheck/visual commands and fall back to auto-detect. Resolve them once
here and carry the resolved values.

## 1. Create or resume the worktree (SKILL Step 1)

**Record `<original-root>` first**, while still in the main checkout:

```bash
git rev-parse --show-toplevel
```

Note it in your progress file. (If it is ever lost, section 3 shows how to recover it — do
**not** re-run this from inside the worktree, where it returns the worktree's path.) Run every
`git worktree` command below **from `<original-root>`** so the relative path resolves correctly.

**Fetch, then resolve the base start-point.** Cut the branch from the **up-to-date remote base**,
not a possibly-stale local ref, so the branch and the PR target share the same commits:

```bash
git fetch origin
```

Resolve `<base>` from config `base_branch`. For `auto`, use `dev` if a `dev` branch exists either
locally or on the remote — check both (a non-empty line from either means it exists), else `main`:

```bash
git branch --list dev
git branch -r --list origin/dev
```

(Two separate commands, not chained — `||` is a parser error in PowerShell.) Then pick the
**`<start-point>`** to cut from: `origin/<base>` when that remote-tracking ref exists (the
up-to-date remote base), otherwise the local `<base>` branch. Everywhere below, `<start-point>` is
that resolved ref.

**Resume check (before creating anything):**

```bash
git worktree list --porcelain
```

- An entry for `.../issue-<N>` is present:
  - **Directory missing** (registered but deleted on disk) → `git worktree prune`, then create fresh
    (below).
  - **Checkout state first:** if the entry is `detached` or sits on `<base>` rather than a
    `feat/`/`fix/` branch (no `branch refs/heads/<name>` line, or it points at `<base>`), do
    **not** commit or resume — stop and report so the user decides.
  - Otherwise read that entry's authoritative branch from its `branch refs/heads/<name>` line —
    use **that** name for everything here, not one re-derived from the (possibly-edited) title.
    Confirm the work isn't already done: `gh pr list --head <that-branch> --state all` and
    `gh issue view <N> --json state,stateReason`. If the PR is **already merged**, the work is done
    → run the **section-3** post-merge cleanup (remove the worktree, delete the now-merged local +
    remote branch). If the issue is closed/abandoned with **no** merged PR → report it and offer
    the **section-3b** teardown (keeps any open PR). Otherwise `cd` into the path, re-verify
    dependencies are installed (a crash between create and setup, or a moved clone, leaves them
    missing) and re-install if needed, then continue — the Step 2.5 progress + design files inside
    the worktree are restored.
- The path exists on disk but is **absent** from `git worktree list` → do not overwrite. Stop and
  ask (a leftover from a crashed run, or an unrelated directory).

**Create (when no worktree exists yet), from `<original-root>`:**

```bash
git worktree add "../<repo>-worktrees/issue-<N>" -b "<branch>" "<start-point>"
```

Then `cd "../<repo>-worktrees/issue-<N>"`.

**Install dependencies / project setup.** A worktree holds only tracked files — gitignored deps
(`node_modules`, `.venv`, `target`, build caches) are **not** copied, and it's a sibling dir so
upward module resolution can't reach the main checkout's. Before the Step 6 gates can pass,
bootstrap it the way a fresh clone is (`npm ci`/`npm install`, `pip install -r` / `poetry install`,
`cargo build`, `go mod download`) — match the project's documented setup.

**Create-failure handling.** Read the error text — three distinct causes, never conflated:

- **`already exists`** (path or branch) — a concurrent run, or a leftover from a crashed run or a
  section-3b teardown that kept the branch. **Never** a sandbox problem; **never** work in place.
  Re-run `git worktree list --porcelain`: a worktree now at `.../issue-<N>` → resume case above; no
  worktree but the **branch** `<branch>` already exists (e.g. kept by 3b, PR still open) →
  re-attach a worktree to that existing branch, `git worktree add "../<repo>-worktrees/issue-<N>"
  "<branch>"` (no `-b`), then continue; only a stale dir with no branch → stop and ask.
- **`invalid reference` / unknown start-point** — re-resolve `<start-point>` (`git fetch`, then
  `origin/<base>` or the local `<base>`) and retry; if the base genuinely doesn't exist, stop and
  ask.
- **Permission / sandbox denial** — and only this — triggers the **in-place fallback**: tell the
  user the sandbox blocked worktree creation and work **in place** in `<original-root>`. Cut the
  branch there (`git switch -c "<branch>" "<start-point>"`); its deps are already present. Sections
  2 and 3 then use their in-place variants.

Running the pipeline in `<original-root>` because of an `already exists`/`invalid reference` error
would break isolation and can clobber a concurrent run's tree — never do it.

## 2. Merge on approval (SKILL Step 11)

Runs only after the user approves *this* PR in-session.

**Get into the right tree.** A later turn may have reset your CWD.
- **Worktree mode:** `cd "<wt>"` — all Step 11 work happens there.
- **In-place mode** (sandbox fallback, no worktree): you are already in `<original-root>` on
  `<branch>`; do **not** `cd` into `<wt>` (it doesn't exist).

**Precondition — every local commit is on the remote,** and confirm the push actually landed
(don't merge a stale remote head). Just push — idempotent, no upstream math (avoid `@{upstream}`,
a hard parse error in PowerShell):

```bash
git push
```

`Everything up-to-date` or a successful push → proceed. If the push is **rejected** (non-fast-forward,
auth) → **stop, do not merge**; resolve the push first, or the change-request commit would be
excluded from the squash.

**Merge — GitHub side only.** Target the PR by its **head branch**, never the issue number (`<N>`
is the *issue* number; issues and PRs share one sequence, so `<N>` is never a valid PR number). Do
**not** pass `--delete-branch` (the branch is still checked out; deletion is section 3):

```bash
gh pr merge <branch> --squash
```

If the repo disallows squash (`Squash merging is not allowed…`), use its allowed method
(`--merge` or `--rebase`) instead and note it — the section-3 `git branch -D` still applies.

**Failure handling** — read the error text:
- **Pending required checks** (running, not failed): wait once, retry the single command once.
- **Merge conflict, branch protection, failed checks, or a second failure:** stop, print the exact
  `gh` error, ask how to proceed. Leave the worktree and branch intact — no cleanup runs.

**After a successful merge, confirm the outcome.** GitHub's `Closes #<N>` auto-closes the issue
(and moves the board card to Done) **only when the PR merged into the repo's default branch**. If
`<base>` is not the default (e.g. a `dev` integration branch), the issue stays open on purpose —
it closes later when `dev` reaches the default branch. Check and report honestly:

```bash
gh issue view <N> --json state,stateReason
```

Issue `CLOSED` → done. Issue still `OPEN` because `<base>` isn't the default → say so in the
report (merged to `<base>`; the issue/card will close when `<base>` reaches the default branch);
do **not** claim the issue is closed, and do not force it closed unless the user asks.

Never force-push, never bypass branch protection, never merge on the same turn the PR opened.

## 3. Post-merge cleanup (SKILL Step 12)

Runs only after a **successful** merge.

**Recover `<original-root>` if lost** — the **first** `worktree` line of `git worktree list
--porcelain` (do **not** use `git rev-parse --show-toplevel` from inside the worktree — it returns
the worktree path):

```bash
git worktree list --porcelain
```

**Salvage the design doc first.** `git worktree remove` silently deletes gitignored files, so a
`tmp/task-<N>/design.md` (when the project does **not** commit design docs) would vanish without
tripping the dirty-tree guard below. Before removing anything, if such a design doc has lasting
value, surface its content in the final report (or copy it under `<original-root>` outside the
worktree).

Then, in order (worktree mode):

```bash
cd "<original-root>"
git worktree remove "../<repo>-worktrees/issue-<N>"
git branch -D "<branch>"
git push origin --delete "<branch>"
```

- Removing the worktree first frees `<branch>`, so `git branch -D` succeeds. `-D` is safe: the
  section-2 precondition confirmed every local commit is in the merged PR.
- `git push origin --delete` removes the remote branch. If GitHub already auto-deleted the head,
  this prints `remote ref does not exist` — harmless, ignore it. (This deletes the PR's head, which
  is fine **only because the PR is already merged** — never run it on an unmerged PR; see 3b.)
- If `git worktree remove` refuses, the worktree is **dirty** — untracked files **or** uncommitted
  tracked modifications. Inspect explicitly (you already `cd`'d to `<original-root>`):
  ```bash
  git -C "../<repo>-worktrees/issue-<N>" status --porcelain
  ```
  - **Only untracked / disposable** (`??`) → salvage the keep-list, then
    `git worktree remove --force "../<repo>-worktrees/issue-<N>"`.
  - **Any modified/staged tracked file** (` M`, `M `, `A `, …) → **STOP.** That edit isn't in the
    merged PR; `--force` would destroy it. Show the diff and ask before removing.

**In-place (sandbox-fallback) variant** — no worktree to remove; `<branch>` is checked out in
`<original-root>`, so switch off it first:

```bash
cd "<original-root>"
git switch "<base>"
git branch -D "<branch>"
git push origin --delete "<branch>"
```

**Remove temp artifacts outside the worktree.** Worktree mode: the Step 2.5 `tmp/task-<N>/` dir is
inside the worktree and already gone with it (design doc salvaged above). In-place mode: the Step
2.5 files are in the session scratchpad — sweep them there.

**Keep-list — never remove:** committed `docs/` (or wherever design docs are committed), anything
already in the PR, anything the user asked to keep.

**Confirm.** One line: what was merged, what was removed (worktree path, local + remote branch,
temp), and anything kept.

## 3b. Teardown without merging (user self-merges or abandons)

When the user will merge the PR themselves later, or abandons the task, and asks to clear the local
workspace — clear the **local** workspace only and **keep the PR intact**. Do **not** delete the
remote branch (that would close the open PR).

**Salvage any lasting design doc first** (as in section 3 — `git worktree remove` silently deletes
gitignored files, so the salvage must precede the removal). Then:

- **Worktree mode:**
  ```bash
  cd "<original-root>"
  git worktree remove "../<repo>-worktrees/issue-<N>"
  ```
  (Dirty-tree handling as in section 3.)
- **In-place mode** (sandbox fallback, no worktree): there is nothing to remove — leave
  `<original-root>` on `<branch>` as-is.

Either way, sweep the outside-worktree temp artifacts (the scratchpad in in-place mode), and leave
`<branch>` and its remote head in place so the PR stays open and mergeable. Report that the PR and
branch were kept and only the local workspace was cleared.

A later re-invocation of the same issue finds no worktree but the kept `<branch>` still exists, so
the create path's `-b <branch>` would report "already exists" — handled by the create-failure
case above, which re-attaches a worktree to the existing branch (`git worktree add
"../<repo>-worktrees/issue-<N>" "<branch>"`, no `-b`).

## 4. What "Done" means (board-mode)

`Done` is left to GitHub's built-in project automation, which moves the card when the issue
auto-closes on merge — and that closing fires **only on a merge into the default branch** (see the
outcome check in section 2). For a non-default `<base>`, the card advances to Done later, when
`<base>` reaches the default branch; the skill does not set `Done` manually (that would race the
platform).
