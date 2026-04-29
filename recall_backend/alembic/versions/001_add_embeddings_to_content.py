"""Add embedding and extracted_content columns to content_items

Revision ID: 001_add_embeddings
Revises: dbd94275e9bb
Create Date: 2025-12-22 10:00:00.000000

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '001_add_embeddings'
down_revision: Union[str, None] = 'dbd94275e9bb'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Add embedding and extracted_content columns to content_items table.

    NOTE: This migration is currently a no-op because:
    1. pgvector is not installed yet (will be added in future phase)
    2. embedding and extracted_content columns are commented out in the model
    3. These features will be enabled later when pgvector is set up

    This placeholder migration ensures the migration chain remains intact.
    """
    # Skip pgvector setup for now - will be enabled in future phase
    # TODO: Enable when pgvector is installed
    # op.execute('CREATE EXTENSION IF NOT EXISTS vector')
    # op.add_column('content_items', sa.Column('extracted_content', sa.Text(), nullable=True))
    # op.execute('ALTER TABLE content_items ADD COLUMN embedding vector(768)')
    pass


def downgrade() -> None:
    """
    Remove embedding and extracted_content columns.

    NOTE: Currently a no-op since upgrade is also a no-op.
    """
    # TODO: Enable when pgvector columns are added
    # op.drop_column('content_items', 'embedding')
    # op.drop_column('content_items', 'extracted_content')
    pass
