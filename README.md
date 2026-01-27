# unity-dev

A Claude Code plugin for Unity C# development with architecture design, coding guidelines, testing patterns, and specialized review agents.

## Installation

```bash
/plugin install unity-dev@DmitriyYukhanov/claude-plugins
```

## Features

### Command: `/unity-dev`

Orchestrates a complete Unity development workflow:

1. **Discovery** - Analyzes project structure and requirements
2. **Architecture** - Designs component hierarchies, interfaces, test stubs, Mermaid diagrams
3. **Implementation** - Follows Unity C# coding guidelines
4. **Review** - Unity-specific code review for performance, lifecycle, serialization issues
5. **Testing** - EditMode and PlayMode test patterns

### Skills (Reference Knowledge)

- **unity-architect** - Architecture patterns, Mermaid diagrams, test stub templates
- **unity-coder** - C# naming conventions, member ordering, Unity-specific guidelines
- **unity-testing** - EditMode/PlayMode patterns, performance testing, code coverage

### Agents (Autonomous Tasks)

- **unity-reviewer** - Parallel code reviewer for Unity-specific issues
- **unity-simplifier** - Code simplification following Unity patterns

## Usage

```bash
# Full development workflow
/unity-dev Add player health system with damage and healing

# Individual phases
/unity-dev architect only - Design a save system
/unity-dev review only - Review recent changes
```

## What It Checks

### Performance
- Uncached `GetComponent` in Update loops
- Allocations in hot paths (LINQ, string concatenation)
- Missing object pooling

### Lifecycle
- Proper Awake/Start/OnEnable/OnDisable/OnDestroy usage
- Event subscription/unsubscription symmetry
- Static state cleanup with `[RuntimeInitializeOnLoadMethod]`

### Serialization
- Correct use of `[SerializeField]` and `[field:SerializeField]`
- Missing `[System.Serializable]` on nested classes

### Platform
- IL2CPP compatibility (no runtime reflection)
- Platform-specific `#if` directives

## License

MIT
