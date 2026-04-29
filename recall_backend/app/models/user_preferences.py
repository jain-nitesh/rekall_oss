"""
User preferences database model.
"""
from sqlalchemy import Column, String, Boolean, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
import uuid

from app.db.session import Base


class UserPreferences(Base):
    """User preferences table for storing user-specific settings"""
    __tablename__ = "user_preferences"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    summary_style = Column(String(50), nullable=False, server_default="bullet_points")  # bullet_points, paragraph, concise
    auto_categorize = Column(Boolean, nullable=False, server_default="true")
    connected_sources = Column(JSONB, nullable=True)  # ["twitter", "reddit", etc.]
    daily_gems_enabled = Column(Boolean, nullable=False, server_default="false")
    daily_gems_time = Column(String(20), nullable=False, server_default="9:00 AM")

    # Self-entity: links to the Entity representing the user themselves
    self_entity_id = Column(UUID(as_uuid=True), ForeignKey("entities.id", ondelete="SET NULL"), nullable=True)
    self_entity_last_refreshed_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, nullable=False, server_default=func.now())
    updated_at = Column(DateTime, nullable=True, server_default=func.now(), onupdate=func.now())

    # Relationships
    self_entity = relationship("Entity", foreign_keys=[self_entity_id])
