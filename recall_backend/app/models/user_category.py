"""
User category database model.

Represents user-created categories for organizing content.
"""
from sqlalchemy import Column, String, DateTime, ForeignKey, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime
from app.db.session import Base


class UserCategory(Base):
    """
    User-created category model.

    Allows users to create custom categories for organizing their content.
    Categories are user-specific and can be assigned to content items.
    """
    __tablename__ = "user_categories"

    # Primary key
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Foreign key to user
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Category name (e.g., "Machine Learning", "Design Inspiration")
    name = Column(String(100), nullable=False)

    # Optional description
    description = Column(String(500), nullable=True)

    # Color for UI display (hex color code, e.g., "#FF5733")
    color = Column(String(7), nullable=True, default="#6366F1")

    # Usage count (how many content items use this category)
    usage_count = Column(Integer, default=0, nullable=False)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationship to user
    user = relationship("User", back_populates="user_categories")

    def __repr__(self):
        """String representation for debugging."""
        return f"<UserCategory(id={self.id}, name={self.name}, user_id={self.user_id})>"

