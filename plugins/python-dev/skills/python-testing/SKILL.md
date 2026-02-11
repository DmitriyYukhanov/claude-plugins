---
name: python-testing
description: Python testing patterns with pytest including unit tests, integration tests, fixtures, mocking, and coverage. Use when writing or running Python tests.
---

# Python Testing Skill

You are a testing specialist for Python projects.

## Testing Framework

### Framework Detection
- `conftest.py` or `pytest.ini` → pytest
- `unittest` imports → unittest (suggest migrating to pytest)
- `tox.ini` → tox runner
- `nox` → nox runner

## Test Distribution

- **~75% Unit Tests**: Fast, mocked dependencies
- **~20% Integration Tests**: Database, API interactions
- **~5% E2E Tests**: Full workflows

## Unit Test Patterns

### Arrange-Act-Assert with Fixtures
```python
import pytest
from unittest.mock import Mock, AsyncMock, patch

class TestUserService:
    @pytest.fixture
    def mock_repository(self) -> Mock:
        return Mock(spec=UserRepository)

    @pytest.fixture
    def service(self, mock_repository: Mock) -> UserService:
        return UserService(mock_repository)

    def test_get_user_returns_user_when_exists(
        self, service: UserService, mock_repository: Mock
    ) -> None:
        # Arrange
        expected_user = User(id="1", name="Test", email="test@example.com")
        mock_repository.find_by_id.return_value = expected_user

        # Act
        result = service.get_user("1")

        # Assert
        assert result == expected_user
        mock_repository.find_by_id.assert_called_once_with("1")

    def test_get_user_returns_none_when_not_exists(
        self, service: UserService, mock_repository: Mock
    ) -> None:
        # Arrange
        mock_repository.find_by_id.return_value = None

        # Act
        result = service.get_user("unknown")

        # Assert
        assert result is None
```

### Parametrized Tests
```python
@pytest.mark.parametrize("input_value,expected", [
    ("hello", "HELLO"),
    ("", ""),
    ("Hello World", "HELLO WORLD"),
])
def test_to_uppercase(input_value: str, expected: str) -> None:
    assert to_uppercase(input_value) == expected
```

### Mocking Strategies
```python
# Mock with spec for type safety
mock_repo = Mock(spec=UserRepository)

# Patch module-level dependencies
with patch("myapp.services.requests.get") as mock_get:
    mock_get.return_value.json.return_value = {"id": "1"}
    result = fetch_user("1")

# AsyncMock for async functions
mock_client = AsyncMock(spec=HttpClient)
mock_client.get.return_value = {"data": "value"}
```

## Async Testing

Requires `pytest-asyncio` package (`pip install pytest-asyncio`).

```python
import pytest

@pytest.mark.asyncio
async def test_async_fetch() -> None:
    mock_session = AsyncMock()
    mock_session.get.return_value.__aenter__.return_value.json = AsyncMock(
        return_value={"id": "1"}
    )

    result = await fetch_data(mock_session, "http://example.com")
    assert result == {"id": "1"}
```

## Integration Test Patterns

### Database Tests
```python
@pytest.fixture
async def db_session():
    """Create a test database session."""
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async with AsyncSession(async_engine) as session:
        yield session

    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

@pytest.mark.asyncio
async def test_create_and_fetch_user(db_session: AsyncSession) -> None:
    repo = SqlAlchemyUserRepository(db_session)
    user = User(name="Test", email="test@example.com")

    await repo.save(user)
    fetched = await repo.find_by_id(user.id)

    assert fetched is not None
    assert fetched.name == "Test"
```

### API Tests (FastAPI)
```python
from fastapi.testclient import TestClient

@pytest.fixture
def client() -> TestClient:
    return TestClient(app)

def test_create_user(client: TestClient) -> None:
    response = client.post("/users", json={"name": "Test", "email": "test@example.com"})
    assert response.status_code == 201
    assert response.json()["name"] == "Test"
```

## Conftest Patterns

```python
# conftest.py - shared fixtures
import pytest

@pytest.fixture(scope="session")
def app_config() -> Config:
    """Application config for tests."""
    return Config(api_url="http://test", timeout=5, debug=True)

@pytest.fixture
def temp_dir(tmp_path: "Path") -> "Path":
    """Temporary directory for file tests."""
    return tmp_path
```

## Coverage Guidelines

- Enforce ≥80% coverage on critical business logic
- Don't chase 100% - focus on meaningful tests
- Use `pytest-cov` for coverage reports
- Never commit real `.env` files or API keys in tests
- Use test fixtures for complex data structures
