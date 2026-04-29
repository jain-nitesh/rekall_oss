"""create_spaces_tables

Revision ID: 2c1d3f88545e
Revises: 004f56dfcb01
Create Date: 2025-12-23 23:20:07.478224

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = '2c1d3f88545e'
down_revision: Union[str, None] = '004f56dfcb01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Enable uuid-ossp extension for uuid_generate_v4() function
    op.execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    # Note: Enum type will be created automatically by SQLAlchemy when first Enum column is created
    # We use create_type=True on the first Enum usage to let SQLAlchemy handle it

    # Create spaces table
    op.create_table(
        'spaces',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('description', sa.Text, nullable=True),
        sa.Column('created_by', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('invite_token', sa.String(255), unique=True, nullable=False),
        sa.Column('invite_token_expires_at', sa.DateTime, nullable=True),
        sa.Column('is_active', sa.Boolean, nullable=False, server_default='true'),
        sa.Column('created_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime, nullable=True, server_default=sa.text('NOW()'))
    )

    op.create_index('idx_spaces_created_by', 'spaces', ['created_by'])
    op.create_index('idx_spaces_invite_token', 'spaces', ['invite_token'])
    op.create_index('idx_spaces_is_active', 'spaces', ['is_active'])

    # Create space_members table
    op.create_table(
        'space_members',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('space_id', UUID(as_uuid=True), sa.ForeignKey('spaces.id', ondelete='CASCADE'), nullable=False),
        sa.Column('user_id', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('role', sa.Enum('owner', 'admin', 'member', 'viewer', name='space_member_role', create_type=True, checkfirst=True), nullable=False, server_default='member'),
        sa.Column('joined_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()')),
        sa.Column('invited_by', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.UniqueConstraint('space_id', 'user_id', name='uq_space_user')
    )

    op.create_index('idx_space_members_space_id', 'space_members', ['space_id'])
    op.create_index('idx_space_members_user_id', 'space_members', ['user_id'])
    op.create_index('idx_space_members_role', 'space_members', ['role'])

    # Create space_content table
    op.create_table(
        'space_content',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('space_id', UUID(as_uuid=True), sa.ForeignKey('spaces.id', ondelete='CASCADE'), nullable=False),
        sa.Column('content_id', UUID(as_uuid=True), sa.ForeignKey('content_items.id', ondelete='CASCADE'), nullable=False),
        sa.Column('added_by', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('added_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()')),
        sa.UniqueConstraint('space_id', 'content_id', name='uq_space_content')
    )

    op.create_index('idx_space_content_space_id', 'space_content', ['space_id'])
    op.create_index('idx_space_content_content_id', 'space_content', ['content_id'])
    op.create_index('idx_space_content_added_at', 'space_content', ['added_at'])

    # Create space_invitations table
    op.create_table(
        'space_invitations',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('space_id', UUID(as_uuid=True), sa.ForeignKey('spaces.id', ondelete='CASCADE'), nullable=False),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('invited_by', UUID(as_uuid=True), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('role', sa.Enum('owner', 'admin', 'member', 'viewer', name='space_member_role', create_type=True, checkfirst=True), nullable=False, server_default='member'),
        sa.Column('token', sa.String(255), unique=True, nullable=False),
        sa.Column('expires_at', sa.DateTime, nullable=False),
        sa.Column('accepted_at', sa.DateTime, nullable=True),
        sa.Column('created_at', sa.DateTime, nullable=False, server_default=sa.text('NOW()')),
        sa.UniqueConstraint('space_id', 'email', name='uq_space_invitation_email')
    )

    op.create_index('idx_space_invitations_token', 'space_invitations', ['token'])
    op.create_index('idx_space_invitations_email', 'space_invitations', ['email'])
    op.create_index('idx_space_invitations_space_id', 'space_invitations', ['space_id'])


def downgrade() -> None:
    # Drop tables in reverse order (respecting foreign key dependencies)
    op.drop_table('space_invitations')
    op.drop_table('space_content')
    op.drop_table('space_members')
    op.drop_table('spaces')

    # Drop enum type
    op.execute('DROP TYPE space_member_role')
