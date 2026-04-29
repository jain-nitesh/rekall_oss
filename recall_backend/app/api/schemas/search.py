"""
Search schemas for request/response validation.
"""
from pydantic import BaseModel, Field, field_validator
from datetime import datetime
from typing import Optional, List


class SearchHistoryItem(BaseModel):
    """Individual search history item"""
    id: str
    query: str
    created_at: datetime

    model_config = {
        "from_attributes": True,
    }

    @field_validator("id", mode="before")
    @classmethod
    def coerce_id(cls, v):
        return str(v)


class SearchHistoryCreate(BaseModel):
    """Request to save a search to history"""
    query: str


class SemanticSearchRequest(BaseModel):
    """Request for semantic search"""
    query: str = Field(..., min_length=1, max_length=500)
    limit: int = Field(default=20, ge=1, le=100)
    threshold: float = Field(default=0.3, ge=0.0, le=1.0)


class SmartSearchRequest(BaseModel):
    """Request for smart search with natural language query understanding"""
    query: str = Field(..., min_length=1, max_length=500)
    limit: int = Field(default=20, ge=1, le=100)
    content_type: Optional[str] = Field(None, description="Filter: 'url', 'image', 'video', or None for all")


class SmartSearchResult(BaseModel):
    """A search result with relevance scoring"""
    content: "ContentResponse"
    score: float = Field(..., description="Relevance score 0.0-1.0")
    match_reason: Optional[str] = Field(None, description="Why this result matched")
    match_type: Optional[str] = Field(None, description="'vector', 'fts', or 'hybrid'")

    model_config = {"from_attributes": True}


class SearchSuggestion(BaseModel):
    """A search suggestion item"""
    text: str
    source: str = Field(..., description="Source: 'history', 'tag', 'category'")


# Avoid circular import
from app.api.schemas.content import ContentResponse
SmartSearchResult.model_rebuild()
