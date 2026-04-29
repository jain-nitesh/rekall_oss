"""add_google_oauth_support

Revision ID: bfbb3ee5795a
Revises: 584019ab5515
Create Date: 2026-01-10 13:55:29.320039

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'bfbb3ee5795a'
down_revision: Union[str, None] = '584019ab5515'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add google_id column to users table
    op.add_column('users',
        sa.Column('google_id', sa.String(255), nullable=True)
    )

    # Create unique constraint on google_id
    op.create_unique_constraint(
        'uq_users_google_id',
        'users',
        ['google_id']
    )

    # Create index for fast lookups
    op.create_index(
        'ix_users_google_id',
        'users',
        ['google_id']
    )


def downgrade() -> None:
    # Drop index
    op.drop_index('ix_users_google_id', 'users')

    # Drop unique constraint
    op.drop_constraint('uq_users_google_id', 'users', type_='unique')

    # Drop column
    op.drop_column('users', 'google_id')
