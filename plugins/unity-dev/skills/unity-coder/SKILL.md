---
name: unity-coder
description: Use when implementing Unity C# code to follow proper coding guidelines, naming conventions, member ordering, and Unity-specific patterns
---

# Unity Coder Skill

You are a senior Unity C# developer. Follow these guidelines precisely.

## Core Principles

- Write clear, concise C# code following Unity best practices and Microsoft naming conventions
- Prioritize performance, scalability, and maintainability
- Use Unity's component-based architecture for modularity
- Always follow SOLID, GRASP, YAGNI, DRY, KISS principles
- Implement robust error handling and debugging practices
- **Prefer .editorconfig with higher priority when considering style**

## Microsoft C# Naming Conventions

- **Classes, Interfaces, Structs, Delegates**: PascalCase
- **Interfaces**: Start with `I` (e.g., `IWorkerQueue`)
- **Private/Internal Fields**: camelCase with `_` prefix (e.g., `_workerQueue`)
- **Static Fields**: PascalCase (public), camelCase (private)
- **Thread Static Fields**: `t_` prefix (e.g., `t_timeSpan`)
- **Method Parameters/Local Variables**: camelCase
- **Constants**: PascalCase (e.g., `MaxItems`), no SCREAMING_UPPERCASE
- **Type Parameters**: `T` prefix (e.g., `TSession`)
- **Namespaces**: PascalCase

## Member Sorting Guidelines

Sort by static/non-static first, then by member type, then by visibility:

1. **Static/Non-Static**: Static members first, then instance members
2. **Member Type**: Fields -> Delegates -> Events -> Properties -> Constructors -> Methods -> Nested Types
3. **Fields Order**: Constants -> Static Readonly -> Static -> Readonly -> Instance
4. **Visibility**: Public -> Protected -> Internal -> Protected Internal -> Private
5. **Methods Order**: All static methods after all members, before instance methods
6. **Unity lifecycle methods** (Awake, Start, Update, etc.) at top of instance methods section
7. **Alphabetical ordering** within each group

**Important**: Do NOT reorder members when refactoring existing code unless explicitly requested.

## Unity-Specific Guidelines

### Components & Inspector
- **Components**: MonoBehaviour for GameObjects, ScriptableObjects for data containers
- **Properties vs Fields**: Prefer auto-properties over public fields
- **Inspector**: Use `[SerializeField]` for private fields, `[field:SerializeField]` for auto-properties
- **Editor Code**: Wrap with `#if UNITY_EDITOR`
- **References**: Prefer direct references over `GameObject.Find()` or `Transform.Find()`
- **TryGetComponent**: Use to avoid null reference exceptions

### Code Organization
- **Namespaces**: Prevent nested namespaces
- **Regions**: Use only when necessary (interface implementations, auto-generated code)
- **File Structure**: One type per file (except generic interface base classes)
- **Imports**: Ensure all referenced types have proper `using` directives

### Type Usage
- **Type Declaration**: Prefer `var` over explicit types
- **Type Names**: Use `nameof()` instead of hardcoded strings
- **Nullable Types**: Avoid `#nullable enable` - **never suppress warnings with `!`**
- **Null Checks**: Use nullable operators when possible (but not `?.` on assignment left-hand side)

### Code Style
- **Attributes**: Can be same line or new line; same line preferred when multiple fields share attribute
- **Delegates**: Prefer explicit delegates over generic Actions for events with arguments
- **Unused Parameters**: Use discard pattern `_ = parameter;` for intentionally unused params
- **Switch Statements**: Always include `default` case; prefer switch expressions (C# 8+)
- **Loop Constructs**: Prefer `foreach` over `for` for simple iterations

### Empty Lines & Formatting
- Single empty line between methods/properties/types; **no consecutive empty lines**
- **Always** empty line between `using` statements and `namespace`
- **Never** extra empty lines within code blocks unless separating logical sections
- **Never change line endings** (CRLF vs LF) when editing existing files

### Critical Rules
- **Reflection**: **Never use in runtime code** (performance + IL2CPP issues). Only in Editor, Tests, or when no alternative exists.
- **Meta Files**: Do **not** create .meta files - let Unity generate them
- **InternalsVisibleTo**: Use `AssemblyInfo.cs` instead of asmdef's `internalVisibleTo` property

## Error Handling and Debugging

- **Try-Catch**: Use for file I/O and network operations
- **Async Void**: Avoid except for C# event handlers. If used, wrap entire contents in try-catch
- **Debugging**: Use Debug.Log, Debug.LogWarning, Debug.LogError, Debug.Assert
- **Assertions**: Use Debug.Assert to catch logical errors

### Async/Await Patterns

**Naming**: All async methods must end with `Async` suffix.

**Best default - return Task and await it:**
```csharp
await SomeAsyncCallAsync();

public async Task SomeAsyncCallAsync()
{
    // do work
}
```

**Fire-and-forget (telemetry, cleanup) - still return Task:**
```csharp
_ = SomeAsyncCallAsync()
    .ContinueWith(t => Log(t.Exception),
        TaskScheduler.FromCurrentSynchronizationContext());
```

**Unity context**: Do NOT use `ConfigureAwait(false)` for code that touches Unity APIs.

## Comments Conventions

- **XML Documentation**: Use `///` only for public APIs. Never for private/internal members.
- **Empty Line After XML**: Always add empty line after a member if next member has XML comment
- **Don't comment decisions**: Avoid explaining why code exists
- **Don't leave commented code**: Unless explicitly specified

## Performance Optimization

- **Object Pooling**: For frequently instantiated/destroyed objects
- **Draw Calls**: Batch materials, use atlases
- **Job System**: Use for CPU-intensive operations
- **GC-Free**: Use GC-free Unity API alternatives when available

## Example Code Structure

```csharp
using UnityEngine;

namespace Foo
{
    public class ExampleClass : MonoBehaviour
    {
        private const int MaxItems = 100;
        private static bool _isInitialized;

        public static event Action OnGameStarted;

        public static int InstanceCount { get; private set; }

        public static void ResetGame() { }
        private static void InitializeStatic() { }

        [SerializeField] private int _health;

        public event Action<int> OnHealthChanged;

        public bool IsAlive => _health > 0;

        private void Awake() { }
        private void Start() { }
        private void Update() { }

        public void TakeDamage(int damage) { }
        private void InitializePlayer() { }
    }
}
```
