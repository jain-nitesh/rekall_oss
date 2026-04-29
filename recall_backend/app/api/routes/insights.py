"""
Insights API endpoint.
Returns personalized insights about user's content library.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel
from typing import List, Optional

from app.db.session import get_db
from app.models.user import User
from app.api.routes.auth import get_current_user
from app.services.insights_service import insights_service

router = APIRouter(prefix="/insights", tags=["Insights"])


class InsightResponse(BaseModel):
    """A single insight card."""
    type: str
    title: str
    description: str
    value: Optional[int] = None
    icon: Optional[str] = None


@router.get("", response_model=List[InsightResponse])
async def get_insights(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get personalized insights for the current user.

    Returns insight cards such as:
    - Monthly activity summary
    - Most active topic
    - Media capture count
    - Unexplored connections
    - Trending tags
    - Forgotten gems
    """
    insights = await insights_service.get_user_insights(
        user_id=str(current_user.id),
        db=db,
    )

    return [
        InsightResponse(
            type=i.type,
            title=i.title,
            description=i.description,
            value=i.value,
            icon=i.icon,
        )
        for i in insights
    ]
