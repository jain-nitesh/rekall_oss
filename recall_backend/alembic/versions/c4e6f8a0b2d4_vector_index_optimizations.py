"""vector_index_optimizations

Revision ID: c4e6f8a0b2d4
Revises: b3d5e7f9a1c3
Create Date: 2026-04-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c4e6f8a0b2d4'
down_revision: Union[str, None] = 'b3d5e7f9a1c3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Vector index optimizations:
    1. Rebuild HNSW indexes with ef_construction=128 for better recall
    2. Add user-scoped partial index for faster filtered vector searches
    3. Add embedding_updated_at column for tracking embedding freshness
    """
    # 1. Rebuild content_items HNSW index with better params
    op.execute('DROP INDEX IF EXISTS idx_content_items_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_content_items_embedding_hnsw '
        'ON content_items USING hnsw (embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=128)'
    )

    # Rebuild entities HNSW index
    op.execute('DROP INDEX IF EXISTS idx_entities_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_entities_embedding_hnsw '
        'ON entities USING hnsw (embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=128)'
    )

    # Rebuild wiki_pages HNSW index
    op.execute('DROP INDEX IF EXISTS idx_wiki_pages_content_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_wiki_pages_content_embedding_hnsw '
        'ON wiki_pages USING hnsw (content_embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=128)'
    )

    # Rebuild conversation_messages HNSW index
    op.execute('DROP INDEX IF EXISTS idx_conv_messages_context_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_conv_messages_context_embedding_hnsw '
        'ON conversation_messages USING hnsw (context_embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=128)'
    )

    # 2. Add user-scoped partial index for faster per-user vector searches
    op.execute(
        'CREATE INDEX IF NOT EXISTS idx_content_items_user_embedding_not_null '
        'ON content_items (user_id) '
        'WHERE embedding IS NOT NULL'
    )

    op.execute(
        'CREATE INDEX IF NOT EXISTS idx_entities_user_embedding_not_null '
        'ON entities (user_id) '
        'WHERE embedding IS NOT NULL'
    )

    # 3. Add embedding_updated_at column
    op.add_column(
        'content_items',
        sa.Column('embedding_updated_at', sa.DateTime(), nullable=True)
    )


def downgrade() -> None:
    """Revert vector index optimizations."""
    # Remove embedding_updated_at
    op.drop_column('content_items', 'embedding_updated_at')

    # Remove user-scoped indexes
    op.execute('DROP INDEX IF EXISTS idx_entities_user_embedding_not_null')
    op.execute('DROP INDEX IF EXISTS idx_content_items_user_embedding_not_null')

    # Rebuild HNSW indexes with original params
    op.execute('DROP INDEX IF EXISTS idx_conv_messages_context_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_conv_messages_context_embedding_hnsw '
        'ON conversation_messages USING hnsw (context_embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=64)'
    )

    op.execute('DROP INDEX IF EXISTS idx_wiki_pages_content_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_wiki_pages_content_embedding_hnsw '
        'ON wiki_pages USING hnsw (content_embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=64)'
    )

    op.execute('DROP INDEX IF EXISTS idx_entities_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_entities_embedding_hnsw '
        'ON entities USING hnsw (embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=64)'
    )

    op.execute('DROP INDEX IF EXISTS idx_content_items_embedding_hnsw')
    op.execute(
        'CREATE INDEX idx_content_items_embedding_hnsw '
        'ON content_items USING hnsw (embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=64)'
    )
