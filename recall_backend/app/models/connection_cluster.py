"""
Connection cluster models.
Represents groups of semantically related content items discovered through connections.
"""
from sqlalchemy import Column, String, DateTime, Boolean, Float, Text, Integer, ForeignKey, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime
from app.db.session import Base


class ConnectionCluster(Base):
    """
    Represents a cluster of semantically related content items.

    Clusters are built by analyzing the connection graph - groups of items
    that are densely connected to each other form a cluster with an
    AI-generated theme label.
    """
    __tablename__ = "connection_clusters"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    label = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    item_count = Column(Integer, default=0)
    avg_similarity = Column(Float, nullable=True)
    is_stale = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    items = relationship("ConnectionClusterItem", back_populates="cluster", cascade="all, delete-orphan")

    def __repr__(self):
        return f"<ConnectionCluster(id={self.id}, label='{self.label}', items={self.item_count})>"


class ConnectionClusterItem(Base):
    """
    Join table linking clusters to content items.
    """
    __tablename__ = "connection_cluster_items"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    cluster_id = Column(
        UUID(as_uuid=True),
        ForeignKey("connection_clusters.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    content_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    __table_args__ = (
        UniqueConstraint('cluster_id', 'content_item_id', name='uq_cluster_item'),
    )

    # Relationships
    cluster = relationship("ConnectionCluster", back_populates="items")
    content_item = relationship("ContentItem", foreign_keys=[content_item_id])

    def __repr__(self):
        return f"<ConnectionClusterItem(cluster={self.cluster_id}, item={self.content_item_id})>"
