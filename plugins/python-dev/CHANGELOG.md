# Changelog

All notable changes to the **python-dev** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.1] - 2026-04-03

### Added
- CHANGELOG.md with backfilled version history

## [1.2.0] - 2026-03-25

### Added
- WSL support with shell safety fixes
- Agent tool restrictions and `allowed-tools` configuration
- Agent color theming

### Changed
- Add review guardrails to coding guidelines
- Improve coder workflow preambles

### Fixed
- Fix Task -> Agent delegation bug

## [1.0.0] - 2026-02-15

### Added
- `python-architect` skill for high-level architecture with protocols and Mermaid diagrams
- `python-coder` skill with PEP 8-aligned coding guidelines and type-hint best practices
- `python-testing` skill with pytest patterns, fixtures, mocking, and coverage
- `python-reviewer` agent for Python-specific code review
- `/python-dev` command for end-to-end workflows (discovery -> architecture -> implementation -> review -> testing)
