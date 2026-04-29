"""
Chrome extension bookmark sync API endpoints.

- POST /chrome-sync/check-urls   - Bulk URL existence check for deduplication
- POST /chrome-sync/bulk-ingest  - Bulk bookmark ingestion
- POST /chrome-sync/map-to-spaces - Assign content to spaces by folder name
"""
import uuid
import logging
from datetime import datetime
from fastapi import APIRouter, Depends, BackgroundTasks, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.db.session import get_db
from app.models.user import User
from app.models.content_item import ContentItem, IngestionStatus, AIStatus
from app.models.space import Space, SpaceMember, SpaceContent, SpaceMemberRole
from app.api.routes.auth import get_current_user
from app.api.routes.content import ingest_content_async
from app.api.schemas.chrome_sync import (
    ChromeUrlCheckRequest, ChromeUrlCheckResponse,
    ChromeBulkIngestRequest, ChromeBulkIngestResponse, ChromeBulkIngestResultItem,
    ChromeSpaceMapRequest, ChromeSpaceMapResponse, ChromeSpaceMapResultItem,
)
from app.utils.url_normalizer import normalize_url
from app.utils.content_cleaner import clean_title
from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/chrome-sync", tags=["Chrome Sync"])


# ===== Helpers =====

async def _get_user_url_map(user_id, db: AsyncSession) -> dict:
    """Get a mapping of normalized URL -> content_id for a user's library."""
    result = await db.execute(
        select(ContentItem.id, ContentItem.url).where(
            ContentItem.user_id == user_id
        )
    )
    url_map = {}
    for row in result.fetchall():
        normalized = normalize_url(row.url)
        # Keep the first content_id for each normalized URL
        if normalized not in url_map:
            url_map[normalized] = str(row.id)
    return url_map


async def _find_or_create_space(
    space_name: str, user_id, db: AsyncSession
) -> tuple:
    """
    Find an existing space owned by the user with this name, or create one.

    Returns:
        (space_id, created: bool)
    """
    # Look for an existing active space with this name owned by the user
    result = await db.execute(
        select(Space).join(
            SpaceMember,
            and_(
                SpaceMember.space_id == Space.id,
                SpaceMember.user_id == user_id,
                SpaceMember.role == SpaceMemberRole.owner
            )
        ).where(
            Space.name == space_name,
            Space.is_active == True
        )
    )
    existing = result.scalar_one_or_none()

    if existing:
        return str(existing.id), False

    # Create new space
    space = Space(
        name=space_name,
        description=f"Synced from Chrome bookmarks folder",
        created_by=user_id,
        invite_token=Space.generate_invite_token()
    )
    db.add(space)
    await db.flush()

    # Add user as owner
    member = SpaceMember(
        space_id=space.id,
        user_id=user_id,
        role=SpaceMemberRole.owner
    )
    db.add(member)
    await db.flush()

    return str(space.id), True


# ===== Endpoints =====

