"""
Magic link token database model.

Stores temporary tokens for passwordless authentication.
"""
from sqlalchemy import Column, String, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from datetime import datetime, timedelta
import uuid
from app.db.session import Base
from app.core.config import settings


class MagicLinkToken(Base):
    """
    Magic link token model for passwordless authentication.

    Tokens are single-use and expire after 15 minutes.
    """
    __tablename__ = "magic_link_tokens"

    # Primary key
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # User ID (nullable for new signups)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
        index=True
    )

    # Email address (required)
    email = Column(String(255), nullable=False, index=True)

    # Token string (unique, indexed for fast lookups)
    token = Column(String(255), unique=True, nullable=False, index=True)

    # Expiration timestamp
    expires_at = Column(DateTime, nullable=False)

    # Timestamp when token was used (null if not used yet)
    used_at = Column(DateTime, nullable=True)

    # Creation timestamp
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationship to user (optional)
    user = relationship("User", back_populates="magic_link_tokens")

    def is_expired(self) -> bool:
        """Check if token has expired."""
        return datetime.utcnow() > self.expires_at

    def is_used(self) -> bool:
        """Check if token has been used."""
        return self.used_at is not None

    def is_valid(self) -> bool:
        """Check if token is valid (not expired and not used)."""
        return not self.is_expired() and not self.is_used()

    @staticmethod
    def create_expires_at() -> datetime:
        """Create expiration timestamp (15 minutes from now)."""
        return datetime.utcnow() + timedelta(minutes=15)

    def __repr__(self):
        """String representation for debugging."""
        return f"<MagicLinkToken(id={self.id}, email={self.email}, expires_at={self.expires_at})>"

