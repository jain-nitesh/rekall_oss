"""restore_search_history_table

Revision ID: c2a6ae908ce8
Revises: 731ae42e653b
Create Date: 2026-01-10 12:42:40.581128

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c2a6ae908ce8'
down_revision: Union[str, None] = '731ae42e653b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enable uuid-ossp extension (if not already enabled)
    op.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    # Create search_history table
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
    # Drop search_history table
    op.drop_index('idx_search_history_created_at', table_name='search_history')
    op.drop_index('idx_search_history_user_id', table_name='search_history')
    op.drop_table('search_history')
