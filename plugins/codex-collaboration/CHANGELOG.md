# Changelog

All notable changes to the **codex-collaboration** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.4.0] - 2026-04-14

### Added
- Context gathering guidance for non-code artifacts — reviewers now read referenced source files before reviewing design/plan/architecture specs
- Cross-reference triage table showing which reviewers found each issue at what severity
- Fallback path when `/codex:status` Skill tool fails with `disable-model-invocation`
- Stale task dismissal step in auto-retry protocol to ignore late-arriving notifications from dead tasks

### Fixed
- Flow interruption after Codex setup — setup → dispatch is now explicitly uninterruptible
- Triage → cross-validation flow runs without stopping for user acknowledgment

## [1.3.0] - 2026-04-14

### Added
- PID liveness verification within 30 seconds of Codex dispatch to catch dead processes early
- Starting-stuck detection at 2-minute threshold (down from 9+ minutes in practice)
- Fresh `/codex:setup` re-invocation before each Codex dispatch to prevent pipe-mismatch zombie tasks
- Auto-retry protocol on dead process: re-setup then re-dispatch with max 1 retry

### Changed
- Hang detection is now two-tier: PID liveness (fast) then log staleness (slow)
- Stale-log monitor re-runs `/codex:setup` before retry to establish fresh runtime

## [1.2.0] - 2026-04-08

### Added
- Cross-validation step — each model verifies the other's findings before presenting to user
- Evidence-based dispute resolution — resolve disagreements via docs/code research instead of always asking the user
- Per-artifact-type domain agents for design, plan, and architecture reviews
- REFINE verdict — agree with an issue but adjust its severity or fix
- Fast-path exits for zero findings, full agreement, and degraded mode

### Changed
- Evidence-first resolution replaces immediate user escalation as core principle

## [1.1.0] - 2026-04-04

### Added
- Liveness check after preflight to catch zombie broker processes
- Stale-log monitor for hang detection with automatic single-retry

### Changed
- Codex monitoring uses log-staleness detection instead of hard timeouts

## [1.0.2] - 2026-04-03

### Fixed
- Add `--fresh` to all `/codex:rescue` invocations to prevent thread-resume prompts during automated workflows

## [1.0.1] - 2026-03-29

### Fixed
- Minor refinements to collaboration workflows

## [1.0.0] - 2026-03-29

### Added
- `collaborative-loop` skill — sequential drive/validate/act cycles between Claude and Codex
- `cross-review` skill — parallel dual review with independent analysis, cross-validation, and triage
- Unified plugin replacing separate collaborative-loop and cross-review plugins
