# Changelog

All notable changes to the **codex-collaboration** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-04-04

### Added
- Liveness check after preflight — verify broker can complete work, not just accept connections
- Stale-log monitor for hang detection — check log freshness every 2 minutes instead of rapid polling
- Automatic single-retry on stall with clear infrastructure failure reporting
- Guidance against rapid status polling (prevents 50+ wasted bash commands)

### Changed
- Runtime Failure Policy now covers infinite hangs (zombie broker), not just errors and empty output
- Codex monitoring uses log-staleness detection instead of hard timeouts to avoid killing legitimate long tasks

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
