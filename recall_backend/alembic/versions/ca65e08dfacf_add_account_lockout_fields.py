"""add_account_lockout_fields

Revision ID: ca65e08dfacf
Revises: 3d7e9f1c8b4a
Create Date: 2026-01-14 14:06:06.697903

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'ca65e08dfacf'
down_revision: Union[str, None] = '3d7e9f1c8b4a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add account lockout fields to users table
    op.add_column('users', sa.Column('failed_login_attempts', sa.Integer(), nullable=False, server_default='0'))
    op.add_column('users', sa.Column('locked_until', sa.DateTime(), nullable=True))


def downgrade() -> None:
    # Remove account lockout fields from users table
    op.drop_column('users', 'locked_until')
    op.drop_column('users', 'failed_login_attempts')