@router.post("/check-urls", response_model=ChromeUrlCheckResponse)
async def check_urls(
    request: ChromeUrlCheckRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Check which URLs already exist in the user's library.

    Used by the Chrome extension before ingesting to avoid duplicates.
    URLs are normalized before comparison (strips tracking params, www., etc.).
    """
    url_map = await _get_user_url_map(current_user.id, db)

    existing_urls = {}
    missing_urls = []

    for url in request.urls:
        normalized = normalize_url(url)
        if normalized in url_map:
            existing_urls[url] = url_map[normalized]
        else:
            missing_urls.append(url)

    return ChromeUrlCheckResponse(
        existing_urls=existing_urls,
        missing_urls=missing_urls
    )


@router.post(
    "/bulk-ingest",
    response_model=ChromeBulkIngestResponse,
    status_code=status.HTTP_202_ACCEPTED
)
async def bulk_ingest(
    request: ChromeBulkIngestRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Bulk ingest bookmarks from the Chrome extension.

    Creates ContentItem placeholders and schedules background ingestion.
    Deduplicates against the user's existing library using normalized URLs.
    """
    url_map = await _get_user_url_map(current_user.id, db)

    results = []
    created = 0
    skipped = 0
    errors = 0

    for bookmark in request.bookmarks:
        try:
            normalized = normalize_url(bookmark.url)

            # Check for duplicate
            if normalized in url_map:
                results.append(ChromeBulkIngestResultItem(
                    chrome_bookmark_id=bookmark.chrome_bookmark_id,
                    content_id=url_map[normalized],
                    status="duplicate"
                ))
                skipped += 1
                continue

            # Create placeholder content item
            from urllib.parse import urlparse
            parsed = urlparse(bookmark.url)
            domain = parsed.netloc.replace('www.', '')
            path_parts = [p for p in parsed.path.split('/') if p]
            placeholder_title = bookmark.title or (
                path_parts[-1].replace('-', ' ').title() if path_parts else domain
            )

            content = ContentItem(
                user_id=current_user.id,
                url=bookmark.url,
                title=clean_title(placeholder_title),
                summary="Synced from Chrome — processing...",
                tags=["chrome-sync"],
                source_app="chrome_extension",
                category="other",
                reading_time_minutes=5,
                is_done=False,
                is_favorite=False,
                ingestion_status=IngestionStatus.pending,
                ai_status=AIStatus.pending if settings.ai_enabled else AIStatus.disabled
            )

            db.add(content)
            await db.flush()

            # Track in url_map to avoid intra-batch duplicates
            url_map[normalized] = str(content.id)

            # Schedule background ingestion
            background_tasks.add_task(
                ingest_content_async,
                content_id=str(content.id),
                url=bookmark.url,
                user_id=str(current_user.id),
                custom_title=bookmark.title
            )

            results.append(ChromeBulkIngestResultItem(
                chrome_bookmark_id=bookmark.chrome_bookmark_id,
                content_id=str(content.id),
                status="created"
            ))
            created += 1

        except Exception as e:
            logger.error(f"Error ingesting bookmark {bookmark.chrome_bookmark_id}: {e}")
            results.append(ChromeBulkIngestResultItem(
                chrome_bookmark_id=bookmark.chrome_bookmark_id,
                status="error",
                error=str(e)
            ))
            errors += 1

    await db.commit()

    logger.info(
        f"Chrome bulk ingest for user {current_user.id}: "
        f"{created} created, {skipped} duplicates, {errors} errors"
    )

    return ChromeBulkIngestResponse(
        results=results,
        created=created,
        skipped=skipped,
        errors=errors
    )


@router.post("/map-to-spaces", response_model=ChromeSpaceMapResponse)
async def map_to_spaces(
    request: ChromeSpaceMapRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Assign content items to spaces based on Chrome bookmark folder structure.

    For each mapping, finds or creates a space with the given name,
    then links the content item to that space.
    """
    results = []
    spaces_created = 0
    spaces_reused = 0
    items_mapped = 0
    items_already_mapped = 0
    error_count = 0

    # Cache space lookups within this request
    space_cache: dict[str, str] = {}  # space_name -> space_id

    for mapping in request.mappings:
        try:
            # Find or create the space
            if mapping.space_name in space_cache:
                space_id = space_cache[mapping.space_name]
                was_created = False
            else:
                space_id, was_created = await _find_or_create_space(
                    mapping.space_name, current_user.id, db
                )
                space_cache[mapping.space_name] = space_id
                if was_created:
                    spaces_created += 1
                else:
                    spaces_reused += 1

            # Check if content is already in this space
            existing = await db.execute(
                select(SpaceContent).where(
                    SpaceContent.space_id == space_id,
                    SpaceContent.content_id == mapping.content_id
                )
            )
            if existing.scalar_one_or_none():
                results.append(ChromeSpaceMapResultItem(
                    content_id=mapping.content_id,
                    space_name=mapping.space_name,
                    space_id=space_id,
                    status="already_mapped"
                ))
                items_already_mapped += 1
                continue

            # Add content to space
            space_content = SpaceContent(
                space_id=space_id,
                content_id=mapping.content_id,
                added_by=current_user.id
            )
            db.add(space_content)
            await db.flush()

            results.append(ChromeSpaceMapResultItem(
                content_id=mapping.content_id,
                space_name=mapping.space_name,
                space_id=space_id,
                status="mapped"
            ))
            items_mapped += 1

        except Exception as e:
            logger.error(f"Error mapping content {mapping.content_id} to space '{mapping.space_name}': {e}")
            results.append(ChromeSpaceMapResultItem(
                content_id=mapping.content_id,
                space_name=mapping.space_name,
                status="error",
                error=str(e)
            ))
            error_count += 1

    await db.commit()

    logger.info(
        f"Chrome space mapping for user {current_user.id}: "
        f"{spaces_created} spaces created, {spaces_reused} reused, "
        f"{items_mapped} mapped, {items_already_mapped} already mapped, {error_count} errors"
    )

    return ChromeSpaceMapResponse(
        results=results,
        spaces_created=spaces_created,
        spaces_reused=spaces_reused,
        items_mapped=items_mapped,
        items_already_mapped=items_already_mapped,
        errors=error_count
    )
