"""Add entity tables for knowledge graph.

Revision ID: entities_001
Revises: media_support_001
Create Date: 2026-04-07

Creates the Entity, ContentEntity, and EntityRelationship tables
for the Second Brain / Memory Graph feature. Also adds entity_status
processing column to content_items (Phase 3 of processing pipeline).
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID, JSONB


# revision identifiers, used by Alembic.
revision: str = 'entities_001'
down_revision: Union[str, None] = 'media_support_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # === Create entity_extraction_status enum ===
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'entityextractionstatus') THEN
                CREATE TYPE entityextractionstatus AS ENUM ('pending', 'processing', 'completed', 'failed');
            END IF;
        END $$;
    """)

    # === Create entities table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS entities (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name VARCHAR(300) NOT NULL,
            entity_type VARCHAR(50) NOT NULL,
            aliases JSONB DEFAULT '[]'::jsonb,
            description TEXT,
            embedding vector(1536),
            first_seen_at TIMESTAMP NOT NULL DEFAULT NOW(),
            last_seen_at TIMESTAMP NOT NULL DEFAULT NOW(),
            mention_count INTEGER DEFAULT 0,
            confidence FLOAT DEFAULT 0.0,
            metadata JSONB DEFAULT '{}'::jsonb,
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW(),
            CONSTRAINT uq_user_entity_name_type UNIQUE (user_id, name, entity_type)
        );
    """)

    # Indexes for entities
    op.execute("CREATE INDEX IF NOT EXISTS ix_entities_user_id ON entities(user_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_entities_entity_type ON entities(entity_type);")
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_entities_embedding
        ON entities USING hnsw (embedding vector_cosine_ops)
        WITH (m=16, ef_construction=64);
    """)

    # === Create content_entities junction table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS content_entities (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            content_item_id UUID NOT NULL REFERENCES content_items(id) ON DELETE CASCADE,
            entity_id UUID NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            relevance_score FLOAT NOT NULL DEFAULT 0.5,
            context_snippet TEXT,
            extraction_confidence FLOAT NOT NULL DEFAULT 0.8,
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_content_entity UNIQUE (content_item_id, entity_id)
        );
    """)

    # Indexes for content_entities
    op.execute("CREATE INDEX IF NOT EXISTS ix_content_entities_content_item_id ON content_entities(content_item_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_content_entities_entity_id ON content_entities(entity_id);")

    # === Create entity_relationships table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS entity_relationships (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            source_entity_id UUID NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            target_entity_id UUID NOT NULL REFERENCES entities(id) ON DELETE CASCADE,
            relationship_type VARCHAR(100) NOT NULL,
            description TEXT,
            strength FLOAT DEFAULT 0.5,
            evidence_count INTEGER DEFAULT 1,
            first_seen_at TIMESTAMP NOT NULL DEFAULT NOW(),
            last_seen_at TIMESTAMP NOT NULL DEFAULT NOW(),
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            CONSTRAINT uq_entity_relationship UNIQUE (user_id, source_entity_id, target_entity_id, relationship_type)
        );
    """)

    # Indexes for entity_relationships
    op.execute("CREATE INDEX IF NOT EXISTS ix_entity_relationships_user_id ON entity_relationships(user_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_entity_relationships_source ON entity_relationships(source_entity_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_entity_relationships_target ON entity_relationships(target_entity_id);")

    # === Add entity_status columns to content_items ===
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'content_items' AND column_name = 'entity_status'
            ) THEN
                ALTER TABLE content_items
                    ADD COLUMN entity_status entityextractionstatus NOT NULL DEFAULT 'pending',
                    ADD COLUMN entity_error TEXT,
                    ADD COLUMN entity_attempts INTEGER DEFAULT 0,
                    ADD COLUMN last_entity_processed_at TIMESTAMP;
            END IF;
        END $$;
    """)

    op.execute("CREATE INDEX IF NOT EXISTS ix_content_items_entity_status ON content_items(entity_status);")


def downgrade() -> None:
    # Drop entity_status columns from content_items
    op.execute("""
        ALTER TABLE content_items
            DROP COLUMN IF EXISTS entity_status,
            DROP COLUMN IF EXISTS entity_error,
            DROP COLUMN IF EXISTS entity_attempts,
            DROP COLUMN IF EXISTS last_entity_processed_at;
    """)
    op.execute("DROP INDEX IF EXISTS ix_content_items_entity_status;")

    # Drop tables in reverse dependency order
    op.execute("DROP TABLE IF EXISTS entity_relationships;")
    op.execute("DROP TABLE IF EXISTS content_entities;")
    op.execute("DROP TABLE IF EXISTS entities;")

    # Drop enum
    op.execute("DROP TYPE IF EXISTS entityextractionstatus;")
