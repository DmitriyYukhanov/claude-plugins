---
name: typescript-dev
description: Start TypeScript development workflow with architecture, implementation, review, and testing phases
arguments:
  - name: task
    description: Feature or task to implement (optional - will prompt if not provided)
    required: false
---

# TypeScript Development Workflow

You are orchestrating a complete TypeScript development workflow. Follow these phases systematically.

## Phase 1: Discovery

First, understand the project and task:

1. **Check for TypeScript project markers:**
   - `tsconfig.json`
   - `package.json`
   - `.ts`, `.tsx` files
   - Framework config files (next.config.js, vite.config.ts, etc.)

2. **Read existing architecture:**
   - Check for `CLAUDE.md` or project documentation
   - Look at existing code patterns in `src/`
   - Identify framework (React, Vue, Angular, Node.js, etc.)

3. **Clarify requirements** if task is ambiguous using AskUserQuestion

## Phase 2: Architecture

Use the `typescript-architect` skill knowledge to:

1. **Design module structure** - Interfaces, types, module boundaries
2. **Create test stubs** - Jest/Vitest test cases
3. **Generate Mermaid diagrams** - Class, data flow diagrams
4. **Define contracts** - Interfaces before implementations

Present the architecture to the user for approval before implementing.

## Phase 3: Implementation

Use the `typescript-coder` skill knowledge to implement:

1. Follow TypeScript coding guidelines precisely
2. Implement against the test stubs created in Phase 2
3. Run tests continuously as you implement
4. Use strict types (avoid `any`)

## Phase 4: Review

Spawn the `typescript-reviewer` agent to perform TypeScript-specific code review:

- Type safety issues
- Async pattern problems
- React/Framework patterns (if applicable)
- Performance red flags
- Accessibility issues

## Phase 5: Testing

Use the `typescript-testing` skill knowledge to:

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
/typescript-dev Add user authentication with JWT
/typescript-dev Implement REST API with Express
/typescript-dev Create React component library
```
