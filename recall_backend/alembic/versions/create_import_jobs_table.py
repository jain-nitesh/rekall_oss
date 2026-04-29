"""Create import_jobs table for bookmark import tracking

Revision ID: import_jobs_001
Revises: connections_001
Create Date: 2026-03-06

"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = 'import_jobs_001'
down_revision: Union[str, None] = 'connections_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'import_jobs',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, index=True),
        sa.Column('source', sa.String(50), nullable=False),  # 'chrome', 'pocket', 'raindrop'
        sa.Column('total_items', sa.Integer, nullable=False, default=0),
        sa.Column('processed_items', sa.Integer, nullable=False, server_default='0'),
        sa.Column('failed_items', sa.Integer, nullable=False, server_default='0'),
        sa.Column('status', sa.String(20), nullable=False, default='processing'),  # 'processing', 'completed', 'failed'
        sa.Column('created_at', sa.DateTime, server_default=sa.func.now(), nullable=False),
        sa.Column('completed_at', sa.DateTime, nullable=True),
    )


def downgrade() -> None:
    op.drop_table('import_jobs')
