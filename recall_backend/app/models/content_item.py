"""
Content item database model.
Represents saved content: URLs, images, videos, and notes.

For beginners:
- This model stores all content that users save (articles, videos, links, images, etc.)
- Each content item belongs to a user (foreign key relationship)
- We store both the URL and extracted metadata (title, summary, tags)
- Phase 3: Added embedding vector for semantic search using pgvector
- Phase 4: Added processing_status for resilient async processing
- Phase 6: Added media support (images, videos) with OCR and visual AI processing
"""
from sqlalchemy import Column, String, DateTime, Integer, Boolean, Text, ARRAY, ForeignKey, Enum as SQLEnum, Float, BigInteger
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from pgvector.sqlalchemy import Vector
import uuid
from datetime import datetime
from enum import Enum
from app.db.session import Base

# Import deferred to avoid circular imports - EntityExtractionStatus is defined in entity.py
# but we need it here for the column definition
from app.models.entity import EntityExtractionStatus


class ContentType(str, Enum):
    """
    Type of content stored in a content item.

    - url: Traditional web content (articles, videos, social posts)
    - image: Captured or uploaded image (whiteboard, menu, book page, screenshot)
    - video: Short recorded video (5-20 second clips)
    - note: Text-only note (no URL or media)
    """
    url = "url"
    image = "image"
    video = "video"
    note = "note"


class ProcessingStatus(str, Enum):
    """
    DEPRECATED: Use IngestionStatus and AIStatus instead.

    Content processing status for async background processing.

    Flow: pending → processing → completed (or failed)

    Note: Enum names are lowercase to match database enum values.
    SQLAlchemy uses the enum name (not value) when working with database enums.
    """
    pending = "pending"      # Waiting to be processed
    processing = "processing"  # Currently being processed
    completed = "completed"   # Successfully processed
    failed = "failed"         # Processing failed (will be retried)


class IngestionStatus(str, Enum):
    """
    URL fetch and metadata extraction status (Phase 1).

    Flow: pending → fetching → ingested (or failed)

    Phase 1 is fast (~1-3 seconds) and makes content immediately visible to users.
    """
    pending = "pending"      # Not yet fetched
    fetching = "fetching"    # Currently fetching URL
    ingested = "ingested"    # Successfully fetched and metadata extracted
    failed = "failed"        # Fetch failed (will retry)


class AIStatus(str, Enum):
    """
    AI processing status (Phase 2: summarization + embeddings).

    Flow: pending → processing → completed (or failed)

    Phase 2 enriches content with AI insights (~5-10 seconds, rate-limited).
    Content is already visible to users during this phase.
    """
    pending = "pending"      # Waiting for AI processing
    processing = "processing"  # Currently running AI
    completed = "completed"   # AI processing complete
    failed = "failed"         # AI processing failed (will retry)
    disabled = "disabled"     # AI disabled in config (content still usable)


class FetchErrorType(str, Enum):
    """
    Type of fetch error encountered during URL ingestion.

    Used to show different UI feedback to users (e.g., auth banner).
    """
    none = "none"                    # No error (successful fetch)
    auth_required = "auth_required"  # 401/403 or login page redirect
    network = "network"              # Network/timeout errors
    not_found = "not_found"          # 404 errors
    server_error = "server_error"    # 5xx errors
    blocked = "blocked"              # Rate-limited or bot-blocked
    other = "other"                  # Unknown/other errors


