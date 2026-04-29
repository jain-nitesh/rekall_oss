"""
Security utilities: password hashing and JWT token management.

For beginners:
- Password hashing: Converting passwords into unrecoverable strings
- JWT (JSON Web Token): Secure way to verify user identity without sessions
"""
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from app.core.config import settings


# Password hashing context
# bcrypt is the industry standard for password hashing
# It's "slow" by design - makes brute-force attacks impractical
#
# What is bcrypt?
# - One-way function: Can hash password, but can't reverse the hash
# - Includes salt: Random data mixed in, so same password → different hashes
# - Adjustable cost: Can make it slower as computers get faster
#
# deprecated="auto": Automatically upgrade old hashes to new scheme
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    """
    Hash a plain text password using bcrypt.

    Example:
        hash_password("mypassword123")
        → "$2b$12$KIXxLj3pYGq4Q.K9m6nZRO7Y8mC1vD2e3F4g5H6i7J8k9L0m1N2o3"

    The hash includes:
    - Algorithm identifier: $2b$ (bcrypt)
    - Cost factor: 12 (2^12 = 4096 rounds of hashing)
    - Salt: Random 22 characters
    - Hash: Resulting 31 characters

    Why is this secure?
    - Takes ~0.3 seconds to compute (slow enough to stop brute-force)
    - Different every time (even for same password)
    - Impossible to reverse (one-way function)

    Args:
        password: Plain text password from user

    Returns:
        Hashed password safe to store in database
    """
    return pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a password against its hash.

    How it works:
    1. Extracts the salt from the stored hash
    2. Hashes the plain password with the same salt
    3. Compares the result to the stored hash

    Example:
        stored_hash = "$2b$12$KIXx..."
        verify_password("mypassword123", stored_hash)  → True
        verify_password("wrongpassword", stored_hash)  → False

    Args:
        plain_password: Password entered by user
        hashed_password: Password hash from database

    Returns:
        True if password is correct, False otherwise
    """
    return pwd_context.verify(plain_password, hashed_password)


def create_refresh_token(data: dict) -> str:
    """
    Create a long-lived JWT refresh token (30 days).
    Used to obtain new access tokens without re-authentication.
    """
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(
        minutes=settings.jwt_refresh_token_expire_minutes
    )
    to_encode.update({"exp": expire, "type": "refresh"})

    encoded_jwt = jwt.encode(
        to_encode,
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm
    )
    return encoded_jwt


def decode_refresh_token(token: str) -> Optional[str]:
    """
    Decode and verify a refresh token.
    Returns user ID if valid refresh token, None otherwise.
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm]
        )
        if payload.get("type") != "refresh":
            return None
        return payload.get("sub")
    except JWTError:
        return None


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    Create a JWT access token.

    What is JWT?
    JWT (JSON Web Token) is like a secure "badge" that proves who you are.
    Structure: header.payload.signature
    - Header: Algorithm and token type
    - Payload: Your data (user ID, expiration)
    - Signature: Cryptographic proof that token hasn't been tampered with

    Why use JWT instead of sessions?
    - Stateless: Server doesn't need to store sessions (scales better)
    - Self-contained: All info is in the token
    - Cross-domain: Works across multiple services

    Security:
    - Signed with secret key (only server can create valid tokens)
    - Includes expiration (tokens are temporary)
    - Can't be modified (signature would break)

    Example token:
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkw..."

    Decoded payload example:
        {
            "sub": "550e8400-e29b-41d4-a716-446655440000",  # User ID
            "exp": 1735689600  # Expiration timestamp
        }

    Args:
        data: Dictionary to encode (usually {"sub": user_id})
        expires_delta: How long token is valid (default: from settings)

    Returns:
        JWT token string
    """
    # Make a copy so we don't modify the original
    to_encode = data.copy()

    # Set expiration time
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        # Default: 7 days (10080 minutes)
        expire = datetime.utcnow() + timedelta(
            minutes=settings.jwt_access_token_expire_minutes
        )

    # Add expiration to token payload
    # "exp" is a standard JWT claim for expiration
    to_encode.update({"exp": expire})

    # Create and sign the token
    # The signature proves this token was created by our server
    # Only someone with jwt_secret_key can create valid tokens
    encoded_jwt = jwt.encode(
        to_encode,
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm  # HS256 = HMAC with SHA-256
    )

    return encoded_jwt


def decode_access_token(token: str) -> Optional[str]:
    """
    Decode and verify a JWT token.

    Verification checks:
    1. Signature is valid (token wasn't modified)
    2. Token hasn't expired
    3. Token was signed with our secret key

    Example:
        token = "eyJhbGciOiJIUzI1NiIs..."
        user_id = decode_access_token(token)
        # Returns: "550e8400-e29b-41d4-a716-446655440000"

    If token is invalid or expired:
        decode_access_token("bad-token")  → None

    Args:
        token: JWT token from Authorization header

    Returns:
        User ID from token, or None if token is invalid/expired
    """
    try:
        # Decode and verify token
        # This automatically checks signature and expiration
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm]
        )

        # Extract user ID from "sub" (subject) field
        # "sub" is a standard JWT claim for the subject (usually user ID)
        user_id: str = payload.get("sub")

        return user_id

    except JWTError:
        # Token is invalid, expired, or tampered with
        # Don't reveal why to prevent information leakage
        return None
