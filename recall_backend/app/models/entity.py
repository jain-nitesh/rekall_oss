"""
Entity database model.
Represents named entities (people, companies, technologies, concepts, etc.)
extracted from content items to form the knowledge graph.

Part of the Second Brain / Memory Graph feature:
- Entities are first-class nodes in the knowledge graph
- Each entity aggregates knowledge across multiple content items
- Entities have embeddings for semantic similarity search
- Entity relationships form typed edges in the graph
"""
from sqlalchemy import Column, String, DateTime, Integer, Float, Text, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from pgvector.sqlalchemy import Vector
import uuid
from datetime import datetime
from enum import Enum
from app.db.session import Base


class EntityType(str, Enum):
    """
    Type of named entity extracted from content.
    """
    person = "person"
    company = "company"
    technology = "technology"
    concept = "concept"
    topic = "topic"
    place = "place"
    event = "event"


class EntityExtractionStatus(str, Enum):
    """
    Entity extraction status (Phase 3 of processing pipeline).

    Flow: pending -> processing -> completed (or failed)

    Phase 3 runs after AI processing (Phase 2) completes.
    It extracts named entities and relationships from content.
    """
    pending = "pending"
    processing = "processing"
    completed = "completed"
    failed = "failed"


class Entity(Base):
    """
    A named entity extracted from content items.

    Entities are the core nodes of the knowledge graph. They represent
    people, companies, technologies, concepts, topics, places, and events
    that appear across the user's saved content.

    Each entity:
    - Has an embedding for semantic similarity
    - Tracks how many content items mention it
    - Has an AI-compiled description
    - Can have aliases (e.g., "OpenAI" and "Open AI")
    - Links to other entities via EntityRelationship
    """
    __tablename__ = "entities"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Canonical name of the entity
    name = Column(String(300), nullable=False)

    # Entity type classification
    entity_type = Column(String(50), nullable=False, index=True)

    # Alternative names/spellings (e.g., ["OpenAI", "Open AI", "openai"])
    aliases = Column(JSONB, default=list)

    # AI-compiled description synthesizing knowledge from all mentions
    description = Column(Text, nullable=True)

    # Embedding for semantic similarity search (same 1536-dim space as content)
    embedding = Column(Vector(1536), nullable=True)

    # Temporal tracking
    first_seen_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    last_seen_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    # How many content items mention this entity
    mention_count = Column(Integer, default=0)

    # Average extraction confidence across all mentions
    confidence = Column(Float, default=0.0)

    # Type-specific metadata (e.g., company: {industry, founded}, person: {role, org})
    entity_metadata = Column("metadata", JSONB, default=dict)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint('user_id', 'name', 'entity_type', name='uq_user_entity_name_type'),
    )

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    content_links = relationship("ContentEntity", back_populates="entity", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<Entity(id={self.id}, name='{self.name}', type={self.entity_type}, mentions={self.mention_count})>"


class ContentEntity(Base):
    """
    Junction table linking content items to extracted entities.

    Tracks which entities were found in which content items, along with
    relevance scoring and the specific context where the entity was mentioned.
    """
    __tablename__ = "content_entities"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    content_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    entity_id = Column(
        UUID(as_uuid=True),
        ForeignKey("entities.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # How central is this entity to the content (0.0 = barely mentioned, 1.0 = main subject)
    relevance_score = Column(Float, nullable=False, default=0.5)

    # The passage/sentence where the entity was mentioned
    context_snippet = Column(Text, nullable=True)

    # NER extraction confidence for this specific mention
    extraction_confidence = Column(Float, nullable=False, default=0.8)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint('content_item_id', 'entity_id', name='uq_content_entity'),
    )

    # Relationships
    content_item = relationship("ContentItem", foreign_keys=[content_item_id])
    entity = relationship("Entity", back_populates="content_links", foreign_keys=[entity_id])

    def __repr__(self):
        return f"<ContentEntity(content={self.content_item_id}, entity={self.entity_id}, relevance={self.relevance_score:.2f})>"


class EntityRelationship(Base):
    """
    Typed relationship between two entities.

    Unlike ContentConnection (which links content-to-content by embedding similarity),
    EntityRelationship represents semantic relationships between entities:
    - "works_at", "founded_by", "competes_with", "built_with", "part_of", "influences", etc.

    These are discovered by the AI during entity extraction and strengthened
    as more content items provide evidence for the relationship.
    """
    __tablename__ = "entity_relationships"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    source_entity_id = Column(
        UUID(as_uuid=True),
        ForeignKey("entities.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    target_entity_id = Column(
        UUID(as_uuid=True),
        ForeignKey("entities.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Relationship type (e.g., "works_at", "competes_with", "built_with")
    relationship_type = Column(String(100), nullable=False)

    # AI-generated explanation of the relationship
    description = Column(Text, nullable=True)

    # Relationship strength (0.0 = weak, 1.0 = strong)
    strength = Column(Float, default=0.5)

    # How many content items provide evidence for this relationship
    evidence_count = Column(Integer, default=1)

    # Temporal tracking
    first_seen_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_seen_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    __table_args__ = (
        UniqueConstraint(
            'user_id', 'source_entity_id', 'target_entity_id', 'relationship_type',
            name='uq_entity_relationship'
        ),
    )

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    source_entity = relationship("Entity", foreign_keys=[source_entity_id])
    target_entity = relationship("Entity", foreign_keys=[target_entity_id])

    def __repr__(self):
        return f"<EntityRelationship(source={self.source_entity_id}, type='{self.relationship_type}', target={self.target_entity_id})>"
