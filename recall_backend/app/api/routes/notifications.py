"""
Notification API routes.

Endpoints for managing notification settings, device tokens, and history.
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from sqlalchemy.exc import IntegrityError
from typing import List
from datetime import time, datetime, timedelta
import os

from app.api.schemas.notification import (
    NotificationSettingsUpdate, NotificationSettingsResponse,
    DeviceRegistration, DeviceResponse,
    NotificationOpenedEvent, NotificationHistoryResponse
)
from app.models.notification_settings import UserNotificationSettings, UserDevice, NotificationHistory
from app.models.user import User
from app.db.session import get_db
from app.api.routes.auth import get_current_user
from app.services.gem_selector import GemSelector
from app.services.fcm_service import FCMService
from app.core.config import settings

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("/settings", response_model=NotificationSettingsResponse)
async def get_notification_settings(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get current user's notification settings.

    If settings don't exist, creates default settings with notifications disabled.
    """
    # Query settings
    result = await db.execute(
        select(UserNotificationSettings).where(
            UserNotificationSettings.user_id == current_user.id
        )
    )
    settings = result.scalar_one_or_none()

    if not settings:
        # Create default settings
        settings = UserNotificationSettings(
            user_id=current_user.id,
            is_enabled=False,  # Disabled by default until user opts in
            notification_time_utc=time(13, 0),  # 1 PM UTC
            utc_offset_minutes=0
        )
        db.add(settings)
        await db.commit()
        await db.refresh(settings)

    # Compute local time for response
    utc_time = settings.notification_time_utc
    offset_delta = timedelta(minutes=settings.utc_offset_minutes)
    local_datetime = datetime.combine(datetime.today(), utc_time) + offset_delta

    return NotificationSettingsResponse(
        user_id=str(settings.user_id),
        is_enabled=settings.is_enabled,
        notification_time_utc=str(settings.notification_time_utc),
        notification_time_local=local_datetime.strftime("%H:%M"),
        utc_offset_minutes=settings.utc_offset_minutes,
        last_notification_sent_at=settings.last_notification_sent_at
    )


@router.put("/settings", response_model=NotificationSettingsResponse)
async def update_notification_settings(
    update: NotificationSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update notification settings.

    Can update:
    - is_enabled: Enable/disable notifications
    - notification_time_local + utc_offset_minutes: Set notification time
    """
    # Get or create settings
    result = await db.execute(
        select(UserNotificationSettings).where(
            UserNotificationSettings.user_id == current_user.id
        )
    )
    settings = result.scalar_one_or_none()

    if not settings:
        settings = UserNotificationSettings(user_id=current_user.id)
        db.add(settings)

    # Update fields
    if update.is_enabled is not None:
        settings.is_enabled = update.is_enabled

    if update.notification_time_local and update.utc_offset_minutes is not None:
        # Convert local time to UTC
        hours, minutes = map(int, update.notification_time_local.split(':'))
        local_time = time(hours, minutes)

        # Calculate UTC time
        local_datetime = datetime.combine(datetime.today(), local_time)
        utc_datetime = local_datetime - timedelta(minutes=update.utc_offset_minutes)

        settings.notification_time_utc = utc_datetime.time()
        settings.utc_offset_minutes = update.utc_offset_minutes

    await db.commit()
    await db.refresh(settings)

    # Return formatted response
    return await get_notification_settings(current_user, db)


@router.post("/devices", response_model=DeviceResponse, status_code=status.HTTP_201_CREATED)
async def register_device(
    device: DeviceRegistration,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Register or update FCM device token.

    If token already exists:
    - Updates user_id, platform, device info
    - Reactivates if was inactive
    - Updates last_seen_at

    If token is new:
    - Creates new device record
    """
    try:
        # Check if token already exists
        result = await db.execute(
            select(UserDevice).where(UserDevice.fcm_token == device.fcm_token)
        )
        existing = result.scalar_one_or_none()

        if existing:
            # Update existing device
            existing.user_id = current_user.id
            existing.platform = device.platform
            existing.device_name = device.device_name
            existing.app_version = device.app_version
            existing.is_active = True
            existing.last_seen_at = datetime.utcnow()
            await db.commit()
            await db.refresh(existing)
            return existing

        # Create new device
        new_device = UserDevice(
            user_id=current_user.id,
            fcm_token=device.fcm_token,
            platform=device.platform,
            device_name=device.device_name,
            app_version=device.app_version
        )
        db.add(new_device)
        await db.commit()
        await db.refresh(new_device)
        return new_device

    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=400, detail="Device registration failed")


