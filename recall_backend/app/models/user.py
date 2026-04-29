"""
User database model.
Represents the 'users' table in PostgreSQL.

For beginners:
- This class defines the structure of our users table
- Each class attribute becomes a column in the database
- SQLAlchemy handles the conversion between Python objects and database rows
"""
from sqlalchemy import Column, String, DateTime, Boolean, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime
from app.db.session import Base


class User(Base):
    """
    User account model.

    This represents a user in the ReKall system. Each user has:
    - A unique ID (UUID)
    - Email and password for authentication
    - Profile information (name, avatar)
    - Account status (active/inactive)
    - Timestamps for when they joined and last updated

    Why use this instead of a regular Python class?
    SQLAlchemy automatically:
    - Creates the database table
    - Converts between Python objects and database rows
    - Handles queries (finding users, updating, deleting)
    """
    __tablename__ = "users"

    # Primary key: UUID (Universally Unique Identifier)
    # What is a UUID? It's a 128-bit number like: 550e8400-e29b-41d4-a716-446655440000
    # Why use UUID instead of integer IDs?
    # 1. Globally unique (can merge databases without ID conflicts)
    # 2. Not sequential (harder for attackers to guess user IDs)
    # 3. Can be generated client-side (useful for distributed systems)
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Email with unique constraint
    # unique=True: No two users can have the same email
    # nullable=False: Email is required
    # index=True: Creates a database index for fast lookups (important for login!)
    #
    # What is an index? Think of it like a book index - instead of scanning every page,
    # you can jump directly to the right location. Critical for login performance!
    email = Column(String(255), unique=True, nullable=False, index=True)

    # Google OAuth user ID
    # Stores the unique Google user identifier (sub claim from Google ID token)
    # unique=True: One Google account can only link to one ReCall account
    # nullable=True: Users can sign up without Google (existing users)
    # index=True: Fast lookups during Google OAuth login
    google_id = Column(String(255), unique=True, nullable=True, index=True)

    # Apple Sign-In user ID
    # Stores the unique Apple user identifier (sub claim from Apple identity token)
    # unique=True: One Apple account can only link to one ReCall account
    # nullable=True: Users can sign up without Apple
    # index=True: Fast lookups during Apple Sign-In login
    apple_id = Column(String(255), unique=True, nullable=True, index=True)

    # User's display name
    # String(255) means max 255 characters
    name = Column(String(255), nullable=False)

    # Hashed password (NEVER store plain text passwords!)
    # Security rule: Always hash passwords before storing
    # We'll use passlib with bcrypt to hash passwords (very secure!)
    #
    # Example: "mypassword123" → "$2b$12$KIXxLj3..." (60 char hash)
    # Even if database is compromised, attackers can't recover passwords
    # nullable=True: Users can sign up with magic link only (no password)
    hashed_password = Column(String(255), nullable=True)

    # Optional avatar URL
    # nullable=True means this field is optional
    # Will store URL to user's profile picture
    avatar_url = Column(String(512), nullable=True)

    # Account status
    # Allows us to disable accounts without deleting them
    # Useful for: banned users, subscription expiry, etc.
    # default=True means new users are active by default
    is_active = Column(Boolean, default=True)

    # Security: Account lockout fields
    # Track failed login attempts to prevent brute force attacks
    # After 5 failed attempts, account is temporarily locked for 30 minutes
    failed_login_attempts = Column(Integer, default=0, nullable=False)
    locked_until = Column(DateTime, nullable=True)

    # Timestamps
    # created_at: When the account was created (never changes)
    # updated_at: Last time the account was modified (auto-updates)
    #
    # datetime.utcnow: Use UTC time (Universal Time) for consistency
    # Why UTC? Avoids timezone confusion - convert to local time in the app
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    # This creates a "one-to-many" relationship: one user has many content items
    # back_populates: Creates reverse relationship (content.user)
    # cascade: When user is deleted, delete their content too
    content_items = relationship("ContentItem", back_populates="user", cascade="all, delete-orphan")

    # User-created categories (one-to-many relationship)
    # Keep categories tied to their user and clean them up if the user is deleted
    user_categories = relationship(
        "UserCategory",
        back_populates="user",
        cascade="all, delete-orphan"
    )

    # Notification settings (one-to-one relationship)
    # uselist=False: Only one settings object per user
    notification_settings = relationship(
        "UserNotificationSettings",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan"
    )

    # User devices (one-to-many relationship)
    # One user can have multiple devices (iPhone + iPad + Android)
    devices = relationship(
        "UserDevice",
        back_populates="user",
        cascade="all, delete-orphan"
    )

    # Notification history (one-to-many relationship)
    # Track all notifications sent to this user
    notification_history = relationship(
        "NotificationHistory",
        back_populates="user",
        cascade="all, delete-orphan"
    )

    # Magic link tokens (one-to-many relationship)
    # Users can have multiple magic link tokens (for different devices/sessions)
    magic_link_tokens = relationship(
        "MagicLinkToken",
        back_populates="user",
        cascade="all, delete-orphan"
    )

    def __repr__(self):
        """String representation for debugging"""
        return f"<User(id={self.id}, email={self.email}, name={self.name})>"
