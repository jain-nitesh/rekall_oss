"""
Content connection model.
Represents AI-discovered connections between content items.
"""
from sqlalchemy import Column, String, DateTime, Boolean, Float, Text, ForeignKey, Integer
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime
from app.db.session import Base


class ContentConnection(Base):
    """
    Represents a semantic connection between two content items.

    Discovered automatically when new content is saved - the system
    finds similar items in the user's library using vector similarity.
    """
    __tablename__ = "content_connections"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    source_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    target_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    similarity_score = Column(Float, nullable=False)
    connection_type = Column(String(50), nullable=False, default='semantic')
    ai_explanation = Column(Text, nullable=True)
    is_dismissed = Column(Boolean, default=False, nullable=False)
    explored_at = Column(DateTime, nullable=True)
    explored_count = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    source_item = relationship("ContentItem", foreign_keys=[source_item_id])
    target_item = relationship("ContentItem", foreign_keys=[target_item_id])

    def __repr__(self):
        return f"<ContentConnection(id={self.id}, score={self.similarity_score:.2f})>"
