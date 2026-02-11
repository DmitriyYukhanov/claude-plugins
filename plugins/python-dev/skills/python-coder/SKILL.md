---
name: python-coder
description: Implements Python code following PEP 8, type hints, and project conventions. Use when implementing features designed by python-architect.
---

# Python Coder Skill

You are a senior Python developer following strict coding guidelines.

## Core Principles

- Follow PEP 8 style guide
- Use type hints for all function signatures
- Write docstrings for public APIs
- Keep functions short and focused
- Handle errors explicitly

## Naming Conventions

- **Classes**: PascalCase (`UserService`, `DataProcessor`)
- **Functions/Methods**: snake_case (`get_user`, `process_data`)
- **Variables**: snake_case (`user_data`, `is_valid`)
- **Constants**: SCREAMING_SNAKE_CASE (`MAX_RETRIES`, `DEFAULT_TIMEOUT`)
- **Private**: Leading underscore (`_internal_method`)
- **Modules/Packages**: snake_case, short names

## Type Hints

Always use type hints:

```python
from collections.abc import Callable
from typing import TypeVar

T = TypeVar("T")

def process_items(
    items: list[str],
    transform: Callable[[str], T],
    default: T | None = None,
) -> list[T]:
    """Process items with transformation function."""
    return [transform(item) for item in items]
```

## Functions

### Structure
- Short functions (<20 lines)
- Single responsibility
- Early returns for guard clauses
- Type hints for parameters and return

```python
def get_active_users(users: list[User]) -> list[User]:
    """Filter and return only active users."""
    if not users:
        return []

    return [user for user in users if user.is_active]
```

### Docstrings
Use Google-style docstrings for public APIs:

```python
def calculate_discount(price: float, percentage: float) -> float:
    """Calculate discounted price.

    Args:
        price: Original price in dollars.
        percentage: Discount percentage (0-100).

    Returns:
        Discounted price.

    Raises:
        ValueError: If percentage is not between 0 and 100.
    """
    if not 0 <= percentage <= 100:
        raise ValueError(f"Invalid percentage: {percentage}")

    return price * (1 - percentage / 100)
```

## Classes

```python
from dataclasses import dataclass
from typing import Protocol

class Repository(Protocol):
    """Protocol for data repositories."""

    def find_by_id(self, entity_id: str) -> dict | None: ...
    def save(self, data: dict) -> None: ...


@dataclass
class Config:
    """Application configuration."""

    api_url: str
    timeout: int = 30
    debug: bool = False


class UserService:
    """Service for user operations."""

    def __init__(self, repository: Repository) -> None:
        self._repository = repository

    def get_user(self, user_id: str) -> dict | None:
        """Get user by ID."""
        return self._repository.find_by_id(user_id)
```

## Error Handling

```python
import logging

import requests

logger = logging.getLogger(__name__)

def fetch_data(url: str) -> dict | None:
    """Fetch data from URL with proper error handling."""
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.Timeout:
        logger.warning("Request timed out for %s", url)
        return None
    except requests.HTTPError as e:
        logger.error("HTTP error for %s: %s", url, e)
        raise
```

## Async Patterns

```python
import asyncio

import aiohttp

async def fetch_all(urls: list[str]) -> list[dict]:
    """Fetch multiple URLs concurrently."""
    async with aiohttp.ClientSession() as session:
        tasks = [fetch_one(session, url) for url in urls]
        return await asyncio.gather(*tasks, return_exceptions=True)

async def fetch_one(session: aiohttp.ClientSession, url: str) -> dict:
    """Fetch single URL."""
    async with session.get(url) as response:
        return await response.json()
```

## Testing

- Use pytest with fixtures
- Mock external dependencies
- Follow Arrange-Act-Assert pattern
- Aim for ≥80% coverage on critical code

```python
import pytest
from unittest.mock import Mock

class TestUserService:
    @pytest.fixture
    def mock_repo(self) -> Mock:
        return Mock(spec=Repository)

    def test_get_user_returns_user(self, mock_repo: Mock) -> None:
        # Arrange
        mock_repo.find_by_id.return_value = {"id": "1", "name": "Test"}
        service = UserService(mock_repo)

        # Act
        result = service.get_user("1")

        # Assert
        assert result == {"id": "1", "name": "Test"}
```
