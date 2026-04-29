"""
Knowledge health check service.

Runs periodic analysis to surface proactive intelligence insights:
- Gap detection: entities with many mentions but shallow/no wiki pages
- Staleness detection: wiki pages not recompiled with recent new content
- Contradiction detection: unresolved contradictions across wiki pages
- Trend detection: entities with accelerating mention frequency
- Suggestions: areas where knowledge could be deepened

Designed to run weekly for users with 20+ content items.
"""
from datetime import datetime, timedelta
from typing import List, Dict
from sqlalchemy import select, func, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.entity import Entity, ContentEntity
from app.models.wiki import WikiPage, WikiContradiction
from app.models.content_item import ContentItem
from app.models.health_check import KnowledgeHealthCheck
from app.db.session import AsyncSessionLocal


async def run_health_checks() -> int:
    """
    Run health checks for all eligible users (20+ content items).
    Called periodically by the background processor.

    Returns:
        Number of insights generated.
    """
    async with AsyncSessionLocal() as db:
        # Find users with 20+ items
        stmt = (
            select(User.id)
            .join(ContentItem, ContentItem.user_id == User.id)
            .group_by(User.id)
            .having(func.count(ContentItem.id) >= 20)
        )
        result = await db.execute(stmt)
        user_ids = [str(row[0]) for row in result.all()]

        if not user_ids:
            return 0

        total_insights = 0
        for user_id in user_ids:
            try:
                count = await _run_user_health_checks(user_id, db)
                total_insights += count
            except Exception as e:
                print(f"[WARN] Health check failed for user {user_id[:8]}: {e}")

        if total_insights > 0:
            print(f"[HEALTH] Generated {total_insights} insight(s) for {len(user_ids)} user(s)")

        return total_insights


async def _run_user_health_checks(user_id: str, db: AsyncSession) -> int:
    """Run all health checks for a single user."""
    # Clear old non-dismissed insights (older than 7 days)
    await _clear_old_insights(user_id, db)

    insights = []
    insights.extend(await _detect_knowledge_gaps(user_id, db))
    insights.extend(await _detect_stale_pages(user_id, db))
    insights.extend(await _detect_open_contradictions(user_id, db))
    insights.extend(await _detect_trending_entities(user_id, db))

    # Store insights
    for insight in insights:
        check = KnowledgeHealthCheck(
            user_id=user_id,
            check_type=insight['type'],
            title=insight['title'],
            description=insight.get('description'),
            priority=insight.get('priority', 'medium'),
            related_entity_id=insight.get('entity_id'),
            related_wiki_page_id=insight.get('wiki_page_id'),
            created_at=datetime.utcnow(),
        )
        db.add(check)

    if insights:
        await db.commit()

    return len(insights)


async def _clear_old_insights(user_id: str, db: AsyncSession):
    """Remove non-dismissed insights older than 7 days."""
    cutoff = datetime.utcnow() - timedelta(days=7)
    stmt = select(KnowledgeHealthCheck).where(
        (KnowledgeHealthCheck.user_id == user_id) &
        (KnowledgeHealthCheck.is_dismissed == False) &
        (KnowledgeHealthCheck.is_acted_on == False) &
        (KnowledgeHealthCheck.created_at < cutoff)
    )
    result = await db.execute(stmt)
    old_checks = result.scalars().all()
    for check in old_checks:
        await db.delete(check)
    if old_checks:
        await db.commit()


async def _detect_knowledge_gaps(user_id: str, db: AsyncSession) -> List[Dict]:
    """Find entities with many mentions but no/shallow wiki pages."""
    # Entities with 5+ mentions that have no wiki page or only a draft
    stmt = text("""
        SELECT e.id, e.name, e.entity_type, e.mention_count,
               wp.id as wiki_page_id, wp.status, wp.source_count
        FROM entities e
        LEFT JOIN wiki_pages wp ON wp.entity_id = e.id AND wp.user_id = e.user_id
        WHERE e.user_id = :user_id
          AND e.mention_count >= 5
          AND (wp.id IS NULL OR wp.status = 'draft' OR wp.source_count < 3)
        ORDER BY e.mention_count DESC
        LIMIT 5
    """)
    result = await db.execute(stmt, {'user_id': user_id})
    rows = result.all()

    insights = []
    for row in rows:
        entity_name = row[1]
        mention_count = row[3]
        has_page = row[4] is not None

        if not has_page:
            title = f"Knowledge gap: {entity_name} has no wiki page"
            desc = f"{entity_name} ({row[2]}) has been mentioned {mention_count} times but has no compiled wiki page."
            priority = "high" if mention_count >= 10 else "medium"
        else:
            title = f"Shallow wiki page: {entity_name}"
            desc = f"The wiki page for {entity_name} only uses {row[6] or 0} sources despite {mention_count} mentions."
            priority = "medium"

        insights.append({
            'type': 'gap',
            'title': title,
            'description': desc,
            'priority': priority,
            'entity_id': str(row[0]),
            'wiki_page_id': str(row[4]) if row[4] else None,
        })

    return insights


