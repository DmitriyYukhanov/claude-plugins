---
name: unity-tests-write
description: Use when writing Unity tests, including EditMode tests, PlayMode tests, performance testing, and code coverage
---

# Unity Testing Skill

You are a Unity testing specialist using Unity Test Framework.

## First Checks

- Read project test setup first (`Packages/manifest.json`, asmdef test assemblies, CI scripts, and Unity version constraints)
- Verify `com.unity.test-framework` version before choosing async test style (`IEnumerator` baseline vs `async Task` in newer UTF versions)
- Match existing conventions (test naming, fixture style, and coverage gates) unless the user asks to change them

## Test Distribution

- **EditMode Tests**: Editor code, static analysis, serialization, utilities, pure logic
- **PlayMode Tests**: Runtime behavior, MonoBehaviour lifecycle, physics, coroutines, UI

## Test Project Structure

For tests inside a project:
```
Tests/
├── Editor/
│   ├── <Company>.<Package>.Editor.Tests.asmdef
│   └── FeatureTests.cs
└── Runtime/
    ├── <Company>.<Package>.Tests.asmdef
    └── FeaturePlayModeTests.cs
```

For UPM packages where tests must NOT ship with the package, use a separate test package:
```
MyPackage/                    (published SDK — no tests)
├── Runtime/
├── Editor/
└── package.json

MyPackage.Tests/              (never published — internal only)
├── package.json
└── Editor/
    ├── com.company.package.tests.editor.asmdef
    └── FeatureTests.cs
```

## UPM Package Test Setup

For tests in UPM packages to appear in Test Runner:

1. **Test asmdef must have** `UNITY_INCLUDE_TESTS` define constraint:
```json
{
    "name": "com.company.package.tests.editor",
    "references": ["com.company.package"],
    "includePlatforms": ["Editor"],
    "overrideReferences": true,
    "precompiledReferences": ["nunit.framework.dll"],
    "autoReferenced": false,
    "defineConstraints": ["UNITY_INCLUDE_TESTS"]
}
```

2. **Consuming project manifest.json must list the test package in `testables`**:
```json
{
    "dependencies": {
        "com.company.package.tests": "file:../path/to/Package.Tests"
    },
    "testables": ["com.company.package.tests"]
}
```

Without `testables`, Unity will not compile or show tests from packages.

## Testing Internal Members

Use `InternalsVisibleTo` + `internal` visibility instead of making methods `public` just for testing:

**In the runtime assembly** (`AssemblyInfo.cs`):
```csharp
using System.Runtime.CompilerServices;

[assembly: InternalsVisibleTo("com.company.package.tests.editor")]
```

**In the code under test**:
```csharp
internal static bool SomeLogic(string input) { ... }
```

This keeps the public API clean while allowing test access.

## EditMode Test Pattern

```csharp
using NUnit.Framework;

[TestFixture]
public class FeatureEditorTests
{
    [SetUp]
    public void Setup()
    {
        // Arrange common test setup
    }

    [TearDown]
    public void TearDown()
    {
        // Cleanup
    }

    [Test]
    public void MethodName_Condition_ExpectedResult()
    {
        // Arrange
        var sut = new SystemUnderTest();

        // Act
        var result = sut.DoSomething();

        // Assert
        Assert.AreEqual(42, result);
    }
}
```

## Parameterized Tests

Use `[TestCase]` when multiple inputs test the same behavior. Prefer over duplicate test methods:

```csharp
[TestCase(null)]
[TestCase("")]
public void Parse_InvalidInput_ReturnsDefault(string input)
{
    var result = Parser.Parse(input);
    Assert.AreEqual(default, result);
}

[TestCase(1, 2, 3)]
[TestCase(0, 0, 0)]
[TestCase(-1, 1, 0)]
public void Add_VariousInputs_ReturnsSum(int a, int b, int expected)
{
    Assert.AreEqual(expected, Calculator.Add(a, b));
}
```

