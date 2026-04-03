# Changelog

All notable changes to the **typescript-dev** plugin will be documented in this file.

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
- `typescript-architect` skill for architecture design with modules, interfaces, and Mermaid diagrams
- `typescript-coder` skill with TypeScript coding guidelines, async patterns, and framework-aware checks
- `typescript-testing` skill with testing patterns for unit, integration, and E2E tests (Jest/Vitest)
- `typescript-reviewer` agent for TypeScript-specific code review
- `/typescript-dev` command for full-stack TypeScript workflows
