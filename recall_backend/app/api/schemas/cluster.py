"""
Pydantic schemas for cluster endpoints.
"""
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime


class ClusterPreviewItem(BaseModel):
    id: str
    title: str
    thumbnail_url: Optional[str] = None
    category: Optional[str] = None
    source_app: Optional[str] = None


class ClusterResponse(BaseModel):
    id: str
    label: str
    description: Optional[str] = None
    item_count: int
    avg_similarity: Optional[float] = None
    preview_items: List[ClusterPreviewItem]
    source_apps: List[str] = []
    created_at: datetime


class ClusterDetailItem(BaseModel):
    id: str
    title: str
    summary: Optional[str] = None
    url: str
    thumbnail_url: Optional[str] = None
    source_app: Optional[str] = None
    category: Optional[str] = None


class ClusterConnection(BaseModel):
    source_item_id: str
    target_item_id: str
    similarity_score: float
    ai_explanation: Optional[str] = None


class ClusterDetailResponse(BaseModel):
    id: str
    label: str
    description: Optional[str] = None
    items: List[ClusterDetailItem]
    connections: List[ClusterConnection]
    avg_similarity: Optional[float] = None


class ClusterListResponse(BaseModel):
    clusters: List[ClusterResponse]
    total: int
