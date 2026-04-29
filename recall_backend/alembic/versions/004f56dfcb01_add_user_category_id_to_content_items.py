"""add_user_category_id_to_content_items

Revision ID: 004f56dfcb01
Revises: 459b44380b5f
Create Date: 2025-12-23 16:53:52.331426

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = '004f56dfcb01'
down_revision: Union[str, None] = '459b44380b5f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # First, create user_categories table
    op.create_table(
        'user_categories',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('name', sa.String(100), nullable=False),
        sa.Column('description', sa.String(500), nullable=True),
        sa.Column('color', sa.String(7), nullable=True, server_default='#6366F1'),
        sa.Column('usage_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.DateTime(), nullable=False, server_default=sa.func.now(), onupdate=sa.func.now())
    )
    
    # Create index on user_id for user_categories
    op.create_index('idx_user_categories_user_id', 'user_categories', ['user_id'])
    
    # Now add user_category_id to content_items
    op.add_column('content_items', 
        sa.Column('user_category_id', UUID(as_uuid=True), sa.ForeignKey('user_categories.id', ondelete='SET NULL'), nullable=True)
    )
    
    # Create index on user_category_id
    op.create_index('idx_content_items_user_category_id', 'content_items', ['user_category_id'])


def downgrade() -> None:
    # Drop index and column from content_items
    op.drop_index('idx_content_items_user_category_id', table_name='content_items')
    op.drop_column('content_items', 'user_category_id')
    
    # Drop user_categories table and index
    op.drop_index('idx_user_categories_user_id', table_name='user_categories')
    op.drop_table('user_categories')
