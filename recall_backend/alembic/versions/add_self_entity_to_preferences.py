"""Add self_entity_id and self_entity_last_refreshed_at to user_preferences.

Revision ID: self_entity_001
Revises: health_001
Create Date: 2026-04-08

Adds self-entity reference to user_preferences so users can seed personal
information (bio, social links) that creates a "self" entity in the
knowledge graph.
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision: str = 'self_entity_001'
down_revision: Union[str, None] = 'health_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'user_preferences',
        sa.Column('self_entity_id', UUID(as_uuid=True), sa.ForeignKey('entities.id', ondelete='SET NULL'), nullable=True)
    )
    op.add_column(
        'user_preferences',
        sa.Column('self_entity_last_refreshed_at', sa.DateTime(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('user_preferences', 'self_entity_last_refreshed_at')
    op.drop_column('user_preferences', 'self_entity_id')
