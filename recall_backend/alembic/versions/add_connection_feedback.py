"""Add explored_at and explored_count columns to content_connections

Revision ID: connection_feedback_001
Revises: connections_001
Create Date: 2026-03-08

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'connection_feedback_001'
down_revision: Union[str, None] = 'collections_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('content_connections',
        sa.Column('explored_at', sa.DateTime, nullable=True)
    )
    op.add_column('content_connections',
        sa.Column('explored_count', sa.Integer, server_default='0', nullable=False)
    )


def downgrade() -> None:
    op.drop_column('content_connections', 'explored_count')
    op.drop_column('content_connections', 'explored_at')
