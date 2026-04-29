"""add_processing_status_to_content_items

Revision ID: 18bea3302767
Revises: 001_add_embeddings
Create Date: 2025-12-22 21:20:52.999985

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '18bea3302767'
down_revision: Union[str, None] = '001_add_embeddings'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create enum type for processing status
    op.execute("CREATE TYPE processingstatus AS ENUM ('pending', 'processing', 'completed', 'failed')")

    # Add processing status columns
    op.add_column('content_items', sa.Column('processing_status', sa.Enum('pending', 'processing', 'completed', 'failed', name='processingstatus'), nullable=False, server_default='pending'))
    op.add_column('content_items', sa.Column('processing_error', sa.Text(), nullable=True))
    op.add_column('content_items', sa.Column('processing_attempts', sa.Integer(), nullable=True, server_default='0'))
    op.add_column('content_items', sa.Column('last_processed_at', sa.DateTime(), nullable=True))

    # Create index on processing_status for efficient queries
    op.create_index('ix_content_items_processing_status', 'content_items', ['processing_status'])


def downgrade() -> None:
    # Drop index
    op.drop_index('ix_content_items_processing_status', 'content_items')

    # Drop columns
    op.drop_column('content_items', 'last_processed_at')
    op.drop_column('content_items', 'processing_attempts')
    op.drop_column('content_items', 'processing_error')
    op.drop_column('content_items', 'processing_status')

    # Drop enum type
    op.execute("DROP TYPE processingstatus")