@router.get("/devices", response_model=List[DeviceResponse])
async def list_devices(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    List user's registered devices.

    Only returns active devices, ordered by most recently seen.
    """
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.user_id == current_user.id,
            UserDevice.is_active == True
        ).order_by(UserDevice.last_seen_at.desc())
    )
    devices = result.scalars().all()

    return devices


@router.delete("/devices/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device(
    device_id: int,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Unregister a device (soft delete).

    Sets is_active = False instead of deleting the record.
    """
    result = await db.execute(
        select(UserDevice).where(
            UserDevice.id == device_id,
            UserDevice.user_id == current_user.id
        )
    )
    device = result.scalar_one_or_none()

    if not device:
        raise HTTPException(status_code=404, detail="Device not found")

    device.is_active = False
    await db.commit()
    return None


@router.post("/opened", status_code=status.HTTP_204_NO_CONTENT)
async def mark_notification_opened(
    event: NotificationOpenedEvent,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Track when user opens a notification.

    Updates notification history with opened timestamp.
    Used for analytics and engagement tracking.
    """
    result = await db.execute(
        select(NotificationHistory).where(
            NotificationHistory.id == event.notification_history_id,
            NotificationHistory.user_id == current_user.id
        )
    )
    history = result.scalar_one_or_none()

    if history:
        history.was_opened = True
        history.opened_at = datetime.utcnow()
        await db.commit()

    return None


@router.get("/history", response_model=List[NotificationHistoryResponse])
async def get_notification_history(
    limit: int = 30,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get notification history.

    Returns last N notifications sent to user, ordered by most recent.
    """
    result = await db.execute(
        select(NotificationHistory).where(
            NotificationHistory.user_id == current_user.id
        ).order_by(NotificationHistory.sent_at.desc()).limit(limit)
    )
    history = result.scalars().all()

    return [
        NotificationHistoryResponse(
            id=h.id,
            content_item_id=str(h.content_item_id),
            sent_at=h.sent_at,
            was_opened=h.was_opened,
            opened_at=h.opened_at
        )
        for h in history
    ]


@router.post("/test/send-notification", tags=["testing"])
async def test_send_notification(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    TESTING ONLY: Manually trigger notification for current user.

    Bypasses scheduler and time checks.
    Immediately selects gem and sends FCM notification.

    Returns:
        - status: "sent", "no_gem_found", "no_devices", or "fcm_disabled"
        - gem details if sent
        - send results
        - diagnostics: device info, FCM status, etc.
    """
    diagnostics = {
        "user_id": str(current_user.id),
        "fcm_initialized": False,
        "devices_found": 0,
        "devices_details": [],
        "firebase_path": settings.firebase_service_account_path,
        "resolved_path": None,
        "file_exists": False,
        "firebase_admin_available": False
    }

    # Check if firebase-admin is available
    try:
        import firebase_admin
        diagnostics["firebase_admin_available"] = firebase_admin is not None
    except ImportError:
        diagnostics["firebase_admin_available"] = False

    # Check FCM service initialization
    # Create new instance (will reuse Firebase if already initialized by main.py)
    fcm_service = FCMService(settings.firebase_service_account_path)
    diagnostics["fcm_initialized"] = fcm_service.initialized
    diagnostics["resolved_path"] = getattr(fcm_service, 'service_account_path', None)
    diagnostics["firebase_project_id"] = getattr(fcm_service, 'project_id', None)
    diagnostics["firebase_client_email"] = getattr(fcm_service, 'client_email', None)
    
    # Check if file exists
    if diagnostics["resolved_path"]:
        from pathlib import Path
        diagnostics["file_exists"] = Path(diagnostics["resolved_path"]).exists()

    if not fcm_service.initialized:
        error_msg = "Firebase not initialized."
        if not diagnostics["firebase_admin_available"]:
            error_msg += " firebase-admin package not installed."
        elif not diagnostics["file_exists"]:
            error_msg += f" Service account file not found at: {diagnostics['resolved_path']}"
        else:
            error_msg += " Check server logs for initialization errors."
        
        if diagnostics.get("firebase_project_id"):
            error_msg += f"\n\nProject ID: {diagnostics['firebase_project_id']}"
            error_msg += f"\nService Account: {diagnostics.get('firebase_client_email', 'N/A')}"
        
        return {
            "status": "fcm_disabled",
            "message": error_msg,
            "diagnostics": diagnostics
        }

    # Get devices
    devices_result = await db.execute(
        select(UserDevice).where(
            and_(
                UserDevice.user_id == current_user.id,
                UserDevice.is_active == True
            )
        )
    )
    devices = devices_result.scalars().all()
    diagnostics["devices_found"] = len(devices)
    diagnostics["devices_details"] = [
        {
            "id": d.id,
            "platform": d.platform,
            "device_name": d.device_name,
            "token_preview": d.fcm_token[:20] + "..." if d.fcm_token else None,
            "last_seen": d.last_seen_at.isoformat() if d.last_seen_at else None
        }
        for d in devices
    ]

    if not devices:
        return {
            "status": "no_devices",
            "message": "No active devices registered. Make sure the app has registered its FCM token.",
            "diagnostics": diagnostics
        }

    # Select gem using async session
    gem_selector = GemSelector(db)
    gem = await gem_selector.select_gem_for_user(str(current_user.id))

    if not gem:
        return {
            "status": "no_gem_found",
            "message": "No suitable gem found for user. User may not have any unread content.",
            "diagnostics": diagnostics
        }

    # Send notification
    result = fcm_service.send_gem_notification(devices, gem, db)

    # Handle invalid tokens asynchronously if needed
    if result.get("invalid_tokens"):
        await fcm_service._deactivate_tokens_async(result["invalid_tokens"], db)

    # Add error details to diagnostics if send failed
    if result.get("error"):
        diagnostics["send_error"] = result.get("error")
        diagnostics["send_error_type"] = result.get("error_type")

    if result["success"] > 0:
        # Record in history
        history = NotificationHistory(
            user_id=current_user.id,
            content_item_id=gem.id,
            notification_type="test_notification"
        )
        db.add(history)
        await db.commit()

    # Build response message with error details if available
    if result["success"] > 0:
        message = f"Notification sent to {result['success']} device(s)"
    elif result.get("error"):
        message = f"Failed to send notification: {result.get('error')}"
        if "404" in result.get("error", "") or "/batch" in result.get("error", ""):
            project_id = diagnostics.get("firebase_project_id", "recall-fa971")
            client_email = diagnostics.get("firebase_client_email", "N/A")
            message += f"\n\nProject: {project_id}"
            message += f"\nService Account: {client_email}"
            message += "\n\nTroubleshooting:\n"
            message += f"1. Verify FCM API is enabled: https://console.cloud.google.com/apis/library/fcm.googleapis.com?project={project_id}\n"
            message += f"2. Check IAM permissions: https://console.cloud.google.com/iam-admin/iam?project={project_id}\n"
            message += f"   - Find service account: {client_email}\n"
            message += "   - Ensure it has 'Firebase Cloud Messaging API Admin' OR 'Firebase Admin SDK Administrator Service Agent' role\n"
            message += "3. Wait 2-3 minutes after enabling API (propagation delay)\n"
            message += "4. Restart the backend server after enabling API"
    else:
        message = "Failed to send notification"

    return {
        "status": "sent" if result["success"] > 0 else "failed",
        "message": message,
        "gem": {
            "id": str(gem.id),
            "title": gem.title,
            "url": gem.url,
            "summary": gem.summary[:100] if gem.summary else None
        },
        "send_results": {
            "devices_sent": result["success"],
            "devices_failed": result["failed"],
            "invalid_tokens_count": len(result.get("invalid_tokens", [])),
            "error": result.get("error"),
            "error_type": result.get("error_type")
        },
        "diagnostics": diagnostics
    }
