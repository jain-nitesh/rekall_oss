"""add_detailed_summary_column

Revision ID: b3d5e7f9a1c3
Revises: a7b2c4d6e8f0
Create Date: 2026-04-10

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b3d5e7f9a1c3'
down_revision: Union[str, None] = 'a7b2c4d6e8f0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add detailed_summary column for richer AI-generated content summaries."""
    op.add_column(
        'content_items',
        sa.Column('detailed_summary', sa.Text(), nullable=True)
    )


def downgrade() -> None:
    """Remove detailed_summary column."""
    op.drop_column('content_items', 'detailed_summary')
