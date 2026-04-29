"""
Firebase Cloud Messaging service for sending push notifications.

Handles sending daily gem notifications to user devices via FCM.
"""
from typing import List, Optional, Union
import logging
import os
from pathlib import Path
from datetime import datetime

try:
    import firebase_admin
    from firebase_admin import credentials, messaging
except ImportError:
    firebase_admin = None
    messaging = None

from app.models.content_item import ContentItem
from app.models.notification_settings import UserDevice
from sqlalchemy.orm import Session
from sqlalchemy.ext.asyncio import AsyncSession

logger = logging.getLogger(__name__)


class FCMService:
    """
    Firebase Cloud Messaging service for sending push notifications.

    Handles:
    - FCM initialization with service account
    - Sending multicast messages to multiple devices
    - Invalid token cleanup
    """

    def __init__(self, service_account_path: Optional[str] = None):
        """
        Initialize FCM service.

        Args:
            service_account_path: Path to Firebase service account JSON file
        """
        self.initialized = False
        self.service_account_path = None
        self.project_id = None
        self.client_email = None

        if not firebase_admin:
            logger.warning("firebase-admin not installed, FCM disabled")
            return

        if not service_account_path:
            logger.warning("Firebase service account path not provided, FCM disabled")
            return

        # Resolve path - handle relative paths relative to backend directory
        resolved_path = self._resolve_path(service_account_path)
        self.service_account_path = str(resolved_path)

        if not resolved_path.exists():
            logger.error(f"Firebase service account file not found: {resolved_path}")
            logger.error(f"Current working directory: {os.getcwd()}")
            logger.error(f"Resolved path: {resolved_path.absolute()}")
            return

        try:
            # Load service account to verify project ID
            import json
            with open(resolved_path, 'r') as f:
                service_account_data = json.load(f)
            
            self.project_id = service_account_data.get('project_id')
            self.client_email = service_account_data.get('client_email')
            
            logger.info(f"Loading Firebase service account: project_id={self.project_id}, client_email={self.client_email}")
            
            cred = credentials.Certificate(str(resolved_path))
            
            # Check if Firebase app is already initialized
            try:
                existing_app = firebase_admin.get_app()
                logger.warning("Firebase app already initialized, skipping re-initialization")
                # Verify it's using the same project
                if hasattr(existing_app, 'project_id'):
                    logger.info(f"Existing Firebase app project: {existing_app.project_id}")
                self.initialized = True
            except ValueError:
                # App not initialized, initialize it
                # Use explicit project_id to ensure we're using the correct project
                app = firebase_admin.initialize_app(
                    cred,
                    options={'projectId': self.project_id}
                )
                self.initialized = True
                logger.info(f"Firebase Admin SDK initialized with service account: {resolved_path}")
                logger.info(f"Firebase project ID: {self.project_id}")
                logger.info(f"Using HTTP v1 API (not legacy /batch endpoint)")
        except Exception as e:
            logger.error(f"Failed to initialize Firebase: {e}")
            import traceback
            logger.error(traceback.format_exc())
            self.project_id = None
            self.client_email = None

    def _resolve_path(self, path: str) -> Path:
        """
        Resolve file path, handling relative paths.

        If path is relative, resolve it relative to the backend directory.
        """
        path_obj = Path(path)
        
        # If absolute path, return as-is
        if path_obj.is_absolute():
            return path_obj
        
        # If relative, resolve relative to backend directory
        # Get the backend directory (where this file is located)
        backend_dir = Path(__file__).parent.parent.parent  # app/services -> app -> recall_backend
        resolved = backend_dir / path_obj
        
        return resolved

    def send_gem_notification(
        self,
        devices: List[UserDevice],
        content_item: ContentItem,
        db: Union[Session, AsyncSession]
    ) -> dict:
        """
        Send gem notification to multiple devices.

        Args:
            devices: List of user devices to send to
            content_item: Content item to notify about
            db: Database session for updating invalid tokens

        Returns:
            Dictionary with send results:
            {
                "success": int,  # Number of successful sends
                "failed": int,   # Number of failed sends
                "invalid_tokens": List[str]  # Tokens that are invalid
            }
        """
        if not self.initialized:
            logger.error("FCM not initialized - cannot send notification")
            logger.error(f"Firebase admin installed: {firebase_admin is not None}")
            logger.error(f"Service account path: {self.service_account_path}")
            logger.error(f"Project ID: {self.project_id}")
            logger.error(f"Client email: {self.client_email}")
            return {
                "success": 0,
                "failed": 0,
                "invalid_tokens": [],
                "error": "FCM not initialized",
                "error_type": "FCMNotInitialized"
            }

        tokens = [d.fcm_token for d in devices if d.is_active]
        if not tokens:
            logger.warning(f"No active device tokens to send to (total devices: {len(devices)}, active: {sum(1 for d in devices if d.is_active)})")
            return {
                "success": 0,
                "failed": 0,
                "invalid_tokens": [],
                "error": "No active device tokens",
                "error_type": "NoActiveTokens"
            }

        logger.info(f"Preparing FCM notification for {len(tokens)} token(s)")

        try:
            # Build notification payload
            notification = messaging.Notification(
                title="💎 Your Daily Gem",
                body=self._truncate(content_item.summary or content_item.title, 150),
                image=content_item.thumbnail_url if content_item.thumbnail_url else None
            )

            # Deep link data
            data = {
                "type": "daily_gem",
                "content_item_id": str(content_item.id),  # Fixed: mobile app expects content_item_id
                "click_action": "FLUTTER_NOTIFICATION_CLICK",
                "route": f"/content/{content_item.id}"
            }

            # Send multicast message
            message = messaging.MulticastMessage(
                notification=notification,
                data=data,
                tokens=tokens,
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        icon="ic_launcher",
                        color="#FF5722"
                    )
                ),
                apns=messaging.APNSConfig(
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(
                            badge=1,
                            sound="default"
                        )
                    )
                )
            )

            logger.info(f"Sending FCM multicast message to {len(tokens)} device(s)")
            # Firebase Admin SDK 7.0.0+ uses send_each_for_multicast() instead of send_multicast()
            response = messaging.send_each_for_multicast(message)
            
            # Validate response structure
            if not hasattr(response, 'success_count') or not hasattr(response, 'failure_count'):
                logger.error(
                    f"Unexpected FCM response structure: {type(response)}, "
                    f"attributes: {dir(response)}"
                )
                return {
                    "success": 0,
                    "failed": len(tokens),
                    "invalid_tokens": [],
                    "error": f"Unexpected response structure: {type(response)}",
                    "error_type": "InvalidResponse"
                }
            
            success_count = getattr(response, 'success_count', 0)
            failure_count = getattr(response, 'failure_count', 0)
            
            # Check for unexpected state: both counts are 0 but we have tokens
            if success_count == 0 and failure_count == 0 and len(tokens) > 0:
                logger.error(
                    f"Unexpected FCM response: both success_count and failure_count are 0 "
                    f"but {len(tokens)} token(s) were sent. Response type: {type(response)}, "
                    f"Response attributes: {[attr for attr in dir(response) if not attr.startswith('_')]}"
                )
                # This shouldn't happen, but if it does, treat as failure
                failure_count = len(tokens)
            
            logger.info(
                f"FCM sent: {success_count} success, "
                f"{failure_count} failed for content '{content_item.title[:50]}'"
            )

            # Handle invalid tokens
            invalid_tokens = []
            if failure_count > 0:
                logger.warning(f"Processing {failure_count} failed FCM send(s)")
                if hasattr(response, 'responses') and response.responses:
                    for idx, result in enumerate(response.responses):
                        if not result.success:
                            if idx < len(tokens):
                                token = tokens[idx]
                                error_code = result.exception.code if result.exception else None
                                error_message = str(result.exception) if result.exception else "Unknown error"

                                logger.warning(
                                    f"FCM send failed: code={error_code}, message={error_message}"
                                )

                                # Mark token as inactive if permanently invalid
                                if error_code in ['INVALID_ARGUMENT', 'NOT_FOUND', 'UNREGISTERED']:
                                    logger.warning(f"Invalid FCM token: {error_code}")
                                    invalid_tokens.append(token)
                                    # For sync sessions, deactivate immediately
                                    # For async sessions, caller should handle deactivation
                                    if not isinstance(db, AsyncSession):
                                        self._deactivate_token(token, db)
                                else:
                                    logger.warning(f"FCM send error: {error_code} - {error_message}")
                            else:
                                logger.error(f"Response index {idx} out of range for tokens list (len={len(tokens)})")
                else:
                    logger.warning(f"Response has no 'responses' attribute or responses list is empty")

            return {
                "success": success_count,
                "failed": failure_count,
                "invalid_tokens": invalid_tokens
            }

        except Exception as e:
            error_msg = str(e)
            error_type = type(e).__name__
            
            # Log full exception details
            import traceback
            full_traceback = traceback.format_exc()
            logger.error(f"FCM send failed: {error_type}: {error_msg}")
            logger.error(f"FCM send exception traceback:\n{full_traceback}")
            logger.error(f"FCM send context: tokens_count={len(tokens)}, project_id={self.project_id}, initialized={self.initialized}")
            
            # Check for specific error patterns
            if "404" in error_msg or "/batch" in error_msg:
                logger.error(
                    f"FCM API 404 error for project: {self.project_id}\n"
                    "This usually means:\n"
                    "1. Firebase Cloud Messaging API is not enabled for your project\n"
                    "2. Service account doesn't have 'Firebase Cloud Messaging API Admin' permission\n"
                    "   OR 'Firebase Admin SDK Administrator Service Agent' role\n"
                    "3. Wrong Firebase project ID in service account\n"
                    "4. API propagation delay (wait a few minutes after enabling)\n"
                    f"Check API: https://console.cloud.google.com/apis/library/fcm.googleapis.com?project={self.project_id}\n"
                    f"Check IAM: https://console.cloud.google.com/iam-admin/iam?project={self.project_id}\n"
                    f"Service account: {self.client_email}"
                )
            elif "401" in error_msg or "403" in error_msg:
                logger.error(
                    "FCM API authentication error - Service account may not have proper permissions"
                )
            elif "network" in error_msg.lower() or "connection" in error_msg.lower():
                logger.error("FCM API network error - Check internet connectivity")
            elif not error_msg or error_msg == "Unknown error":
                logger.error(
                    "FCM send failed with generic/empty error message. "
                    "This might indicate:\n"
                    "1. Firebase Admin SDK not properly initialized\n"
                    "2. Service account credentials issue\n"
                    "3. Network/timeout issue\n"
                    f"Check initialization: initialized={self.initialized}, "
                    f"project_id={self.project_id}, "
                    f"service_account_path={self.service_account_path}"
                )
            
            return {
                "success": 0, 
                "failed": len(tokens) if tokens else 0, 
                "invalid_tokens": [],
                "error": error_msg if error_msg else "Unknown error",
                "error_type": error_type if error_type else "Unknown"
            }

    async def _deactivate_tokens_async(self, tokens: List[str], db: AsyncSession):
        """
        Deactivate multiple tokens asynchronously.
        
        Args:
            tokens: List of FCM tokens to deactivate
            db: Async database session
        """
        try:
            from sqlalchemy import select, update
            from app.models.notification_settings import UserDevice
            
            for token in tokens:
                result = await db.execute(
                    select(UserDevice).filter(UserDevice.fcm_token == token)
                )
                device = result.scalar_one_or_none()
                if device:
                    device.is_active = False
                    logger.info(f"Deactivated device token: {device.id}")
            
            await db.commit()
        except Exception as e:
            logger.error(f"Failed to deactivate tokens asynchronously: {e}")
            await db.rollback()

    def _truncate(self, text: str, max_length: int) -> str:
        """
        Truncate text to max length with ellipsis.

        Args:
            text: Text to truncate
            max_length: Maximum length

        Returns:
            Truncated text
        """
        if len(text) <= max_length:
            return text
        return text[:max_length-3] + "..."

    def _deactivate_token(self, token: str, db: Union[Session, AsyncSession]):
        """
        Mark device token as inactive.

        Args:
            token: FCM token to deactivate
            db: Database session (sync or async)
        """
        try:
            if isinstance(db, AsyncSession):
                # For async sessions, we'll deactivate in the calling code
                # This method is called from sync context, so we just log
                logger.warning("Token deactivation skipped for async session")
                # The calling code should handle async deactivation
            else:
                # Handle sync session
                device = db.query(UserDevice).filter(UserDevice.fcm_token == token).first()
                if device:
                    device.is_active = False
                    db.commit()
                    logger.info(f"Deactivated device token: {device.id}")
        except Exception as e:
            logger.error(f"Failed to deactivate token: {e}")
            if not isinstance(db, AsyncSession):
                db.rollback()
