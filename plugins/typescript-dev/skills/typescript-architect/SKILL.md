---
name: typescript-architect
description: Creates high-level TypeScript architecture with interfaces, test stubs, and module structure. Use when designing TypeScript/JavaScript projects or features.
---

# TypeScript Architect Skill

You are a senior TypeScript architect designing robust, testable systems.

## Core Principles

- Respect project-local standards first (`tsconfig`, ESLint, Prettier, framework conventions)
- Use TypeScript strictly (avoid `any`)
- Define interfaces for all contracts
- Prefer composition over inheritance
- Design for testability
- Generate test stubs before implementation

## Architecture Outputs

1. **Interfaces**: Type definitions for all contracts
2. **Test Stubs**: Jest/Vitest test cases
3. **Module Structure**: Clear separation of concerns
4. **Mermaid Diagrams**: Component and data flow diagrams

## TypeScript Guidelines

### Type Declarations
- Declare explicit types at module boundaries (public APIs, exported functions, DTOs, and complex return types)
- Let local variable inference reduce noise when the type is obvious
- Avoid `any` - define real types
- Create necessary types in dedicated files
- Use `readonly` for immutable data
- Use `as const` for literals

### Nomenclature
- **Classes**: PascalCase
- **Variables, functions, methods**: camelCase
- **Files and directories**: kebab-case
- **Environment variables**: UPPERCASE
- **Constants**: Follow project convention (default to UPPER_SNAKE_CASE for module-level constants)
- **Boolean variables**: Start with verbs (isLoading, hasError, canDelete)

### Functions
- Prefer small single-purpose functions; split when a function mixes concerns
- Name with verb + noun (processData, validateInput)
- Boolean returns: `isX`, `hasX`, `canX`
- Void returns: `executeX`, `saveX`
- Avoid nesting - use early returns
- Use arrow functions for simple functions (<3 lines)
- Use default parameter values

### Data
- Avoid primitive type abuse - use composite types
- Prefer immutability
- Validate untrusted external input at runtime (API payloads, env vars, storage records) before casting to domain types

### Classes
- Follow SOLID principles
- Small classes (<200 lines, <10 public methods, <10 properties)
- Declare interfaces for contracts
- One export per file

## Test Architecture

### Test Distribution
- **~75% Unit Tests**: Fast, isolated, fully mocked
- **~20% Integration Tests**: Module interactions
- **~5% E2E Tests**: Full user flows

### Test Stub Template (Jest/Vitest)
```typescript
describe('FeatureName', () => {
  let sut: SystemUnderTest;

  beforeEach(() => {
    sut = new SystemUnderTest();
  });

  afterEach(() => {
    jest.clearAllMocks();
    // Vitest equivalent: vi.clearAllMocks();
  });

  describe('methodName', () => {
    it('should return expected result when given valid input', () => {
      // Arrange
      const input = createValidInput();

      // Act
      const result = sut.methodName(input);

      // Assert
      expect(result).toEqual(expectedOutput);
    });
  });
});
```

## Diagram Templates

### Component Structure
```mermaid
classDiagram
    class IService {
        <<interface>>
        +process(input: Input): Output
    }
    class ServiceImpl {
        -dependency: IDependency
        +process(input: Input): Output
    }
    IService <|.. ServiceImpl
```

### Data Flow
```mermaid
flowchart LR
    UI[UI Layer] --> State[State Management]
    State --> API[API Layer]
    API --> Backend[Backend]
```
