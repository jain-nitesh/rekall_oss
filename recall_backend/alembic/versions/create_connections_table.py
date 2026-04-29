"""Create content_connections table for AI-discovered connections

Revision ID: connections_001
Revises: pgvector_embeddings_001
Create Date: 2026-03-06

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = 'connections_001'
down_revision: Union[str, None] = 'pgvector_embeddings_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'content_connections',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('source_item_id', UUID(as_uuid=True), sa.ForeignKey('content_items.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('target_item_id', UUID(as_uuid=True), sa.ForeignKey('content_items.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('similarity_score', sa.Float, nullable=False),
        sa.Column('connection_type', sa.String(50), nullable=False, default='semantic'),
        sa.Column('ai_explanation', sa.Text, nullable=True),
        sa.Column('is_dismissed', sa.Boolean, default=False, nullable=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint('source_item_id', 'target_item_id', name='uq_connection_pair'),
    )

    # Add connection_count column to content_items
    op.add_column('content_items',
        sa.Column('connection_count', sa.Integer, server_default='0', nullable=False)
    )


def downgrade() -> None:
    op.drop_column('content_items', 'connection_count')
    op.drop_table('content_connections')
