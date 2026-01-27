---
name: unity-dev
description: Start Unity C# development workflow with architecture, implementation, review, and testing phases
arguments:
  - name: task
    description: Feature or task to implement (optional - will prompt if not provided)
    required: false
---

# Unity Development Workflow

You are orchestrating a complete Unity C# development workflow. Follow these phases systematically.

## Phase 1: Discovery

First, understand the project and task:

1. **Check for Unity project markers:**
   - `*.csproj` files
   - `ProjectSettings/` folder
   - `Assets/` folder
   - `*.unity` scene files

2. **Read existing architecture:**
   - Check for `CLAUDE.md` or project documentation
   - Look at existing code patterns in `Assets/Scripts/`
   - Identify assembly definitions (`.asmdef` files)

3. **Clarify requirements** if task is ambiguous using AskUserQuestion

## Phase 2: Architecture

Use the `unity-architect` skill knowledge to:

1. **Design component hierarchy** - MonoBehaviour structure, interfaces
2. **Create test stubs** - EditMode + PlayMode test cases
3. **Generate Mermaid diagrams** - Class, sequence, state machine
4. **Define contracts** - Interfaces before implementations

Present the architecture to the user for approval before implementing.

## Phase 3: Implementation

Use the `unity-coder` skill knowledge to implement:

1. Follow Unity C# coding guidelines precisely
2. Implement against the test stubs created in Phase 2
3. Run tests continuously as you implement
4. Use proper serialization attributes (`[SerializeField]`, `[field:SerializeField]`)

## Phase 4: Review

Spawn the `unity-reviewer` agent to perform Unity-specific code review:

- MonoBehaviour lifecycle issues
- Serialization problems
- Performance red flags
- Memory leaks (static events, unsubscribed handlers)
- Platform compatibility

## Phase 5: Testing

Use the `unity-testing` skill knowledge to:

1. Ensure EditMode tests pass (Editor code, static analysis)
2. Ensure PlayMode tests pass (runtime behavior, lifecycle)
3. Generate coverage report for critical paths if requested

## Workflow Commands

You can run individual phases:
- "architect only" - Just Phase 2
- "implement only" - Just Phase 3 (requires existing architecture)
- "review only" - Just Phase 4
- "test only" - Just Phase 5

## Usage Examples

```
/unity-dev Add player health system with damage and healing
/unity-dev Implement object pooling for projectiles
/unity-dev Create save/load system using ScriptableObjects
```
