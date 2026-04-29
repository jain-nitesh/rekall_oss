"""
Wiki database models.
Represents AI-compiled knowledge pages that synthesize information
across multiple content items — the core of the LLM Wiki pattern.

Wiki pages are:
- Auto-created when an entity reaches 3+ mentions
- Auto-marked stale when new content references their entity
- Periodically recompiled by the background processor
- Searchable via their own embedding vector
"""
from sqlalchemy import Column, String, DateTime, Integer, Float, Text, Boolean, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from pgvector.sqlalchemy import Vector
import uuid
from datetime import datetime
from enum import Enum
from app.db.session import Base


class WikiPageStatus(str, Enum):
    """Status of a wiki page."""
    draft = "draft"          # Being compiled for the first time
    published = "published"  # Compiled and ready to read
    stale = "stale"          # Needs recompilation (new content arrived)


class ContradictionStatus(str, Enum):
    """Status of a detected contradiction."""
    open = "open"          # Unresolved contradiction
    resolved = "resolved"  # User or AI resolved it
    dismissed = "dismissed"  # User dismissed it as non-issue


class WikiPage(Base):
    """
    An AI-compiled knowledge page that synthesizes information
    from multiple content items about an entity or topic.

    Following the LLM Wiki pattern: "a compiled memory layer
    where queries compound instead of disappearing."
    """
    __tablename__ = "wiki_pages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Link to entity (optional — most wiki pages are entity-based)
    entity_id = Column(
        UUID(as_uuid=True),
        ForeignKey("entities.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )

    # Link to cluster (optional — some wiki pages are cluster-based)
    cluster_id = Column(
        UUID(as_uuid=True),
        ForeignKey("connection_clusters.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )

    title = Column(String(300), nullable=False)
    slug = Column(String(300), nullable=False)

    # AI-compiled markdown content with source citations
    content_markdown = Column(Text, nullable=True)

    # Embedding for semantic search across wiki pages
    content_embedding = Column(Vector(1536), nullable=True)

    # How many content items were synthesized into this page
    source_count = Column(Integer, default=0)

    # Overall confidence in the compiled knowledge (0.0 - 1.0)
    confidence_score = Column(Float, default=0.0)

    # Incremental patching tracking
    patch_count = Column(Integer, default=0, server_default='0', nullable=False)
    compilation_mode = Column(String(20), default='full', server_default='full', nullable=False)

    # Page status
    status = Column(String(20), default="draft", nullable=False, index=True)

    last_compiled_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint('user_id', 'slug', name='uq_wiki_page_slug'),
    )

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    entity = relationship("Entity", foreign_keys=[entity_id])
    backlinks = relationship("WikiBacklink", back_populates="wiki_page", cascade="all, delete-orphan")
    contradictions = relationship("WikiContradiction", back_populates="wiki_page", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<WikiPage(id={self.id}, title='{self.title}', status={self.status})>"


class WikiBacklink(Base):
    """
    Tracks cross-references: which content items or other wiki pages
    are sources for or referenced by a wiki page.
    """
    __tablename__ = "wiki_backlinks"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    wiki_page_id = Column(
        UUID(as_uuid=True),
        ForeignKey("wiki_pages.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # What kind of source: 'content_item' or 'wiki_page'
    source_type = Column(String(20), nullable=False)

    # ID of the source (content_item.id or another wiki_page.id)
    source_id = Column(UUID(as_uuid=True), nullable=False, index=True)

    # The passage that creates the backlink
    context_snippet = Column(Text, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    wiki_page = relationship("WikiPage", back_populates="backlinks")

    def __repr__(self):
        return f"<WikiBacklink(page={self.wiki_page_id}, source={self.source_type}:{self.source_id})>"


class WikiContradiction(Base):
    """
    Tracks conflicting claims detected across different sources
    during wiki page compilation.
    """
    __tablename__ = "wiki_contradictions"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    wiki_page_id = Column(
        UUID(as_uuid=True),
        ForeignKey("wiki_pages.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    claim_a = Column(Text, nullable=False)
    source_a_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="SET NULL"),
        nullable=True
    )

    claim_b = Column(Text, nullable=False)
    source_b_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="SET NULL"),
        nullable=True
    )

    # User or AI resolution
    resolution = Column(Text, nullable=True)
    status = Column(String(20), default="open", nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    wiki_page = relationship("WikiPage", back_populates="contradictions")

    def __repr__(self):
        return f"<WikiContradiction(page={self.wiki_page_id}, status={self.status})>"
