"""add notification tables

Revision ID: f9c3d5e8a1b2
Revises: 18bea3302767
Create Date: 2025-12-23 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY


# revision identifiers, used by Alembic.
revision: str = 'f9c3d5e8a1b2'
down_revision: Union[str, None] = '18bea3302767'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create notification-related tables"""

    # 1. user_notification_settings table
    op.create_table(
        'user_notification_settings',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.UUID(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False, unique=True),
        sa.Column('is_enabled', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('notification_time_utc', sa.Time(), nullable=False, server_default='13:00:00'),
        sa.Column('utc_offset_minutes', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('min_reading_time', sa.Integer(), server_default='3'),
        sa.Column('preferred_categories', ARRAY(sa.String()), nullable=True),
        sa.Column('include_favorites_only', sa.Boolean(), server_default='false'),
        sa.Column('last_notification_sent_at', sa.TIMESTAMP(), nullable=True),
        sa.Column('created_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.Column('updated_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint('utc_offset_minutes BETWEEN -720 AND 840', name='check_utc_offset')
    )

    # Indexes for user_notification_settings
    op.create_index(
        'idx_notification_settings_user_id',
        'user_notification_settings',
        ['user_id']
    )

    # Partial index for enabled notifications (critical for scheduler performance)
    op.execute("""
        CREATE INDEX idx_notification_settings_enabled_time
        ON user_notification_settings (is_enabled, notification_time_utc)
        WHERE is_enabled = true
    """)

    # 2. user_devices table
    op.create_table(
        'user_devices',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.UUID(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('fcm_token', sa.Text(), nullable=False, unique=True),
        sa.Column('platform', sa.String(20), nullable=False),
        sa.Column('device_name', sa.Text(), nullable=True),
        sa.Column('app_version', sa.Text(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('last_seen_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.Column('created_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.CheckConstraint("platform IN ('ios', 'android')", name='check_platform')
    )

    # Indexes for user_devices
    op.create_index(
        'idx_user_devices_user_id',
        'user_devices',
        ['user_id']
    )

    # Partial index for active devices
    op.execute("""
        CREATE INDEX idx_user_devices_token
        ON user_devices (fcm_token)
        WHERE is_active = true
    """)

    # Partial index for cleanup of stale devices
    op.execute("""
        CREATE INDEX idx_user_devices_stale
        ON user_devices (last_seen_at)
        WHERE is_active = true
    """)

    # 3. notification_history table
    op.create_table(
        'notification_history',
        sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column('user_id', sa.UUID(), sa.ForeignKey('users.id', ondelete='CASCADE'), nullable=False),
        sa.Column('content_item_id', sa.UUID(), sa.ForeignKey('content_items.id', ondelete='CASCADE'), nullable=False),
        sa.Column('sent_at', sa.TIMESTAMP(), nullable=False, server_default=sa.func.now()),
        sa.Column('notification_type', sa.String(50), nullable=False, server_default='daily_gem'),
        sa.Column('was_opened', sa.Boolean(), server_default='false'),
        sa.Column('opened_at', sa.TIMESTAMP(), nullable=True)
    )

    # Indexes for notification_history
    op.create_index(
        'idx_notification_history_user_date',
        'notification_history',
        ['user_id', sa.text('sent_at DESC')]
    )

    op.create_index(
        'idx_notification_history_content',
        'notification_history',
        ['content_item_id']
    )

    # Unique constraint to prevent duplicate notifications per day
    op.execute("""
        CREATE UNIQUE INDEX unique_daily_notification
        ON notification_history (user_id, content_item_id, DATE(sent_at))
    """)


def downgrade() -> None:
    """Drop notification-related tables (safe if already missing)"""
    # Drop in dependency order; use IF EXISTS to avoid failures if tables were removed
    op.execute("DROP TABLE IF EXISTS notification_history CASCADE")
    op.execute("DROP TABLE IF EXISTS user_devices CASCADE")
    op.execute("DROP TABLE IF EXISTS user_notification_settings CASCADE")
