"""
Alembic environment configuration.

For beginners:
- Alembic is like Git for databases - it tracks changes to database schema
- This file tells Alembic how to connect to the database and what models exist
- We use async mode because our SQLAlchemy setup is async
"""
import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

# Import our settings and database base
from app.core.config import settings
from app.db.session import Base

# Import all models so Alembic can detect schema changes
# IMPORTANT: Add new models here when you create them!
from app.models.user import User  # noqa: F401
from app.models.content_item import ContentItem  # noqa: F401

# this is the Alembic Config object, which provides
# access to the values within the .ini file in use.
config = context.config

# Override sqlalchemy.url with our settings
# This allows us to use the DATABASE_URL from .env instead of hardcoding it
config.set_main_option("sqlalchemy.url", settings.database_url)

# Interpret the config file for Python logging.
# This line sets up loggers basically.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Set target metadata for 'autogenerate' support
# This tells Alembic which models to track
# Base.metadata contains all table definitions from our models
target_metadata = Base.metadata

# other values from the config, defined by the needs of env.py,
# can be acquired:
# my_important_option = config.get_main_option("my_important_option")
# ... etc.


def run_migrations_offline() -> None:
    """
    Run migrations in 'offline' mode.

    This generates SQL scripts without connecting to database.
    Useful for:
    - Generating migration SQL for DBAs to review
    - Running migrations on production (no direct DB access)

    The SQL is printed to stdout or saved to a file.
    """
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    """
    Helper function to run migrations with a connection.

    This is called by run_migrations_online() after establishing connection.
    """
    context.configure(connection=connection, target_metadata=target_metadata)

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    """
    Run migrations in async mode.

    This is necessary because we're using async SQLAlchemy (asyncpg driver).

    How it works:
    1. Create async engine from alembic.ini config
    2. Connect to database asynchronously
    3. Run migrations within the connection
    4. Close connection

    Why async?
    - Our app uses async/await for database operations
    - Alembic needs to use the same engine type for compatibility
    """
    # Create async engine
    # We need to replace postgresql:// with postgresql+asyncpg://
    configuration = config.get_section(config.config_ini_section, {})
    configuration["sqlalchemy.url"] = settings.database_url.replace(
        'postgresql://', 'postgresql+asyncpg://'
    )

    connectable = async_engine_from_config(
        configuration,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,  # Don't use connection pooling for migrations
    )

    # Connect and run migrations
    async with connectable.connect() as connection:
        # run_sync() executes synchronous code within async context
        # Alembic's migration code is synchronous, so we wrap it
        await connection.run_sync(do_run_migrations)

    # Clean up
    await connectable.dispose()


def run_migrations_online() -> None:
    """
    Run migrations in 'online' mode.

    This actually connects to the database and applies migrations.

    We use asyncio.run() to run the async migration function.
    """
    asyncio.run(run_async_migrations())


# Determine which mode to use
if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
