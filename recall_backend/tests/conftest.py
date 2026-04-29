import os

# Set env vars BEFORE any app imports to prevent lifespan sys.exit(1)
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-for-testing-only-32chars")
os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://test:test@localhost/test")
os.environ.setdefault("AI_PROVIDER", "openai")
os.environ.setdefault("OPENAI_API_KEY", "test-key")
os.environ["RATELIMIT_ENABLED"] = "false"

import uuid
from unittest.mock import AsyncMock, MagicMock
import pytest
from starlette.testclient import TestClient

from main import app
from app.db.session import get_db
from app.api.routes.auth import get_current_user
from app.models.user import User
from app.core.security import create_access_token


@pytest.fixture
def mock_db():
    """AsyncMock implementing AsyncSession interface."""
    db = AsyncMock()
    db.execute = AsyncMock()
    db.execute.return_value = MagicMock()
    db.execute.return_value.scalar_one_or_none = MagicMock(return_value=None)
    db.execute.return_value.scalars = MagicMock(return_value=MagicMock(all=MagicMock(return_value=[])))
    db.execute.return_value.scalar = MagicMock(return_value=0)
    db.execute.return_value.fetchall = MagicMock(return_value=[])
    db.execute.return_value.fetchone = MagicMock(return_value=None)
    db.add = MagicMock()
    db.commit = AsyncMock()
    db.refresh = AsyncMock()
    db.delete = AsyncMock()
    db.rollback = AsyncMock()
    return db


@pytest.fixture
def mock_user():
    """A User mock with known id/email, avoids DetachedInstanceError."""
    user = MagicMock(spec=User)
    user.id = uuid.uuid4()
    user.email = "test@example.com"
    user.name = "Test User"
    user.hashed_password = "hashed"
    user.is_active = True
    return user


@pytest.fixture
def auth_headers(mock_user):
    """Real JWT token for mock_user, returned as Authorization header dict."""
    token = create_access_token(data={"sub": str(mock_user.id)})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def test_client(mock_db):
    """TestClient with only get_db overridden — allows testing auth failures."""
    async def override_get_db():
        yield mock_db

    app.dependency_overrides[get_db] = override_get_db

    client = TestClient(app, raise_server_exceptions=True)

    yield client

    app.dependency_overrides.clear()


@pytest.fixture
def authenticated_client(mock_db, mock_user):
    """TestClient with get_db and get_current_user both overridden."""
    async def override_get_db():
        yield mock_db

    async def override_get_current_user():
        return mock_user

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user

    client = TestClient(app, raise_server_exceptions=True)

    yield client

    app.dependency_overrides.clear()
