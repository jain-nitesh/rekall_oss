import uuid
from datetime import datetime, timedelta
from unittest.mock import MagicMock
import pytest

from app.core.security import hash_password, create_refresh_token, create_access_token


@pytest.fixture
def mock_user_with_password(mock_user):
    """mock_user extended with fields needed for auth routes."""
    mock_user.hashed_password = hash_password("SecurePass123!")
    mock_user.failed_login_attempts = 0
    mock_user.locked_until = None
    mock_user.avatar_url = None
    mock_user.created_at = datetime(2025, 1, 1)
    return mock_user


# ---------------------------------------------------------------------------
# POST /api/auth/signup
# ---------------------------------------------------------------------------

def test_signup_new_email(test_client, mock_db, mock_user_with_password):
    mock_db.execute.return_value.scalar_one_or_none.return_value = None

    async def fake_refresh(obj):
        obj.id = mock_user_with_password.id
        obj.email = "new@example.com"
        obj.name = "New User"
        obj.hashed_password = "hashed"
        obj.avatar_url = None
        obj.created_at = datetime(2025, 1, 1)

    mock_db.refresh.side_effect = fake_refresh

    resp = test_client.post("/api/auth/signup", json={
        "email": "new@example.com",
        "name": "New User",
        "password": "SecurePass123!",
    })
    assert resp.status_code == 200
    body = resp.json()
    assert "access_token" in body
    assert "refresh_token" in body
    assert body["token_type"] == "bearer"
    assert "user" in body


def test_signup_duplicate_email(test_client, mock_db, mock_user_with_password):
    mock_db.execute.return_value.scalar_one_or_none.return_value = mock_user_with_password

    resp = test_client.post("/api/auth/signup", json={
        "email": "test@example.com",
        "name": "Test User",
        "password": "SecurePass123!",
    })
    assert resp.status_code == 409


# ---------------------------------------------------------------------------
# POST /api/auth/login
# ---------------------------------------------------------------------------

def test_login_correct_credentials(test_client, mock_db, mock_user_with_password):
    mock_db.execute.return_value.scalar_one_or_none.return_value = mock_user_with_password

    resp = test_client.post("/api/auth/login", json={
        "email": "test@example.com",
        "password": "SecurePass123!",
    })
    assert resp.status_code == 200
    body = resp.json()
    assert "access_token" in body
    assert "refresh_token" in body
    assert body["token_type"] == "bearer"


def test_login_wrong_password(test_client, mock_db, mock_user_with_password):
    mock_db.execute.return_value.scalar_one_or_none.return_value = mock_user_with_password

    resp = test_client.post("/api/auth/login", json={
        "email": "test@example.com",
        "password": "WrongPassword!",
    })
    assert resp.status_code == 401


# ---------------------------------------------------------------------------
# POST /api/auth/refresh
# ---------------------------------------------------------------------------

def test_refresh_valid_token(test_client, mock_db, mock_user_with_password):
    refresh_token = create_refresh_token(data={"sub": str(mock_user_with_password.id)})
    mock_db.execute.return_value.scalar_one_or_none.return_value = mock_user_with_password

    resp = test_client.post("/api/auth/refresh", json={"refresh_token": refresh_token})
    assert resp.status_code == 200
    assert "access_token" in resp.json()


# ---------------------------------------------------------------------------
# GET /api/auth/me
# ---------------------------------------------------------------------------

def test_get_me_authenticated(authenticated_client, mock_user):
    mock_user.avatar_url = None
    mock_user.created_at = datetime(2025, 1, 1)

    resp = authenticated_client.get("/api/auth/me")
    assert resp.status_code == 200
    body = resp.json()
    assert body["email"] == mock_user.email
    assert body["name"] == mock_user.name
    assert "id" in body


def test_get_me_missing_token(test_client):
    resp = test_client.get("/api/auth/me")
    assert resp.status_code == 403


def test_get_me_invalid_token(test_client):
    resp = test_client.get(
        "/api/auth/me",
        headers={"Authorization": "Bearer invalid-token-here"},
    )
    assert resp.status_code == 401


def test_get_me_expired_token(test_client):
    expired_token = create_access_token(
        data={"sub": str(uuid.uuid4())},
        expires_delta=timedelta(seconds=-1),
    )
    resp = test_client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {expired_token}"},
    )
    assert resp.status_code == 401
