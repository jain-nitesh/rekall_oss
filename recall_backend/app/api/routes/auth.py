"""
Authentication API endpoints.

This file defines three main endpoints:
1. POST /auth/signup - Create a new account
2. POST /auth/login - Login with email and password
3. GET /auth/me - Get current user's information (requires JWT token)

For beginners:
- @router.post(...) means "when someone POSTs to this URL, run this function"
- Depends(...) means "call this function first and pass its result as a parameter"
- HTTPException is how we return error responses (400, 401, 404, etc.)
"""
from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import logging
from app.core.limiter import limiter
from datetime import datetime, timedelta
from app.db.session import get_db
from app.models.user import User
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_access_token,
    decode_refresh_token,
    hash_password,
    verify_password,
)
from app.core.config import settings
from app.api.schemas.auth import (
    AuthResponse,
    UserResponse,
    GoogleOAuthRequest,
    AppleOAuthRequest,
    RefreshTokenRequest,
    LoginRequest,
    SignupRequest,
)
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

logger = logging.getLogger(__name__)

# Router groups related endpoints together
# All routes in this file will be under /auth prefix
# tags=["Authentication"] groups them in the API docs
router = APIRouter(prefix="/auth", tags=["Authentication"])

# Module-level constant — computed once at startup for timing-safe login
_DUMMY_HASH = hash_password("dummy-that-never-matches-any-real-password")

