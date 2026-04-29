"""add_magic_link_tokens_and_nullable_password

Revision ID: 459b44380b5f
Revises: f9c3d5e8a1b2
Create Date: 2025-12-23 14:55:29.125008

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '459b44380b5f'
down_revision: Union[str, None] = 'f9c3d5e8a1b2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Make hashed_password nullable (for magic link authentication)
    op.alter_column('users', 'hashed_password',
               existing_type=sa.VARCHAR(length=255),
               nullable=True)
    
    # Create magic_link_tokens table
    op.create_table(
        'magic_link_tokens',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=True),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('token', sa.String(255), nullable=False, unique=True),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('used_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False, server_default=sa.func.now())
    )
    
    # Create indexes for magic_link_tokens
    op.create_index('idx_magic_link_tokens_user_id', 'magic_link_tokens', ['user_id'])
    op.create_index('idx_magic_link_tokens_email', 'magic_link_tokens', ['email'])
    op.create_index('idx_magic_link_tokens_token', 'magic_link_tokens', ['token'], unique=True)


def downgrade() -> None:
    # Drop magic_link_tokens table and indexes (if they exist)
    # Use raw SQL with IF EXISTS to handle case where table was never created
    op.execute("DROP INDEX IF EXISTS idx_magic_link_tokens_token")
    op.execute("DROP INDEX IF EXISTS idx_magic_link_tokens_email")
    op.execute("DROP INDEX IF EXISTS idx_magic_link_tokens_user_id")
    op.execute("DROP TABLE IF EXISTS magic_link_tokens")
    
    # Make hashed_password NOT NULL again
    op.alter_column('users', 'hashed_password',
               existing_type=sa.VARCHAR(length=255),
               nullable=False)
