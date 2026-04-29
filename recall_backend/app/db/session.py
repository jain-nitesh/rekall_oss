"""
Database session configuration.
This file handles SQLAlchemy async engine and session creation.

For beginners:
- SQLAlchemy is an ORM (Object-Relational Mapping) tool that lets us work with database tables as Python classes
- Async means operations don't block the server - it can handle other requests while waiting for database
- Session is like a "workspace" - changes are tracked and saved together (transactional)
"""
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from app.core.config import settings

# Convert postgresql:// to postgresql+asyncpg:// for async support
# asyncpg is a fast PostgreSQL driver that supports async/await
DATABASE_URL = settings.database_url.replace('postgresql://', 'postgresql+asyncpg://')

# Create async engine with connection pooling
# What is connection pooling? Instead of opening a new database connection for each request,
# we keep a "pool" of reusable connections. This is much faster!
#
# Parameters explained:
# - echo: Log all SQL queries when debug=True (helpful for learning!)
# - pool_size: Number of persistent connections (20 is good for small-medium apps)
# - max_overflow: Additional connections that can be created when pool is full
# - pool_pre_ping: Verify connections are alive before using (prevents stale connections)
engine = create_async_engine(
    DATABASE_URL,
    echo=settings.debug,  # Log SQL queries in debug mode
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
)

# Create session factory
# This is a "factory" that creates new sessions for each request
#
# Parameters explained:
# - expire_on_commit=False: Keep objects usable after commit (otherwise they'd be "expired")
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

# Base class for all SQLAlchemy models
# All our database models (User, ContentItem, etc.) will inherit from this
Base = declarative_base()

from contextlib import asynccontextmanager

@asynccontextmanager
async def get_db_context():
    """Async context manager for use outside of FastAPI dependency injection."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()


# Dependency for FastAPI routes
# This creates a new database session for each request and closes it afterward
# Think of it as: "Give me a database workspace for this request, then clean up when done"
async def get_db():
    """
    Dependency that provides database session to route handlers.

    Usage in routes:
        @router.get("/users")
        async def get_users(db: AsyncSession = Depends(get_db)):
            # db is now a database session you can use
            result = await db.execute(select(User))
            return result.scalars().all()

    Why use a dependency?
    FastAPI automatically calls this function for each request, passes the session
    to your route, and guarantees cleanup even if an error occurs.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session  # Provide session to route
        finally:
            await session.close()  # Always close session when done
