"""
Pydantic schemas for authentication requests and responses.

For beginners:
- Pydantic models define the "shape" of data (what fields, what types)
- They automatically validate incoming data and generate API documentation
- Think of them as "contracts" - they specify exactly what the API expects and returns

Why use Pydantic instead of plain dictionaries?
- Type checking: Catches errors before runtime
- Validation: Ensures email is valid, required fields are present
- Documentation: FastAPI auto-generates OpenAPI docs from these schemas
- Serialization: Converts between Python objects and JSON
"""
from pydantic import BaseModel, EmailStr, Field, field_validator
from datetime import datetime
from uuid import UUID
from typing import Optional
import re


class SignupRequest(BaseModel):
    """
    Data required to create a new account.

    This schema defines what the client must send to /auth/signup

    Validations:
    - email: Must be valid email format (thanks to EmailStr)
    - password: Minimum 12 characters with complexity requirements (uppercase, lowercase, number, special char)
    - name: Required, user's display name
    """
    email: EmailStr  # EmailStr validates email format automatically
    password: str = Field(
        ...,
        min_length=12,
        description="Password (minimum 12 characters, must include uppercase, lowercase, number, and special character)"
    )
    name: str = Field(..., min_length=1, description="User's display name")

    @field_validator('password')
    @classmethod
    def validate_password_strength(cls, v: str) -> str:
        """
        Enforce strong password policy to prevent weak passwords.

        Requirements:
        - At least 12 characters
        - At least one uppercase letter (A-Z)
        - At least one lowercase letter (a-z)
        - At least one number (0-9)
        - At least one special character (!@#$%^&*(),.?":{}|<>)

        This prevents common weak passwords like "password123" which are
        vulnerable to brute force attacks.
        """
        if len(v) < 12:
            raise ValueError("Password must be at least 12 characters long")

        if not re.search(r'[A-Z]', v):
            raise ValueError("Password must contain at least one uppercase letter (A-Z)")

        if not re.search(r'[a-z]', v):
            raise ValueError("Password must contain at least one lowercase letter (a-z)")

        if not re.search(r'[0-9]', v):
            raise ValueError("Password must contain at least one number (0-9)")

        if not re.search(r'[!@#$%^&*(),.?":{}|<>]', v):
            raise ValueError("Password must contain at least one special character (!@#$%^&*(),.?\":{}|<>)")

        return v

    class Config:
        # Example for API documentation
        # This shows up in the interactive docs at /docs
        json_schema_extra = {
            "example": {
                "email": "user@example.com",
                "password": "SecurePass123!",
                "name": "John Doe"
            }
        }


class LoginRequest(BaseModel):
    """
    Data required to login.

    This schema defines what the client must send to /auth/login

    Simpler than SignupRequest - only needs email and password
    """
    email: EmailStr
    password: str

    class Config:
        json_schema_extra = {
            "example": {
                "email": "user@example.com",
                "password": "securepassword123"
            }
        }


class GoogleOAuthRequest(BaseModel):
    """
    Google OAuth authentication request.

    The mobile app uses google_sign_in package to get an ID token,
    which is then sent to the backend for verification.

    Flow:
    1. Mobile app initiates Google Sign-In
    2. Google returns ID token to mobile app
    3. Mobile app sends ID token to backend
    4. Backend verifies token with Google servers
    5. Backend creates/links user account and returns JWT
    """
    id_token: str = Field(..., description="Google ID token from mobile client")

    class Config:
        json_schema_extra = {
            "example": {
                "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IjZmNzI1NDEwMWY1NmU0MWNmMzVjOTkyNmRlODRhMmE1OTM1ZjZjZjIiLCJ0eXAiOiJKV1QifQ..."
            }
        }


class RefreshTokenRequest(BaseModel):
    """Request to refresh an access token using a refresh token."""
    refresh_token: str = Field(..., description="Refresh token from login response")

    class Config:
        json_schema_extra = {
            "example": {
                "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
            }
        }


class AppleOAuthRequest(BaseModel):
    """
    Apple Sign-In authentication request.

    The mobile app uses sign_in_with_apple package to get an identity token,
    which is then sent to the backend for verification.

    Note: Apple only sends the user's name on the FIRST authorization.
    Subsequent sign-ins will not include the name, so the mobile app must
    capture and send it on the first attempt.
    """
    id_token: str = Field(..., description="Apple identity token (JWT) from mobile client")
    name: Optional[str] = Field(None, description="User's name (only available on first authorization)")

    class Config:
        json_schema_extra = {
            "example": {
                "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6IjZmNzI1NDEwMWY1NmU0MWNmMzVjOTkyNmRlODRhMmE1OTM1ZjZjZjIifQ...",
                "name": "John Doe"
            }
        }


class UserResponse(BaseModel):
    """
    User data returned by API.

    SECURITY: Notice we don't include hashed_password!
    Never send passwords (even hashed) to the client.

    This schema is used for:
    - Signup response
    - Login response
    - GET /auth/me response

    Why from_attributes = True?
    Allows converting from SQLAlchemy model to Pydantic model:
        user = User(...)  # SQLAlchemy object
        response = UserResponse.model_validate(user)  # Pydantic object
    """
    id: UUID
    email: str
    name: str
    avatar_url: Optional[str] = None  # Optional field (can be None)
    created_at: datetime

    class Config:
        # Allows creation from SQLAlchemy models
        # In Pydantic v2, this is called from_attributes
        # In Pydantic v1, it was called orm_mode
        from_attributes = True

        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "email": "user@example.com",
                "name": "John Doe",
                "avatar_url": "https://example.com/avatar.jpg",
                "created_at": "2025-01-01T00:00:00Z"
            }
        }


class AuthResponse(BaseModel):
    """
    Response after successful login/signup.

    This is what the client receives after authentication.

    Fields:
    - access_token: JWT token to use for authenticated requests
    - token_type: Always "bearer" for JWT (industry standard)
    - user: Full user information

    How the client uses this:
    1. Receives access_token
    2. Stores it (localStorage, SharedPreferences, etc.)
    3. Sends it with every request: "Authorization: Bearer <token>"

    Example Authorization header:
        Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
    """
    access_token: str
    refresh_token: str
    token_type: str = "bearer"  # Type of token (always "bearer" for JWT)
    user: UserResponse

    class Config:
        json_schema_extra = {
            "example": {
                "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                "token_type": "bearer",
                "user": {
                    "id": "550e8400-e29b-41d4-a716-446655440000",
                    "email": "user@example.com",
                    "name": "John Doe",
                    "avatar_url": None,
                    "created_at": "2025-01-01T00:00:00Z"
                }
            }
        }
