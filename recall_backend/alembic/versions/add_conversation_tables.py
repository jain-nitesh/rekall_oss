"""Add conversation tables for RAG chat.

Revision ID: conversations_001
Revises: wiki_001
Create Date: 2026-04-07

Creates conversations and conversation_messages tables
for the conversational memory feature (Second Brain Phase 3).
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = 'conversations_001'
down_revision: Union[str, None] = 'wiki_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # === Create conversations table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS conversations (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            title VARCHAR(300),
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        );
    """)

    op.execute("CREATE INDEX IF NOT EXISTS ix_conversations_user_id ON conversations(user_id);")

    # === Create conversation_messages table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS conversation_messages (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
            role VARCHAR(20) NOT NULL,
            content TEXT NOT NULL,
            referenced_items JSONB DEFAULT '[]'::jsonb,
            referenced_wiki_pages JSONB DEFAULT '[]'::jsonb,
            context_embedding vector(1536),
            token_count INTEGER,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
    """)

    op.execute("CREATE INDEX IF NOT EXISTS ix_conversation_messages_conv_id ON conversation_messages(conversation_id);")
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_conversation_messages_embedding
        ON conversation_messages USING hnsw (context_embedding vector_cosine_ops)
        WITH (m=16, ef_construction=64);
    """)


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS conversation_messages;")
    op.execute("DROP TABLE IF EXISTS conversations;")
