"""add_apple_sign_in_support

Revision ID: apple_sign_in_001
Revises: connection_feedback_001
Create Date: 2026-03-26

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'apple_sign_in_001'
down_revision: Union[str, None] = 'clusters_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add apple_id column to users table
    op.add_column('users',
        sa.Column('apple_id', sa.String(255), nullable=True)
    )

    # Create unique constraint on apple_id
    op.create_unique_constraint(
        'uq_users_apple_id',
        'users',
        ['apple_id']
    )

    # Create index for fast lookups
    op.create_index(
        'ix_users_apple_id',
        'users',
        ['apple_id']
    )


def downgrade() -> None:
    # Drop index
    op.drop_index('ix_users_apple_id', 'users')

    # Drop unique constraint
    op.drop_constraint('uq_users_apple_id', 'users', type_='unique')

    # Drop column
    op.drop_column('users', 'apple_id')