class ContentItem(Base):
    """
    Content item model - represents saved URLs.

    This stores everything about a saved piece of content:
    - URL and basic metadata (title, summary, thumbnail)
    - Classification (source app, category)
    - AI-generated fields (embedding vector, extracted content)
    - User flags (favorite, done)
    - Timestamps for when it was saved

    Phase 2: Basic version with keyword categorization
    Phase 3: Added embedding vector for semantic search
    """
    __tablename__ = "content_items"

    # Primary key
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Foreign key to user
    # When user is deleted, their content is deleted too (cascade)
    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True  # Index for fast "get all content for user" queries
    )

    # ===== Content Type =====

    # Type of content: url (default), image, video, or note
    content_type = Column(
        SQLEnum(ContentType),
        default=ContentType.url,
        nullable=False,
        index=True
    )

    # ===== URL and Basic Metadata =====

    # The original URL that was saved (nullable for image/video/note content)
    url = Column(Text, nullable=True)

    # Title of the content (extracted from page, user-provided, or AI-generated for media)
    title = Column(String(512), nullable=True)

    # Short summary/description of the content (AI-generated for media content)
    summary = Column(Text, nullable=True)

    # Tags for organization (PostgreSQL array type)
    # Example: ['python', 'tutorial', 'fastapi']
    tags = Column(ARRAY(String), default=list)

    # ===== Classification Fields =====

    # Source app where content came from
    # Stored as string to match mobile enum
    # Values: 'linkedin', 'reddit', 'twitter', 'youtube', etc.
    source_app = Column(String(50), nullable=False, index=True)

    # Human-readable source app name from mobile share intent
    # Example: "Myntra", "LinkedIn", "Twitter"
    source_app_name = Column(String(100), nullable=True)

    # Source app package name from mobile share intent
    # Example: "com.myntra.android", "com.linkedin.android"
    source_app_package = Column(String(200), nullable=True)

    # Content category (fixed categories for backward compatibility)
    # Values: 'technology', 'design', 'business', 'science', etc.
    category = Column(String(50), nullable=False, index=True)

    # User-created category (optional, for dynamic categories)
    user_category_id = Column(
        UUID(as_uuid=True),
        ForeignKey("user_categories.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )

    # ===== Optional Metadata =====

    # URL to preview image/thumbnail
    thumbnail_url = Column(String(512), nullable=True)

    # Hero image URL for detail view (larger, higher quality than thumbnail)
    hero_image_url = Column(Text, nullable=True)

    # Estimated reading time in minutes
    reading_time_minutes = Column(Integer, default=5)

    # AI-generated key takeaways (stored as JSONB array)
    # Example: ["Key point 1", "Key point 2", "Key point 3"]
    # Note: Using JSONB for flexibility and compatibility
    key_takeaways = Column(JSONB, nullable=True)

    # ===== Media Fields (Phase 6: Memory Engine) =====

    # URL of the uploaded media file in object storage (R2/S3)
    media_url = Column(Text, nullable=True)

    # MIME type of the media file (e.g., image/jpeg, video/mp4)
    media_mime_type = Column(String(100), nullable=True)

    # File size in bytes
    media_size_bytes = Column(BigInteger, nullable=True)

    # Duration in seconds (for video content)
    media_duration_seconds = Column(Float, nullable=True)

    # Text extracted via OCR from images or video key frames
    ocr_text = Column(Text, nullable=True)

    # Flexible metadata: EXIF, GPS coordinates, dimensions, key frame timestamps, etc.
    media_metadata = Column(JSONB, nullable=True)

    # ===== AI-Generated Fields (Phase 3) =====

    # Embedding vector for semantic search (1536 dimensions)
    # OpenAI text-embedding-3-small: native 1536 dims
    # Ollama nomic-embed-text: 768 dims zero-padded to 1536
    embedding = Column(Vector(1536), nullable=True)

    # Full extracted text content from the page
    extracted_content = Column(Text, nullable=True)

    # AI-generated detailed narrative summary (200-300 words)
    detailed_summary = Column(Text, nullable=True)

    # Which embedding model generated the vector
    embedding_model = Column(String(50), nullable=True)

    # When the embedding was last generated (supports model upgrades and re-embedding)
    embedding_updated_at = Column(DateTime, nullable=True)

    # Number of discovered connections to other content items
    connection_count = Column(Integer, default=0)

    # ===== Processing Status (Two-Phase Architecture) =====

    # PHASE 1: Ingestion Status (URL Fetch + Metadata Extraction)
    # This phase completes quickly (~1-3 seconds) and makes content immediately visible
    ingestion_status = Column(
        SQLEnum(IngestionStatus),
        default=IngestionStatus.pending,
        nullable=False,
        index=True  # Index for finding items to ingest
    )
    ingestion_error = Column(Text, nullable=True)
    ingestion_attempts = Column(Integer, default=0)
    last_ingestion_at = Column(DateTime, nullable=True)

    # PHASE 2: AI Processing Status (Summarization + Embeddings)
    # This phase enriches content with AI insights (rate-limited)
    ai_status = Column(
        SQLEnum(AIStatus),
        default=AIStatus.pending,
        nullable=False,
        index=True  # Index for finding items to process with AI
    )
    ai_error = Column(Text, nullable=True)
    ai_attempts = Column(Integer, default=0)
    last_ai_processed_at = Column(DateTime, nullable=True)

    # Fetch Error Type (for showing auth banners, etc.)
    # Tracks what kind of error occurred during URL fetch
    fetch_error_type = Column(
        SQLEnum(FetchErrorType),
        default=FetchErrorType.none,
        nullable=False,
        index=False  # No need to query by this
    )

    # PHASE 3: Entity Extraction Status (Named Entity Recognition)
    # This phase extracts entities and relationships from content for the knowledge graph
    entity_status = Column(
        SQLEnum(EntityExtractionStatus),
        default=EntityExtractionStatus.pending,
        nullable=False,
        index=True  # Index for finding items to extract entities from
    )
    entity_error = Column(Text, nullable=True)
    entity_attempts = Column(Integer, default=0)
    last_entity_processed_at = Column(DateTime, nullable=True)

    # DEPRECATED: Old single-status fields (will be removed in migration)
    # Kept temporarily for backwards compatibility during migration
    processing_status = Column(
        SQLEnum(ProcessingStatus),
        default=ProcessingStatus.pending,
        nullable=True,
        index=True
    )
    processing_error = Column(Text, nullable=True)
    processing_attempts = Column(Integer, default=0)
    last_processed_at = Column(DateTime, nullable=True)

    # ===== User Notes =====

    # User's personal notes about this content
    notes = Column(Text, nullable=True)

    # ===== User Flags =====

    # Has user marked this as "done" (read/watched)?
    is_done = Column(Boolean, default=False, index=True)

    # Is this a favorite?
    is_favorite = Column(Boolean, default=False, index=True)

    # ===== Timestamps =====

    # When was this content saved?
    # Index for sorting by recency and memory feed queries
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Last time this item was modified
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # ===== Relationships =====

    # Relationship to user
    # back_populates creates bidirectional relationship
    user = relationship("User", back_populates="content_items")

    # Relationship to user category (optional)
    user_category = relationship("UserCategory", foreign_keys=[user_category_id])

    # Relationship to shared spaces (will be added in Phase 5)
    # spaces = relationship("SpaceContent", back_populates="content")

    def __repr__(self):
        """String representation for debugging"""
        return f"<ContentItem(id={self.id}, title={self.title[:50]}, user_id={self.user_id})>"
