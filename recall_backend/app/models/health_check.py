"""
Knowledge health check models.
Tracks proactive intelligence insights: gaps, staleness, contradictions,
trends, and suggestions surfaced by periodic analysis.
"""
from sqlalchemy import Column, String, DateTime, Boolean, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime
from enum import Enum
from app.db.session import Base


class HealthCheckType(str, Enum):
    """Type of health check insight."""
    gap = "gap"                  # Entity with shallow wiki page
    stale = "stale"              # Wiki page not recompiled recently
    contradiction = "contradiction"  # Unresolved contradictions
    trend = "trend"              # Entity with accelerating mentions
    suggestion = "suggestion"    # AI-generated suggestion


class HealthCheckPriority(str, Enum):
    """Priority level of a health check."""
    high = "high"
    medium = "medium"
    low = "low"


class KnowledgeHealthCheck(Base):
    """A proactive intelligence insight about the user's knowledge base."""
    __tablename__ = "knowledge_health_checks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    check_type = Column(String(30), nullable=False, index=True)
    title = Column(String(300), nullable=False)
    description = Column(Text, nullable=True)
    priority = Column(String(10), default="medium", nullable=False)

    # Optional links to related items
    related_entity_id = Column(
        UUID(as_uuid=True),
        ForeignKey("entities.id", ondelete="SET NULL"),
        nullable=True
    )
    related_wiki_page_id = Column(
        UUID(as_uuid=True),
        ForeignKey("wiki_pages.id", ondelete="SET NULL"),
        nullable=True
    )

    is_dismissed = Column(Boolean, default=False, nullable=False)
    is_acted_on = Column(Boolean, default=False, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    related_entity = relationship("Entity", foreign_keys=[related_entity_id])
    related_wiki_page = relationship("WikiPage", foreign_keys=[related_wiki_page_id])

    def __repr__(self):
        return f"<KnowledgeHealthCheck(type={self.check_type}, title='{self.title}')>"
