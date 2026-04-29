"""
Pydantic schemas for content management.

For beginners:
- These schemas define the "shape" of data for content API requests and responses
- They validate incoming data and generate API documentation
- Request schemas: What the client sends to the API
- Response schemas: What the API returns to the client
"""
from pydantic import BaseModel, HttpUrl, Field, field_validator, model_validator
from datetime import datetime
from uuid import UUID
from typing import List, Optional


class ContentIngestRequest(BaseModel):
    """
    Request to save a new URL.

    This is what the mobile app sends when user shares a URL.

    Required fields:
    - url: The URL to save

    Optional fields:
    - title: If provided, use this instead of extracting from page
    - source_app_name: App name from mobile share intent (e.g., "Myntra", "Twitter")
    - source_app_package: Package name from mobile share intent (e.g., "com.myntra.android")
    - shared_text: Full text from share intent (includes URL + preview text, used as fallback for private/auth-required content)
    - shared_html: HTML content from share intent if available

    Note: created_at is always set by the backend to current time
    """
    url: str = Field(default="", description="URL to save (empty for note-type content)", max_length=2048)
    title: Optional[str] = Field(None, description="Optional custom title", max_length=512)
    source_app_name: Optional[str] = Field(None, description="Source app name from mobile share intent", max_length=100)
    source_app_package: Optional[str] = Field(None, description="Source app package name from mobile share intent", max_length=200)

    # NEW: Support for private/authenticated content
    shared_text: Optional[str] = Field(None, description="Full text from share intent (includes URL + preview text)", max_length=10000)
    shared_html: Optional[str] = Field(None, description="HTML content from share intent if available", max_length=50000)

    @model_validator(mode='after')
    def validate_url_or_note(self) -> 'ContentIngestRequest':
        """Validate that either a valid URL or shared_text (note) is provided."""
        url = self.url
        shared_text = self.shared_text

        # If URL is empty, shared_text must be provided (note mode)
        if not url:
            if not shared_text or not shared_text.strip():
                raise ValueError("Either a URL or shared_text (note) must be provided")
            return self

        # URL validation
        if len(url) > 2048:
            raise ValueError("URL too long (max 2048 characters)")
        if not (url.startswith('http://') or url.startswith('https://')):
            raise ValueError("URL must start with http:// or https://")
        # Basic URL validation - check for valid domain
        if '.' not in url.split('://', 1)[-1].split('/')[0]:
            raise ValueError("Invalid URL format")
        return self

    @field_validator('title')
    @classmethod
    def validate_title(cls, v: Optional[str]) -> Optional[str]:
        """Validate title length."""
        if v is not None and len(v) > 512:
            raise ValueError("Title too long (max 512 characters)")
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "url": "https://example.com/article",
                "title": "Optional custom title"
            }
        }


class ContentUpdateRequest(BaseModel):
    """
    Request to update content flags.

    Used for marking content as done, favoriting, or updating tags.
    All fields are optional - only send what you want to update.
    """
    is_done: Optional[bool] = Field(None, description="Mark as done/not done")
    is_favorite: Optional[bool] = Field(None, description="Mark as favorite/not favorite")
    tags: Optional[List[str]] = Field(None, description="Update tags", max_length=20)
    notes: Optional[str] = Field(None, description="User's personal notes about this content", max_length=5000)

    @field_validator('tags')
    @classmethod
    def validate_tags(cls, v: Optional[List[str]]) -> Optional[List[str]]:
        """Validate tags list."""
        if v is not None:
            if len(v) > 20:
                raise ValueError("Too many tags (max 20)")
            # Validate each tag
            for tag in v:
                if not tag or len(tag.strip()) == 0:
                    raise ValueError("Tags cannot be empty")
                if len(tag) > 50:
                    raise ValueError("Tag too long (max 50 characters)")
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "is_done": True,
                "is_favorite": False,
                "tags": ["python", "tutorial"],
                "notes": "Great intro to FastAPI, revisit the dependency injection section"
            }
        }


