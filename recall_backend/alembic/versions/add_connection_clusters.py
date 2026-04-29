"""Add connection_clusters and connection_cluster_items tables

Revision ID: clusters_001
Revises: connection_feedback_001
Create Date: 2026-03-08

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = 'clusters_001'
down_revision: Union[str, None] = 'connection_feedback_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'connection_clusters',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('label', sa.String(200), nullable=False),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('item_count', sa.Integer, default=0),
        sa.Column('avg_similarity', sa.Float, nullable=True),
        sa.Column('is_stale', sa.Boolean, default=True),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime, server_default=sa.func.now()),
    )

    op.create_table(
        'connection_cluster_items',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('cluster_id', UUID(as_uuid=True), sa.ForeignKey('connection_clusters.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('content_item_id', UUID(as_uuid=True), sa.ForeignKey('content_items.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.UniqueConstraint('cluster_id', 'content_item_id', name='uq_cluster_item'),
    )


def downgrade() -> None:
    op.drop_table('connection_cluster_items')
    op.drop_table('connection_clusters')
