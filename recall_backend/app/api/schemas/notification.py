"""
Pydantic schemas for notification API endpoints.

Defines request/response models for notification settings and device management.
"""
from pydantic import BaseModel, Field, field_validator
from datetime import time, datetime
from typing import Optional, List


# ===== Request Schemas =====

class NotificationSettingsUpdate(BaseModel):
    """Request schema for updating notification settings"""
    is_enabled: Optional[bool] = None
    notification_time_local: Optional[str] = Field(
        None,
        pattern=r"^([0-1][0-9]|2[0-3]):[0-5][0-9]$",
        description="Local time in HH:MM format (e.g., '09:30')"
    )
    utc_offset_minutes: Optional[int] = Field(
        None,
        ge=-720,
        le=840,
        description="UTC offset in minutes (e.g., -300 for EST)"
    )

    @field_validator('utc_offset_minutes')
    @classmethod
    def validate_offset(cls, v):
        """Validate UTC offset is within reasonable range"""
        if v is not None and (v < -720 or v > 840):
            raise ValueError("UTC offset must be between -12h and +14h")
        return v


class DeviceRegistration(BaseModel):
    """Request schema for registering a device token"""
    fcm_token: str = Field(..., min_length=10, description="Firebase Cloud Messaging token")
    platform: str = Field(..., pattern=r"^(ios|android)$", description="Device platform: 'ios' or 'android'")
    device_name: Optional[str] = Field(None, description="Optional device name (e.g., 'iPhone 13 Pro')")
    app_version: Optional[str] = Field(None, description="Optional app version (e.g., '1.0.0')")


class NotificationOpenedEvent(BaseModel):
    """Request schema for tracking when user opens a notification"""
    notification_history_id: int = Field(..., description="ID of the notification from history")


# ===== Response Schemas =====

class NotificationSettingsResponse(BaseModel):
    """Response schema for notification settings"""
    user_id: str
    is_enabled: bool
    notification_time_utc: str  # "14:00:00"
    notification_time_local: str  # "09:00" (computed from UTC + offset)
    utc_offset_minutes: int
    last_notification_sent_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class DeviceResponse(BaseModel):
    """Response schema for device information"""
    id: int
    platform: str
    device_name: Optional[str] = None
    is_active: bool
    last_seen_at: datetime

    model_config = {"from_attributes": True}


class NotificationHistoryResponse(BaseModel):
    """Response schema for notification history"""
    id: int
    content_item_id: str
    sent_at: datetime
    was_opened: bool
    opened_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
