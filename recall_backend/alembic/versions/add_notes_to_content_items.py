"""Add notes column to content_items table.

Revision ID: notes_001
Revises: apple_sign_in_001
Create Date: 2026-04-01

Allows users to add personal notes to saved content.
Notes are searchable via full-text search.
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'notes_001'
down_revision: Union[str, None] = 'apple_sign_in_001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add notes column (nullable text, no default needed)
    op.execute("""
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_name = 'content_items' AND column_name = 'notes'
            ) THEN
                ALTER TABLE content_items ADD COLUMN notes TEXT;
            END IF;
        END $$;
    """)


def downgrade() -> None:
    op.drop_column('content_items', 'notes')
