"""
Knowledge health check API endpoints.

Surfaces proactive intelligence insights: knowledge gaps, stale pages,
contradictions, trends, and suggestions.
"""
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID

from app.db.session import get_db
from app.models.user import User
from app.models.health_check import KnowledgeHealthCheck
from app.api.routes.auth import get_current_user

router = APIRouter(prefix="/health-checks", tags=["Health Checks"])


# ===== Response Models =====

class HealthCheckItem(BaseModel):
    """A single health check insight."""
    id: str
    check_type: str
    title: str
    description: Optional[str] = None
    priority: str = "medium"
    related_entity_id: Optional[str] = None
    related_wiki_page_id: Optional[str] = None
    is_dismissed: bool = False
    is_acted_on: bool = False
    created_at: Optional[str] = None


# ===== Endpoints =====

@router.get("", response_model=List[HealthCheckItem])
async def list_health_checks(
    check_type: Optional[str] = Query(None, description="Filter: gap, stale, contradiction, trend, suggestion"),
    include_dismissed: bool = Query(False),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get proactive intelligence insights for the current user."""
    from app.services.health_check_service import get_user_health_checks

    checks = await get_user_health_checks(
        user_id=str(current_user.id),
        db=db,
        check_type=check_type,
        include_dismissed=include_dismissed,
        limit=limit,
    )
    return [HealthCheckItem(**c) for c in checks]


@router.post("/{check_id}/dismiss")
async def dismiss_health_check(
    check_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Dismiss a health check insight."""
    check = await db.get(KnowledgeHealthCheck, check_id)
    if not check or str(check.user_id) != str(current_user.id):
        raise HTTPException(status_code=404, detail="Health check not found")

    check.is_dismissed = True
    await db.commit()
    return {"status": "dismissed", "id": str(check_id)}


@router.post("/{check_id}/act")
async def mark_acted_on(
    check_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Mark a health check as acted upon."""
    check = await db.get(KnowledgeHealthCheck, check_id)
    if not check or str(check.user_id) != str(current_user.id):
        raise HTTPException(status_code=404, detail="Health check not found")

    check.is_acted_on = True
    await db.commit()
    return {"status": "acted_on", "id": str(check_id)}


@router.post("/run")
async def trigger_health_checks(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Manually trigger health checks for the current user."""
    from app.services.health_check_service import _run_user_health_checks

    count = await _run_user_health_checks(str(current_user.id), db)
    return {"status": "completed", "insights_generated": count}
