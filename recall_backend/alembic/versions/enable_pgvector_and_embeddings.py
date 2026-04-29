"""Enable pgvector extension and add embedding columns to content_items

Revision ID: pgvector_embeddings_001
Revises: afdf7052e9ba
Create Date: 2026-03-06

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'pgvector_embeddings_001'
down_revision: Union[str, None] = 'afdf7052e9ba'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enable pgvector extension
    op.execute('CREATE EXTENSION IF NOT EXISTS vector')

    # Add embedding column (1536 dims - OpenAI native, Ollama zero-padded)
    op.execute('ALTER TABLE content_items ADD COLUMN IF NOT EXISTS embedding vector(1536)')

    # Add extracted_content column for storing full text
    op.add_column('content_items',
        sa.Column('extracted_content', sa.Text(), nullable=True)
    )

    # Add embedding_model column to track which model generated the embedding
    op.add_column('content_items',
        sa.Column('embedding_model', sa.String(50), nullable=True)
    )

    # Create HNSW index for fast cosine similarity search
    op.execute(
        'CREATE INDEX IF NOT EXISTS idx_content_items_embedding '
        'ON content_items USING hnsw (embedding vector_cosine_ops) '
        'WITH (m=16, ef_construction=64)'
    )


def downgrade() -> None:
    op.execute('DROP INDEX IF EXISTS idx_content_items_embedding')
    op.drop_column('content_items', 'embedding_model')
    op.drop_column('content_items', 'extracted_content')
    op.execute('ALTER TABLE content_items DROP COLUMN IF EXISTS embedding')
    op.execute('DROP EXTENSION IF EXISTS vector')