# Security scheme for JWT authentication
# HTTPBearer means we expect: Authorization: Bearer <token>
# This will extract the token from the Authorization header
security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    Dependency that extracts and validates user from JWT token.

    This is a "dependency" - other routes can use it to require authentication.

    Usage in protected routes:
        @router.get("/protected")
        async def protected_route(current_user: User = Depends(get_current_user)):
            # current_user is automatically extracted from JWT token
            return {"user_id": current_user.id}

    How it works:
    1. Extracts token from Authorization header
    2. Decodes token to get user ID
    3. Fetches user from database
    4. Returns user object to the route

    If token is invalid/expired, raises 401 error.

    Why is this a dependency instead of a regular function?
    - FastAPI automatically calls it before the route
    - Guarantees authentication (route only runs if user is valid)
    - Reusable across many routes (DRY principle)

    Args:
        credentials: Extracted from "Authorization: Bearer <token>" header
        db: Database session (injected by FastAPI)

    Returns:
        User object if token is valid

    Raises:
        HTTPException 401: Invalid or expired token
        HTTPException 401: User not found (deleted account)
    """
    # Step 1: Extract token from Authorization header
    # credentials.credentials contains just the token part
    # (HTTPBearer already removed "Bearer " prefix)
    token = credentials.credentials

    # Step 2: Decode token to get user ID
    user_id = decode_access_token(token)

    if not user_id:
        # Token is invalid, expired, or tampered with
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},  # Tells client to use Bearer auth
        )

    # Step 3: Fetch user from database
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()

    if not user:
        # User was deleted after token was issued
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Step 4: Return user object
    return user


@router.get("/me", response_model=UserResponse)
async def get_me(current_user: User = Depends(get_current_user)):
    """
    Get current user's information.

    This is a protected route - requires valid JWT token.

    Example request:
        GET /api/auth/me
        Authorization: Bearer eyJhbGci...

    Example response:
        {
            "id": "550e8400-...",
            "email": "user@example.com",
            "name": "John Doe",
            "avatar_url": null,
            "created_at": "2025-01-01T00:00:00Z"
        }

    How authentication works:
    1. Client sends: Authorization: Bearer <token>
    2. get_current_user dependency extracts and validates token
    3. If valid, current_user contains the User object
    4. Route returns user information

    Error responses:
    - 401 Unauthorized: No token, invalid token, or expired token
    """
    # current_user is automatically injected by get_current_user dependency
    # If we reached this line, token is valid and user exists
    return UserResponse.model_validate(current_user)


@router.post("/google-auth", response_model=AuthResponse)
@limiter.limit("10/minute")
async def google_oauth_login(
    request: Request,
    request_body: GoogleOAuthRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Authenticate user with Google OAuth.

    Flow:
    1. Verify Google ID token
    2. Check if user exists (by email or google_id)
    3. If exists: Link Google account and update user
    4. If not exists: Create new user with Google info
    5. Generate JWT token
    6. Return JWT + user info

    Example request:
        POST /api/auth/google-auth
        {
            "id_token": "eyJhbGci..."
        }

    Example response:
        {
            "access_token": "eyJhbGci...",
            "token_type": "bearer",
            "user": {
                "id": "550e8400-...",
                "email": "user@gmail.com",
                "name": "John Doe",
                ...
            }
        }

    Errors:
        400: Invalid or expired Google token
        500: Server error
    """
    from app.services.google_oauth_service import google_oauth_service

    # Step 1: Verify Google ID token
    google_user_info = google_oauth_service.verify_id_token(request_body.id_token)

    if not google_user_info:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Google ID token"
        )

    # Security check: Ensure email is verified
    if not google_user_info.get('email_verified', False):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Google email not verified"
        )

    google_id = google_user_info['google_id']
    email = google_user_info['email']
    name = google_user_info.get('name', email.split('@')[0])
    picture = google_user_info.get('picture', '')

    # Step 2: Check if user exists by google_id
    result = await db.execute(
        select(User).where(User.google_id == google_id)
    )
    user = result.scalar_one_or_none()

    if user:
        # User exists with this Google account - just login
        logger.info(f"Google OAuth login for existing user: {user.id}")
    else:
        # Check if user exists by email (for account linking)
        result = await db.execute(
            select(User).where(User.email == email)
        )
        user = result.scalar_one_or_none()

        if user:
            # Link Google account to existing user
            user.google_id = google_id
            if picture and not user.avatar_url:
                user.avatar_url = picture
            await db.commit()
            await db.refresh(user)
            logger.info(f"Linked Google account to existing user: {user.id}")
        else:
            # Create new user with Google info
            user = User(
                email=email,
                name=name,
                google_id=google_id,
                avatar_url=picture if picture else None,
                hashed_password=None,  # No password for Google users
            )
            db.add(user)
            await db.commit()
            await db.refresh(user)
            logger.info(f"Created new user via Google OAuth: {user.id}")

    # Step 3: Generate JWT tokens
    access_token = create_access_token(data={"sub": str(user.id)})
    refresh_token = create_refresh_token(data={"sub": str(user.id)})

    # Step 4: Return response
    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        user=UserResponse.model_validate(user)
    )


