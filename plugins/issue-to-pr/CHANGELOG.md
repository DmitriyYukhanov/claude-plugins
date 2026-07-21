# Changelog

All notable changes to the **issue-to-pr** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
