# lsp-setup

Set up Language Server Protocol support in Claude Code for the current project: go-to-definition, find-references, hover, symbols, diagnostics, and call hierarchy at ~50ms instead of 30-60s of grep-based navigation.

## Installation

```bash
/plugin install lsp-setup@dmitriy-claude-plugins
```

## Features

### Skill: `lsp-setup`

Activates when you ask to "set up LSP", "configure language server", "fix LSP", and similar. The skill:

- Detects project languages from source files and project markers
- Detects the environment (MINGW, WSL, macOS, Linux) and applies known gotchas
- Installs language server binaries and the matching official Claude Code LSP plugins
- Runs as a state machine: on re-invocation it detects the current state and resumes (install, restart, validate)
- Validates after restart that LSP operations actually work per language

Supports the 12 languages with official Claude Code LSP plugins: C#, Python, TypeScript/JS, Go, Rust, Java, Kotlin, Lua, PHP, Ruby, Swift, and C/C++.

## Usage

```text
Set up LSP for this project
```

After plugin installation Claude Code needs a restart before language servers pick up; the skill tells you when and validates afterwards.

## License

MIT
