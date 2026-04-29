"""fix_database_state_restore_tables

Revision ID: afdf7052e9ba
Revises: ca65e08dfacf
Create Date: 2026-01-16 11:15:00.915689

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision: str = 'afdf7052e9ba'
down_revision: Union[str, None] = 'ca65e08dfacf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Fix database state after incorrectly applied ca65e08dfacf migration.
    - Drop space_invitations table (should have been removed)
    - Recreate user_preferences table (was incorrectly dropped)
    - Recreate search_history table (was incorrectly dropped)
    """
    conn = op.get_bind()
    inspector = inspect(conn)
    existing_tables = inspector.get_table_names()

    # Drop space_invitations if it exists (it shouldn't be there)
    if 'space_invitations' in existing_tables:
        op.drop_index('ix_space_invitations_token', table_name='space_invitations', if_exists=True)
        op.drop_index('ix_space_invitations_space_id', table_name='space_invitations', if_exists=True)
        op.drop_index('ix_space_invitations_email', table_name='space_invitations', if_exists=True)
        op.drop_table('space_invitations')

    # Recreate user_preferences table if it doesn't exist
    if 'user_preferences' not in existing_tables:
        # Enable uuid-ossp extension (if not already enabled)
        op.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

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

    # Recreate search_history table if it doesn't exist
    if 'search_history' not in existing_tables:
        # Enable uuid-ossp extension (if not already enabled)
        op.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

        op.create_table(
            'search_history',
            sa.Column('id', sa.dialects.postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
            sa.Column('user_id', sa.dialects.postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
            sa.Column('query', sa.Text, nullable=False),
            sa.Column('created_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()'))
        )

        op.create_index('idx_search_history_user_id', 'search_history', ['user_id'])
        op.create_index('idx_search_history_created_at', 'search_history', ['created_at'])


def downgrade() -> None:
    """
    Reverse the fix (return to the broken state - not recommended)
    """
    # Drop the restored tables
    op.drop_index('idx_search_history_created_at', table_name='search_history', if_exists=True)
    op.drop_index('idx_search_history_user_id', table_name='search_history', if_exists=True)
    op.drop_table('search_history', if_exists=True)

    op.drop_index('idx_user_preferences_user_id', table_name='user_preferences', if_exists=True)
    op.drop_table('user_preferences', if_exists=True)

    # Recreate space_invitations (the broken state)
    op.create_table(
        'space_invitations',
        sa.Column('id', sa.dialects.postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('space_id', sa.dialects.postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('invited_by', sa.dialects.postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('role', sa.Enum('owner', 'admin', 'member', 'viewer', name='space_member_role', create_type=False), nullable=False),
        sa.Column('token', sa.String(length=255), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('accepted_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(['invited_by'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['space_id'], ['spaces.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_space_invitations_email', 'space_invitations', ['email'])
    op.create_index('ix_space_invitations_space_id', 'space_invitations', ['space_id'])
    op.create_index('ix_space_invitations_token', 'space_invitations', ['token'], unique=True)
