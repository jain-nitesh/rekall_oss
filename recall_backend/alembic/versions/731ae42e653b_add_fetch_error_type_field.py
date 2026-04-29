"""add_fetch_error_type_field

Revision ID: 731ae42e653b
Revises: 8b5f77ebacc2
Create Date: 2026-01-09 19:38:46.563378

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '731ae42e653b'
down_revision: Union[str, None] = '8b5f77ebacc2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create the fetch_error_type enum type in PostgreSQL
    fetch_error_type_enum = sa.Enum(
        'none', 'auth_required', 'network', 'not_found',
        'server_error', 'blocked', 'other',
        name='fetcherrortype'
    )
    fetch_error_type_enum.create(op.get_bind(), checkfirst=True)

    # Add the fetch_error_type column with default value 'none'
    op.add_column(
        'content_items',
        sa.Column(
            'fetch_error_type',
            fetch_error_type_enum,
            nullable=False,
            server_default='none'
        )
    )


def downgrade() -> None:
    # Drop the column
    op.drop_column('content_items', 'fetch_error_type')

    # Drop the enum type
    sa.Enum(name='fetcherrortype').drop(op.get_bind(), checkfirst=True)
