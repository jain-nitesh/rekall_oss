"""
Connections service - discovers semantic connections between content items.

This is the core "wow" feature of ReCall. When a user saves new content,
we find similar items in their library using vector similarity and create
bidirectional connections with AI-generated explanations.
"""
import logging
from typing import List, Optional
from urllib.parse import urlparse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, text, update, func
from sqlalchemy import update as sql_update
from app.models.content_item import ContentItem
from app.models.content_connection import ContentConnection
from app.services.ai_service import AIService
from app.core.config import settings

logger = logging.getLogger(__name__)


def _extract_domain(url: Optional[str]) -> Optional[str]:
    """Extract domain from a URL, returning None if invalid."""
    if not url:
        return None
    try:
        parsed = urlparse(url)
        return parsed.netloc or None
    except Exception:
        return None


async def discover_connections(
    content_id: str,
    user_id: str,
    db: AsyncSession,
    similarity_threshold: float = 0.60,
    max_connections: int = 5
) -> List[ContentConnection]:
    """
    Discover connections between a content item and the user's other content.

    Uses pgvector cosine similarity to find the most semantically similar items,
    applies cross-category scoring adjustments, then runs an AI quality gate
    to only keep insightful (non-obvious) connections.

    Args:
        content_id: The new content item to find connections for
        user_id: The user who owns the content
        db: Database session
        similarity_threshold: Minimum similarity score (0.0-1.0)
        max_connections: Maximum number of connections to create

    Returns:
        List of created ContentConnection objects
    """
    # Get the source item's embedding
    source_item = await db.get(ContentItem, content_id)
    if not source_item or source_item.embedding is None:
        logger.info(f"No embedding for content {content_id}, skipping connection discovery")
        return []

    # Find similar items using pgvector cosine distance
    embedding_str = '[' + ','.join(str(x) for x in source_item.embedding) + ']'

    sql = text("""
        SELECT id, title, summary, category, url,
               1 - (embedding <=> :query_embedding) as similarity
        FROM content_items
        WHERE user_id = :user_id
          AND id != :content_id
          AND embedding IS NOT NULL
          AND 1 - (embedding <=> :query_embedding) >= :threshold
        ORDER BY embedding <=> :query_embedding
        LIMIT :limit
    """)

    result = await db.execute(sql, {
        'query_embedding': embedding_str,
        'user_id': str(user_id),
        'content_id': str(content_id),
        'threshold': similarity_threshold,
        'limit': max_connections * 2,  # Fetch extra candidates for re-ranking
    })

    similar_items = result.fetchall()

    if not similar_items:
        logger.info(f"No similar items found for content {content_id}")
        return []

    logger.info(f"Found {len(similar_items)} similar items for content {content_id}")

    # A3: Cross-category scoring adjustments
    source_category = source_item.category
    source_domain = _extract_domain(source_item.url)

    scored_candidates = []
    for row in similar_items:
        similarity = float(row.similarity)
        target_category = row.category
        target_domain = _extract_domain(row.url)

        final_score = similarity
        if source_category and target_category and source_category != target_category:
            final_score += 0.05  # Cross-category bonus
        if source_domain and target_domain and source_domain == target_domain:
            final_score -= 0.10  # Same-source penalty

        scored_candidates.append((row, final_score))

    # Re-rank by final_score descending and take top max_connections
    scored_candidates.sort(key=lambda x: x[1], reverse=True)
    scored_candidates = scored_candidates[:max_connections]

    # Initialize AI service for quality gate
    try:
        ai_service = AIService()
    except Exception as e:
        logger.error(f"Failed to initialize AI service for quality gate: {e}")
        ai_service = None

    created_connections = []

    for row, final_score in scored_candidates:
        target_id = str(row.id)

        # Check if connection already exists (either direction)
        existing = await db.execute(
            select(ContentConnection).where(
                and_(
                    ContentConnection.user_id == user_id,
                    (
                        (ContentConnection.source_item_id == content_id) &
                        (ContentConnection.target_item_id == target_id)
                    ) | (
                        (ContentConnection.source_item_id == target_id) &
                        (ContentConnection.target_item_id == content_id)
                    )
                )
            )
        )

        if existing.scalar_one_or_none():
            continue

        # A2: AI quality gate - check if connection is insightful before persisting
        ai_explanation = None
        if ai_service:
            try:
                source_title = source_item.title or "Untitled"
                source_summary = (source_item.summary or "")[:200]
                target_title = row.title or "Untitled"
                target_summary = (row.summary or "")[:200]

                result = await ai_service.provider.generate_connection_explanation(
                    source_title, source_summary, target_title, target_summary
                )

                verdict = result.get('verdict', '').upper()
                if verdict != 'INSIGHTFUL':
                    logger.info(
                        f"Skipping OBVIOUS connection between {content_id} and {target_id}"
                    )
                    continue

                ai_explanation = result.get('explanation')

            except Exception as e:
                logger.error(f"AI quality gate failed for {content_id} <-> {target_id}: {e}")
                # If AI fails, skip this candidate rather than persisting without quality check
                continue

        # Create connection with explanation from quality gate
        connection = ContentConnection(
            user_id=user_id,
            source_item_id=content_id,
            target_item_id=target_id,
            similarity_score=final_score,
            connection_type='semantic',
            ai_explanation=ai_explanation,
        )
        db.add(connection)
        created_connections.append(connection)

    if created_connections:
        # Update connection_count on all affected items
        affected_ids = [str(content_id)] + [str(c.target_item_id) for c in created_connections]

        for item_id in set(affected_ids):
            # Count total connections for this item
            count_sql = text("""
                SELECT COUNT(*) FROM content_connections
                WHERE (source_item_id = :item_id OR target_item_id = :item_id)
                  AND is_dismissed = false
            """)
            count_result = await db.execute(count_sql, {'item_id': item_id})
            count = count_result.scalar() or 0

            # Add count for new uncommitted connections
            new_count = sum(
                1 for c in created_connections
                if str(c.source_item_id) == item_id or str(c.target_item_id) == item_id
            )

            await db.execute(
                update(ContentItem)
                .where(ContentItem.id == item_id)
                .values(connection_count=count + new_count)
            )

        await db.commit()
        logger.info(f"Created {len(created_connections)} connections for content {content_id}")

    # A6: Mark user's clusters as stale for lazy rebuild
    try:
        from app.models.connection_cluster import ConnectionCluster
        await db.execute(
            sql_update(ConnectionCluster)
            .where(ConnectionCluster.user_id == user_id)
            .values(is_stale=True)
        )
        await db.commit()
    except Exception:
        pass  # Clusters table may not exist yet

    return created_connections