class ContentResponse(BaseModel):
    """
    Content data returned by API.

    This is the complete representation of a content item.
    Sent when:
    - Creating new content (POST /content/ingest or /content/upload-media)
    - Getting single content (GET /content/{id})
    - Updating content (PATCH /content/{id})

    Two-Phase Processing Status:
    - ingestion_status: URL fetch + metadata extraction (Phase 1)
    - ai_status: AI summarization + embeddings (Phase 2)

    Note: Matches the Flutter ContentItem model structure
    """
    id: UUID
    user_id: UUID
    content_type: str = Field(default="url", description="Content type: 'url', 'image', 'video', 'note'")
    url: Optional[str] = Field(default="", description="URL (empty string for media content, for backward compat with older app versions)")
    title: Optional[str] = Field(default="Untitled")
    summary: Optional[str] = Field(default="")
    tags: List[str] = Field(default_factory=list)
    source_app: str  # Enum values as strings
    source_app_name: Optional[str] = None  # Human-readable app name (e.g., "Myntra", "LinkedIn")
    source_app_package: Optional[str] = None  # App package name from share intent
    category: str    # Enum values as strings
    category_name: Optional[str] = None  # User-friendly category name
    category_color: Optional[str] = None  # Category color code
    category_id: Optional[str] = None  # User category ID if applicable
    thumbnail_url: Optional[str] = None
    hero_image_url: Optional[str] = None  # Hero image for detail view
    detailed_summary: Optional[str] = None  # AI-generated detailed narrative summary (200-300 words)
    key_takeaways: Optional[List[str]] = None  # AI-generated key takeaways
    reading_time_minutes: int
    notes: Optional[str] = None
    is_done: bool
    is_favorite: bool
    created_at: datetime

    # Media fields (Phase 6: Memory Engine)
    media_url: Optional[str] = Field(None, description="URL of uploaded media file in object storage")
    media_mime_type: Optional[str] = Field(None, description="MIME type (e.g., image/jpeg, video/mp4)")
    media_duration_seconds: Optional[float] = Field(None, description="Duration in seconds (video only)")
    ocr_text: Optional[str] = Field(None, description="Text extracted via OCR from images/video frames")

    # Two-Phase Processing Status
    ingestion_status: str = Field(..., description="Phase 1: URL fetch + metadata extraction ('pending', 'fetching', 'ingested', 'failed')")
    ai_status: str = Field(..., description="Phase 2: AI processing ('pending', 'processing', 'completed', 'failed', 'disabled')")

    # Fetch Error Type (NEW)
    fetch_error_type: Optional[str] = Field(
        default="none",
        description="Type of fetch error ('none', 'auth_required', 'network', 'not_found', 'server_error', 'blocked', 'other')"
    )

    @model_validator(mode='after')
    def generate_source_app_name(self):
        """Generate human-readable source app name from source_app if not provided."""
        if self.source_app_name is None or self.source_app_name == '':
            # Format source_app string to display name (capitalize first letter)
            # e.g., "myntra" -> "Myntra", "linkedin" -> "LinkedIn"
            if self.source_app:
                # Handle camelCase (e.g., "productHunt" -> "Product Hunt")
                if any(c.isupper() for c in self.source_app):
                    # Split on uppercase letters
                    import re
                    words = re.findall(r'[A-Z]?[a-z]+', self.source_app)
                    self.source_app_name = ' '.join(word.capitalize() for word in words)
                else:
                    # Simple capitalize (e.g., "myntra" -> "Myntra")
                    self.source_app_name = self.source_app.capitalize()
        return self

    @model_validator(mode='after')
    def ensure_backward_compat(self):
        """Ensure nullable fields have safe defaults for older app versions.

        Older app versions expect url/title/summary to be non-null strings
        and tags to be a non-null list. Media content may have these as None
        in the DB, so we coerce them here for API safety.
        """
        if self.url is None:
            self.url = ""
        if self.title is None:
            self.title = "Untitled"
        if self.summary is None:
            self.summary = ""
        if self.tags is None:
            self.tags = []
        return self

    @model_validator(mode='after')
    def convert_enum_to_string(self):
        """Convert enum values to strings for API response."""
        # Convert content_type enum to string
        if hasattr(self.content_type, 'value'):
            self.content_type = self.content_type.value
        # Convert status enums to string values if they're enum objects
        if hasattr(self.ingestion_status, 'value'):
            self.ingestion_status = self.ingestion_status.value
        if hasattr(self.ai_status, 'value'):
            self.ai_status = self.ai_status.value
        if hasattr(self.fetch_error_type, 'value'):
            self.fetch_error_type = self.fetch_error_type.value
        return self

    class Config:
        from_attributes = True  # Allows creation from SQLAlchemy models
        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "user_id": "660e8400-e29b-41d4-a716-446655440001",
                "url": "https://fastapi.tiangolo.com/tutorial/",
                "title": "FastAPI Tutorial - User Guide",
                "summary": "Learn how to build APIs with FastAPI, a modern Python framework.",
                "tags": ["python", "fastapi", "tutorial"],
                "source_app": "other",
                "source_app_name": "Other",
                "category": "technology",
                "thumbnail_url": "https://fastapi.tiangolo.com/img/logo-margin/logo-teal.png",
                "reading_time_minutes": 15,
                "is_done": False,
                "is_favorite": False,
                "created_at": "2025-01-01T00:00:00Z",
                "ingestion_status": "ingested",
                "ai_status": "completed"
            }
        }


