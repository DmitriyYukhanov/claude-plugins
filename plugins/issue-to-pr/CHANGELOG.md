# Changelog

All notable changes to the **issue-to-pr** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
