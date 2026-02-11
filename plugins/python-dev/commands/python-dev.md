---
name: python-dev
description: Start Python development workflow with architecture, implementation, review, and testing phases
arguments:
  - name: task
    description: Feature or task to implement (optional - will prompt if not provided)
    required: false
---

# Python Development Workflow

You are orchestrating a complete Python development workflow. Follow these phases systematically.

## Phase 1: Discovery

First, understand the project and task:

1. **Check for Python project markers:**
   - `pyproject.toml`
   - `requirements.txt` or `Pipfile`
   - `setup.py` or `setup.cfg`
   - `.py` files
   - Framework config (FastAPI, Django, Flask)

2. **Read existing architecture:**
   - Check for `CLAUDE.md` or project documentation
   - Look at existing code patterns in `src/`
   - Identify framework and dependencies

3. **Clarify requirements** if task is ambiguous using AskUserQuestion

## Phase 2: Architecture

Use the `python-architect` skill knowledge to:

1. **Design module structure** - Protocols, package hierarchy
2. **Create test stubs** - pytest test cases
3. **Generate Mermaid diagrams** - Class, data flow diagrams
4. **Define contracts** - Protocols/ABCs before implementations

Present the architecture to the user for approval before implementing.

## Phase 3: Implementation

Use the `python-coder` skill knowledge to implement:

1. Follow PEP 8 and project conventions precisely
2. Implement against the test stubs created in Phase 2
3. Run tests continuously as you implement
4. Use type hints everywhere

## Phase 4: Review

Spawn the `python-reviewer` agent to perform Python-specific code review:

- Type hint coverage
- PEP 8 compliance
- Error handling patterns
- Async correctness
- Performance concerns

## Phase 5: Testing

Use the `python-testing` skill knowledge to:

1. Ensure unit tests pass
2. Ensure integration tests pass
3. Generate coverage report for critical paths if requested

## Workflow Commands

You can run individual phases:
- "architect only" - Just Phase 2
- "implement only" - Just Phase 3 (requires existing architecture)
- "review only" - Just Phase 4
- "test only" - Just Phase 5

## Usage Examples

```
/python-dev Add REST API with FastAPI
/python-dev Implement data processing pipeline
/python-dev Create CLI tool with Click
```
