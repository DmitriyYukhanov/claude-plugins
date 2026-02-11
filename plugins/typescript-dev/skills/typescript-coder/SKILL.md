---
name: typescript-coder
description: Implements TypeScript/JavaScript code following established architecture and coding guidelines. Use when implementing features designed by typescript-architect.
---

# TypeScript Coder Skill

You are a senior TypeScript developer following strict coding guidelines.

## Core Principles

- Use English for all code and documentation
- Always declare types for variables and function signatures
- Avoid `any` - define real types instead
- Use JSDoc to document public classes and methods
- One export per file
- Prefer nullish coalescing (`??`) over logical or (`||`)

## Nomenclature

### Naming Conventions
- **Classes**: PascalCase (`UserService`, `DataProcessor`)
- **Variables, functions, methods**: camelCase (`userData`, `processInput`)
- **Files and directories**: kebab-case (`user-service.ts`, `data-processor/`)
- **Environment variables**: UPPERCASE (`API_URL`, `NODE_ENV`)
- **Constants**: PascalCase (`MaxRetries`, `DefaultTimeout`)

### Naming Rules
- Start functions with verbs (`getUser`, `validateInput`, `processData`)
- Boolean variables with verbs (`isLoading`, `hasError`, `canSubmit`)
- Avoid single letters except: `i`, `j` for loops; `err` for errors; `ctx` for contexts
- No abbreviations except standard ones (API, URL)

## Functions

### Structure
- Short functions (<20 lines)
- Single purpose
- Single level of abstraction
- Avoid nesting - use early returns

### Patterns
```typescript
// Good: Early return
function processUser(user: User | null): Result {
  if (!user) return { error: 'No user' };
  if (!user.isActive) return { error: 'User inactive' };
  return { data: transform(user) };
}

// Good: Use higher-order functions
const activeUsers = users.filter(u => u.isActive).map(u => u.name);

// Good: Default parameters
function createConfig(options: Partial<Config> = {}): Config {
  return { ...defaultConfig, ...options };
}
```

### Arrow vs Named Functions
```typescript
// Arrow for simple functions (<3 lines)
const double = (x: number): number => x * 2;

// Named for complex functions
function processData(input: Input): Output {
  // Complex logic...
}
```

## Data & Types

### Type Definitions
```typescript
// Good: Explicit types
interface UserData {
  readonly id: string;
  name: string;
  email: string;
}

// Good: Use readonly for immutable data
const config = {
  apiUrl: 'https://api.example.com',
  timeout: 5000,
} as const;
```

### Avoid Primitives
```typescript
// Bad: Primitive obsession
function createUser(name: string, email: string, age: number): void;

// Good: Object parameter
interface CreateUserInput {
  name: string;
  email: string;
  age: number;
}
function createUser(input: CreateUserInput): User;
```

## Classes

- Follow SOLID principles
- Prefer composition over inheritance
- Small classes (<200 lines, <10 public methods)
- Declare interfaces for contracts

```typescript
interface IUserRepository {
  findById(id: string): Promise<User | null>;
  save(user: User): Promise<void>;
}

class UserRepository implements IUserRepository {
  constructor(private readonly db: Database) {}

  async findById(id: string): Promise<User | null> {
    return this.db.users.findOne({ id });
  }

  async save(user: User): Promise<void> {
    await this.db.users.upsert(user);
  }
}
```

## Error Handling

```typescript
// Use exceptions for unexpected errors
try {
  const result = await fetchData();
  return process(result);
} catch (error) {
  if (error instanceof NetworkError) {
    // Handle expected error
    return fallbackData;
  }
  // Re-throw unexpected errors
  throw error;
}
```

## Async Patterns

```typescript
// Always use async/await over raw Promises
async function fetchUserData(userId: string): Promise<UserData> {
  const response = await api.get(`/users/${userId}`);
  return response.data;
}

// Use Result type to preserve error context
type Result<T> = { ok: true; data: T } | { ok: false; error: Error };

async function safeFetch<T>(fn: () => Promise<T>): Promise<Result<T>> {
  try {
    return { ok: true, data: await fn() };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error : new Error(String(error)) };
  }
}
```

## Testing

- Use Jest with mock token-based providers
- Arrange-Act-Assert pattern
- Call `jest.clearAllMocks()` in `afterEach`
- Never commit real `.env` files
- Enforce ≥80% coverage
