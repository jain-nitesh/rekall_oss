"""
Daily notification scheduler service.

Runs every minute to check for users whose notification time matches current UTC time.
Selects "gem" content and sends push notifications via FCM.
"""
import logging
from datetime import datetime, time, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func

from app.db.session import AsyncSessionLocal
from app.models.notification_settings import (
    UserNotificationSettings,
    NotificationHistory,
    UserDevice
)
from app.services.gem_selector import GemSelector
from app.services.connection_gem_selector import ConnectionGemSelector
from app.services.fcm_service import FCMService

logger = logging.getLogger(__name__)


class NotificationScheduler:
    """
    Daily notification scheduler - runs every minute.

    Sends notifications to users whose notification_time_utc matches current UTC time.
    Multi-instance safe using database-level duplicate prevention.
    """

    def __init__(self, fcm_service: FCMService):
        """
        Initialize notification scheduler.

        Args:
            fcm_service: Firebase Cloud Messaging service for sending notifications
        """
        self.fcm_service = fcm_service

    async def run_scheduled_notifications(self):
        """
        Main scheduler method - called every minute.

        Flow:
        1. Find users whose notification time matches current hour:minute
        2. For each user:
           - Check if already notified today
           - Select best gem using GemSelector
           - Get user's active devices
           - Send FCM notification
           - Record in history
        """
        print(f"[NOTIFICATION SCHEDULER] Running at {datetime.utcnow().isoformat()}")
        logger.info(f"Notification scheduler running at {datetime.utcnow().isoformat()}")
        
        db = AsyncSessionLocal()
        try:
            current_utc_time = datetime.utcnow().time()
            current_hour = current_utc_time.hour
            current_minute = current_utc_time.minute
            print(f"[NOTIFICATION SCHEDULER] Checking for notifications at {current_hour:02d}:{current_minute:02d} UTC")

            # Create target time range (current minute)
            # We use a range to handle time precision issues
            target_time_start = time(current_hour, current_minute)
            next_minute = current_minute + 1
            if next_minute >= 60:
                target_time_end = time((current_hour + 1) % 24, 0)
            else:
                target_time_end = time(current_hour, next_minute)

            # Log what we're looking for
            print(f"[NOTIFICATION SCHEDULER] Looking for users with notification_time_utc = {current_hour:02d}:{current_minute:02d} (current UTC: {current_utc_time})")
            logger.info(f"Notification scheduler check: Looking for users with notification_time_utc = {current_hour:02d}:{current_minute:02d} (current UTC: {current_utc_time})")

            # Find users whose notification time matches current time
            # Compare hour and minute separately to avoid issues with seconds/microseconds
            result = await db.execute(
                select(UserNotificationSettings).where(
                    and_(
                        UserNotificationSettings.is_enabled == True,
                        # Extract hour from notification_time_utc and compare
                        func.extract('hour', UserNotificationSettings.notification_time_utc) == current_hour,
                        # Extract minute from notification_time_utc and compare
                        func.extract('minute', UserNotificationSettings.notification_time_utc) == current_minute
                    )
                )
            )
            users_to_notify = result.scalars().all()

            # Log all notification settings to help diagnose
            if not users_to_notify:
                # Check for enabled settings
                debug_result = await db.execute(
                    select(UserNotificationSettings).where(
                        UserNotificationSettings.is_enabled == True
                    )
                )
                all_enabled = debug_result.scalars().all()
                
                # Also check for all settings (enabled or disabled)
                all_result = await db.execute(select(UserNotificationSettings))
                all_settings = all_result.scalars().all()
                
                if all_enabled:
                    logger.info(f"Found {len(all_enabled)} enabled notification setting(s), but none match current time {current_hour:02d}:{current_minute:02d}:")
                    for s in all_enabled:
                        notif_hour = s.notification_time_utc.hour
                        notif_minute = s.notification_time_utc.minute
                        logger.info(f"  - User {s.user_id}: notification_time_utc={s.notification_time_utc} ({notif_hour:02d}:{notif_minute:02d})")
                elif all_settings:
                    print(f"[NOTIFICATION SCHEDULER] ⚠️ Found {len(all_settings)} notification setting(s) in database, but ALL are DISABLED (is_enabled=False)")
                    print(f"[NOTIFICATION SCHEDULER] ⚠️ Users need to enable notifications via PUT /api/notifications/settings with is_enabled=true")
                    logger.warning(f"Found {len(all_settings)} notification setting(s) in database, but ALL are DISABLED (is_enabled=False)")
                    logger.warning("Users need to enable notifications via PUT /api/notifications/settings with is_enabled=true")
                    for s in all_settings:
                        notif_hour = s.notification_time_utc.hour
                        notif_minute = s.notification_time_utc.minute
                        logger.info(f"  - User {s.user_id}: is_enabled={s.is_enabled}, notification_time_utc={s.notification_time_utc} ({notif_hour:02d}:{notif_minute:02d})")
                else:
                    print(f"[NOTIFICATION SCHEDULER] ⚠️ No notification settings found in database at all")
                    print(f"[NOTIFICATION SCHEDULER] ⚠️ Users need to call GET /api/notifications/settings to create settings, then enable them")
                    logger.warning("No notification settings found in database at all")
                    logger.warning("Users need to call GET /api/notifications/settings to create settings, then enable them")
                return

            print(f"[NOTIFICATION SCHEDULER] Processing notifications for {len(users_to_notify)} user(s) at {target_time_start} (current UTC: {current_utc_time})")
            logger.info(f"Processing notifications for {len(users_to_notify)} user(s) at {target_time_start} (current UTC: {current_utc_time})")

            for settings in users_to_notify:
                try:
                    # Check if already notified today
                    if self._already_notified_today(settings):
                        logger.info(f"User {settings.user_id} already notified today, skipping")
                        continue

                    # Try connection notification first, fall back to gem
                    print(f"[NOTIFICATION SCHEDULER] Selecting notification for user {settings.user_id}")
                    logger.info(f"Selecting notification for user {settings.user_id}")

                    notification_type = "daily_gem"
                    notification_title = None
                    notification_body = None
                    notification_data = {}
                    gem = None
                    connection_result = None

                    # Try connection-based notification first
                    try:
                        conn_selector = ConnectionGemSelector(db)
                        connection_result = await conn_selector.select_connection_for_user(str(settings.user_id))
                    except Exception as conn_err:
                        logger.warning(f"Connection selector failed for user {settings.user_id}: {conn_err}")

                    if connection_result:
                        conn, source, target = connection_result
                        notification_type = "daily_connection"
                        notification_title = "Your reading is connected"
                        explanation = conn.ai_explanation or "These articles share a common thread"
                        notification_body = f'"{source.title[:50]}" relates to "{target.title[:50]}" — {explanation}'
                        notification_data = {
                            'type': 'daily_connection',
                            'connection_id': str(conn.id),
                            'source_item_id': str(source.id),
                            'target_item_id': str(target.id),
                        }
                        gem = source  # Use source item for history tracking
                        print(f"[NOTIFICATION SCHEDULER] Connection selected: {conn.id}")
                    else:
                        # Fall back to regular gem notification
                        gem_selector = GemSelector(db)
                        gem = await gem_selector.select_gem_for_user(str(settings.user_id))

                    if not gem:
                        logger.info(f"No content found for user {settings.user_id}, skipping notification")
                        continue

                    if not notification_title:
                        notification_data = {
                            'type': 'daily_gem',
                            'content_item_id': str(gem.id),
                        }

                    print(f"[NOTIFICATION SCHEDULER] Content selected for user {settings.user_id}: {gem.id} - '{gem.title[:50]}' (type: {notification_type})")
                    logger.info(f"Content selected for user {settings.user_id}: {gem.id} - '{gem.title[:50]}' (type: {notification_type})")

                    # Get user's devices
                    logger.info(f"Fetching devices for user {settings.user_id}")
                    devices_result = await db.execute(
                        select(UserDevice).where(
                            and_(
                                UserDevice.user_id == settings.user_id,
                                UserDevice.is_active == True
                            )
                        )
                    )
                    devices = devices_result.scalars().all()

                    if not devices:
                        print(f"[NOTIFICATION SCHEDULER] ⚠️ No active devices for user {settings.user_id} - notification cannot be sent")
                        logger.warning(f"No active devices for user {settings.user_id} - notification cannot be sent")
                        continue

                    print(f"[NOTIFICATION SCHEDULER] Found {len(devices)} active device(s) for user {settings.user_id}")
                    logger.info(f"Found {len(devices)} active device(s) for user {settings.user_id}")

                    # Send notification
                    logger.info(f"Sending FCM notification to {len(devices)} device(s) for user {settings.user_id}")
                    result = self.fcm_service.send_gem_notification(devices, gem, db)
                    print(f"[NOTIFICATION SCHEDULER] FCM send result for user {settings.user_id}: success={result.get('success', 0)}, failed={result.get('failed', 0)}, invalid_tokens={len(result.get('invalid_tokens', []))}")
                    logger.info(f"FCM send result for user {settings.user_id}: success={result.get('success', 0)}, failed={result.get('failed', 0)}, invalid_tokens={len(result.get('invalid_tokens', []))}")

                    # Handle invalid tokens asynchronously if needed
                    if result.get("invalid_tokens"):
                        logger.info(f"Deactivating {len(result['invalid_tokens'])} invalid token(s) for user {settings.user_id}")
                        await self.fcm_service._deactivate_tokens_async(result["invalid_tokens"], db)

                    if result["success"] > 0:
                        # Record in history
                        logger.info(f"Recording notification history for user {settings.user_id}")
                        history = NotificationHistory(
                            user_id=settings.user_id,
                            content_item_id=gem.id,
                            notification_type=notification_type
                        )
                        db.add(history)

                        # Update last sent timestamp
                        settings.last_notification_sent_at = datetime.utcnow()

                        logger.info(f"Committing notification for user {settings.user_id}")
                        await db.commit()
                        print(f"[NOTIFICATION SCHEDULER] ✅ Successfully sent notification to user {settings.user_id} for content '{gem.title[:50]}' ({result['success']} device(s))")
                        logger.info(
                            f"✅ Successfully sent notification to user {settings.user_id} "
                            f"for content '{gem.title[:50]}' ({result['success']} device(s))"
                        )
                    else:
                        error_msg = result.get("error", "Unknown error")
                        error_type = result.get("error_type", "Unknown")
                        print(f"[NOTIFICATION SCHEDULER] ❌ Failed to send notification to user {settings.user_id}: success={result.get('success', 0)}, failed={result.get('failed', 0)}, error={error_type}: {error_msg}")
                        logger.warning(
                            f"❌ Failed to send notification to user {settings.user_id}: "
                            f"success={result.get('success', 0)}, failed={result.get('failed', 0)}, "
                            f"error={error_type}: {error_msg}"
                        )

                except Exception as e:
                    logger.error(f"Error processing notification for user {settings.user_id}: {e}")
                    import traceback
                    logger.error(traceback.format_exc())
                    try:
                        await db.rollback()
                    except Exception as rollback_error:
                        logger.error(f"Error during rollback: {rollback_error}")
                    continue

        except Exception as e:
            logger.error(f"Error in notification scheduler: {e}")
            import traceback
            traceback.print_exc()
        finally:
            await db.close()

    def _already_notified_today(self, settings: UserNotificationSettings) -> bool:
        """
        Check if user already received notification today.

        Args:
            settings: User's notification settings

        Returns:
            True if already notified today, False otherwise
        """
        if not settings.last_notification_sent_at:
            return False

        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        return settings.last_notification_sent_at >= today_start
