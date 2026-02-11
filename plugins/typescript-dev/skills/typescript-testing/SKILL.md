---
name: typescript-testing
description: TypeScript testing patterns with Jest/Vitest including unit tests, integration tests, mocking strategies, and coverage. Use when writing or running TypeScript tests.
---

# TypeScript Testing Skill

You are a testing specialist for TypeScript projects.

## Testing Frameworks

### Framework Detection
- `jest.config.*` or `"jest"` in package.json → Jest
- `vitest.config.*` or `"vitest"` in package.json → Vitest
- `cypress.config.*` → Cypress (E2E)
- `playwright.config.*` → Playwright (E2E)

## Test Distribution

- **~75% Unit Tests**: Fast, isolated, fully mocked
- **~20% Integration Tests**: Module interactions, API contracts
- **~5% E2E Tests**: Full user flows (Cypress/Playwright)

## Unit Test Patterns

### Arrange-Act-Assert
```typescript
describe('UserService', () => {
  let sut: UserService;
  let mockRepository: jest.Mocked<IUserRepository>;

  beforeEach(() => {
    mockRepository = {
      findById: jest.fn(),
      save: jest.fn(),
    };
    sut = new UserService(mockRepository);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('getUser', () => {
    it('should return user when found', async () => {
      // Arrange
      const expectedUser = { id: '1', name: 'Test' };
      mockRepository.findById.mockResolvedValue(expectedUser);

      // Act
      const result = await sut.getUser('1');

      // Assert
      expect(result).toEqual(expectedUser);
      expect(mockRepository.findById).toHaveBeenCalledWith('1');
    });

    it('should return null when user not found', async () => {
      // Arrange
      mockRepository.findById.mockResolvedValue(null);

      // Act
      const result = await sut.getUser('unknown');

      // Assert
      expect(result).toBeNull();
    });
  });
});
```

### Mocking Strategies

```typescript
// Mock modules
jest.mock('./database', () => ({
  getConnection: jest.fn().mockResolvedValue(mockConnection),
}));

// Mock implementations (include standard Response properties)
const mockData = { id: '1', name: 'Test' };
const mockFetch = jest.fn().mockImplementation((url: string) =>
  Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(mockData) })
);

// Spy on methods
const spy = jest.spyOn(service, 'validate');
expect(spy).toHaveBeenCalledTimes(1);
```

## Integration Test Patterns

```typescript
describe('API Integration', () => {
  let app: Express;

  beforeAll(async () => {
    app = await createApp({ database: testDb });
  });

  afterAll(async () => {
    await testDb.close();
  });

  it('should create and retrieve user', async () => {
    const createResponse = await request(app)
      .post('/users')
      .send({ name: 'Test', email: 'test@example.com' })
      .expect(201);

    const getResponse = await request(app)
      .get(`/users/${createResponse.body.id}`)
      .expect(200);

    expect(getResponse.body.name).toBe('Test');
  });
});
```

## React Component Testing

```typescript
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

describe('Button', () => {
  it('should call onClick when clicked', async () => {
    const user = userEvent.setup();
    const handleClick = jest.fn();
    render(<Button onClick={handleClick}>Click me</Button>);

    await user.click(screen.getByText('Click me'));

    expect(handleClick).toHaveBeenCalledTimes(1);
  });

  it('should be disabled when loading', () => {
    render(<Button isLoading>Submit</Button>);

    expect(screen.getByRole('button')).toBeDisabled();
  });
});
```

## Async Testing

```typescript
// Testing async functions
it('should handle async errors', async () => {
  mockApi.get.mockRejectedValue(new NetworkError('timeout'));

  await expect(service.fetchData('url')).rejects.toThrow(NetworkError);
});

// Testing timers (clean up in afterEach to prevent leaks on failure)
describe('debounce', () => {
  beforeEach(() => jest.useFakeTimers());
  afterEach(() => jest.useRealTimers());

  it('should debounce input', () => {
    const callback = jest.fn();

    debounce(callback, 300)('test');
    expect(callback).not.toHaveBeenCalled();

    jest.advanceTimersByTime(300);
    expect(callback).toHaveBeenCalledWith('test');
  });
});
```

## Vitest Equivalents

If using Vitest instead of Jest, the API is nearly identical:

| Jest | Vitest |
|------|--------|
| `jest.fn()` | `vi.fn()` |
| `jest.mock()` | `vi.mock()` |
| `jest.spyOn()` | `vi.spyOn()` |
| `jest.clearAllMocks()` | `vi.clearAllMocks()` |
| `jest.useFakeTimers()` | `vi.useFakeTimers()` |
| `jest.Mocked<T>` | `MockedObject<T>` (from `vitest`) |

## Coverage Guidelines

- Enforce ≥80% coverage on critical business logic
- Don't chase 100% - focus on meaningful tests
- Never commit real `.env` files or API keys in tests
- Use test fixtures for complex data structures
