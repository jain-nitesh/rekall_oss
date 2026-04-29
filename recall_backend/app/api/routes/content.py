"""
Content management API endpoints.

For beginners:
- These routes handle all content-related operations
- POST /content/ingest - Save a new URL
- GET /content - List all content for user
- GET /content/{id} - Get single content item
- PATCH /content/{id} - Update content flags (is_done, is_favorite, tags)
- DELETE /content/{id} - Delete content item
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query, BackgroundTasks, Request, UploadFile, File, Form
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc, delete
from typing import Optional
from datetime import datetime
import uuid
import logging
from urllib.parse import urlparse

from app.db.session import get_db
from app.models.user import User
from app.models.content_item import ContentItem, ContentType, ProcessingStatus, IngestionStatus, AIStatus, FetchErrorType
from app.api.routes.auth import get_current_user
from app.api.schemas.content import (
    ContentIngestRequest,
    ContentUpdateRequest,
    ContentResponse,
    ContentListResponse,
    FilterOptionsResponse,
    FilterOptionItem,
    ContentSearchRequest
)
from app.services.content_fetcher import ContentFetcherService
from app.services.categorizer import BasicCategorizer
from app.services.ai_service import AIService
from app.core.exceptions import NotFoundError, ValidationError
from app.core.config import settings
from app.utils.content_cleaner import (
    clean_source_app, clean_category,
    clean_thumbnail_url, clean_tags
)
from app.utils.title_cleaner import clean_title  # Use intelligent title cleaner
from app.services.media_storage_service import media_storage_service as _media_storage

logger = logging.getLogger(__name__)

# --- Presigned URL helper for R2/S3 media ---

async def _presign_media_urls(response: ContentResponse) -> ContentResponse:
    """Replace private R2/S3 URLs with presigned URLs so the client can load them."""
    if not settings.s3_endpoint_url:
        return response
    updates = {}
    for field in ('media_url', 'thumbnail_url'):
        url = getattr(response, field, None)
        if url and url.startswith(settings.s3_endpoint_url):
            presigned = await _media_storage.get_presigned_url(url)
            if presigned:
                updates[field] = presigned
    if updates:
        return response.model_copy(update=updates)
    return response


async def _presign_content_list(items) -> list[ContentResponse]:
    """Presign media URLs for a list of ContentResponse objects."""
    return [await _presign_media_urls(ContentResponse.model_validate(item)) for item in items]


# --- Shared text fallback helpers (for auth-walled / paywall content) ---

_KNOWN_DOMAINS = {
    'x.com': 'X', 'twitter.com': 'X',
    'linkedin.com': 'LinkedIn', 'medium.com': 'Medium',
    'reddit.com': 'Reddit', 'facebook.com': 'Facebook',
    'instagram.com': 'Instagram', 'youtube.com': 'YouTube',
    'github.com': 'GitHub', 'substack.com': 'Substack',
}


def _extract_source_label(url: str) -> str:
    """Extract a human-readable source label from any URL."""
    try:
        domain = urlparse(url).netloc.lower().replace('www.', '')
        for key, label in _KNOWN_DOMAINS.items():
            if domain == key or domain.endswith('.' + key):
                return label
        parts = domain.split('.')
        return parts[-2].capitalize() if len(parts) >= 2 else domain.capitalize()
    except Exception:
        return 'Shared'


def _extract_url_context(url: str) -> str:
    """Extract human-readable context from URL path segments."""
    try:
        parsed = urlparse(url)
        segments = [s for s in parsed.path.split('/') if s]
        if not segments:
            return ''
        first = segments[0]
        # Already an @username (e.g. medium.com/@dan/...)
        if first.startswith('@'):
            return first
        # Section-first URLs: /posts/johndoe, /in/johndoe (LinkedIn)
        if first in ('posts', 'in', 'pub') and len(segments) >= 2:
            return f"@{segments[1]}"
        # User-first URLs: /username/status/123 (X, Twitter)
        if len(segments) >= 2 and segments[1] in ('status', 'p', 'comments'):
            return f"@{first}"
        # Subreddit-style: r/programming, u/username
        if first in ('r', 'u') and len(segments) >= 2:
            return f"{first}/{segments[1]}"
        # Slug-style paths: humanize the last meaningful segment
        slug = segments[-1] if segments[-1] not in ('status', 'posts', 'p') else segments[0]
        return slug.replace('-', ' ').replace('_', ' ')[:60]
    except Exception:
        return ''


def _title_from_shared_text(shared_text: str, url: str) -> str:
    """Build the best possible title from shared_text and URL context."""
    source = _extract_source_label(url)
    lines = [l.strip() for l in shared_text.split('\n') if l.strip() and not l.strip().startswith('http')]

    if lines:
        preview = lines[0][:90]
        title = f"{source}: {preview}"
        if len(title) > 100:
            title = title[:97] + "..."
        return title

    # No useful text content — extract context from URL path
    context = _extract_url_context(url)
    if context:
        return f"{source}: {context}"
    return f"{source}: Shared Content"


def _is_placeholder_title(title: str) -> bool:
    """Check if a title is generic/placeholder and should be replaced."""
    t = (title or '').strip().lower()
    return (
        not t or
        t in ('untitled', 'shared content', 'no title') or
        'shared from external app' in t or
        'processing' in t
    )


# Router for content endpoints
router = APIRouter(prefix="/content", tags=["Content Management"])


async def ingest_content_async(
    content_id: str,
    url: str,
    user_id: str,
    custom_title: Optional[str] = None,
    source_app_name: Optional[str] = None,
    source_app_package: Optional[str] = None,
    shared_text: Optional[str] = None
):
    """
    PHASE 1: Ingest content (fetch URL + extract metadata).

    This completes FAST (typically 1-3 seconds) and makes content
    immediately available to the user.

    If shared_text is provided, it's used as fallback when URL fetch fails
    (useful for private/authenticated content like private Twitter, LinkedIn, paywalls).

    After completion:
    - Content is visible in the app with metadata
    - Content is searchable by title/URL
    - ai_status remains 'pending' for Phase 2 processing
    """
    logger.debug(f"╔════════════════════════════════════════════════════╗")
    logger.debug(f"║  PHASE 1: INGESTION - {content_id[:8]}...         ║")
    logger.debug(f"╚════════════════════════════════════════════════════╝")
    logger.debug(f"URL: {url}")

    # Initialize services
    # Import playwright_pool from main (global singleton)
    from main import playwright_pool
    from app.core.config import settings
    fetcher = ContentFetcherService(
        playwright_pool=playwright_pool,
        selective_mode=settings.playwright_selective_mode
    )
    categorizer = BasicCategorizer()

    # Get database session (create new session for background task)
    from app.db.session import AsyncSessionLocal
    async with AsyncSessionLocal() as db:
        try:
            # Mark as fetching
            stmt = select(ContentItem).where(ContentItem.id == content_id)
            result = await db.execute(stmt)
            content = result.scalar_one_or_none()

            if not content:
                logger.error(f"❌ Content {content_id} not found!")
                return

            # Note mode: ingestion already done, nothing to fetch
            if content.content_type == ContentType.note and content.ingestion_status == IngestionStatus.ingested:
                logger.debug(f"📝 Note content - ingestion already complete, skipping URL fetch")
                logger.debug(f"[OK] INGESTION COMPLETE (note) - Content available to user!")
                logger.debug(f"=" * 55)
                return

            content.ingestion_status = IngestionStatus.fetching
            content.ingestion_attempts = (content.ingestion_attempts or 0) + 1
            content.last_ingestion_at = datetime.utcnow()
            await db.commit()
            logger.debug(f"[OK] Marked as FETCHING (attempt #{content.ingestion_attempts})")

            # Step 1: Fetch URL content
            logger.debug(f"Step 1: Fetching URL content...")
            logger.debug(f"  - shared_text parameter: {shared_text[:200] if shared_text else 'None/Empty'}")

            fetched = await fetcher.fetch_url(url)
            error_type = fetched.get('error_type', 'none')

            # Check if fetch encountered an error
            if error_type != 'none':
                logger.error(f"❌ URL fetch failed: {error_type}")
                logger.debug(f"  - Error message: {fetched.get('error_message')}")

                # Try shared_text as fallback for private/authenticated content
                if shared_text:
                    logger.debug(f"✓ Using shared_text as fallback ({len(shared_text)} chars)")
                    clean_text = shared_text.strip()

                    fetched = {
                        'title': _title_from_shared_text(clean_text, url),
                        'description': clean_text[:300] + ('...' if len(clean_text) > 300 else ''),
                        'main_content': shared_text,
                        'thumbnail_url': None,
                        'error_type': error_type,  # Preserve error type
                    }
                else:
                    # No fallback available - mark as failed
                    stmt = select(ContentItem).where(ContentItem.id == content_id)
                    result = await db.execute(stmt)
                    content = result.scalar_one_or_none()
                    if content:
                        content.ingestion_status = IngestionStatus.failed
                        content.ingestion_error = fetched.get('error_message', 'URL fetch failed')
                        content.fetch_error_type = FetchErrorType[error_type]
                        await db.commit()
                    logger.debug(f"[OK] Marked as INGESTION FAILED (no shared_text fallback)")
                    return
            else:
                logger.debug(f"✓ URL fetch successful!")
                logger.debug(f"  - Title: {fetched.get('title', 'N/A')}")
                # Safely handle None values in main_content
                main_content = fetched.get('main_content') or ''
                logger.debug(f"  - Content length: {len(main_content)} chars")

                # Check if fetched content is poor and shared_text can improve it
                fetched_desc = (fetched.get('description') or '').strip()
                content_is_poor = (
                    not main_content or len(main_content) < 50 or
                    (fetched_desc in ('', 'No description available.') and len(main_content) < 200)
                )
                title_is_poor = _is_placeholder_title(fetched.get('title') or '')

                if shared_text and (content_is_poor or title_is_poor):
                    logger.warning(f"⚠️ Fetched content is poor, enriching with shared_text ({len(shared_text)} chars)")
                    clean_text = shared_text.strip()

                    if content_is_poor:
                        fetched['main_content'] = shared_text

                    if title_is_poor:
                        fetched['title'] = _title_from_shared_text(clean_text, url)
                        logger.debug(f"  ✓ Title from shared_text: '{fetched['title']}'")

                    if not fetched_desc or fetched_desc == 'No description available.':
                        fetched['description'] = clean_text[:300] + ('...' if len(clean_text) > 300 else '')

            # Step 2: Detect source app
            logger.debug(f"Step 2: Detecting source app...")
            if source_app_name:
                source_app = clean_source_app(source_app_name, url)
                logger.debug(f"✓ Source app from share intent: {source_app}")
            else:
                source_app = categorizer.detect_source_app(url)
                logger.debug(f"✓ Source app from URL detection: {source_app}")

            # Step 3: Extract metadata (NO AI, just metadata)
            logger.debug(f"Step 3: Extracting metadata...")
            meta_keywords = fetched.get('meta_keywords', [])
            meta_tags = fetched.get('meta_tags', [])
            og_tags = fetched.get('og_tags', {})

            # Category from OpenGraph or URL/title-based detection
            category = None
            if og_tags and 'section' in og_tags:
                og_section = og_tags['section'].lower()
                category = categorizer._map_og_section_to_category(og_section)
                logger.debug(f"✓ Category from OpenGraph: {category}")

            if not category:
                category = categorizer.detect_category(url, fetched.get('title') or '', fetched.get('description') or '')
                logger.debug(f"✓ Category detected: {category}")

            # Extract tags from metadata
            tags = categorizer.extract_basic_tags(
                fetched.get('title') or '',
                fetched.get('description') or '',
                meta_keywords=meta_keywords,
                meta_tags=meta_tags,
                og_tags=og_tags
            )

            # Estimate reading time
            reading_time = categorizer.estimate_reading_time(fetched.get('main_content') or '')

            # Step 4: Update content with metadata (IMMEDIATE AVAILABILITY)
            stmt = select(ContentItem).where(ContentItem.id == content_id)
            result = await db.execute(stmt)
            content = result.scalar_one_or_none()

            if content:
                # Use fetched title or custom title as fallback
                fetched_title = (fetched.get('title') or '').strip()

                has_meaningful_title = fetched_title and not _is_placeholder_title(fetched_title)
                final_title = fetched_title if has_meaningful_title else (custom_title or 'Untitled')

                logger.debug(f"Step 4: Setting content title...")
                logger.debug(f"  - fetched_title: '{fetched_title}'")
                logger.debug(f"  - has_meaningful_title: {has_meaningful_title}")
                logger.debug(f"  - custom_title: '{custom_title}'")
                logger.debug(f"  - final_title: '{final_title}'")

                # Update with metadata
                content.title = clean_title(final_title, url)
                logger.debug(f"  - content.title (after clean): '{content.title}'")
                content.summary = fetched.get('description') or ''  # Use metadata description (not AI)
                content.tags = clean_tags(tags)
                content.category = clean_category(category)
                content.source_app = clean_source_app(source_app, url)
                content.thumbnail_url = clean_thumbnail_url(fetched.get('thumbnail_url'))
                content.reading_time_minutes = reading_time

                # Mark ingestion as complete
                content.ingestion_status = IngestionStatus.ingested
                content.ingestion_error = None

                # Set fetch error type (may be 'auth_required' even if ingestion succeeded via shared_text)
                error_type_str = fetched.get('error_type', 'none')
                try:
                    content.fetch_error_type = FetchErrorType[error_type_str]
                except (KeyError, ValueError):
                    content.fetch_error_type = FetchErrorType.none

                # Set AI status based on config
                if not settings.ai_enabled:
                    content.ai_status = AIStatus.disabled
                    logger.debug(f"[OK] AI is disabled - content ready to use")
                else:
                    content.ai_status = AIStatus.pending
                    logger.debug(f"[OK] AI status set to PENDING for Phase 2")

                await db.commit()
                logger.debug(f"[OK] INGESTION COMPLETE - Content available to user!")
                logger.debug(f"=" * 55)

        except Exception as e:
            logger.error(f"[ERROR] Ingestion failed: {e}")
            import traceback
            logger.exception(e)

            # Mark ingestion as failed
            try:
                stmt = select(ContentItem).where(ContentItem.id == content_id)
                result = await db.execute(stmt)
                content = result.scalar_one_or_none()
                if content:
                    content.ingestion_status = IngestionStatus.failed
                    content.ingestion_error = f"Critical error: {str(e)}"
                    await db.commit()
            except Exception as e:
                logger.warning(f"Failed to update status after error: {e}")


async def _process_url_ai(content, url: str, ai_service) -> dict:
    """Process URL-based content through AI pipeline."""
    fetcher = ContentFetcherService(selective_mode=settings.playwright_selective_mode)
    fetched = await fetcher.fetch_url(url)
    main_content = fetched.get('main_content') or ''
    logger.debug(f"  - Content length for AI: {len(main_content)} chars")

    result = await ai_service.process_content(
        url=url,
        title=content.title or '',
        content=main_content,
        provided_source_app=content.source_app
    )
    # Preserve raw page text for wiki/chat/entity enrichment
    result['extracted_content'] = main_content
    return result


async def _process_media_ai(content, ai_service, db) -> dict:
    """Process image/video content through visual AI pipeline."""
    import tempfile
    import os

    content_type_val = content.content_type.value if hasattr(content.content_type, 'value') else str(content.content_type)
    logger.debug(f"  Processing {content_type_val} content via visual AI...")

    # Download media from R2/S3 via authenticated S3 client
    from app.services.media_storage_service import media_storage_service

    expected_endpoint = settings.s3_endpoint_url
    if expected_endpoint and not content.media_url.startswith(expected_endpoint):
        logger.warning(f"Media URL does not match expected S3 endpoint: {content.media_url}")

    media_bytes = await media_storage_service.download_media(content.media_url)

    logger.debug(f"  - Downloaded {len(media_bytes)} bytes from {content.media_url}")

    if content_type_val == "image":
        result = await ai_service.process_visual_content(
            image_bytes=media_bytes,
            mime_type=content.media_mime_type or "image/jpeg",
            context=content.notes,
        )
    else:
        # Video: extract key frames, then analyze
        from app.services.video_processing_service import video_processing_service

        # Write to temp file for ffmpeg
        # Derive temp file suffix from MIME type for correct ffmpeg format detection
        _mime_to_ext = {"video/mp4": ".mp4", "video/quicktime": ".mov", "video/webm": ".webm"}
        tmp_suffix = _mime_to_ext.get(content.media_mime_type, ".mp4")
        with tempfile.NamedTemporaryFile(suffix=tmp_suffix, delete=False) as tmp:
            tmp.write(media_bytes)
            tmp_path = tmp.name

        try:
            frames = await video_processing_service.extract_key_frames(tmp_path)
            metadata = await video_processing_service.get_video_metadata(tmp_path)
            duration = metadata.get("duration", 0)

            # Generate thumbnail if we don't have one
            thumb_url = None
            if not content.thumbnail_url:
                thumb_bytes = await video_processing_service.generate_video_thumbnail(tmp_path)
                if thumb_bytes:
                    from app.services.media_storage_service import media_storage_service
                    thumb_url = await media_storage_service.upload_media(
                        file_bytes=thumb_bytes,
                        mime_type="image/jpeg",
                        user_id=str(content.user_id),
                        content_id=str(content.id),
                        filename="thumbnail.jpg",
                    )

            result = await ai_service.process_video_content(
                frames=frames,
                duration_seconds=duration,
                context=content.notes,
            )
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)

    # Store OCR text
    result["ocr_text"] = result.get("ocr_text", "")
    # Adapt result keys to match URL processing format
    if "reading_time" not in result:
        result["reading_time_minutes"] = 0

    # Pass video-specific fields through result dict (avoids ORM re-query losing mutations)
    if content_type_val == "video":
        result["_media_duration_seconds"] = duration
        result["_media_metadata"] = metadata
        if thumb_url:
            result["_thumbnail_url"] = thumb_url

    return result


async def process_ai_async(content_id: str, url: str):
    """
    PHASE 2: AI processing (summarization + embeddings).

    This runs AFTER ingestion completes successfully.
    Content is already visible to user - this enriches it with AI insights.

    Branches by content_type:
    - url: Fetch URL content, extract with LLM, generate embedding
    - image: Download from media_url, run visual AI (OCR + extraction), generate embedding
    - video: Download from media_url, extract key frames, run visual AI, generate embedding

    Features:
    - Runs only if AI is enabled
    - Rate-limited to avoid overwhelming AI provider
    - Updates existing content with AI results
    - Graceful degradation: if AI fails, content still usable with metadata
    """
    logger.debug(f"╔════════════════════════════════════════════════════╗")
    logger.debug(f"║  PHASE 2: AI PROCESSING - {content_id[:8]}...     ║")
    logger.debug(f"╚════════════════════════════════════════════════════╝")

    # Initialize AI service
    ai_service = AIService()

    from app.db.session import AsyncSessionLocal
    async with AsyncSessionLocal() as db:
        try:
            # Check if AI is enabled
            if not settings.ai_enabled:
                logger.debug(f"[SKIP] AI disabled in config")
                stmt = select(ContentItem).where(ContentItem.id == content_id)
                result = await db.execute(stmt)
                content = result.scalar_one_or_none()
                if content:
                    content.ai_status = AIStatus.disabled
                    await db.commit()
                return

            # Mark as processing
            stmt = select(ContentItem).where(ContentItem.id == content_id)
            result = await db.execute(stmt)
            content = result.scalar_one_or_none()

            if not content:
                logger.error(f"❌ Content {content_id} not found!")
                return

            # Skip if ingestion not completed
            if content.ingestion_status != IngestionStatus.ingested:
                logger.debug(f"[SKIP] Ingestion not complete yet (status: {content.ingestion_status})")
                return

            content.ai_status = AIStatus.processing
            content.ai_attempts = (content.ai_attempts or 0) + 1
            content.last_ai_processed_at = datetime.utcnow()
            await db.commit()
            logger.debug(f"[OK] Marked as AI_PROCESSING (attempt #{content.ai_attempts})")

            # Branch based on content type
            content_type_val = content.content_type.value if hasattr(content.content_type, 'value') else str(content.content_type)

            if content_type_val in ("image", "video"):
                ai_result = await _process_media_ai(content, ai_service, db)
            elif content_type_val == "note":
                # Notes already have extracted_content, just run AI on it
                note_content = content.extracted_content or ''
                logger.debug(f"  - Note content length for AI: {len(note_content)} chars")
                ai_result = await ai_service.process_content(
                    url='',
                    title=content.title or '',
                    content=note_content,
                    provided_source_app='recall'
                )
            else:
                ai_result = await _process_url_ai(content, url, ai_service)

            logger.debug(f"✓ AI processing successful!")

            # Update with AI results (enrichment)
            stmt = select(ContentItem).where(ContentItem.id == content_id)
            result = await db.execute(stmt)
            content = result.scalar_one_or_none()

            if content:
                # AI can improve/override metadata-based fields
                ai_title = (ai_result.get('title') or '').strip()
                if ai_title and ai_title not in ['Untitled', '']:
                    content.title = clean_title(ai_title, url) if url else ai_title[:512]
                    logger.debug(f"✓ Title enriched by AI")

                content.summary = ai_result.get('summary') or content.summary
                content.tags = clean_tags(ai_result.get('tags', []))
                content.category = clean_category(ai_result.get('category', 'other'))
                content.reading_time_minutes = ai_result.get('reading_time_minutes', 0)

                # Store raw page text for richer wiki/chat/entity context
                if ai_result.get('extracted_content'):
                    content.extracted_content = ai_result['extracted_content'][:8000]
                    logger.debug(f"✓ Extracted content stored ({len(content.extracted_content)} chars)")

                # Store detailed narrative summary and key takeaways
                if ai_result.get('detailed_summary'):
                    content.detailed_summary = ai_result['detailed_summary']
                    logger.debug(f"✓ Detailed summary stored ({len(content.detailed_summary)} chars)")
                if ai_result.get('key_takeaways'):
                    content.key_takeaways = ai_result['key_takeaways']
                    logger.debug(f"✓ Key takeaways stored ({len(ai_result['key_takeaways'])} items)")

                # Store OCR text for media content
                if ai_result.get('ocr_text'):
                    content.ocr_text = ai_result['ocr_text']
                    logger.debug(f"✓ OCR text stored ({len(ai_result['ocr_text'])} chars)")

                # Apply video-specific fields from _process_media_ai
                if ai_result.get('_media_duration_seconds') is not None:
                    content.media_duration_seconds = ai_result['_media_duration_seconds']
                if ai_result.get('_media_metadata'):
                    content.media_metadata = ai_result['_media_metadata']
                if ai_result.get('_thumbnail_url'):
                    content.thumbnail_url = ai_result['_thumbnail_url']

                # Store embedding and model info
                if 'embedding' in ai_result and ai_result['embedding']:
                    content.embedding = ai_result['embedding']
                    content.embedding_model = ai_result.get('embedding_model')
                    content.embedding_updated_at = datetime.utcnow()
                    logger.debug(f"✓ Embedding stored ({len(ai_result['embedding'])} dims)")

                # If AI inferred better source_app, use it
                if 'source_app' in ai_result:
                    ai_source = ai_result['source_app']
                    if ai_source:
                        content.source_app = clean_source_app(ai_source, url or '')
                        logger.debug(f"✓ Source app enriched by AI")

                # Mark AI processing as complete
                content.ai_status = AIStatus.completed
                content.ai_error = None

                await db.commit()
                logger.debug(f"[OK] AI PROCESSING COMPLETE - Content enriched!")

                # Phase 3: Discover connections if embedding was stored
                if content.embedding is not None:
                    try:
                        from app.services.connections_service import discover_connections
                        logger.debug(f"Step 3: Discovering connections...")
                        connections = await discover_connections(
                            content_id=content_id,
                            user_id=str(content.user_id),
                            db=db
                        )
                        if connections:
                            logger.debug(f"✓ Found {len(connections)} connections (with explanations)")
                        else:
                            logger.debug(f"  No connections found above threshold")
                    except Exception as conn_err:
                        logger.warning(f"[WARN] Connection discovery failed (non-fatal): {conn_err}")
                        import traceback
                        logger.exception(e)

                # Phase 3b: Extract entities for knowledge graph
                try:
                    from app.services.entity_extraction_service import extract_entities_for_content
                    entities = await extract_entities_for_content(
                        content_id=content_id,
                        db=db
                    )
                    if entities:
                        logger.debug(f"✓ Extracted {len(entities)} entities for knowledge graph")
                    else:
                        logger.debug(f"  No entities extracted")
                except Exception as entity_err:
                    logger.warning(f"[WARN] Entity extraction failed (non-fatal): {entity_err}")
                    import traceback
                    logger.exception(e)

                logger.debug(f"=" * 55)

        except Exception as e:
            logger.error(f"[ERROR] AI processing failed: {e}")
            import traceback
            logger.exception(e)

            # Mark AI processing as failed (content still usable with metadata)
            try:
                stmt = select(ContentItem).where(ContentItem.id == content_id)
                result = await db.execute(stmt)
                content = result.scalar_one_or_none()
                if content:
                    content.ai_status = AIStatus.failed
                    content.ai_error = f"AI error: {str(e)}"
                    await db.commit()
                    logger.debug(f"[OK] Marked as AI_FAILED (content still usable with metadata)")
            except Exception as update_err:
                logger.error(f"[ERROR] Failed to update status after AI error: {update_err}")


async def process_content_async(
    content_id: str,
    url: str,
    user_id: str,
    custom_title: Optional[str] = None,
    source_app_name: Optional[str] = None,
    source_app_package: Optional[str] = None
):
    """
    Background task to process content (fetch + AI).

    This runs asynchronously after the API response is returned.
    Updates the content item once processing is complete.

    Features resilient processing with status tracking:
    - Updates processing_status to track progress
    - Records errors for debugging
    - Counts attempts for retry logic
    - Survives backend restarts (persisted in database)
    """
    logger.debug(f"╔════════════════════════════════════════════════════╗")
    logger.debug(f"║  BACKGROUND: Processing content {content_id[:8]}...║")
    logger.debug(f"╚════════════════════════════════════════════════════╝")
    logger.debug(f"URL: {url}")

    # Initialize services
    # Import playwright_pool from main (global singleton)
    from main import playwright_pool
    from app.core.config import settings
    fetcher = ContentFetcherService(
        playwright_pool=playwright_pool,
        selective_mode=settings.playwright_selective_mode
    )
    categorizer = BasicCategorizer()
    ai_service = AIService()

    # Get database session (create new session for background task)
    from app.db.session import AsyncSessionLocal
    async with AsyncSessionLocal() as db:
        try:
            # Mark as processing
            stmt = select(ContentItem).where(ContentItem.id == content_id)
            result = await db.execute(stmt)
            content = result.scalar_one_or_none()

            if not content:
                logger.error(f"❌ Content {content_id} not found!")
                return

            content.processing_status = ProcessingStatus.processing
            content.processing_attempts = (content.processing_attempts or 0) + 1
            content.last_processed_at = datetime.utcnow()
            await db.commit()
            logger.debug(f"[OK] Marked as PROCESSING (attempt #{content.processing_attempts})")
            # Step 1: Fetch URL content
            logger.debug(f"Step 1: Fetching URL content...")
            try:
                fetched = await fetcher.fetch_url(url)
                logger.debug(f"✓ URL fetch successful!")
                logger.debug(f"  - Title: {fetched.get('title', 'N/A')}")
                logger.debug(f"  - Content length: {len(fetched.get('main_content', ''))} chars")
            except Exception as e:
                logger.error(f"❌ URL fetch failed: {type(e).__name__}: {e}")
                # Update content with error status
                stmt = select(ContentItem).where(ContentItem.id == content_id)
                result = await db.execute(stmt)
                content = result.scalar_one_or_none()
                if content:
                    content.summary = f"Failed to fetch URL: {str(e)}"
                    content.tags = ["error", "fetch_failed"]
                    content.processing_status = ProcessingStatus.failed
                    content.processing_error = f"URL fetch failed: {str(e)}"
                    await db.commit()
                logger.debug(f"[OK] Marked as FAILED (URL fetch error)")
                return

            # Step 2: Detect source app
            logger.debug(f"Step 2: Detecting source app...")
            if source_app_name:
                # Use provided source app name from mobile share intent (clean it)
                source_app = clean_source_app(source_app_name, url)
                logger.debug(f"✓ Source app from share intent: {source_app}")
            else:
                # Will be inferred by AI or fall back to URL-based detection
                source_app = None
                logger.debug(f"⟳ Source app will be inferred by AI or URL")

            # Step 3: Process with AI (if enabled) or use metadata-based extraction
            ai_processing_successful = False
            
            if settings.ai_enabled:
                try:
                    logger.debug(f"Step 3: Processing with AI...")
                    ai_result = await ai_service.process_content(
                        url=url,
                        title=fetched.get('title') or '',
                        content=fetched.get('main_content') or '',
                        provided_source_app=source_app
                    )
                    logger.debug(f"✓ AI processing successful!")
                    
                    # Use AI-inferred source app if not provided
                    if not source_app and 'source_app' in ai_result:
                        source_app = ai_result['source_app']
                        logger.debug(f"✓ Source app inferred by AI: {source_app}")
                    
                    # Fall back to URL-based detection if still not determined
                    if not source_app:
                        source_app = categorizer.detect_source_app(url)
                        logger.debug(f"✓ Source app from URL detection: {source_app}")

                    # Update content with AI results
                    stmt = select(ContentItem).where(ContentItem.id == content_id)
                    result = await db.execute(stmt)
                    content = result.scalar_one_or_none()

                    if content:
                        # Always prefer AI-inferred title over mobile-provided placeholder
                        # Only fall back to custom_title if AI returned nothing meaningful
                        ai_title = (ai_result.get('title') or '').strip()
                        has_meaningful_title = ai_title and ai_title not in ['Untitled', '']

                        final_title = ai_title if has_meaningful_title else (custom_title or 'Untitled')

                        # Clean all values before inserting
                        content.title = clean_title(final_title, url)
                        content.summary = ai_result['summary']  # Text field, no limit
                        content.tags = clean_tags(ai_result.get('tags', []))
                        content.category = clean_category(ai_result['category'])
                        content.source_app = clean_source_app(source_app, url)
                        content.thumbnail_url = clean_thumbnail_url(fetched.get('thumbnail_url'))
                        content.reading_time_minutes = ai_result['reading_time_minutes']
                        content.processing_status = ProcessingStatus.completed
                        content.processing_error = None  # Clear any previous errors
                        await db.commit()
                        logger.debug(f"[OK] Updated content with AI results")
                        logger.debug(f"[OK] Marked as COMPLETED")
                        ai_processing_successful = True

                except Exception as e:
                    logger.warning(f"⚠️  AI processing failed: {type(e).__name__}: {e}")
                    logger.debug(f"Falling back to metadata-based extraction...")
                    # Fall through to metadata-based extraction below
                    pass

            # Use metadata-based extraction (when AI is disabled or AI processing failed)
            if not settings.ai_enabled or not ai_processing_successful:
                logger.debug(f"Step 3: Using metadata-based extraction...")
                
                # Extract tags from HTML metadata and OpenGraph tags
                meta_keywords = fetched.get('meta_keywords', [])
                meta_tags = fetched.get('meta_tags', [])
                og_tags = fetched.get('og_tags', {})
                
                # Use OpenGraph article:section for category hint if available
                category = None
                if og_tags and 'section' in og_tags:
                    # Map OpenGraph section to our category
                    og_section = og_tags['section'].lower()
                    category = categorizer._map_og_section_to_category(og_section)
                    logger.debug(f"✓ Category from OpenGraph section: {category}")
                
                # Fall back to URL/title-based detection if no OpenGraph section
                if not category:
                    category = categorizer.detect_category(url, fetched.get('title') or '', fetched.get('description') or '')

                tags = categorizer.extract_basic_tags(
                    fetched.get('title') or '',
                    fetched.get('description') or '',
                    meta_keywords=meta_keywords,
                    meta_tags=meta_tags,
                    og_tags=og_tags
                )
                reading_time = categorizer.estimate_reading_time(fetched.get('main_content') or '')

                # Update content with metadata-based results
                stmt = select(ContentItem).where(ContentItem.id == content_id)
                result = await db.execute(stmt)
                content = result.scalar_one_or_none()

                # Ensure source_app is set (use provided, OpenGraph site_name, or fall back to URL detection)
                if not source_app:
                    # Try OpenGraph site_name first
                    if og_tags and 'site_name' in og_tags:
                        site_name = og_tags['site_name']
                        source_app = clean_source_app(site_name, url)
                        logger.debug(f"✓ Source app from OpenGraph site_name: {source_app}")
                    
                    # Fall back to URL detection if still not determined
                    if not source_app:
                        detected = categorizer.detect_source_app(url)
                        source_app = clean_source_app(detected, url)
                        logger.debug(f"✓ Source app from URL detection: {source_app}")
                
                # Clean all values before inserting
                if content:
                    # Always prefer fetched/resolved title over mobile-provided placeholder
                    # Mobile title is just extracted from URL path, not actual content
                    # Only fall back to custom_title if fetching failed or returned nothing meaningful
                    fetched_title = (fetched.get('title') or '').strip()
                    has_meaningful_title = fetched_title and fetched_title not in ['Untitled', '']

                    final_title = fetched_title if has_meaningful_title else (custom_title or 'Untitled')
                    content.title = clean_title(final_title, url)
                    content.summary = fetched.get('description') or ''  # Text field, no limit
                    content.tags = clean_tags(tags)
                    content.category = clean_category(category)
                    content.source_app = clean_source_app(source_app, url)
                    content.thumbnail_url = clean_thumbnail_url(fetched.get('thumbnail_url'))
                    content.reading_time_minutes = reading_time
                    content.processing_status = ProcessingStatus.completed
                    content.processing_error = None  # Clear any previous errors
                    await db.commit()
                    logger.debug(f"[OK] Updated content with metadata-based results")
                    logger.debug(f"[OK] Marked as COMPLETED")

            logger.debug("=" * 55)

        except Exception as e:
            logger.error(f"[ERROR] CRITICAL ERROR in background processing: {e}")
            import traceback
            logger.exception(e)

            # Mark as FAILED with error details
            try:
                stmt = select(ContentItem).where(ContentItem.id == content_id)
                result = await db.execute(stmt)
                content = result.scalar_one_or_none()
                if content:
                    content.processing_status = ProcessingStatus.failed
                    content.processing_error = f"Critical error: {str(e)}"
                    await db.commit()
                    logger.debug(f"[OK] Marked as FAILED (critical error)")
            except Exception as e:
                logger.warning(f"Failed to update status after critical error: {e}")


@router.post("/ingest", response_model=ContentResponse)
async def ingest_content(
    http_request: Request,
    request: ContentIngestRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Ingest a new URL and save to database.

    TWO-PHASE ASYNC FLOW (Decoupled AI):
    1. Create placeholder content item immediately
    2. Return response to client (fast!)
    3. PHASE 1 (Background): Fetch URL + extract metadata → content visible (~1-3 seconds)
    4. PHASE 2 (Background): Run AI summarization → content enriched (~5-10 seconds, rate-limited)

    This enables users to see content immediately after Phase 1 completes.
    AI enrichment happens transparently in Phase 2 without blocking content availability.

    Example request:
        POST /api/content/ingest
        {
            "url": "https://fastapi.tiangolo.com/tutorial/",
            "title": "Optional custom title",
            "source_app_name": "Twitter",  # optional
            "source_app_package": "com.twitter.android"  # optional
        }

    Returns:
        ContentResponse with placeholder data (Phase 1 will update with metadata,
        Phase 2 will enrich with AI insights)
    """
    logger.debug("═══════════════════════════════════════════════════")
    logger.debug("CONTENT INGEST REQUEST (TWO-PHASE ASYNC)")
    logger.debug("═══════════════════════════════════════════════════")
    logger.debug(f"Timestamp: {datetime.now().isoformat()}")
    logger.debug(f"User ID: {current_user.id}")
    logger.debug(f"URL: {request.url}")
    logger.debug(f"Title: {request.title}")

    # Detect note mode: no URL, just shared_text
    is_note = not request.url and request.shared_text

    if is_note:
        # === NOTE MODE: Save text note directly, no URL fetching needed ===
        logger.debug(f"📝 NOTE MODE: Saving text note ({len(request.shared_text)} chars)")
        note_text = request.shared_text.strip()
        note_title = request.title or (note_text[:80] + ('...' if len(note_text) > 80 else ''))

        content = ContentItem(
            user_id=current_user.id,
            url=None,
            title=note_title,
            summary=note_text[:300] + ('...' if len(note_text) > 300 else ''),
            tags=[],
            source_app="recall",
            category="note",
            content_type=ContentType.note,
            reading_time_minutes=max(1, len(note_text.split()) // 200),
            is_done=False,
            is_favorite=False,
            ingestion_status=IngestionStatus.ingested,
            ai_status=AIStatus.pending if settings.ai_enabled else AIStatus.disabled,
            extracted_content=note_text,
        )

        db.add(content)
        await db.commit()
        await db.refresh(content)

        logger.debug(f"✓ Note saved directly")
        logger.debug(f"  - Content ID: {content.id}")
        logger.debug(f"  - Title: {content.title}")
        # AI processing (Phase 2) will be picked up by the background processor
        logger.debug(f"✓ API response returned (background processor will handle AI)")
        logger.debug(f"═══════════════════════════════════════════════════")
    else:
        # === URL MODE: Original two-phase flow ===
        # Determine source app: prefer provided name, otherwise use URL-based detection
        categorizer = BasicCategorizer()
        if request.source_app_name:
            # Clean the provided source app name
            source_app = clean_source_app(request.source_app_name, request.url)
        else:
            # Fall back to URL-based detection for placeholder
            detected = categorizer.detect_source_app(request.url)
            source_app = clean_source_app(detected, request.url)

        # Extract title from URL as placeholder
        try:
            from urllib.parse import urlparse
            parsed = urlparse(request.url)
            domain = parsed.netloc.replace('www.', '')
            path_parts = [p for p in parsed.path.split('/') if p]
            placeholder_title = request.title or (path_parts[-1].replace('-', ' ').title() if path_parts else domain)
        except Exception as e:
            logger.warning(f"Failed to parse URL for title generation: {e}")
            placeholder_title = request.title or request.url

        # Create placeholder content item immediately (with cleaned values)
        content = ContentItem(
            user_id=current_user.id,
            url=request.url,
            title=clean_title(placeholder_title, request.url),  # Pass URL for smart cleaning
            summary="Fetching content... This will be updated soon.",
            tags=["fetching"],
            source_app=clean_source_app(source_app, request.url),
            category="other",
            reading_time_minutes=5,
            is_done=False,
            is_favorite=False,
            # NEW: Set initial statuses for two-phase processing
            ingestion_status=IngestionStatus.pending,
            ai_status=AIStatus.pending if settings.ai_enabled else AIStatus.disabled
        )

        # Save placeholder to database
        db.add(content)
        await db.commit()
        await db.refresh(content)

        logger.debug(f"✓ Created placeholder content item")
        logger.debug(f"  - Content ID: {content.id}")
        logger.debug(f"  - Title: {content.title}")
        logger.debug(f"  - Ingestion Status: {content.ingestion_status.value}")
        logger.debug(f"  - AI Status: {content.ai_status.value}")
        logger.debug(f"⟳ Scheduled PHASE 1: Ingestion...")

        # Schedule PHASE 1: Ingestion (fetch URL + metadata extraction)
        background_tasks.add_task(
            ingest_content_async,
            content_id=str(content.id),
            url=request.url,
            user_id=str(current_user.id),
            custom_title=request.title,
            source_app_name=request.source_app_name,
            source_app_package=request.source_app_package,
            shared_text=request.shared_text  # NEW: Pass shared_text for private content fallback
        )

        # NOTE: PHASE 2 (AI processing) will be handled by background processor
        # once ingestion completes successfully

        logger.debug(f"✓ API response returned (Phase 1 scheduled)")
        logger.debug(f"═══════════════════════════════════════════════════")

    # Return placeholder immediately (Phase 1 & 2 happen in background)
    return await _presign_media_urls(ContentResponse.model_validate(content))


@router.post("/upload-media", response_model=ContentResponse)
async def upload_media(
    file: UploadFile = File(..., description="Media file (image or video)"),
    content_type: str = Form("image", description="Content type: 'image' or 'video'"),
    title: Optional[str] = Form(None, description="Optional title"),
    notes: Optional[str] = Form(None, description="Optional notes"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Upload a media file (image or video) and create a content item.

    TWO-PHASE ASYNC FLOW:
    1. Upload file to R2/S3, create content item immediately
    2. Background AI processing: OCR, visual analysis, embedding generation

    For images: whiteboard photos, restaurant menus, book pages, screenshots
    For videos: up to 5 second clips processed via key frame extraction + OCR

    Returns ContentResponse with media_url set. AI fields (title, summary, tags)
    will be populated by background processing.
    """
    from app.services.media_storage_service import media_storage_service

    # Validate content_type parameter
    if content_type not in ("image", "video"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="content_type must be 'image' or 'video'"
        )

    # Read file bytes
    file_bytes = await file.read()
    mime_type = file.content_type or "application/octet-stream"

    # Validate actual file content matches claimed MIME type (magic bytes check)
    _MAGIC_BYTES = {
        b'\xff\xd8\xff': 'image/jpeg',
        b'\x89PNG': 'image/png',
        b'RIFF': 'image/webp',  # RIFF....WEBP
        b'\x00\x00\x00': 'video/mp4',  # ftyp box (offset 4)
    }
    detected_type = None
    for magic, mtype in _MAGIC_BYTES.items():
        if file_bytes[:len(magic)] == magic:
            detected_type = mtype
            break
    # For video/mp4, also check ftyp signature at offset 4
    if file_bytes[4:8] == b'ftyp':
        detected_type = 'video/mp4'
    # For QuickTime (.mov), ftyp with 'qt' brand
    if file_bytes[4:8] == b'ftyp' or (len(file_bytes) > 8 and file_bytes[4:8] in (b'moov', b'mdat', b'wide', b'free')):
        if mime_type == 'video/quicktime':
            detected_type = 'video/quicktime'

    if detected_type and detected_type != mime_type:
        # Allow close matches (e.g. video/quicktime detected as video/mp4)
        if not (detected_type.startswith('video/') and mime_type.startswith('video/')):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"File content does not match declared type {mime_type}"
            )

    # Validate file size and type
    validation_error = media_storage_service.validate_upload(file_bytes, mime_type)
    if validation_error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=validation_error
        )

    # Validate video duration (max 5 seconds)
    if content_type == "video":
        import tempfile
        from app.services.video_processing_service import VideoProcessingService
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
            tmp.write(file_bytes)
            tmp_path = tmp.name
        try:
            vps = VideoProcessingService()
            metadata = await vps.get_video_metadata(tmp_path)
            duration = metadata.get("duration", 0)
            if duration > 5:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Video too long ({duration:.1f}s). Maximum duration is 5 seconds."
                )
        finally:
            import os as _os2
            if _os2.path.exists(tmp_path):
                _os2.unlink(tmp_path)

    # Generate content ID
    content_id = uuid.uuid4()

    # Sanitize filename to prevent path traversal
    import os as _os
    safe_filename = _os.path.basename(file.filename) if file.filename else f"capture.{mime_type.split('/')[-1]}"
    # Strip any remaining special characters
    safe_filename = "".join(c for c in safe_filename if c.isalnum() or c in '.-_')
    if not safe_filename:
        safe_filename = f"capture.{mime_type.split('/')[-1]}"

    # Upload to R2/S3
    media_url = await media_storage_service.upload_media(
        file_bytes=file_bytes,
        mime_type=mime_type,
        user_id=str(current_user.id),
        content_id=str(content_id),
        filename=safe_filename,
    )

    # Generate thumbnail for images
    thumbnail_url = await media_storage_service.generate_thumbnail(
        file_bytes=file_bytes,
        mime_type=mime_type,
        user_id=str(current_user.id),
        content_id=str(content_id),
    )

    # Determine duration for videos (will be updated by AI processing)
    media_size_bytes = len(file_bytes)

    # Create content item - title/summary will be AI-generated in Phase 2
    ct = ContentType.image if content_type == "image" else ContentType.video
    content = ContentItem(
        id=content_id,
        user_id=current_user.id,
        content_type=ct,
        url=None,
        title=title or f"Captured {content_type.capitalize()}",
        summary=f"Processing {content_type}... AI analysis in progress.",
        tags=[],
        source_app="camera",
        category="other",
        reading_time_minutes=0,
        is_done=False,
        is_favorite=False,
        notes=notes,
        media_url=media_url,
        media_mime_type=mime_type,
        media_size_bytes=media_size_bytes,
        thumbnail_url=thumbnail_url,
        # Skip Phase 1 (no URL to fetch), go straight to Phase 2
        ingestion_status=IngestionStatus.ingested,
        ai_status=AIStatus.pending if settings.ai_enabled else AIStatus.disabled,
    )

    db.add(content)
    await db.commit()
    await db.refresh(content)

    logger.debug(f"[MEDIA UPLOAD] Created {content_type} content item {content_id}")
    logger.debug(f"  - Media URL: {media_url}")
    logger.debug(f"  - Size: {media_size_bytes} bytes")
    logger.debug(f"  - AI Status: {content.ai_status.value}")

    # Phase 2 AI processing is handled by the background processor
    # (it picks up items with ai_status=pending automatically)

    return await _presign_media_urls(ContentResponse.model_validate(content))


@router.get("", response_model=ContentListResponse)
async def get_all_content(
    page: int = Query(1, ge=1, le=1000, description="Page number (1-indexed)"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    category: Optional[str] = Query(None, description="Filter by category"),
    source_app: Optional[str] = Query(None, description="Filter by source app"),
    time_added: Optional[str] = Query(None, description="Filter by time added (today, thisWeek, thisMonth, older)"),
    sort_by: Optional[str] = Query(None, description="Sort by (newest, oldest, alphabetical)"),
    read_status: Optional[str] = Query(None, description="Filter by read status (read, unread)"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get all content for current user with pagination and optional filters.

    Returns newest content first by default (sorted by created_at desc).

    Query parameters:
    - page: Page number (default: 1)
    - page_size: Items per page (default: 20, max: 100)
    - category: Filter by category (technology, design, business, etc.)
    - source_app: Filter by source app (linkedin, reddit, twitter, etc.)
    - time_added: Filter by time added (today, thisWeek, thisMonth, older)
    - sort_by: Sort order (newest, oldest, alphabetical)
    - read_status: Filter by read status (read, unread)

    Example:
        GET /api/content?page=1&page_size=20&category=technology&source_app=linkedin&read_status=unread

    Returns:
        ContentListResponse with:
        - content: List of ContentResponse objects
        - total: Total number of items
        - page: Current page
        - page_size: Items per page
        - has_more: Whether more pages are available
    """
    from datetime import datetime, timedelta

    # Build base query with filters
    conditions = [ContentItem.user_id == current_user.id]

    # Category filter
    if category:
        conditions.append(ContentItem.category == category)

    # Source app filter
    if source_app:
        conditions.append(ContentItem.source_app == source_app)

    # Time added filter
    if time_added:
        now = datetime.utcnow()
        if time_added == "today":
            # Today: from midnight to now
            start_of_today = datetime(now.year, now.month, now.day)
            conditions.append(ContentItem.created_at >= start_of_today)
        elif time_added == "thisWeek":
            # This week: last 7 days
            start_of_week = now - timedelta(days=7)
            conditions.append(ContentItem.created_at >= start_of_week)
        elif time_added == "thisMonth":
            # This month: last 30 days
            start_of_month = now - timedelta(days=30)
            conditions.append(ContentItem.created_at >= start_of_month)
        elif time_added == "older":
            # Older: more than 30 days ago
            older_than = now - timedelta(days=30)
            conditions.append(ContentItem.created_at < older_than)

    # Read status filter
    if read_status:
        if read_status == "read":
            conditions.append(ContentItem.is_done == True)
        elif read_status == "unread":
            conditions.append(ContentItem.is_done == False)

    # Count total items with filters
    count_query = select(func.count(ContentItem.id)).where(*conditions)
    total_result = await db.execute(count_query)
    total = total_result.scalar()

    # Get paginated items with filters
    offset = (page - 1) * page_size

    # Build query with ordering
    query = select(ContentItem).where(*conditions)

    # Apply sorting
    if sort_by == "oldest":
        query = query.order_by(ContentItem.created_at.asc())
    elif sort_by == "alphabetical":
        query = query.order_by(ContentItem.title.asc())
    else:  # Default: newest
        query = query.order_by(desc(ContentItem.created_at))

    query = query.offset(offset).limit(page_size)

    result = await db.execute(query)
    items = result.scalars().all()

    # Calculate if more pages are available
    has_more = (page * page_size) < total

    logger.debug(f"✅ GET /content - Results:")
    logger.debug(f"   - Total matching items: {total}")
    logger.debug(f"   - Returned items: {len(items)}")
    logger.debug(f"   - Has more: {has_more}")

    return ContentListResponse(
        content=await _presign_content_list(items),
        total=total,
        page=page,
        page_size=page_size,
        has_more=has_more
    )


@router.get("/memory-feed", response_model=ContentListResponse)
async def get_memory_feed(
    days: int = Query(..., ge=1, le=3650, description="Days ago to fetch content for"),
    page: int = Query(1, ge=1, le=1000, description="Page number (1-indexed)"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get content saved approximately X days ago (memory feed).

    Returns paginated content items saved around the specified number of days ago.
    Uses ±3 day tolerance for flexibility (e.g., content from 4-10 days ago appears in "7 days" section).

    Query parameters:
    - days: Number of days ago (required)
    - page: Page number (default: 1)
    - page_size: Items per page (default: 20, max: 100)

    Example:
        GET /api/content/memory-feed?days=7&page=1&page_size=20

    Returns:
        ContentListResponse with pagination metadata
    """
    from datetime import datetime, timedelta

    # Calculate date range: days ago ±3 day tolerance
    # This allows more flexibility for memory feed (e.g., content from 9 days ago shows in "7 days" section)
    target_date = datetime.utcnow() - timedelta(days=days)
    start_date = target_date - timedelta(days=3)
    end_date = target_date + timedelta(days=3)

    # Count total items for this user in date range
    count_query = select(func.count(ContentItem.id)).where(
        ContentItem.user_id == current_user.id,
        ContentItem.created_at >= start_date,
        ContentItem.created_at <= end_date
    )
    total_result = await db.execute(count_query)
    total = total_result.scalar()

    # Get paginated items
    offset = (page - 1) * page_size

    query = select(ContentItem).where(
        ContentItem.user_id == current_user.id,
        ContentItem.created_at >= start_date,
        ContentItem.created_at <= end_date
    ).order_by(
        desc(ContentItem.created_at)  # Newest first
    ).offset(offset).limit(page_size)

    result = await db.execute(query)
    items = result.scalars().all()

    # Calculate if more pages are available
    has_more = (page * page_size) < total

    return ContentListResponse(
        content=await _presign_content_list(items),
        total=total,
        page=page,
        page_size=page_size,
        has_more=has_more
    )


@router.get("/timeline")
async def get_content_timeline(
    sections: str = Query("just_in,today,yesterday", description="Comma-separated list of sections (just_in, today, yesterday, this_week, this_month, older)"),
    page: int = Query(1, ge=1, le=1000, description="Page number (1-indexed)"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    read_status: Optional[str] = Query(None, description="Filter by read status (read, unread)"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get content grouped by time periods for the new feed UX.

    Returns content organized into calendar-based time sections:
    - just_in: Last 3 hours (very recent content)
    - today: From midnight today to now (excluding just_in)
    - yesterday: Previous calendar date (midnight to 11:59:59 PM)
    - this_week: Last 7 days (excluding today and yesterday)
    - this_month: Last 30 days (excluding this week)
    - older: Everything older than yesterday

    Query parameters:
    - sections: Comma-separated list of sections to fetch (default: "just_in,today,yesterday")
    - page: Page number for each section (default: 1)
    - page_size: Items per section page (default: 20, max: 100)

    Example:
        GET /api/content/timeline?sections=just_in,today,yesterday&page=1&page_size=20

    Returns:
        {
            "just_in": {
                "content": [...],
                "total": 5,
                "page": 1,
                "page_size": 20,
                "has_more": false
            },
            "today": {
                "content": [...],
                "total": 8,
                "page": 1,
                "page_size": 20,
                "has_more": false
            },
            "yesterday": {
                "content": [...],
                "total": 12,
                "page": 1,
                "page_size": 20,
                "has_more": false
            }
        }
    """
    from datetime import datetime, timedelta

    # Parse requested sections
    requested_sections = [s.strip() for s in sections.split(",") if s.strip()]

    # Calculate calendar-based time ranges
    now = datetime.utcnow()

    # Get midnight today (start of current calendar day in UTC)
    today_midnight = datetime(now.year, now.month, now.day, 0, 0, 0)

    # Get midnight yesterday (start of previous calendar day in UTC)
    yesterday_midnight = today_midnight - timedelta(days=1)

    # Define time ranges for each section (calendar-based)
    section_ranges = {
        "just_in": (now - timedelta(hours=3), now),  # Last 3 hours
        "today": (today_midnight, now - timedelta(hours=3)),  # Midnight today to 3 hours ago
        "yesterday": (yesterday_midnight, today_midnight),  # Previous calendar date
        "this_week": (now - timedelta(days=7), yesterday_midnight),  # Last 7 days (excluding today/yesterday)
        "this_month": (now - timedelta(days=30), now - timedelta(days=7)),  # Last 30 days (excluding this week)
        "older": (datetime(1970, 1, 1), yesterday_midnight)  # Everything older than yesterday
    }

    # Build response for each requested section
    response = {}

    for section in requested_sections:
        if section not in section_ranges:
            continue

        start_date, end_date = section_ranges[section]

        # Build base conditions
        base_conditions = [
            ContentItem.user_id == current_user.id,
            ContentItem.created_at >= start_date,
            ContentItem.created_at < end_date,
        ]
        if read_status:
            if read_status == "read":
                base_conditions.append(ContentItem.is_done == True)
            elif read_status == "unread":
                base_conditions.append(ContentItem.is_done == False)

        # Count total items in this time range
        count_query = select(func.count(ContentItem.id)).where(*base_conditions)
        total_result = await db.execute(count_query)
        total = total_result.scalar()

        # Get paginated items for this section
        offset = (page - 1) * page_size

        query = select(ContentItem).where(*base_conditions).order_by(
            desc(ContentItem.created_at)  # Newest first
        ).offset(offset).limit(page_size)

        result = await db.execute(query)
        items = result.scalars().all()

        # Calculate if more pages are available
        has_more = (page * page_size) < total

        response[section] = {
            "content": await _presign_content_list(items),
            "total": total,
            "page": page,
            "page_size": page_size,
            "has_more": has_more
        }

    return response


@router.get("/filter-options", response_model=FilterOptionsResponse)
async def get_filter_options(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get available filter options with counts for the current user.

    Returns only categories and sources that have at least 1 content item.
    Used by the search page to display dynamic filters with counts.

    Returns:
        FilterOptionsResponse with:
        - categories: Fixed ContentCategory enum values with counts
        - user_categories: User-created categories with counts
        - sources: Source app values with counts

    Example:
        GET /api/content/filter-options

        Returns:
        {
            "categories": [
                {"value": "technology", "display_name": "Technology", "count": 15, "color": null}
            ],
            "user_categories": [
                {"value": "uuid-here", "display_name": "Custom", "count": 3, "color": "#FF5733"}
            ],
            "sources": [
                {"value": "linkedin", "display_name": "LinkedIn", "count": 23, "color": null}
            ]
        }
    """
    # Query 1: Get fixed categories with counts (only categories with content)
    category_query = select(
        ContentItem.category,
        func.count(ContentItem.id).label('count')
    ).where(
        ContentItem.user_id == current_user.id
    ).group_by(
        ContentItem.category
    ).having(
        func.count(ContentItem.id) > 0
    )

    category_result = await db.execute(category_query)
    categories_data = category_result.all()

    # Format category display names (capitalize first letter)
    categories = [
        FilterOptionItem(
            value=cat,
            display_name=cat.capitalize(),
            count=count,
            color=None
        )
        for cat, count in categories_data
    ]

    # Query 2: Get user-created categories with counts
    # Join ContentItem with user_categories table where user_category_id IS NOT NULL
    from app.models.user_category import UserCategory

    user_category_query = select(
        UserCategory.id,
        UserCategory.name,
        UserCategory.color,
        func.count(ContentItem.id).label('count')
    ).select_from(
        ContentItem
    ).join(
        UserCategory,
        ContentItem.user_category_id == UserCategory.id
    ).where(
        ContentItem.user_id == current_user.id
    ).group_by(
        UserCategory.id,
        UserCategory.name,
        UserCategory.color
    ).having(
        func.count(ContentItem.id) > 0
    )

    user_category_result = await db.execute(user_category_query)
    user_categories_data = user_category_result.all()

    user_categories = [
        FilterOptionItem(
            value=str(cat_id),
            display_name=name,
            count=count,
            color=color
        )
        for cat_id, name, color, count in user_categories_data
    ]

    # Query 3: Get source apps with counts (only sources with content)
    source_query = select(
        ContentItem.source_app,
        func.count(ContentItem.id).label('count')
    ).where(
        ContentItem.user_id == current_user.id
    ).group_by(
        ContentItem.source_app
    ).having(
        func.count(ContentItem.id) > 0
    )

    source_result = await db.execute(source_query)
    sources_data = source_result.all()

    # Format source app display names (handle camelCase like "productHunt")
    def format_source_name(source_app: str) -> str:
        """Format source app string to display name."""
        if not source_app:
            return "Unknown"

        # Handle camelCase (e.g., "productHunt" -> "Product Hunt")
        if any(c.isupper() for c in source_app):
            import re
            words = re.findall(r'[A-Z]?[a-z]+|[A-Z]+(?=[A-Z][a-z]|\b)', source_app)
            return ' '.join(word.capitalize() for word in words)
        else:
            # Simple capitalize (e.g., "linkedin" -> "LinkedIn")
            return source_app.capitalize()

    sources = [
        FilterOptionItem(
            value=source,
            display_name=format_source_name(source),
            count=count,
            color=None
        )
        for source, count in sources_data
    ]

    return FilterOptionsResponse(
        categories=categories,
        user_categories=user_categories,
        sources=sources
    )


@router.get("/{content_id}", response_model=ContentResponse)
async def get_content(
    content_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get single content item by ID.

    Security: Ensures user can only access their own content.

    Example:
        GET /api/content/550e8400-e29b-41d4-a716-446655440000

    Returns:
        ContentResponse

    Errors:
        404: Content not found (or doesn't belong to user)
    """
    query = select(ContentItem).where(
        ContentItem.id == content_id,
        ContentItem.user_id == current_user.id  # Security: user's content only
    )
    result = await db.execute(query)
    content = result.scalar_one_or_none()

    if not content:
        raise NotFoundError("Content")

    return await _presign_media_urls(ContentResponse.model_validate(content))


@router.patch("/{content_id}", response_model=ContentResponse)
async def update_content(
    content_id: str,
    request: ContentUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update content flags (is_done, is_favorite, tags).

    Only updates fields that are provided in the request.
    Other fields remain unchanged.

    Example:
        PATCH /api/content/550e8400-e29b-41d4-a716-446655440000
        {
            "is_done": true,
            "is_favorite": false
        }

    Returns:
        Updated ContentResponse

    Errors:
        404: Content not found
    """
    # Fetch content
    query = select(ContentItem).where(
        ContentItem.id == content_id,
        ContentItem.user_id == current_user.id
    )
    result = await db.execute(query)
    content = result.scalar_one_or_none()

    if not content:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Content not found"
        )

    # Update fields (only if provided)
    if request.is_done is not None:
        content.is_done = request.is_done
    if request.is_favorite is not None:
        content.is_favorite = request.is_favorite
    if request.tags is not None:
        content.tags = request.tags
    if request.notes is not None:
        content.notes = request.notes

    # Save changes
    await db.commit()
    await db.refresh(content)

    return await _presign_media_urls(ContentResponse.model_validate(content))


@router.delete("/{content_id}")
async def delete_content(
    content_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Delete content item.

    Example:
        DELETE /api/content/550e8400-e29b-41d4-a716-446655440000

    Returns:
        Success message

    Errors:
        404: Content not found
    """
    query = select(ContentItem).where(
        ContentItem.id == content_id,
        ContentItem.user_id == current_user.id
    )
    result = await db.execute(query)
    content = result.scalar_one_or_none()

    if not content:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Content not found"
        )

    # Clean up media files from object storage if present
    if content.media_url:
        try:
            from app.services.media_storage_service import media_storage_service
            await media_storage_service.delete_media(content.media_url)
            if content.thumbnail_url and content.thumbnail_url != content.media_url:
                await media_storage_service.delete_media(content.thumbnail_url)
        except Exception as e:
            logger.warning(f"Failed to delete media files for {content_id}: {e}")

    # Delete from database using SQLAlchemy delete statement
    stmt = delete(ContentItem).where(
        ContentItem.id == content_id,
        ContentItem.user_id == current_user.id
    )
    await db.execute(stmt)
    await db.commit()

    return {"message": "Content deleted successfully"}


@router.post("/search", response_model=ContentListResponse)
async def search_content(
    request: ContentSearchRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Search and filter content with multi-select support.

    Supports:
    - Text search across title, summary, and tags
    - Multi-select categories (OR logic within category filters)
    - Multi-select user categories (OR logic within user category filters)
    - Multi-select source apps (OR logic within source filters)
    - Date range filtering
    - Pagination

    Filter Logic:
    - OR logic within the same filter type (e.g., category=tech OR category=science)
    - AND logic between different filter types (e.g., (tech OR science) AND (linkedin OR reddit))

    Example:
        POST /api/content/search
        {
            "query": "python",
            "categories": ["technology", "education"],
            "source_apps": ["linkedin", "reddit"],
            "days": 30,
            "page": 1,
            "page_size": 20
        }

    Returns:
        ContentListResponse with paginated results
    """
    from datetime import timedelta
    from sqlalchemy import or_, and_, cast, String, text as sa_text
    import logging

    logger = logging.getLogger(__name__)

    use_semantic = False
    query_embedding = None

    # Try semantic search when a text query is provided
    if request.query and request.query.strip():
        try:
            from app.services.ai_service import AIService
            ai_service = AIService()
            query_embedding = await ai_service.generate_embedding(request.query)
            use_semantic = True
        except Exception as e:
            logger.warning(f"Embedding generation failed, using keyword search: {e}")

    # --- Helper: build filter clauses for raw SQL ---
    def _build_filter_clauses(params):
        """Build WHERE filter clauses (excluding semantic/embedding filters)."""
        filter_clauses = []

        if request.categories and len(request.categories) > 0:
            cat_placeholders = [f":cat_{i}" for i in range(len(request.categories))]
            cat_clause = f"category IN ({','.join(cat_placeholders)})"
            for i, cat in enumerate(request.categories):
                params[f"cat_{i}"] = cat

            if request.user_category_ids and len(request.user_category_ids) > 0:
                ucat_placeholders = [f":ucat_{i}" for i in range(len(request.user_category_ids))]
                ucat_clause = f"user_category_id::text IN ({','.join(ucat_placeholders)})"
                for i, ucat in enumerate(request.user_category_ids):
                    params[f"ucat_{i}"] = ucat
                filter_clauses.append(f"({cat_clause} OR {ucat_clause})")
            else:
                filter_clauses.append(cat_clause)
        elif request.user_category_ids and len(request.user_category_ids) > 0:
            ucat_placeholders = [f":ucat_{i}" for i in range(len(request.user_category_ids))]
            ucat_clause = f"user_category_id::text IN ({','.join(ucat_placeholders)})"
            for i, ucat in enumerate(request.user_category_ids):
                params[f"ucat_{i}"] = ucat
            filter_clauses.append(ucat_clause)

        if request.source_apps and len(request.source_apps) > 0:
            src_placeholders = [f":src_{i}" for i in range(len(request.source_apps))]
            filter_clauses.append(f"source_app IN ({','.join(src_placeholders)})")
            for i, src in enumerate(request.source_apps):
                params[f"src_{i}"] = src

        if request.days:
            cutoff_date = datetime.utcnow() - timedelta(days=request.days)
            filter_clauses.append("created_at >= :cutoff_date")
            params['cutoff_date'] = cutoff_date

        return filter_clauses

    # --- Hybrid search: semantic results + keyword supplement ---
    if use_semantic:
        embedding_str = '[' + ','.join(str(x) for x in query_embedding) + ']'
        threshold = 0.25  # Slightly lower threshold to catch more semantic matches

        # Build semantic WHERE clauses
        params = {
            'user_id': str(current_user.id),
            'query_embedding': embedding_str,
            'threshold': threshold,
        }

        where_clauses = [
            "user_id = :user_id",
            "embedding IS NOT NULL",
            f"1 - (embedding <=> :query_embedding) >= :threshold",
        ]
        where_clauses.extend(_build_filter_clauses(params))
        where_sql = " AND ".join(where_clauses)
        offset = (request.page - 1) * request.page_size

        # Get semantic results
        results_sql = sa_text(f"""
            SELECT *, 1 - (embedding <=> :query_embedding) as similarity
            FROM content_items
            WHERE {where_sql}
            ORDER BY embedding <=> :query_embedding
            LIMIT :limit OFFSET :offset
        """)
        params['limit'] = request.page_size
        params['offset'] = offset

        result = await db.execute(results_sql, params)
        semantic_rows = result.fetchall()

        # Count semantic results
        count_sql = sa_text(f"SELECT COUNT(*) FROM content_items WHERE {where_sql}")
        count_params = {k: v for k, v in params.items() if k not in ('limit', 'offset')}
        count_result = await db.execute(count_sql, count_params)
        semantic_total = count_result.scalar()

        # If semantic search found enough results, return them
        if len(semantic_rows) >= request.page_size or semantic_total > 0:
            has_more = (request.page * request.page_size) < semantic_total
            return ContentListResponse(
                content=[await _presign_media_urls(ContentResponse.model_validate(dict(row._mapping))) for row in semantic_rows],
                total=semantic_total,
                page=request.page,
                page_size=request.page_size,
                has_more=has_more
            )

        # Semantic found nothing on page 1 — supplement with keyword results
        # This handles cases where items have no embeddings yet
        logger.info(f"Semantic search returned 0 results for '{request.query}', supplementing with keyword search")

    # Keyword/filter search (fallback or supplement)
    # Use PostgreSQL full-text search for better matching than ILIKE
    keyword_params = {
        'user_id': str(current_user.id),
    }

    keyword_where = ["user_id = :user_id"]
    keyword_where.extend(_build_filter_clauses(keyword_params))

    if request.query and request.query.strip():
        # Use full-text search with ts_vector for semantic-like keyword matching
        # plainto_tsquery handles natural language queries (splits words, stems them)
        keyword_where.append("""(
            to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, '') || ' ' || coalesce(extracted_content, '') || ' ' || coalesce(tags::text, '') || ' ' || coalesce(notes, ''))
            @@ plainto_tsquery('english', :search_query)
            OR title ILIKE :search_term
            OR summary ILIKE :search_term
            OR notes ILIKE :search_term
        )""")
        keyword_params['search_query'] = request.query
        keyword_params['search_term'] = f"%{request.query}%"

    keyword_where_sql = " AND ".join(keyword_where)
    offset = (request.page - 1) * request.page_size

    # Count
    count_sql = sa_text(f"SELECT COUNT(*) FROM content_items WHERE {keyword_where_sql}")
    count_result = await db.execute(count_sql, keyword_params)
    total = count_result.scalar()

    # Results — rank by text relevance when there's a query
    if request.query and request.query.strip():
        results_sql = sa_text(f"""
            SELECT *,
                ts_rank(
                    to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, '') || ' ' || coalesce(extracted_content, '') || ' ' || coalesce(tags::text, '') || ' ' || coalesce(notes, '')),
                    plainto_tsquery('english', :search_query)
                ) as text_rank
            FROM content_items
            WHERE {keyword_where_sql}
            ORDER BY text_rank DESC, created_at DESC
            LIMIT :limit OFFSET :offset
        """)
    else:
        results_sql = sa_text(f"""
            SELECT *
            FROM content_items
            WHERE {keyword_where_sql}
            ORDER BY created_at DESC
            LIMIT :limit OFFSET :offset
        """)

    keyword_params['limit'] = request.page_size
    keyword_params['offset'] = offset

    result = await db.execute(results_sql, keyword_params)
    rows = result.fetchall()

    has_more = (request.page * request.page_size) < total

    return ContentListResponse(
        content=[await _presign_media_urls(ContentResponse.model_validate(dict(row._mapping))) for row in rows],
        total=total,
        page=request.page,
        page_size=request.page_size,
        has_more=has_more
    )


