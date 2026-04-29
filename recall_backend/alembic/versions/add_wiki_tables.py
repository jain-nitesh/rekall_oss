"""Add wiki tables for LLM Wiki knowledge compilation.

Revision ID: wiki_001
Revises: entities_001
Create Date: 2026-04-07

Creates wiki_pages, wiki_backlinks, and wiki_contradictions tables
for the AI-compiled knowledge layer (Second Brain Phase 2).
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = 'wiki_001'
down_revision: Union[str, None] = 'entities_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # === Create wiki_pages table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS wiki_pages (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            entity_id UUID REFERENCES entities(id) ON DELETE SET NULL,
            cluster_id UUID REFERENCES connection_clusters(id) ON DELETE SET NULL,
            title VARCHAR(300) NOT NULL,
            slug VARCHAR(300) NOT NULL,
            content_markdown TEXT,
            content_embedding vector(1536),
            source_count INTEGER DEFAULT 0,
            confidence_score FLOAT DEFAULT 0.0,
            status VARCHAR(20) NOT NULL DEFAULT 'draft',
            last_compiled_at TIMESTAMP,
            created_at TIMESTAMP NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW(),
            CONSTRAINT uq_wiki_page_slug UNIQUE (user_id, slug)
        );
    """)

    op.execute("CREATE INDEX IF NOT EXISTS ix_wiki_pages_user_id ON wiki_pages(user_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_wiki_pages_entity_id ON wiki_pages(entity_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_wiki_pages_cluster_id ON wiki_pages(cluster_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_wiki_pages_status ON wiki_pages(status);")
    op.execute("""
        CREATE INDEX IF NOT EXISTS idx_wiki_pages_embedding
        ON wiki_pages USING hnsw (content_embedding vector_cosine_ops)
        WITH (m=16, ef_construction=64);
    """)

    # === Create wiki_backlinks table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS wiki_backlinks (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            wiki_page_id UUID NOT NULL REFERENCES wiki_pages(id) ON DELETE CASCADE,
            source_type VARCHAR(20) NOT NULL,
            source_id UUID NOT NULL,
            context_snippet TEXT,
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
    """)

    op.execute("CREATE INDEX IF NOT EXISTS ix_wiki_backlinks_page_id ON wiki_backlinks(wiki_page_id);")
    op.execute("CREATE INDEX IF NOT EXISTS ix_wiki_backlinks_source ON wiki_backlinks(source_type, source_id);")

    # === Create wiki_contradictions table ===
    op.execute("""
        CREATE TABLE IF NOT EXISTS wiki_contradictions (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            wiki_page_id UUID NOT NULL REFERENCES wiki_pages(id) ON DELETE CASCADE,
            claim_a TEXT NOT NULL,
            source_a_id UUID REFERENCES content_items(id) ON DELETE SET NULL,
            claim_b TEXT NOT NULL,
            source_b_id UUID REFERENCES content_items(id) ON DELETE SET NULL,
            resolution TEXT,
            status VARCHAR(20) NOT NULL DEFAULT 'open',
            created_at TIMESTAMP NOT NULL DEFAULT NOW()
        );
    """)

    op.execute("CREATE INDEX IF NOT EXISTS ix_wiki_contradictions_page_id ON wiki_contradictions(wiki_page_id);")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS wiki_contradictions;")
    op.execute("DROP TABLE IF EXISTS wiki_backlinks;")
    op.execute("DROP TABLE IF EXISTS wiki_pages;")
