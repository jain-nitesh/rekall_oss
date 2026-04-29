"""restore_user_preferences_table

Revision ID: 584019ab5515
Revises: c2a6ae908ce8
Create Date: 2026-01-10 12:45:10.302267

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '584019ab5515'
down_revision: Union[str, None] = 'c2a6ae908ce8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enable uuid-ossp extension (if not already enabled)
    op.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    # Create user_preferences table
    op.create_table(
        'user_preferences',
        sa.Column('id', sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('user_id', sa.dialects.postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True),
        sa.Column('summary_style', sa.String(50), server_default='bullet_points', nullable=False),
        sa.Column('auto_categorize', sa.Boolean, server_default=sa.text('true'), nullable=False),
        sa.Column('connected_sources', sa.dialects.postgresql.JSONB, nullable=True),
        sa.Column('daily_gems_enabled', sa.Boolean, server_default=sa.text('false'), nullable=False),
        sa.Column('daily_gems_time', sa.String(20), server_default='9:00 AM', nullable=False),
        sa.Column('created_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime, nullable=True, server_default=sa.text('NOW()'))
    )

    op.create_index('idx_user_preferences_user_id', 'user_preferences', ['user_id'])


def downgrade() -> None:
    # Drop user_preferences table
    op.drop_index('idx_user_preferences_user_id', table_name='user_preferences')
    op.drop_table('user_preferences')
