"""add_daily_gems_to_user_preferences

Revision ID: 682db436b290
Revises: 2750b6b4274b
Create Date: 2026-01-07 09:48:31.429409

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '682db436b290'
down_revision: Union[str, None] = '2750b6b4274b'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add daily_gems_enabled and daily_gems_time columns to user_preferences table
    op.add_column('user_preferences', sa.Column('daily_gems_enabled', sa.Boolean(), nullable=False, server_default='false'))
    op.add_column('user_preferences', sa.Column('daily_gems_time', sa.String(length=20), nullable=False, server_default='9:00 AM'))


def downgrade() -> None:
    # Remove daily_gems columns
    op.drop_column('user_preferences', 'daily_gems_time')
    op.drop_column('user_preferences', 'daily_gems_enabled')