For complex test data, use `[TestCaseSource]`:
```csharp
private static IEnumerable<TestCaseData> EdgeCases()
{
    yield return new TestCaseData("v1.0", "v1.0").Returns(true).SetName("Same version");
    yield return new TestCaseData("v1.0", "v2.0").Returns(false).SetName("Different version");
}

[TestCaseSource(nameof(EdgeCases))]
public bool VersionCheck_EdgeCases(string saved, string current)
{
    return VersionChecker.IsLoaded(saved, current);
}
```

## PlayMode Test Pattern

```csharp
using System.Collections;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

public class FeaturePlayModeTests
{
    private GameObject _testObject;

    [SetUp]
    public void Setup()
    {
        _testObject = new GameObject("TestObject");
    }

    [TearDown]
    public void TearDown()
    {
        Object.Destroy(_testObject);
    }

    [UnityTest]
    public IEnumerator ComponentBehavior_AfterOneFrame_ShouldUpdate()
    {
        var component = _testObject.AddComponent<TestComponent>();

        yield return null;

        Assert.IsTrue(component.HasUpdated);
    }
}
```

## Async Test Compatibility (Task and Awaitable)

- Widest compatibility baseline (including older Unity/UTF): keep `[UnityTest]` methods returning `IEnumerator`
- For UTF `1.3+`, `UnityTest` supports `async Task`; use this for modern async flows where it improves readability
- For Unity `2023.1+` and Unity `6+`, you can await `UnityEngine.Awaitable` inside async tests
- Do not use `Awaitable` as the test method return type; use `Task` or `IEnumerator` for test entry points
- Await each `Awaitable` instance once only

```csharp
using System.Threading.Tasks;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

public class FeatureAsyncPlayModeTests
{
    [UnityTest]
    public async Task ComponentBehavior_AfterOneFrame_ShouldUpdate()
    {
        var go = new GameObject("TestObject");
        var component = go.AddComponent<TestComponent>();

#if UNITY_6000_0_OR_NEWER
        await Awaitable.NextFrameAsync();
#else
        await Task.Yield();
#endif

        Assert.IsTrue(component.HasUpdated);
        Object.Destroy(go);
    }
}
```

## Performance Testing

Use Unity Performance Testing package for critical paths:

```csharp
using NUnit.Framework;
using Unity.PerformanceTesting;
using UnityEngine;

public class PerformanceTests
{
    [Test, Performance]
    public void MyMethod_Performance()
    {
        Measure.Method(() =>
        {
            MyExpensiveMethod();
        })
        .WarmupCount(10)
        .MeasurementCount(100)
        .Run();
    }
}
```

## Code Coverage

Use Unity Code Coverage package (`com.unity.testtools.codecoverage`):

**Coverage Targets:**
- Use project-defined thresholds first
- If no threshold exists, use >=80% for critical business logic as a default baseline

**Running with coverage:**
```bash
Unity -batchmode -projectPath "$(pwd)" -runTests -testPlatform EditMode -enableCodeCoverage -coverageResultsPath ./CodeCoverage -testResults ./TestResults/editmode.xml -quit
```

## Testing Best Practices

### Do
- Use `[SetUp]` and `[TearDown]` for consistent test isolation
- Test one behavior per test method
- Use descriptive test names: `MethodName_Condition_ExpectedResult`
- Use `[TestCase]` for same-behavior-different-inputs instead of duplicate methods
- Use `internal` + `InternalsVisibleTo` instead of making methods `public` for testing
- Mock external dependencies when possible
- Use `UnityEngine.TestTools.LogAssert` to verify expected log messages
- Extract critical logic into pure testable functions when the inline logic is bug-prone

### Don't
- Share mutable state between tests
- Rely on test execution order
- Test Unity's own functionality
- Leave test GameObjects in scene after tests
- Write separate test methods for inputs that exercise the same code path — use `[TestCase]`
- Make methods `public` solely for test access — use `InternalsVisibleTo`
- Over-extract: don't create testable wrappers for trivial one-liners that can't meaningfully break

## Arrange-Act-Assert Pattern

Always structure tests as:
```csharp
[Test]
public void MethodName_Condition_ExpectedResult()
{
    // Arrange
    var input = CreateTestInput();

    // Act
    var result = systemUnderTest.Process(input);

    // Assert
    Assert.AreEqual(expected, result);
}
```
