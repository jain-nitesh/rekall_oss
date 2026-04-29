"""
Pydantic schemas for Chrome extension bookmark sync.

Defines request/response models for:
- Bulk URL existence checking (deduplication)
- Bulk bookmark ingestion
- Folder-to-space mapping
"""
from pydantic import BaseModel, Field, field_validator
from typing import List, Dict, Optional


# ===== Check URLs =====

class ChromeUrlCheckRequest(BaseModel):
    """Check which URLs already exist in the user's library."""
    urls: List[str] = Field(..., max_length=500, description="URLs to check (max 500)")

    @field_validator('urls')
    @classmethod
    def validate_urls(cls, v: List[str]) -> List[str]:
        if len(v) > 500:
            raise ValueError("Maximum 500 URLs per request")
        return v


class ChromeUrlCheckResponse(BaseModel):
    """Response with existing/missing URL breakdown."""
    existing_urls: Dict[str, str] = Field(
        default_factory=dict,
        description="Map of URL -> content_item_id for URLs that already exist"
    )
    missing_urls: List[str] = Field(
        default_factory=list,
        description="URLs not found in user's library"
    )


# ===== Bulk Ingest =====

class ChromeBulkIngestItem(BaseModel):
    """A single bookmark to ingest."""
    url: str = Field(..., max_length=2048, description="Bookmark URL")
    title: Optional[str] = Field(None, max_length=512, description="Bookmark title")
    chrome_bookmark_id: str = Field(..., description="Chrome's internal bookmark ID for tracking")
    folder_path: Optional[str] = Field(
        None, max_length=512,
        description="Folder path e.g. 'Dev / Python' (null = no space, library only)"
    )

    @field_validator('url')
    @classmethod
    def validate_url(cls, v: str) -> str:
        if not v:
            raise ValueError("URL cannot be empty")
        if not (v.startswith('http://') or v.startswith('https://')):
            raise ValueError("URL must start with http:// or https://")
        return v


class ChromeBulkIngestRequest(BaseModel):
    """Bulk ingest bookmarks from Chrome extension."""
    bookmarks: List[ChromeBulkIngestItem] = Field(
        ..., max_length=100,
        description="Bookmarks to ingest (max 100 per request)"
    )

    @field_validator('bookmarks')
    @classmethod
    def validate_bookmarks(cls, v: List[ChromeBulkIngestItem]) -> List[ChromeBulkIngestItem]:
        if len(v) > 100:
            raise ValueError("Maximum 100 bookmarks per request")
        return v


class ChromeBulkIngestResultItem(BaseModel):
    """Result for a single bookmark ingestion."""
    chrome_bookmark_id: str
    content_id: Optional[str] = None
    status: str = Field(description="'created', 'duplicate', or 'error'")
    error: Optional[str] = None


class ChromeBulkIngestResponse(BaseModel):
    """Response for bulk bookmark ingestion."""
    results: List[ChromeBulkIngestResultItem]
    created: int
    skipped: int
    errors: int


# ===== Map to Spaces =====

class ChromeSpaceMapItem(BaseModel):
    """Map a content item to a space by folder name."""
    content_id: str = Field(..., description="Content item UUID")
    space_name: str = Field(..., max_length=255, description="Space name (from folder path)")


class ChromeSpaceMapRequest(BaseModel):
    """Assign content items to spaces based on folder structure."""
    mappings: List[ChromeSpaceMapItem] = Field(
        ..., max_length=200,
        description="Content-to-space mappings (max 200 per request)"
    )

    @field_validator('mappings')
    @classmethod
    def validate_mappings(cls, v: List[ChromeSpaceMapItem]) -> List[ChromeSpaceMapItem]:
        if len(v) > 200:
            raise ValueError("Maximum 200 mappings per request")
        return v


class ChromeSpaceMapResultItem(BaseModel):
    """Result for a single content-to-space mapping."""
    content_id: str
    space_name: str
    space_id: Optional[str] = None
    status: str = Field(description="'mapped', 'already_mapped', or 'error'")
    error: Optional[str] = None


class ChromeSpaceMapResponse(BaseModel):
    """Response for folder-to-space mapping."""
    results: List[ChromeSpaceMapResultItem]
    spaces_created: int
    spaces_reused: int
    items_mapped: int
    items_already_mapped: int
    errors: int