class ContentListResponse(BaseModel):
    """
    Paginated list of content items.

    Used for:
    - GET /content (all content)
    - GET /content/search (search results)
    - GET /content/memory-feed (memory feed sections)

    Includes pagination metadata so client knows:
    - How many items total
    - Current page number
    - Items per page
    - Whether more pages are available
    """
    content: List[ContentResponse]
    total: int = Field(..., description="Total number of items")
    page: int = Field(..., description="Current page number")
    page_size: int = Field(..., description="Items per page")
    has_more: bool = Field(..., description="Whether more pages are available")

    class Config:
        json_schema_extra = {
            "example": {
                "content": [
                    {
                        "id": "550e8400-e29b-41d4-a716-446655440000",
                        "user_id": "660e8400-e29b-41d4-a716-446655440001",
                        "url": "https://example.com/article1",
                        "title": "Example Article 1",
                        "summary": "Summary of article 1",
                        "tags": ["tag1"],
                        "source_app": "other",
                        "category": "technology",
                        "thumbnail_url": None,
                        "reading_time_minutes": 5,
                        "is_done": False,
                        "is_favorite": False,
                        "created_at": "2025-01-01T00:00:00Z"
                    }
                ],
                "total": 42,
                "page": 1,
                "page_size": 50
            }
        }


class FilterOptionItem(BaseModel):
    """
    Single filter option with count.

    Represents one option in a filter (e.g., "Technology" with 15 items).
    Used for dynamically populating filter dropdowns/chips in the UI.
    """
    value: str = Field(..., description="Filter value (enum value or category ID)")
    display_name: str = Field(..., description="Human-readable display name")
    count: int = Field(..., description="Number of content items matching this filter")
    color: Optional[str] = Field(None, description="Color code for user categories (e.g., '#FF5733')")

    class Config:
        json_schema_extra = {
            "example": {
                "value": "technology",
                "display_name": "Technology",
                "count": 15,
                "color": None
            }
        }


class FilterOptionsResponse(BaseModel):
    """
    Available filter options with counts.

    Returns all filter options that have at least one content item.
    Used by the search page to display dynamic filters.

    Separates:
    - Fixed categories (8 predefined ContentCategory enum values)
    - User-created categories (custom categories created by user)
    - Source apps (where the content was shared from)
    """
    categories: List[FilterOptionItem] = Field(..., description="Fixed category options with counts")
    user_categories: List[FilterOptionItem] = Field(..., description="User-created category options with counts")
    sources: List[FilterOptionItem] = Field(..., description="Source app options with counts")

    class Config:
        json_schema_extra = {
            "example": {
                "categories": [
                    {"value": "technology", "display_name": "Technology", "count": 15, "color": None},
                    {"value": "business", "display_name": "Business", "count": 8, "color": None}
                ],
                "user_categories": [
                    {"value": "550e8400-e29b-41d4-a716-446655440000", "display_name": "My Custom Category", "count": 3, "color": "#FF5733"}
                ],
                "sources": [
                    {"value": "linkedin", "display_name": "LinkedIn", "count": 23, "color": None},
                    {"value": "reddit", "display_name": "Reddit", "count": 12, "color": None}
                ]
            }
        }


class ContentSearchRequest(BaseModel):
    """
    Search and filter request with multi-select support.

    Used by POST /content/search to filter content with multiple criteria.
    All filters use OR logic within the same filter type, and AND logic between different types.

    Example: (category=tech OR category=science) AND (source=linkedin OR source=reddit)
    """
    query: Optional[str] = Field(None, description="Text search query (searches title, summary, tags)", max_length=200)
    categories: Optional[List[str]] = Field(None, description="Fixed category enum values (OR logic)")
    user_category_ids: Optional[List[str]] = Field(None, description="User category UUIDs (OR logic)")
    source_apps: Optional[List[str]] = Field(None, description="Source app enum values (OR logic)")
    days: Optional[int] = Field(None, description="Filter content from last N days", ge=1)
    page: int = Field(1, ge=1, description="Page number (1-indexed)")
    page_size: int = Field(20, ge=1, le=100, description="Items per page (max 100)")

    @field_validator('query')
    @classmethod
    def validate_query(cls, v: Optional[str]) -> Optional[str]:
        """Validate search query length."""
        if v is not None and len(v) > 200:
            raise ValueError("Search query too long (max 200 characters)")
        return v

    @field_validator('categories')
    @classmethod
    def validate_categories(cls, v: Optional[List[str]]) -> Optional[List[str]]:
        """Validate categories list."""
        if v is not None and len(v) > 20:
            raise ValueError("Too many categories (max 20)")
        return v

    @field_validator('source_apps')
    @classmethod
    def validate_source_apps(cls, v: Optional[List[str]]) -> Optional[List[str]]:
        """Validate source apps list."""
        if v is not None and len(v) > 20:
            raise ValueError("Too many source apps (max 20)")
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "query": "python tutorial",
                "categories": ["technology", "education"],
                "user_category_ids": None,
                "source_apps": ["linkedin", "reddit"],
                "days": 30,
                "page": 1,
                "page_size": 20
            }
        }
