"""
Notification settings database models.

Manages user notification preferences, device tokens, and notification history.
"""
from sqlalchemy import Column, Integer, String, Boolean, Time, TIMESTAMP, ARRAY, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.db.session import Base


class UserNotificationSettings(Base):
    """
    User notification preferences.

    Stores when and how users want to receive daily gem notifications.
    One row per user.
    """
    __tablename__ = "user_notification_settings"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True
    )

    # Notification preferences
    is_enabled = Column(Boolean, nullable=False, default=True)
    notification_time_utc = Column(Time, nullable=False, default="13:00:00")  # 1 PM UTC
    utc_offset_minutes = Column(Integer, nullable=False, default=0)  # e.g., -300 for EST

    # Gem selection preferences (for future phases)
    min_reading_time = Column(Integer, default=3)  # Minimum reading time in minutes
    preferred_categories = Column(ARRAY(String), nullable=True)  # NULL = all categories
    include_favorites_only = Column(Boolean, default=False)

    # Tracking
    last_notification_sent_at = Column(TIMESTAMP, nullable=True)
    created_at = Column(TIMESTAMP, nullable=False, server_default=func.now())
    updated_at = Column(TIMESTAMP, nullable=False, server_default=func.now(), onupdate=func.now())

    # Relationship
    user = relationship("User", back_populates="notification_settings")

    def __repr__(self):
        return f"<UserNotificationSettings(user_id={self.user_id}, enabled={self.is_enabled}, time={self.notification_time_utc})>"


class UserDevice(Base):
    """
    User devices for push notifications.

    Stores Firebase Cloud Messaging tokens for each device.
    Supports multiple devices per user (iPhone + iPad + Android).
    """
    __tablename__ = "user_devices"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Device identification
    fcm_token = Column(Text, nullable=False, unique=True)
    platform = Column(String(20), nullable=False)  # 'ios' or 'android'
    device_name = Column(Text, nullable=True)  # Optional: "iPhone 13 Pro"
    app_version = Column(Text, nullable=True)  # Optional: "1.0.0"

    # Token lifecycle
    is_active = Column(Boolean, nullable=False, default=True)
    last_seen_at = Column(TIMESTAMP, nullable=False, server_default=func.now())
    created_at = Column(TIMESTAMP, nullable=False, server_default=func.now())

    # Relationship
    user = relationship("User", back_populates="devices")

    def __repr__(self):
        return f"<UserDevice(user_id={self.user_id}, platform={self.platform}, active={self.is_active})>"


class NotificationHistory(Base):
    """
    Notification send history.

    Tracks which content was sent to which user and when.
    Prevents duplicate notifications and enables analytics.
    """
    __tablename__ = "notification_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    content_item_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Notification details
    sent_at = Column(TIMESTAMP, nullable=False, server_default=func.now())
    notification_type = Column(String(50), nullable=False, default="daily_gem")

    # Tracking engagement (future: mobile app can report back)
    was_opened = Column(Boolean, default=False)
    opened_at = Column(TIMESTAMP, nullable=True)

    # Relationships
    user = relationship("User", back_populates="notification_history")
    content_item = relationship("ContentItem")

    def __repr__(self):
        return f"<NotificationHistory(user_id={self.user_id}, content_id={self.content_item_id}, sent={self.sent_at})>"