async def _detect_stale_pages(user_id: str, db: AsyncSession) -> List[Dict]:
    """Find wiki pages not recompiled in 30+ days with recent new content."""
    cutoff = datetime.utcnow() - timedelta(days=30)
    recent_content_cutoff = datetime.utcnow() - timedelta(days=7)

    stmt = text("""
        SELECT wp.id, wp.title, wp.last_compiled_at, wp.entity_id,
               COUNT(DISTINCT ci.id) as recent_content_count
        FROM wiki_pages wp
        JOIN content_entities ce ON ce.entity_id = wp.entity_id
        JOIN content_items ci ON ci.id = ce.content_item_id
        WHERE wp.user_id = :user_id
          AND wp.status = 'published'
          AND (wp.last_compiled_at IS NULL OR wp.last_compiled_at < :cutoff)
          AND ci.created_at > :recent_cutoff
        GROUP BY wp.id, wp.title, wp.last_compiled_at, wp.entity_id
        HAVING COUNT(DISTINCT ci.id) >= 1
        ORDER BY COUNT(DISTINCT ci.id) DESC
        LIMIT 5
    """)
    result = await db.execute(stmt, {
        'user_id': user_id,
        'cutoff': cutoff,
        'recent_cutoff': recent_content_cutoff,
    })
    rows = result.all()

    insights = []
    for row in rows:
        insights.append({
            'type': 'stale',
            'title': f"Stale wiki page: {row[1]}",
            'description': (
                f"'{row[1]}' hasn't been recompiled since "
                f"{row[2].strftime('%Y-%m-%d') if row[2] else 'never'} "
                f"but has {row[4]} new content item(s) in the last week."
            ),
            'priority': 'high' if row[4] >= 3 else 'medium',
            'wiki_page_id': str(row[0]),
            'entity_id': str(row[3]) if row[3] else None,
        })

    return insights


async def _detect_open_contradictions(user_id: str, db: AsyncSession) -> List[Dict]:
    """Find wiki pages with unresolved contradictions."""
    stmt = text("""
        SELECT wp.id, wp.title, COUNT(wc.id) as contradiction_count
        FROM wiki_pages wp
        JOIN wiki_contradictions wc ON wc.wiki_page_id = wp.id
        WHERE wp.user_id = :user_id
          AND wc.status = 'open'
        GROUP BY wp.id, wp.title
        HAVING COUNT(wc.id) >= 1
        ORDER BY COUNT(wc.id) DESC
        LIMIT 5
    """)
    result = await db.execute(stmt, {'user_id': user_id})
    rows = result.all()

    insights = []
    for row in rows:
        insights.append({
            'type': 'contradiction',
            'title': f"Contradictions in: {row[1]}",
            'description': f"'{row[1]}' has {row[2]} unresolved contradiction(s) that may need your review.",
            'priority': 'high' if row[2] >= 3 else 'medium',
            'wiki_page_id': str(row[0]),
        })

    return insights


async def _detect_trending_entities(user_id: str, db: AsyncSession) -> List[Dict]:
    """Find entities with accelerating mention frequency (recent mentions > historical rate)."""
    # Entities mentioned 3+ times in last 7 days vs their overall rate
    stmt = text("""
        WITH recent_mentions AS (
            SELECT ce.entity_id, COUNT(*) as recent_count
            FROM content_entities ce
            JOIN content_items ci ON ci.id = ce.content_item_id
            WHERE ci.user_id = :user_id
              AND ci.created_at > NOW() - INTERVAL '7 days'
            GROUP BY ce.entity_id
            HAVING COUNT(*) >= 3
        )
        SELECT e.id, e.name, e.entity_type, e.mention_count,
               rm.recent_count
        FROM entities e
        JOIN recent_mentions rm ON rm.entity_id = e.id
        WHERE e.user_id = :user_id
        ORDER BY rm.recent_count DESC
        LIMIT 5
    """)
    result = await db.execute(stmt, {'user_id': user_id})
    rows = result.all()

    insights = []
    for row in rows:
        entity_name = row[1]
        total_mentions = row[3] or 0
        recent_count = row[4]

        insights.append({
            'type': 'trend',
            'title': f"Trending: {entity_name}",
            'description': (
                f"{entity_name} ({row[2]}) has {recent_count} mentions in the last 7 days "
                f"({total_mentions} total). This topic may be gaining importance."
            ),
            'priority': 'low',
            'entity_id': str(row[0]),
        })

    return insights


async def get_user_health_checks(
    user_id: str, db: AsyncSession,
    check_type: str = None, include_dismissed: bool = False, limit: int = 20
) -> List[Dict]:
    """Get health check insights for a user."""
    stmt = select(KnowledgeHealthCheck).where(
        KnowledgeHealthCheck.user_id == user_id
    )

    if not include_dismissed:
        stmt = stmt.where(KnowledgeHealthCheck.is_dismissed == False)

    if check_type:
        stmt = stmt.where(KnowledgeHealthCheck.check_type == check_type)

    stmt = stmt.order_by(
        # High priority first, then by date
        KnowledgeHealthCheck.priority.asc(),
        KnowledgeHealthCheck.created_at.desc()
    ).limit(limit)

    result = await db.execute(stmt)
    checks = result.scalars().all()

    return [
        {
            'id': str(c.id),
            'check_type': c.check_type,
            'title': c.title,
            'description': c.description,
            'priority': c.priority,
            'related_entity_id': str(c.related_entity_id) if c.related_entity_id else None,
            'related_wiki_page_id': str(c.related_wiki_page_id) if c.related_wiki_page_id else None,
            'is_dismissed': c.is_dismissed,
            'is_acted_on': c.is_acted_on,
            'created_at': c.created_at.isoformat() if c.created_at else None,
        }
        for c in checks
    ]
