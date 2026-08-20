# Changelog

All notable changes to the **issue-to-pr** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.6.0] - 2026-08-20

### Changed
- `/issue-to-pr:tune` now tries the cheap answers first: delete the behaviour, ask for explicit input, clarify the wording, and only then add another script or test. The old rule preferred a mechanical stop every time, which is how the plugin came to carry more shell than prose

## [2.5.1] - 2026-08-20

### Changed
- Keep the plugin's repository-level state in `.claude/issue-to-pr/`, a directory that hides itself from git, so a teammate without the plugin installed never finds files they cannot place
- Read the config from `.claude/issue-to-pr/config.md`

### Removed
- Support for a config at the older `.claude/issue-to-pr.local.md` path. A run points at it once and leaves it alone, rather than copying it somewhere and deciding which copy wins

### Added
- Clear away approval markers once they expire, and never one whose timestamp cannot be read

## [2.4.1] - 2026-08-18

### Added
- Detect a test runner that lives inside a project, when the repository has exactly one tracked runner and none at the top
- Leave two or more runners ambiguous and report no test command, so the one you want gets pinned in the config ([#23](https://github.com/DmitriyYukhanov/claude-plugins/issues/23))

### Fixed
- Resolve every Step-0 probe against the repository, so gate detection no longer depends on the directory you start the run from
- Find the pinned config from anywhere in the repository; a run started from a subdirectory used to miss it and replace your pinned test command, base branch and board with guesses
- Report `make check` for a `check:`-only Makefile, instead of a `make typecheck` that no rule defines and that stopped the run on a red gate

## [2.3.2] - 2026-08-17

### Fixed
- The documented salvage list names the files cleanup actually copies
- A PR number now works wherever a branch name does: the merge finds the approval recorded under the branch name instead of refusing it, and cleanup deletes the branch instead of reporting success and leaving it behind
- A relative `--salvage-to` path lands in the main checkout, not inside the worktree that cleanup is about to remove
- Cleanup reports what it salvaged even when it then refuses to remove a worktree with uncommitted changes

## [2.3.0] - 2026-08-16

### Removed
- The `--json` flag on the pipeline's scripts. Nothing ever passed it; board sync still reports JSON exactly as before
- The bundled `research` sub-skill. That step now uses `/deep-research` when it is installed and a plain Explore subagent otherwise, which is what the sub-skill was configured to do anyway

### Changed
- Dead code and stale comments swept out of the scripts and the reference docs: a documented helper that was never written, a header printed twice, a note describing run-directory behaviour this version does not have, and a board-sync flag whose feature shipped elsewhere

## [2.2.1] - 2026-08-15

### Fixed
- Two shellcheck warnings that turned the release build red; no change to how the pipeline behaves

## [2.2.0] - 2026-08-15

### Added
- The security overlay reads uncommitted edits to tracked files as well as new untracked ones, so a change to an existing auth or crypto file triggers the extra review pass
- The overlay also flags Alembic, Flyway, Liquibase and `db/migrate` migration layouts
- Test-command detection covers shell harnesses such as `tests/run-tests.sh`

### Changed
- `base_branch: auto` asks the remote instead of trusting local refs, so a stale `dev` whose remote was deleted no longer becomes the branch point, and `BASE_SOURCE` reports whether the answer was confirmed or guessed
- The security overlay is one call that collects the changed files itself, rather than a shell pipeline the pipeline had to assemble by hand
- The design panel refuses to run when its inputs fail to arrive, and reports which issue it received so the caller can prove it
- Review subagents run in the foreground and never alongside the gates, which used to produce phantom failures
- Cleanup no longer invents a salvage directory on every run; it keeps a run's scratch files only when you name somewhere to put them

### Fixed
- The post-merge smoke check actually runs. It was called without the log directory the gate runner requires, and after cleanup had already removed it, so a merge that broke the base was never caught and the draft revert PR never opened
- The security overlay stops with a reason when it cannot read the diff, instead of reporting a clean scan and skipping the security review
- Installing dependencies at Step 1 no longer omits the log directory the gate runner requires
- Approvals work on macOS: the timestamp check only understood GNU `date`, so every marker was undatable and no merge could ever be approved
- An approval is spent only once the merge has actually run, and never silently when the write fails
- The merge gate's refusal explains that approval and merge must be separate calls, since chaining them could never pass
- The approval quote survives embedded quotes, backslashes and line breaks

### Security
- `worktree.sh` could be made to remove arbitrary directories, including the repository's own `.git`, by an issue argument containing `..`. Every script now rejects a non-numeric issue before building a path from it

## [2.1.0] - 2026-07-22

### Changed
- Step 7's review loop now defaults straight to adversarial review subagents instead of first attempting `/code-review`, since most copies of that command block model-invocation and can never fire mid-pipeline anyway

## [2.0.3] - 2026-07-21

### Fixed
- The merge and stage guards now ignore heredoc bodies, so a commit message that merely quotes `gh pr merge` or `git add -A` in prose no longer trips the gate it's describing

## [2.0.2] - 2026-07-13

### Changed
- Expand the plugin README to cover v2 behavior: tiers, autonomy contract, epic decomposition, the merge gate, post-merge smoke check with draft revert, and the `/issue-to-pr:tune` skill

### Fixed
- Correct install command to use the marketplace name (`@dmitriy-claude-plugins`) instead of the repo path

## [2.0.1] - 2026-07-11

### Fixed
- The merge-approval marker now resolves a PR number to its branch name, so `gh pr merge <PR#>` and `approve.sh <PR#>` key the same approval as their branch-name equivalents instead of silently missing each other
- Merge-gate denial messages now name the plugin and give the exact `approve.sh` command to run, so the model can't mistake the gate for a GitHub restriction or lose time hunting for the script

## [2.0.0] - 2026-07-07

### Added
- Epic tier — decompose a from-scratch request into dependency-ordered child issues, each shipped through its own gated pipeline, gated on one approval of the breakdown
- Start from a plain request with no issue number: the pipeline drafts the issue and proceeds, asking only when the scope is ambiguous
- Merge-failure ladder — a behind-base PR is updated, re-checked, and re-approved automatically only when the base merge leaves the PR's own diff untouched; a conflict or a failed check stops and hands back
- GitHub review ingestion — a changes-requested review or an unresolved thread routes through the change-request path instead of a silent merge
- Post-merge smoke check that opens a draft revert PR (never auto-reverts) when the merged change breaks the base

### Changed
- Major release: the pipeline now accepts free-text and epic entry points alongside a single issue number, and the merge gate gained the failure ladder and review ingestion

## [1.3.0] - 2026-07-06

### Added
- Tier scaling — the pipeline sizes research, design, review depth, and the report to the task's tier (trivial through epic), chosen deterministically from the issue's signals
- Ask contract — at most one batched question per run; every other decision is made autonomously and surfaced in the report and the PR body
- Autonomous design panel (three proposers, two adversarial critics, a judge) replaces the one-question-at-a-time brainstorming interview for complex work
- Forked research that keeps raw exploration out of context, plus a security-review overlay that triggers on sensitive paths
- Self-writing config that pins verified gate commands, and a `/issue-to-pr:tune` skill that turns a friction log into batched improvements
- A hook that denies `git add -A` / `.`, keeping staging explicit

### Changed
- SKILL trimmed to a lean ~140-line spine now that tested scripts own the mechanics; per-task state enables deterministic resume after a context compaction

## [1.2.1] - 2026-07-04

### Fixed
- Post-merge cleanup no longer stalls on Windows and leaves the merged branch behind

## [1.2.0] - 2026-07-03

### Added
- Enforced merge gate — a hook allows a merge only with a fresh, single-use, head-matching in-session approval, always denies `gh pr merge --admin` protection bypass, and asks before a force-push
- Contract-tested bash scripts run the pipeline's git/gh mechanics, with a fake-gh test harness verified under Git Bash on Windows and in CI on Linux and Windows

### Changed
- Preflight, worktree, gate, board-sync, and triage mechanics moved from prose into deterministic scripts sharing one exit-code contract — same pipeline behavior, mechanically enforced gates

## [1.1.0] - 2026-07-03

### Added
- Worktree isolation — each run works in its own `../<repo>-worktrees/issue-<N>` git worktree, so concurrent local agents on different issues never clash
- Approval-gated merge — after you approve the PR in-session, the skill squash-merges and tears down the branch, worktree, and temp artifacts

## [1.0.0] - 2026-06-26

### Added
- `issue-to-pr` skill — one gated pipeline that drives a single GitHub issue from triage to a merge-ready PR (design cross-review, tests green, code-review loop)
- Unified input handling — a bare issue or a Project board card runs the same pipeline; the PR always links the issue to auto-close on merge
- Board-status sync — advances a Projects (v2) card to in-progress when work starts and to in-review when the PR opens, degrading to link-only when the `project` token scope is absent
- Optional `.claude/issue-to-pr.local.md` configuration for board URL, base branch, and typecheck/test/visual commands, with auto-detection when unset
- Graceful companion-skill integration — uses Superpowers, deep-research, cross-review, humanizer, and code-review when installed, with inline fallbacks when they are not
