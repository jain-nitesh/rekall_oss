"""
Trending news endpoint — serves cached AI-generated news for empty-feed users.
"""
from fastapi import APIRouter, Depends, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from app.api.routes.auth import get_current_user
from app.models.user import User
from app.services.trending_news_service import get_trending_news

router = APIRouter(prefix="/trending", tags=["trending"])

limiter = Limiter(key_func=get_remote_address)


@router.get("/news")
@limiter.limit("10/minute")
async def trending_news(request: Request, current_user: User = Depends(get_current_user)):
    """
    Get 5 trending tech/AI news items.

    Cached for 6 hours (configurable via NEWS_CACHE_TTL_SECONDS).
    """
    news = await get_trending_news()
    return {"items": news}
