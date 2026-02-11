# python-dev

A Claude Code plugin for Python development with architecture design, coding guidelines, testing patterns, and specialized review agents.

## Installation

```bash
/plugin install python-dev@DmitriyYukhanov/claude-plugins
```

## Dependencies

This plugin delegates to standard Claude Code plugins for enhanced functionality:

| Agent | Delegates To | Purpose |
|-------|--------------|---------|
| `python-reviewer` | `feature-dev:code-reviewer` | General code quality, logic, and bug detection |

**Required plugins** (install from official marketplace):

```bash
/plugin install feature-dev
```

The Python agents apply domain-specific patterns first, then delegate to general-purpose agents for comprehensive coverage.

## Features

### Command: `/python-dev`

Orchestrates a complete Python development workflow:

1. **Discovery** - Analyzes project structure and requirements
2. **Architecture** - Designs module structure, protocols, test stubs, Mermaid diagrams
3. **Implementation** - Follows PEP 8 and Python coding guidelines
4. **Review** - Python-specific code review for type safety, error handling, async
5. **Testing** - pytest patterns, fixtures, mocking, coverage

### Skills (Reference Knowledge)

- **python-architect** - Architecture patterns, protocols, Mermaid diagrams, test stub templates
- **python-coder** - PEP 8, type hints, naming conventions, async patterns
- **python-testing** - pytest patterns, fixtures, mocking strategies, coverage guidelines

### Agents (Autonomous Tasks)

- **python-reviewer** - Python-specific review, then chains to `feature-dev:code-reviewer`

## Usage

```bash
# Full development workflow
/python-dev Add REST API with FastAPI

# Individual phases
/python-dev architect only - Design a data pipeline
/python-dev review only - Review recent changes
```

## What It Checks

### Type Safety
- Missing type hints on public functions
- `Any` usage without justification
- Incorrect Optional handling

### PEP 8 Compliance
- Naming convention violations
- Import ordering
- Whitespace issues

### Error Handling
- Bare except clauses
- Missing context managers
- Error logging without context

### Async Patterns
- Blocking calls in async code
- Floating coroutines
- Missing resource cleanup

## License

MIT
