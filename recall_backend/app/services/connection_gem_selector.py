"""
Connection gem selector for daily notifications.

Selects the highest-similarity connection that hasn't been notified yet.
Falls back to the regular GemSelector if no connections are available.
"""
import logging
from datetime import datetime, timedelta
from typing import Optional, Tuple
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, desc

from app.models.content_connection import ContentConnection
from app.models.content_item import ContentItem
from app.models.notification_settings import NotificationHistory

logger = logging.getLogger(__name__)


class ConnectionGemSelector:
    """
    Selects the best connection pair for daily notifications.

    Priority:
    1. Highest similarity score
    2. Not dismissed
    3. Not previously notified (type='daily_connection')
    4. Minimum similarity >= 0.7
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    async def select_connection_for_user(
        self, user_id: str
    ) -> Optional[Tuple[ContentConnection, ContentItem, ContentItem]]:
        """
        Select the best connection pair for notification.

        Returns:
            Tuple of (connection, source_item, target_item) or None
        """
        # Get IDs of connections already notified
        notified_result = await self.db.execute(
            select(NotificationHistory.content_item_id).where(
                and_(
                    NotificationHistory.user_id == user_id,
                    NotificationHistory.notification_type == 'daily_connection',
                )
            )
        )
        notified_ids = {str(row[0]) for row in notified_result.fetchall()}

        # Find best unnotified connection
        query = select(ContentConnection).where(
            and_(
                ContentConnection.user_id == user_id,
                ContentConnection.is_dismissed == False,
                ContentConnection.similarity_score >= 0.7,
            )
        ).order_by(desc(ContentConnection.similarity_score)).limit(20)

        result = await self.db.execute(query)
        connections = result.scalars().all()

        for conn in connections:
            # Skip if already notified about this connection
            if str(conn.id) in notified_ids:
                continue

            # Load both items
            source = await self.db.get(ContentItem, conn.source_item_id)
            target = await self.db.get(ContentItem, conn.target_item_id)

            if source and target:
                logger.info(
                    f"Selected connection {conn.id} for user {user_id}: "
                    f"'{source.title[:40]}' <-> '{target.title[:40]}' "
                    f"(similarity: {conn.similarity_score:.2f})"
                )
                return (conn, source, target)

        logger.info(f"No suitable connections found for user {user_id}")
        return None
