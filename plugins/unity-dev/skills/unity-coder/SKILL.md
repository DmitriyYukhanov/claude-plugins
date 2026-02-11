---
name: unity-coder
description: Use when implementing Unity C# code to follow proper coding guidelines, naming conventions, member ordering, and Unity-specific patterns
---

# Unity Coder Skill

You are a senior Unity C# developer. Follow these guidelines precisely.

## Core Principles

- Respect project-local standards first (`.editorconfig`, Roslyn analyzers, asmdef constraints, and Unity version APIs)
- Write clear, concise C# code following Unity best practices and Microsoft naming conventions
- Prioritize performance, scalability, and maintainability
- Use Unity's component-based architecture for modularity
- Always follow SOLID, GRASP, YAGNI, DRY, KISS principles
- Implement robust error handling and debugging practices

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
- **Namespaces**: Prefer flat namespaces; use nesting only when a clear sub-domain exists
- **Regions**: Use only when necessary (interface implementations, auto-generated code)
- **File Structure**: One type per file (except generic interface base classes)
- **Imports**: Ensure all referenced types have proper `using` directives

### Type Usage
- **Type Declaration**: Prefer explicit types when they improve readability; use `var` when the right-hand type is obvious
- **Type Names**: Use `nameof()` instead of hardcoded strings
- **Nullable Types**: Follow the project's nullable context. Prefer fixing nullability at the source instead of suppressing warnings.
- **Null Checks**: Use nullable operators when appropriate, but do not use null-conditional access on Unity engine objects where destroyed-object semantics matter

### Code Style
- **Attributes**: Can be same line or new line; same line preferred when multiple fields share attribute
- **Delegates**: Prefer explicit delegates over generic Actions for events with arguments
- **Unused Parameters**: Use discard pattern `_ = parameter;` for intentionally unused params
- **Switch Statements**: Prefer exhaustive switch expressions; include a defensive default only when required by the project or runtime safety needs
- **Loop Constructs**: Prefer `foreach` over `for` for simple iterations

### Empty Lines & Formatting
- Single empty line between methods/properties/types; **no consecutive empty lines**
- **Always** empty line between `using` statements and `namespace`
- **Never** extra empty lines within code blocks unless separating logical sections
- **Never change line endings** (CRLF vs LF) when editing existing files

### Critical Rules
- **Reflection**: Avoid in runtime code (performance overhead + IL2CPP code stripping). If unavoidable, preserve types via `link.xml`. Acceptable in Editor and Tests.
- **Meta Files**: Do **not** create .meta files - let Unity generate them
- **InternalsVisibleTo**: Use `AssemblyInfo.cs` instead of asmdef's `internalVisibleTo` property

## Error Handling and Debugging

- **Try-Catch**: Use for file I/O and network operations
- **Async Void**: Avoid except for C# event handlers. If used, wrap entire contents in try-catch
- **Debugging**: Use Debug.Log, Debug.LogWarning, Debug.LogError, Debug.Assert
- **Assertions**: Use Debug.Assert to catch logical errors

### Async/Await Patterns

**Naming**: Methods that return `Task`, `ValueTask`, `Awaitable`, or `Awaitable<T>` and are awaited must end with `Async` suffix.

**Version-aware default:**
- For cross-version snippets/packages that may run on pre-2023 Unity, default to `Task`
- For Unity `2023.1+` and Unity `6+`, prefer `UnityEngine.Awaitable` for engine frame/thread operations (`NextFrameAsync`, `MainThreadAsync`, `BackgroundThreadAsync`)
- In shared code, gate `Awaitable` usage with compile symbols and keep a `Task` fallback

```csharp
using System.Threading.Tasks;
using UnityEngine;

public static class FrameDelay
{
    // When supporting code for both Unity 6 and older Unity versions, use conditional flag
#if UNITY_6000_0_OR_NEWER
    public static async Awaitable DelayOneFrameAsync()
    {
        await Awaitable.NextFrameAsync();
    }
#else
    public static async Task DelayOneFrameAsync()
    {
        await Task.Yield();
    }
#endif
}
```

**Fire-and-forget (telemetry, cleanup):**
```csharp
_ = RunBackgroundTaskAsync();

private async Task RunBackgroundTaskAsync()
{
    try
    {
        await SomeAsyncCallAsync();
    }
    catch (Exception ex)
    {
        Debug.LogException(ex);
    }
}
```

**Awaitable safety rules (Unity `2023.1+` / `6+`):**
- Await each `Awaitable` instance at most once (instances are pooled)
- `Awaitable` continuations run synchronously when completion is triggered; avoid heavy work in completion paths
- After `await Awaitable.BackgroundThreadAsync()`, switch back with `await Awaitable.MainThreadAsync()` before Unity API access

**Unity context**: Do NOT use `ConfigureAwait(false)` for code that touches Unity APIs.
**Cancellation**: Thread through `CancellationToken` for operations that may outlive scene/object lifetime.

## Comments Conventions

- **XML Documentation**: Use `///` only for public APIs. Never for private/internal members.
- **Empty Line After XML**: Always add empty line after a member if next member has XML comment
- **Comment why, not what**: Explain non-obvious decisions, trade-offs, and constraints; avoid restating what code does
- **Don't leave commented code**: Unless explicitly specified

## Documentation Formatting

### Menu Item Formatting
When referencing Unity menu items in documentation (both markdown and XML comments):
- **Standard format**: `Menu > Item > SubItem`
- Use `>` (greater than) as the separator, not `▸` or other Unicode characters
- Use backticks around menu paths in markdown
- In XML comments, wrap menu paths in quotes

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
        public static event Action OnGameStarted;

        public static int InstanceCount { get; private set; }

        private const int MaxItems = 100;
        private static bool _isInitialized;

        public delegate void HealthChangedHandler(int newHealth);
        public event HealthChangedHandler OnHealthChanged;

        [SerializeField] private int _health;

        public bool IsAlive => _health > 0;

        public static void ResetGame() { }
        private static void InitializeStatic() { }

        private void Awake() { }
        private void Start() { }
        private void Update() { }

        public void TakeDamage(int damage) { }
        private void InitializePlayer() { }
    }
}
```
