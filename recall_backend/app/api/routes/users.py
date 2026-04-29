"""
User-related API endpoints (preferences, personal info, etc.).

For beginners:
- These routes handle user-specific settings
- GET /user/preferences - Get user preferences
- PUT /user/preferences - Update user preferences
- GET /user/personal-info - Get user's personal info (self-entity)
- POST /user/personal-info - Seed personal info (bio, social links)
"""
from datetime import datetime
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import Optional
import logging

from app.db.session import get_db
from app.models.user import User
from app.models.user_preferences import UserPreferences as UserPreferencesModel
from app.models.entity import Entity
from app.api.routes.auth import get_current_user
from app.api.schemas.user import (
    UserPreferences,
    UserPreferencesUpdate,
    DeleteAccountRequest,
    SeedPersonalInfoRequest,
    PersonalInfoResponse,
)

logger = logging.getLogger(__name__)


# Router for user endpoints
router = APIRouter(prefix="/user", tags=["User"])


@router.get("/preferences", response_model=UserPreferences)
async def get_user_preferences(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get user preferences (summary style, auto-categorize, etc.).

    Creates default preferences if none exist.

    Example:
        GET /api/user/preferences

        Returns:
        {
            "summary_style": "bullet_points",
            "auto_categorize": true,
            "connected_sources": ["twitter", "reddit"]
        }
    """
    # Get existing preferences or create default
    query = select(UserPreferencesModel).where(
        UserPreferencesModel.user_id == current_user.id
    )
    result = await db.execute(query)
    prefs = result.scalar_one_or_none()

    # Create default preferences if none exist
    if not prefs:
        prefs = UserPreferencesModel(
            user_id=current_user.id,
            summary_style="bullet_points",
            auto_categorize=True,
            connected_sources=[],
            daily_gems_enabled=False,
            daily_gems_time="9:00 AM"
        )
        db.add(prefs)
        await db.commit()
        await db.refresh(prefs)

    return UserPreferences(
        summary_style=prefs.summary_style,
        auto_categorize=prefs.auto_categorize,
        connected_sources=prefs.connected_sources or [],
        daily_gems_enabled=prefs.daily_gems_enabled,
        daily_gems_time=prefs.daily_gems_time
    )


@router.put("/preferences", response_model=UserPreferences)
async def update_user_preferences(
    request: UserPreferencesUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update user preferences.

    Only updates fields that are provided in the request.

    Example:
        PUT /api/user/preferences
        {
            "summary_style": "paragraph",
            "auto_categorize": false
        }

    Returns:
        Updated UserPreferences
    """
    # Get existing preferences or create new
    query = select(UserPreferencesModel).where(
        UserPreferencesModel.user_id == current_user.id
    )
    result = await db.execute(query)
    prefs = result.scalar_one_or_none()

    # Create if doesn't exist
    if not prefs:
        prefs = UserPreferencesModel(
            user_id=current_user.id,
            summary_style="bullet_points",
            auto_categorize=True,
            connected_sources=[],
            daily_gems_enabled=False,
            daily_gems_time="9:00 AM"
        )
        db.add(prefs)

    # Update fields (only if provided)
    if request.summary_style is not None:
        prefs.summary_style = request.summary_style
    if request.auto_categorize is not None:
        prefs.auto_categorize = request.auto_categorize
    if request.connected_sources is not None:
        prefs.connected_sources = request.connected_sources
    if request.daily_gems_enabled is not None:
        prefs.daily_gems_enabled = request.daily_gems_enabled
    if request.daily_gems_time is not None:
        prefs.daily_gems_time = request.daily_gems_time

    await db.commit()
    await db.refresh(prefs)

    return UserPreferences(
        summary_style=prefs.summary_style,
        auto_categorize=prefs.auto_categorize,
        connected_sources=prefs.connected_sources or [],
        daily_gems_enabled=prefs.daily_gems_enabled,
        daily_gems_time=prefs.daily_gems_time
    )


@router.delete("/account", status_code=status.HTTP_200_OK)
async def delete_account(
    request: DeleteAccountRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Permanently delete user account and all associated data.

    Requires the user to confirm by providing their email address.
    CASCADE relationships handle cleanup of all related data:
    - Content items, categories, preferences
    - Search history, notification settings, devices
    - Notification history, magic link tokens
    - Space memberships, space invitations, public collections

    Spaces created by the user are preserved (created_by set to NULL).
    """
    # Verify confirmation email matches
    if request.confirmation_email.lower() != current_user.email.lower():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Confirmation email does not match account email"
        )

    logger.info(f"Account deletion requested for user: {current_user.id}")

    # Delete user - CASCADE handles all related data
    await db.delete(current_user)
    await db.commit()

    logger.info(f"Account deleted successfully: {current_user.id}")

    return {"message": "Account deleted successfully"}


@router.get("/personal-info", response_model=PersonalInfoResponse)
async def get_personal_info(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get the user's personal info (bio, social links, enriched data).

    Returns empty fields if not yet seeded.
    """
    query = select(UserPreferencesModel).where(
        UserPreferencesModel.user_id == current_user.id
    )
    result = await db.execute(query)
    prefs = result.scalar_one_or_none()

    if not prefs or not prefs.self_entity_id:
        return PersonalInfoResponse(name=current_user.name)

    # Load the self-entity
    entity_query = select(Entity).where(Entity.id == prefs.self_entity_id)
    entity_result = await db.execute(entity_query)
    entity = entity_result.scalar_one_or_none()

    if not entity:
        return PersonalInfoResponse(name=current_user.name)

    metadata = entity.entity_metadata or {}
    return PersonalInfoResponse(
        entity_id=str(entity.id),
        name=entity.name,
        bio=metadata.get("user_bio") or entity.description,
        social_links=metadata.get("social_links"),
        enriched_data=metadata.get("enriched_profiles"),
        last_refreshed_at=prefs.self_entity_last_refreshed_at,
    )


@router.post("/personal-info", response_model=PersonalInfoResponse)
async def seed_personal_info(
    request: SeedPersonalInfoRequest,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Seed or update personal information about the user.

    Creates a 'person' entity representing the user in the knowledge graph.
    Triggers background enrichment from social media links.
    """
    # Get or create user preferences
    query = select(UserPreferencesModel).where(
        UserPreferencesModel.user_id == current_user.id
    )
    result = await db.execute(query)
    prefs = result.scalar_one_or_none()

    if not prefs:
        prefs = UserPreferencesModel(
            user_id=current_user.id,
            summary_style="bullet_points",
            auto_categorize=True,
            connected_sources=[],
            daily_gems_enabled=False,
            daily_gems_time="9:00 AM"
        )
        db.add(prefs)
        await db.flush()

    # Build metadata
    metadata = {
        "is_self": True,
        "user_bio": request.bio or "",
        "social_links": request.social_links or {},
    }

    # Generate name aliases from user's name
    name_parts = current_user.name.strip().split()
    aliases = []
    if len(name_parts) > 1:
        aliases.append(name_parts[0])  # First name
        aliases.append(f"{name_parts[-1]}, {name_parts[0]}")  # "Last, First"

    if prefs.self_entity_id:
        # Update existing self-entity
        entity_query = select(Entity).where(Entity.id == prefs.self_entity_id)
        entity_result = await db.execute(entity_query)
        entity = entity_result.scalar_one_or_none()

        if entity:
            entity.name = current_user.name
            entity.description = request.bio or ""
            # Preserve enriched_profiles from previous scrape
            old_metadata = entity.entity_metadata or {}
            if "enriched_profiles" in old_metadata:
                metadata["enriched_profiles"] = old_metadata["enriched_profiles"]
            entity.entity_metadata = metadata
            entity.aliases = aliases
            entity.last_seen_at = datetime.utcnow()

            # Regenerate embedding
            try:
                from app.services.ai_service import AIService
                ai_service = AIService()
                embedding_text = f"{current_user.name} (person): {request.bio or ''}"
                entity.embedding = await ai_service.generate_embedding(embedding_text)
            except Exception as e:
                logger.warning(f"Failed to regenerate self-entity embedding: {e}")

            await db.commit()
            await db.refresh(entity)
        else:
            # Entity was deleted, clear reference and create new
            prefs.self_entity_id = None
            entity = None
    else:
        entity = None

    if not entity or not prefs.self_entity_id:
        # Create new self-entity
        entity = Entity(
            user_id=current_user.id,
            name=current_user.name,
            entity_type="person",
            aliases=aliases,
            description=request.bio or "",
            mention_count=0,
            confidence=1.0,
            entity_metadata=metadata,
            first_seen_at=datetime.utcnow(),
            last_seen_at=datetime.utcnow(),
        )
        db.add(entity)
        await db.flush()

        # Generate embedding
        try:
            from app.services.ai_service import AIService
            ai_service = AIService()
            embedding_text = f"{current_user.name} (person): {request.bio or ''}"
            entity.embedding = await ai_service.generate_embedding(embedding_text)
        except Exception as e:
            logger.warning(f"Failed to generate self-entity embedding: {e}")

        prefs.self_entity_id = entity.id
        await db.commit()
        await db.refresh(entity)

    # Trigger background enrichment from social links
    social = request.social_links or {}
    print(f"[PERSONAL-INFO] social_links from request: {social}")
    if social:
        user_id_str = str(current_user.id)
        print(f"[PERSONAL-INFO] Scheduling background enrichment for user {user_id_str[:8]} with {len(social)} link(s)")
        background_tasks.add_task(_enrich_self_entity_background, user_id_str)
    else:
        print(f"[PERSONAL-INFO] No social links provided, skipping enrichment")

    return PersonalInfoResponse(
        entity_id=str(entity.id),
        name=entity.name,
        bio=metadata.get("user_bio") or entity.description,
        social_links=metadata.get("social_links"),
        enriched_data=metadata.get("enriched_profiles"),
        last_refreshed_at=prefs.self_entity_last_refreshed_at,
    )


async def _enrich_self_entity_background(user_id: str):
    """Background task wrapper for social link enrichment."""
    import traceback
    print(f"[ENRICH-BG] Starting background enrichment for user {user_id[:8]}...")
    try:
        from app.db.session import AsyncSessionLocal
        from app.services.social_enrichment_service import enrich_self_entity

        async with AsyncSessionLocal() as db:
            result = await enrich_self_entity(user_id=user_id, db=db)
            print(f"[ENRICH-BG] Enrichment completed for user {user_id[:8]}: success={result}")
    except Exception as e:
        print(f"[ENRICH-BG] ERROR for user {user_id[:8]}: {e}")
        traceback.print_exc()
        logger.error(f"Background self-entity enrichment failed for user {user_id}: {e}")
