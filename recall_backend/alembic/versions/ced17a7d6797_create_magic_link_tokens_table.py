"""create_magic_link_tokens_table

Revision ID: ced17a7d6797
Revises: 2c1d3f88545e
Create Date: 2025-12-31 09:32:59.560675

Note: Skips removed Supabase migrations (a8f7c6d5e9b3, bd0302dc0b6d)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ced17a7d6797'
down_revision: Union[str, None] = '2c1d3f88545e'  # Skip removed Supabase migrations
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Create magic_link_tokens table (idempotent - safe to run multiple times).

    Uses raw SQL with IF NOT EXISTS to prevent errors if already created.
    """
    # Check if table exists before creating
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if 'magic_link_tokens' not in inspector.get_table_names():
        # Create magic_link_tokens table
        op.create_table(
            'magic_link_tokens',
            sa.Column('id', sa.UUID(), nullable=False),
            sa.Column('user_id', sa.UUID(), nullable=True),
            sa.Column('email', sa.String(255), nullable=False),
            sa.Column('token', sa.String(255), nullable=False),
            sa.Column('expires_at', sa.DateTime(), nullable=False),
            sa.Column('used_at', sa.DateTime(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
            sa.PrimaryKeyConstraint('id')
        )

        # Create indexes
        op.create_index('ix_magic_link_tokens_user_id', 'magic_link_tokens', ['user_id'])
        op.create_index('ix_magic_link_tokens_email', 'magic_link_tokens', ['email'])
        op.create_index('ix_magic_link_tokens_token', 'magic_link_tokens', ['token'])

        # Create unique constraint on token
        op.create_unique_constraint('uq_magic_link_tokens_token', 'magic_link_tokens', ['token'])

        print("✅ Created magic_link_tokens table")
    else:
        print("⏭️  Skipped: magic_link_tokens table already exists")


def downgrade() -> None:
    # Drop table and all constraints/indexes
    op.drop_table('magic_link_tokens')
