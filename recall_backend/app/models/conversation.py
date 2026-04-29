"""
Conversation database models.
Represents chat sessions where users can "talk to their memory"
using multi-source RAG (content items + entities + wiki pages).
"""
from sqlalchemy import Column, String, DateTime, Integer, Text, ForeignKey
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from pgvector.sqlalchemy import Vector
import uuid
from datetime import datetime
from enum import Enum
from app.db.session import Base


class MessageRole(str, Enum):
    """Role of a conversation message."""
    user = "user"
    assistant = "assistant"


class Conversation(Base):
    """A chat session where the user queries their memory."""
    __tablename__ = "conversations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    title = Column(String(300), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    user = relationship("User", foreign_keys=[user_id])
    messages = relationship("ConversationMessage", back_populates="conversation",
                            cascade="all, delete-orphan", order_by="ConversationMessage.created_at")

    def __repr__(self):
        return f"<Conversation(id={self.id}, title='{self.title}')>"


class ConversationMessage(Base):
    """An individual message in a conversation."""
    __tablename__ = "conversation_messages"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id = Column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    role = Column(String(20), nullable=False)  # 'user' or 'assistant'
    content = Column(Text, nullable=False)

    # References to sources cited in this message
    referenced_items = Column(JSONB, default=list)       # [{id, title, type}]
    referenced_wiki_pages = Column(JSONB, default=list)  # [{id, title, slug}]

    # Embedding for conversation context continuity
    context_embedding = Column(Vector(1536), nullable=True)

    token_count = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    conversation = relationship("Conversation", back_populates="messages")

    def __repr__(self):
        return f"<ConversationMessage(id={self.id}, role={self.role})>"
