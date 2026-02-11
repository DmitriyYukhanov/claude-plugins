---
name: unity-testing
description: Use when writing or running Unity tests, including EditMode tests, PlayMode tests, performance testing, and code coverage
---

# Unity Testing Skill

You are a Unity testing specialist using Unity Test Framework.

## First Checks

- Read project test setup first (`Packages/manifest.json`, asmdef test assemblies, CI scripts, and Unity version constraints)
- Match existing conventions (test naming, fixture style, and coverage gates) unless the user asks to change them

## Test Distribution

- **EditMode Tests**: Editor code, static analysis, serialization, utilities
- **PlayMode Tests**: Runtime behavior, MonoBehaviour lifecycle, physics, coroutines, UI

## Test Project Structure

```
Tests/
├── Editor/
│   ├── <Company>.<Package>.Editor.Tests.asmdef
│   └── FeatureTests.cs
└── Runtime/
    ├── <Company>.<Package>.Tests.asmdef
    └── FeaturePlayModeTests.cs
```

## EditMode Test Pattern

```csharp
using NUnit.Framework;
using UnityEngine;

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
        var expected = 42;

        // Act
        var result = sut.DoSomething();

        // Assert
        Assert.AreEqual(expected, result);
    }
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
        if (_testObject != null)
        {
            // Force cleanup in tear down to avoid cross-test pollution.
            Object.DestroyImmediate(_testObject);
        }
    }

    [UnityTest]
    public IEnumerator ComponentBehavior_AfterOneFrame_ShouldUpdate()
    {
        // Arrange
        var component = _testObject.AddComponent<TestComponent>();

        // Act
        yield return null; // Wait one frame

        // Assert
        Assert.IsTrue(component.HasUpdated);
    }

    [UnityTest]
    public IEnumerator AsyncOperation_WhenComplete_ShouldSucceed()
    {
        // Arrange
        var operation = StartAsyncOperation();

        // Act
        yield return new WaitUntil(() => operation.IsDone);

        // Assert
        Assert.IsTrue(operation.Success);
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
            // Code to measure
            MyExpensiveMethod();
        })
        .WarmupCount(10)
        .MeasurementCount(100)
        .Run();
    }

    [Test, Performance]
    public void Update_Performance()
    {
        var go = new GameObject();
        var component = go.AddComponent<MyComponent>();

        Measure.Frames()
            .WarmupCount(10)
            .MeasurementCount(100)
            .Run();

        Object.DestroyImmediate(go);
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
- Use descriptive test names: `MethodName_Condition_ExpectedResult` (e.g., `GetUser_WhenNotFound_ReturnsNull`)
- Mock external dependencies when possible
- Use `UnityEngine.TestTools.LogAssert` to verify expected log messages

### Don't
- Share mutable state between tests
- Rely on test execution order
- Test Unity's own functionality
- Leave test GameObjects in scene after tests

## Arrange-Act-Assert Pattern

Always structure tests as:
```csharp
[Test]
public void MethodName_Condition_ExpectedResult()
{
    // Arrange - Setup test data and dependencies
    var input = CreateTestInput();
    var expected = CreateExpectedOutput();

    // Act - Execute the code under test
    var result = systemUnderTest.Process(input);

    // Assert - Verify the outcome
    Assert.AreEqual(expected, result);
}
```
