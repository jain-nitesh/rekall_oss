"""
Insights service for generating personalized user insights.
Computes aggregations from content, connections, and clusters.
"""
import logging
from dataclasses import dataclass
from typing import List, Optional
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text

from app.models.content_item import ContentItem, ContentType
from app.models.content_connection import ContentConnection

logger = logging.getLogger(__name__)


@dataclass
class Insight:
    """A single user insight."""
    type: str  # 'topic_count', 'active_topic', 'connections', 'forgotten_gem', 'streak'
    title: str
    description: str
    value: Optional[int] = None
    icon: Optional[str] = None


class InsightsService:
    """Generate personalized insights from user's content library."""

    async def get_user_insights(self, user_id: str, db: AsyncSession) -> List[Insight]:
        """
        Generate insights for a user. Returns a list of insight cards.

        Insights include:
        - Topic activity ("You've captured 7 ideas about fitness this month")
        - Most active topic
        - Unreviewed connections
        - Content type breakdown
        - Forgotten gems (old items with high connections, never opened)
        """
        insights = []

        # 1. Total content count
        total_sql = select(func.count(ContentItem.id)).where(
            ContentItem.user_id == user_id
        )
        total = (await db.execute(total_sql)).scalar() or 0

        if total == 0:
            return [Insight(
                type="empty",
                title="Start capturing",
                description="Save your first content to start building your personal knowledge base.",
                icon="rocket",
            )]

        # 2. Content added this month
        month_ago = datetime.utcnow() - timedelta(days=30)
        month_sql = select(func.count(ContentItem.id)).where(
            ContentItem.user_id == user_id,
            ContentItem.created_at >= month_ago,
        )
        this_month = (await db.execute(month_sql)).scalar() or 0
        insights.append(Insight(
            type="monthly_activity",
            title=f"{this_month} items this month",
            description=f"You've captured {this_month} items in the last 30 days. Total library: {total} items.",
            value=this_month,
            icon="calendar",
        ))

        # 3. Most active category this month
        cat_sql = text("""
            SELECT category, COUNT(*) as cnt
            FROM content_items
            WHERE user_id = :user_id AND created_at >= :since
            GROUP BY category
            ORDER BY cnt DESC
            LIMIT 1
        """)
        cat_result = await db.execute(cat_sql, {"user_id": user_id, "since": month_ago})
        top_cat = cat_result.fetchone()
        if top_cat and top_cat[0]:
            cat_name = (top_cat[0] or "uncategorized").capitalize()
            insights.append(Insight(
                type="active_topic",
                title=f"Top topic: {cat_name}",
                description=f"Your most active category is {cat_name} with {top_cat[1]} items this month.",
                value=top_cat[1],
                icon="trending_up",
            ))

        # 4. Content type breakdown
        type_sql = text("""
            SELECT content_type, COUNT(*) as cnt
            FROM content_items
            WHERE user_id = :user_id
            GROUP BY content_type
            ORDER BY cnt DESC
        """)
        type_result = await db.execute(type_sql, {"user_id": user_id})
        type_rows = type_result.fetchall()
        type_breakdown = {row[0]: row[1] for row in type_rows}

        media_count = type_breakdown.get("image", 0) + type_breakdown.get("video", 0)
        if media_count > 0:
            insights.append(Insight(
                type="media_count",
                title=f"{media_count} media captures",
                description=f"You have {type_breakdown.get('image', 0)} photos and {type_breakdown.get('video', 0)} videos in your library.",
                value=media_count,
                icon="camera",
            ))

        # 5. Unexplored connections
        conn_sql = text("""
            SELECT COUNT(*) FROM content_connections
            WHERE (source_item_id IN (SELECT id FROM content_items WHERE user_id = :user_id)
                   OR target_item_id IN (SELECT id FROM content_items WHERE user_id = :user_id))
              AND is_dismissed = false
              AND explored_at IS NULL
        """)
        unexplored = (await db.execute(conn_sql, {"user_id": user_id})).scalar() or 0
        if unexplored > 0:
            insights.append(Insight(
                type="connections",
                title=f"{unexplored} connections to explore",
                description=f"AI discovered {unexplored} connections between your saved items. Tap to explore.",
                value=unexplored,
                icon="hub",
            ))

        # 6. Trending tags (most used this week)
        week_ago = datetime.utcnow() - timedelta(days=7)
        tag_sql = text("""
            SELECT unnest(tags) as tag, COUNT(*) as cnt
            FROM content_items
            WHERE user_id = :user_id AND created_at >= :since
            GROUP BY tag
            ORDER BY cnt DESC
            LIMIT 5
        """)
        tag_result = await db.execute(tag_sql, {"user_id": user_id, "since": week_ago})
        trending_tags = [row[0] for row in tag_result.fetchall()]
        if trending_tags:
            insights.append(Insight(
                type="trending_tags",
                title="Trending in your library",
                description=", ".join(trending_tags),
                icon="label",
            ))

        # 7. Forgotten gems (old items with connections but never marked done)
        gem_sql = text("""
            SELECT COUNT(*) FROM content_items
            WHERE user_id = :user_id
              AND created_at < :before
              AND connection_count >= 3
              AND is_done = false
        """)
        old_date = datetime.utcnow() - timedelta(days=30)
        gems = (await db.execute(gem_sql, {"user_id": user_id, "before": old_date})).scalar() or 0
        if gems > 0:
            insights.append(Insight(
                type="forgotten_gems",
                title=f"{gems} forgotten gems",
                description=f"You have {gems} older items with multiple connections that you haven't revisited.",
                value=gems,
                icon="diamond",
            ))

        return insights


# Singleton
insights_service = InsightsService()
