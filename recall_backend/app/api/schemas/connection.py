"""
Connection schemas for request/response validation.
"""
from pydantic import BaseModel
from datetime import datetime
from typing import Optional


class ConnectionItemSummary(BaseModel):
    """Minimal content item info for connection display"""
    id: str
    title: str
    summary: Optional[str] = None
    url: str
    thumbnail_url: Optional[str] = None
    source_app: Optional[str] = None
    category: Optional[str] = None

    model_config = {"from_attributes": True}


class ConnectionResponse(BaseModel):
    """Single connection between two content items"""
    id: str
    source_item: ConnectionItemSummary
    target_item: ConnectionItemSummary
    similarity_score: float
    connection_type: str
    ai_explanation: Optional[str] = None
    is_dismissed: bool = False
    created_at: datetime

    model_config = {"from_attributes": True}


class ConnectionListResponse(BaseModel):
    """Paginated list of connections"""
    connections: list[ConnectionResponse]
    total: int
    page: int
    page_size: int
    has_more: bool
