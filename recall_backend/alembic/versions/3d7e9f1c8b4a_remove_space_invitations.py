"""remove_space_invitations

Revision ID: 3d7e9f1c8b4a
Revises: bfbb3ee5795a
Create Date: 2026-01-11 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '3d7e9f1c8b4a'
down_revision: Union[str, None] = 'bfbb3ee5795a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """
    Drop the space_invitations table as we're replacing email-based invitations
    with shareable invite links using the spaces.invite_token field.
    """
    op.drop_table('space_invitations')


def downgrade() -> None:
    """
    Recreate the space_invitations table if we need to rollback.
    """
    op.create_table(
        'space_invitations',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('space_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('invited_by', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('role', sa.Enum('owner', 'admin', 'member', 'viewer', name='space_member_role'), nullable=False),
        sa.Column('token', sa.String(length=255), nullable=False),
        sa.Column('expires_at', sa.DateTime(), nullable=False),
        sa.Column('accepted_at', sa.DateTime(), nullable=True),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['space_id'], ['spaces.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['invited_by'], ['users.id'], ondelete='CASCADE'),
    )
    op.create_index('ix_space_invitations_email', 'space_invitations', ['email'])
    op.create_index('ix_space_invitations_space_id', 'space_invitations', ['space_id'])
    op.create_index('ix_space_invitations_token', 'space_invitations', ['token'])
    op.create_unique_constraint('uq_space_invitations_token', 'space_invitations', ['token'])
    op.create_unique_constraint('uq_space_invitations_space_email', 'space_invitations', ['space_id', 'email'])
