"""
Connections API endpoints.

- GET /connections/{content_id} - connections for one item
- GET /connections - all user connections (paginated)
- POST /connections/{connection_id}/dismiss - dismiss a connection
- POST /connections/{connection_id}/explore - mark a connection as explored
- POST /connections/cleanup - dismiss low-quality connections
- GET /connections/daily - today's best undiscovered connection
"""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func, desc, update, text
from typing import List

from app.db.session import get_db
from app.models.user import User
from app.models.content_item import ContentItem
from app.models.content_connection import ContentConnection
from app.api.routes.auth import get_current_user
from app.api.schemas.connection import (
    ConnectionResponse,
    ConnectionItemSummary,
    ConnectionListResponse
)

import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/connections", tags=["Connections"])


def _build_connection_response(conn: ContentConnection, source: ContentItem, target: ContentItem) -> ConnectionResponse:
    """Build a ConnectionResponse from a connection and its items."""
    return ConnectionResponse(
        id=str(conn.id),
        source_item=ConnectionItemSummary(
            id=str(source.id),
            title=source.title,
            summary=source.summary,
            url=source.url,
            thumbnail_url=source.thumbnail_url,
            source_app=source.source_app,
            category=source.category,
        ),
        target_item=ConnectionItemSummary(
            id=str(target.id),
            title=target.title,
            summary=target.summary,
            url=target.url,
            thumbnail_url=target.thumbnail_url,
            source_app=target.source_app,
            category=target.category,
        ),
        similarity_score=conn.similarity_score,
        connection_type=conn.connection_type,
        ai_explanation=conn.ai_explanation,
        is_dismissed=conn.is_dismissed,
        created_at=conn.created_at,
    )


@router.get("/daily", response_model=ConnectionResponse)
async def get_daily_connection(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get today's best undiscovered connection pair."""
    # Find highest similarity connection that hasn't been dismissed
    query = select(ContentConnection).where(
        and_(
            ContentConnection.user_id == current_user.id,
            ContentConnection.is_dismissed == False,
            ContentConnection.similarity_score >= 0.50,
        )
    ).order_by(desc(ContentConnection.similarity_score)).limit(1)

    result = await db.execute(query)
    conn = result.scalar_one_or_none()

    if not conn:
        raise HTTPException(status_code=404, detail="No daily connection available")

    source = await db.get(ContentItem, conn.source_item_id)
    target = await db.get(ContentItem, conn.target_item_id)

    if not source or not target:
        raise HTTPException(status_code=404, detail="Connection items not found")

    return _build_connection_response(conn, source, target)


@router.get("", response_model=ConnectionListResponse)
async def get_all_connections(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get all connections for the current user, sorted by similarity."""
    # Count total
    count_query = select(func.count()).select_from(ContentConnection).where(
        and_(
            ContentConnection.user_id == current_user.id,
            ContentConnection.is_dismissed == False,
        )
    )
    total_result = await db.execute(count_query)
    total = total_result.scalar() or 0

    # Get paginated connections
    offset = (page - 1) * page_size
    query = select(ContentConnection).where(
        and_(
            ContentConnection.user_id == current_user.id,
            ContentConnection.is_dismissed == False,
        )
    ).order_by(desc(ContentConnection.similarity_score)).offset(offset).limit(page_size)

    result = await db.execute(query)
    connections = result.scalars().all()

    # Build responses
    responses = []
    for conn in connections:
        source = await db.get(ContentItem, conn.source_item_id)
        target = await db.get(ContentItem, conn.target_item_id)

        if source and target:
            responses.append(_build_connection_response(conn, source, target))

    return ConnectionListResponse(
        connections=responses,
        total=total,
        page=page,
        page_size=page_size,
        has_more=(offset + page_size) < total,
    )


@router.post("/{connection_id}/explore")
async def explore_connection(
    connection_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Mark a connection as explored by the user."""
    query = select(ContentConnection).where(
        and_(
            ContentConnection.id == connection_id,
            ContentConnection.user_id == current_user.id,
        )
    )
    result = await db.execute(query)
    conn = result.scalar_one_or_none()

    if not conn:
        raise HTTPException(status_code=404, detail="Connection not found")

    conn.explored_at = datetime.utcnow()
    conn.explored_count = (conn.explored_count or 0) + 1
    await db.commit()

    return {"status": "explored"}


@router.post("/cleanup")
async def cleanup_connections(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Dismiss low-quality connections with similarity_score < 0.60 and recalculate counts."""
    # Find connections to dismiss
    query = select(ContentConnection).where(
        and_(
            ContentConnection.user_id == current_user.id,
            ContentConnection.is_dismissed == False,
            ContentConnection.similarity_score < 0.60,
        )
    )
    result = await db.execute(query)
    low_quality = result.scalars().all()

    if not low_quality:
        return {"cleaned_up": 0}

    # Collect affected item IDs before dismissing
    affected_item_ids = set()
    for conn in low_quality:
        affected_item_ids.add(str(conn.source_item_id))
        affected_item_ids.add(str(conn.target_item_id))
        conn.is_dismissed = True

    # Recalculate connection_count on affected content items
    for item_id in affected_item_ids:
        count_sql = text("""
            SELECT COUNT(*) FROM content_connections
            WHERE (source_item_id = :item_id OR target_item_id = :item_id)
              AND is_dismissed = false
        """)
        count_result = await db.execute(count_sql, {'item_id': item_id})
        count = count_result.scalar() or 0

        await db.execute(
            update(ContentItem)
            .where(ContentItem.id == item_id)
            .values(connection_count=count)
        )

    await db.commit()

    return {"cleaned_up": len(low_quality)}


@router.get("/{content_id}", response_model=List[ConnectionResponse])
async def get_connections_for_item(
    content_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get all connections for a specific content item."""
    query = select(ContentConnection).where(
        and_(
            ContentConnection.user_id == current_user.id,
            ContentConnection.is_dismissed == False,
            or_(
                ContentConnection.source_item_id == content_id,
                ContentConnection.target_item_id == content_id,
            )
        )
    ).order_by(desc(ContentConnection.similarity_score))

    result = await db.execute(query)
    connections = result.scalars().all()

    responses = []
    for conn in connections:
        source = await db.get(ContentItem, conn.source_item_id)
        target = await db.get(ContentItem, conn.target_item_id)

        if source and target:
            responses.append(_build_connection_response(conn, source, target))

    return responses


@router.post("/{connection_id}/dismiss")
async def dismiss_connection(
    connection_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Dismiss a connection (hide it from the user)."""
    query = select(ContentConnection).where(
        and_(
            ContentConnection.id == connection_id,
            ContentConnection.user_id == current_user.id,
        )
    )
    result = await db.execute(query)
    conn = result.scalar_one_or_none()

    if not conn:
        raise HTTPException(status_code=404, detail="Connection not found")

    conn.is_dismissed = True
    await db.commit()

    return {"status": "dismissed"}
