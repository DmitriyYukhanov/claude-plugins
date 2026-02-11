# typescript-dev

A Claude Code plugin for TypeScript development with architecture design, coding guidelines, testing patterns, and specialized review agents.

## Installation

```bash
/plugin install typescript-dev@DmitriyYukhanov/claude-plugins
```

## Dependencies

This plugin delegates to standard Claude Code plugins for enhanced functionality:

| Agent | Delegates To | Purpose |
|-------|--------------|---------|
| `typescript-reviewer` | `feature-dev:code-reviewer` | General code quality, logic, and bug detection |

**Required plugins** (install from official marketplace):

```bash
/plugin install feature-dev
```

The TypeScript agents apply domain-specific patterns first, then delegate to general-purpose agents for comprehensive coverage.

## Features

### Command: `/typescript-dev`

Orchestrates a complete TypeScript development workflow:

1. **Discovery** - Analyzes project structure and requirements
2. **Architecture** - Designs module structure, interfaces, test stubs, Mermaid diagrams
3. **Implementation** - Follows TypeScript coding guidelines
4. **Review** - TypeScript-specific code review for type safety, async, accessibility
5. **Testing** - Unit, integration, and E2E test patterns

### Skills (Reference Knowledge)

- **typescript-architect** - Architecture patterns, Mermaid diagrams, test stub templates
- **typescript-coder** - TypeScript naming conventions, coding guidelines, async patterns
- **typescript-testing** - Jest/Vitest patterns, mocking strategies, coverage guidelines

### Agents (Autonomous Tasks)

- **typescript-reviewer** - TypeScript-specific review, then chains to `feature-dev:code-reviewer`

## Usage

```bash
# Full development workflow
/typescript-dev Add user authentication with JWT

# Individual phases
/typescript-dev architect only - Design a REST API
/typescript-dev review only - Review recent changes
```

## What It Checks

### Type Safety
- `any` usage without justification
- Missing null/undefined handling
- Incorrect type assertions
- Generic type misuse

### Async Patterns
- Floating promises
- Missing error handling
- Race conditions

### React/Framework
- Hook dependency arrays
- Component re-render optimization
- Prop type definitions

### Accessibility
- Semantic HTML elements
- ARIA attributes
- Keyboard navigation

## License

MIT
