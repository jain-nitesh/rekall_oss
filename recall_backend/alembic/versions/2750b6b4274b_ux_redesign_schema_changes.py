"""ux_redesign_schema_changes

Revision ID: 2750b6b4274b
Revises: fbe4c10336ba
Create Date: 2026-01-05 23:34:54.439871

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '2750b6b4274b'
down_revision: Union[str, None] = 'fbe4c10336ba'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enable uuid-ossp extension (if not already enabled)
    op.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    # 1. Create search_history table
    op.create_table(
        'search_history',
        sa.Column('id', sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('user_id', sa.dialects.postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('query', sa.Text, nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()'))
    )

    op.create_index('idx_search_history_user_id', 'search_history', ['user_id'])
    op.create_index('idx_search_history_created_at', 'search_history', ['created_at'])

    # 2. Create user_preferences table
    op.create_table(
        'user_preferences',
        sa.Column('id', sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('user_id', sa.dialects.postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True),
        sa.Column('summary_style', sa.String(50), nullable=False, server_default='bullet_points'),  # bullet_points, paragraph, concise
        sa.Column('auto_categorize', sa.Boolean, nullable=False, server_default='true'),
        sa.Column('connected_sources', sa.dialects.postgresql.JSONB, nullable=True),  # ["twitter", "reddit", etc.]
        sa.Column('created_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime, nullable=True, server_default=sa.text('NOW()'))
    )

    op.create_index('idx_user_preferences_user_id', 'user_preferences', ['user_id'])

    # 3. Add usage stats columns to users table
    op.add_column('users', sa.Column('ai_summaries_used', sa.Integer, nullable=False, server_default='0'))
    op.add_column('users', sa.Column('monthly_limit', sa.Integer, nullable=False, server_default='500'))
    op.add_column('users', sa.Column('plan', sa.String(20), nullable=False, server_default='free'))  # free, pro, enterprise
    op.add_column('users', sa.Column('username', sa.String(50), nullable=True, unique=True))  # @username for profile

    # 4. Add new columns to spaces table
    op.add_column('spaces', sa.Column('is_pinned', sa.Boolean, nullable=False, server_default='false'))
    op.add_column('spaces', sa.Column('ai_ready', sa.Boolean, nullable=False, server_default='false'))
    op.add_column('spaces', sa.Column('is_public', sa.Boolean, nullable=False, server_default='false'))  # For explore/trending
    op.add_column('spaces', sa.Column('member_count', sa.Integer, nullable=False, server_default='0'))  # Cached count for explore

    op.create_index('idx_spaces_is_pinned', 'spaces', ['is_pinned'])
    op.create_index('idx_spaces_ai_ready', 'spaces', ['ai_ready'])
    op.create_index('idx_spaces_is_public', 'spaces', ['is_public'])

    # 5. Add new columns to content_items table
    op.add_column('content_items', sa.Column('hero_image_url', sa.Text, nullable=True))
    op.add_column('content_items', sa.Column('key_takeaways', sa.dialects.postgresql.JSONB, nullable=True))  # Array of strings


def downgrade() -> None:
    # Drop in reverse order

    # Remove columns from content_items
    op.drop_column('content_items', 'key_takeaways')
    op.drop_column('content_items', 'hero_image_url')

    # Remove columns and indexes from spaces
    op.drop_index('idx_spaces_is_public')
    op.drop_index('idx_spaces_ai_ready')
    op.drop_index('idx_spaces_is_pinned')
    op.drop_column('spaces', 'member_count')
    op.drop_column('spaces', 'is_public')
    op.drop_column('spaces', 'ai_ready')
    op.drop_column('spaces', 'is_pinned')

    # Remove columns from users
    op.drop_column('users', 'username')
    op.drop_column('users', 'plan')
    op.drop_column('users', 'monthly_limit')
    op.drop_column('users', 'ai_summaries_used')

    # Drop user_preferences table
    op.drop_table('user_preferences')

    # Drop search_history table
    op.drop_table('search_history')
