"""
Gem selector service for daily notifications.

Selects the best "gem" content item for each user based on a fixed algorithm:
1. Favorites first (not done, not recently notified)
2. Long-form unread (reading time >= 5 min, last 14 days)
3. Recent quality content (reading time >= 3 min, last 7 days)
4. Fallback: any unread content from last 30 days
"""
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import and_, desc, select
from datetime import datetime, timedelta
from typing import Optional
import logging

from app.models.content_item import ContentItem
from app.models.notification_settings import NotificationHistory, UserNotificationSettings

logger = logging.getLogger(__name__)


class GemSelector:
    """
    Selects the best "gem" content item for daily notifications.

    Algorithm (Phase 1 - Fixed):
    - Tier 1: Favorites (not done, not recently notified)
    - Tier 2: Long-form unread (reading_time >= 5 min, recent saves)
    - Tier 3: Recent quality saves (reading_time >= 3 min, last 7 days)
    - Tier 4: Fallback - any unread content from last 30 days
    """

    def __init__(self, db: AsyncSession):
        """
        Initialize gem selector.

        Args:
            db: SQLAlchemy async database session
        """
        self.db = db

    async def select_gem_for_user(self, user_id: str) -> Optional[ContentItem]:
        """
        Select best gem for user based on fixed algorithm.

        Args:
            user_id: UUID of the user

        Returns:
            ContentItem if suitable gem found, None otherwise
        """
        settings = await self._get_user_settings(user_id)

        # Tier 1: Favorite content (not done, not recently notified)
        gem = await self._try_favorite_gem(user_id, settings)
        if gem:
            logger.info(f"Selected favorite gem for user {user_id}: {gem.id} - '{gem.title[:50]}'")
            return gem

        # Tier 2: Long-form unread (reading_time >= 5 min)
        gem = await self._try_longform_gem(user_id, settings)
        if gem:
            logger.info(f"Selected long-form gem for user {user_id}: {gem.id} - '{gem.title[:50]}'")
            return gem

        # Tier 3: Recent quality content (reading_time >= 3 min, last 7 days)
        gem = await self._try_recent_gem(user_id, settings)
        if gem:
            logger.info(f"Selected recent gem for user {user_id}: {gem.id} - '{gem.title[:50]}'")
            return gem

        # Tier 4: Fallback - any unread from last 30 days
        gem = await self._try_fallback_gem(user_id, settings)
        if gem:
            logger.info(f"Selected fallback gem for user {user_id}: {gem.id} - '{gem.title[:50]}'")
            return gem

        logger.info(f"No suitable gem found for user {user_id}")
        return None

    async def _get_user_settings(self, user_id: str) -> Optional[UserNotificationSettings]:
        """Get user's notification settings"""
        result = await self.db.execute(
            select(UserNotificationSettings).where(
                UserNotificationSettings.user_id == user_id
            )
        )
        return result.scalar_one_or_none()

    async def _get_excluded_content_ids(self, user_id: str, days: int = 30) -> list:
        """
        Get content IDs already notified in last N days.

        Prevents sending the same content repeatedly.

        Args:
            user_id: UUID of the user
            days: Number of days to look back (default: 30)

        Returns:
            List of content item UUIDs
        """
        cutoff = datetime.utcnow() - timedelta(days=days)
        result = await self.db.execute(
            select(NotificationHistory.content_item_id).where(
                and_(
                    NotificationHistory.user_id == user_id,
                    NotificationHistory.sent_at >= cutoff
                )
            )
        )
        return [item[0] for item in result.all()]

    async def _base_query(
        self,
        user_id: str,
        settings: Optional[UserNotificationSettings],
        skip_min_reading_time: bool = False
    ):
        """
        Build base query with common filters.

        Excludes:
        - Completed content (is_done = True)
        - Content already notified in last 30 days

        Applies user settings filters if available:
        - min_reading_time (unless skip_min_reading_time=True)
        - preferred_categories
        - include_favorites_only

        Args:
            user_id: UUID of the user
            settings: User's notification settings
            skip_min_reading_time: If True, ignore min_reading_time filter (for fallback tier)

        Returns:
            SQLAlchemy select statement
        """
        excluded_ids = await self._get_excluded_content_ids(user_id)

        query = select(ContentItem).where(
            and_(
                ContentItem.user_id == user_id,
                ContentItem.is_done == False  # Not completed
            )
        )

        # Exclude already notified content
        if excluded_ids:
            query = query.where(ContentItem.id.notin_(excluded_ids))

        # Apply user settings filters
        if settings:
            if settings.min_reading_time and not skip_min_reading_time:
                query = query.where(
                    ContentItem.reading_time_minutes >= settings.min_reading_time
                )

            if settings.preferred_categories:
                query = query.where(
                    ContentItem.category.in_(settings.preferred_categories)
                )

            if settings.include_favorites_only:
                query = query.where(ContentItem.is_favorite == True)

        return query

    async def _try_favorite_gem(
        self,
        user_id: str,
        settings: Optional[UserNotificationSettings]
    ) -> Optional[ContentItem]:
        """
        Tier 1: Select from favorites.

        Priority:
        - User-marked favorites
        - Not completed
        - Not recently notified
        - Longer content first
        - Most recent first
        """
        query = await self._base_query(user_id, settings)
        query = query.where(ContentItem.is_favorite == True).order_by(
            desc(ContentItem.reading_time_minutes),  # Prioritize longer content
            desc(ContentItem.created_at)  # Then most recent
        )

        result = await self.db.execute(query.limit(1))
        return result.scalars().first()

    async def _try_longform_gem(
        self,
        user_id: str,
        settings: Optional[UserNotificationSettings]
    ) -> Optional[ContentItem]:
        """
        Tier 2: Long-form content (5+ min reads).

        Priority:
        - Reading time >= 5 minutes
        - Saved in last 14 days
        - Not completed
        - Longer content first
        """
        last_14_days = datetime.utcnow() - timedelta(days=14)

        query = await self._base_query(user_id, settings)
        query = query.where(
            and_(
                ContentItem.reading_time_minutes >= 5,
                ContentItem.created_at >= last_14_days
            )
        ).order_by(
            desc(ContentItem.reading_time_minutes),
            desc(ContentItem.created_at)
        )

        result = await self.db.execute(query.limit(1))
        return result.scalars().first()

    async def _try_recent_gem(
        self,
        user_id: str,
        settings: Optional[UserNotificationSettings]
    ) -> Optional[ContentItem]:
        """
        Tier 3: Recent quality content (3+ min, last 7 days).

        Priority:
        - Reading time >= 3 minutes
        - Saved in last 7 days
        - Not completed
        - Longer content first
        """
        last_7_days = datetime.utcnow() - timedelta(days=7)

        query = await self._base_query(user_id, settings)
        query = query.where(
            and_(
                ContentItem.reading_time_minutes >= 3,
                ContentItem.created_at >= last_7_days
            )
        ).order_by(
            desc(ContentItem.reading_time_minutes),
            desc(ContentItem.created_at)
        )

        result = await self.db.execute(query.limit(1))
        return result.scalars().first()

    async def _try_fallback_gem(
        self,
        user_id: str,
        settings: Optional[UserNotificationSettings]
    ) -> Optional[ContentItem]:
        """
        Tier 4: Any unread content from last 30 days.

        This is the fallback when user has no favorites or recent quality content.
        Simply returns the most recent unread item.

        Note: Skips min_reading_time filter to ensure users with only short content
        still receive notifications.
        """
        last_30_days = datetime.utcnow() - timedelta(days=30)

        # Skip min_reading_time filter for fallback tier
        query = await self._base_query(user_id, settings, skip_min_reading_time=True)
        query = query.where(
            ContentItem.created_at >= last_30_days
        ).order_by(
            desc(ContentItem.created_at)
        )

        result = await self.db.execute(query.limit(1))
        return result.scalars().first()
