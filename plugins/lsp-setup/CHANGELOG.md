# Changelog

All notable changes to the **lsp-setup** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-04-03

### Added
- CHANGELOG.md with backfilled version history

## [1.0.0] - 2026-03-20

### Added
- `lsp-setup` skill for Claude Code LSP configuration
- Auto-detection of project languages from source files and project markers
- Automatic installation of language server binaries and Claude Code LSP plugins
- Environment-aware setup (MINGW, WSL, macOS, Linux) with gotcha handling
- State machine workflow that resumes from any point (install -> restart -> validate)
- Post-restart validation confirming LSP operations work per language
- Support for all 12 official LSP plugins (C#, Python, TypeScript/JS, Go, Rust, Java, Kotlin, Lua, PHP, Ruby, Swift, C/C++)
