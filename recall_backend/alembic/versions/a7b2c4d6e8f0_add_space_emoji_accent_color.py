"""add emoji and accent_color to spaces

Revision ID: a7b2c4d6e8f0
Revises: self_entity_001
Create Date: 2026-04-09

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'a7b2c4d6e8f0'
down_revision = 'self_entity_001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('spaces', sa.Column('emoji', sa.String(10), nullable=True))
    op.add_column('spaces', sa.Column('accent_color', sa.String(7), nullable=True))


def downgrade() -> None:
    op.drop_column('spaces', 'accent_color')
    op.drop_column('spaces', 'emoji')