@router.post("/apple-auth", response_model=AuthResponse)
@limiter.limit("10/minute")
async def apple_oauth_login(
    request: Request,
    request_body: AppleOAuthRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Authenticate user with Apple Sign-In.

    Flow:
    1. Verify Apple identity token (JWT)
    2. Check if user exists (by apple_id or email)
    3. If exists: Link Apple account and update user
    4. If not exists: Create new user with Apple info
    5. Generate JWT token
    6. Return JWT + user info

    Note: Apple only sends the user's name on the FIRST authorization.
    The mobile app must capture it and send it in the 'name' field.
    """
    from app.services.apple_oauth_service import apple_oauth_service

    # Step 1: Verify Apple identity token
    apple_user_info = apple_oauth_service.verify_id_token(request_body.id_token)

    if not apple_user_info:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid Apple identity token"
        )

    apple_id = apple_user_info['apple_id']
    email = apple_user_info.get('email', '')
    # Use name from request (only available on first auth), fallback to email prefix
    name = request_body.name or email.split('@')[0] if email else 'User'

    # Step 2: Check if user exists by apple_id
    result = await db.execute(
        select(User).where(User.apple_id == apple_id)
    )
    user = result.scalar_one_or_none()

    if user:
        # User exists with this Apple account - just login
        logger.info(f"Apple Sign-In login for existing user: {user.id}")
    else:
        # Check if user exists by email (for account linking)
        if email:
            result = await db.execute(
                select(User).where(User.email == email)
            )
            user = result.scalar_one_or_none()

        if user:
            # Link Apple account to existing user
            user.apple_id = apple_id
            await db.commit()
            await db.refresh(user)
            logger.info(f"Linked Apple account to existing user: {user.id}")
        else:
            # Create new user with Apple info
            if not email:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email is required for account creation"
                )
            user = User(
                email=email,
                name=name,
                apple_id=apple_id,
                hashed_password=None,
            )
            db.add(user)
            await db.commit()
            await db.refresh(user)
            logger.info(f"Created new user via Apple Sign-In: {user.id}")

    # Step 3: Generate JWT tokens
    access_token = create_access_token(data={"sub": str(user.id)})
    refresh_token = create_refresh_token(data={"sub": str(user.id)})

    # Step 4: Return response
    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        user=UserResponse.model_validate(user)
    )


@router.post("/refresh", response_model=AuthResponse)
@limiter.limit("20/minute")
async def refresh_access_token(
    request: Request,
    request_body: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Refresh an expired access token using a valid refresh token.

    Returns new access_token and refresh_token (token rotation).
    """
    user_id = decode_refresh_token(request_body.refresh_token)

    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    # Verify user still exists
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    # Issue new token pair (rotation)
    new_access_token = create_access_token(data={"sub": str(user.id)})
    new_refresh_token = create_refresh_token(data={"sub": str(user.id)})

    logger.info(f"Token refreshed for user: {user.id}")

    return AuthResponse(
        access_token=new_access_token,
        refresh_token=new_refresh_token,
        token_type="bearer",
        user=UserResponse.model_validate(user)
    )


@router.post("/signup", response_model=AuthResponse)
@limiter.limit("5/minute")
async def signup(
    request: Request,
    request_body: SignupRequest,
    db: AsyncSession = Depends(get_db)
):
    """Create a new account with email and password."""
    # Check if email already taken
    result = await db.execute(select(User).where(User.email == request_body.email))
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An account with this email already exists",
        )

    user = User(
        email=request_body.email,
        name=request_body.name,
        hashed_password=hash_password(request_body.password),
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    logger.info(f"New user signed up: {user.id}")

    access_token = create_access_token(data={"sub": str(user.id)})
    refresh_token = create_refresh_token(data={"sub": str(user.id)})

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        user=UserResponse.model_validate(user),
    )


@router.post("/login", response_model=AuthResponse)
@limiter.limit("10/minute")
async def login(
    request: Request,
    request_body: LoginRequest,
    db: AsyncSession = Depends(get_db)
):
    """Login with email and password."""
    result = await db.execute(select(User).where(User.email == request_body.email))
    user = result.scalar_one_or_none()

    # Account lockout check
    if user and user.locked_until and user.locked_until > datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    # Always call verify_password (even for unknown users) to prevent timing attacks
    hash_to_check = user.hashed_password if (user and user.hashed_password) else _DUMMY_HASH
    password_valid = verify_password(request_body.password, hash_to_check)
    # Extra guard: unknown user or no password is still a failure
    password_valid = password_valid and user is not None and user.hashed_password is not None

    if not password_valid:
        if user:
            user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
            if user.failed_login_attempts >= 5:
                user.locked_until = datetime.utcnow() + timedelta(minutes=30)
                user.failed_login_attempts = 0
            await db.commit()
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    # Reset failed attempts on success
    user.failed_login_attempts = 0
    user.locked_until = None
    await db.commit()

    logger.info(f"User logged in: {user.id}")

    access_token = create_access_token(data={"sub": str(user.id)})
    refresh_token = create_refresh_token(data={"sub": str(user.id)})

    return AuthResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        user=UserResponse.model_validate(user),
    )
