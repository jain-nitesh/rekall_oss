"""Create public_collections and collection_items tables

Revision ID: collections_001
Revises: import_jobs_001
Create Date: 2026-03-06

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = 'collections_001'
down_revision: Union[str, None] = 'import_jobs_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'public_collections',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('title', sa.String(200), nullable=False),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('slug', sa.String(100), unique=True, nullable=False, index=True),
        sa.Column('cover_image_url', sa.Text, nullable=True),
        sa.Column('is_published', sa.Boolean, default=False, nullable=False),
        sa.Column('view_count', sa.Integer, server_default='0', nullable=False),
        sa.Column('fork_count', sa.Integer, server_default='0', nullable=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime, server_default=sa.func.now(), nullable=False),
    )

    op.create_table(
        'collection_items',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('collection_id', UUID(as_uuid=True), sa.ForeignKey('public_collections.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('content_item_id', UUID(as_uuid=True), sa.ForeignKey('content_items.id', ondelete='CASCADE'), nullable=False),
        sa.Column('curator_note', sa.Text, nullable=True),
        sa.Column('position', sa.Integer, server_default='0', nullable=False),
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('collection_items')
    op.drop_table('public_collections')
