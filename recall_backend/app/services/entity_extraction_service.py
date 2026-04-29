"""
Entity extraction service.

Phase 3 of the processing pipeline: extracts named entities and relationships
from content items to build the knowledge graph.

Runs after AI processing (Phase 2) completes. Handles:
- Entity extraction via AI provider
- Entity deduplication (alias matching + embedding similarity)
- Entity relationship creation and strengthening
- Entity-mediated connection discovery
"""
from datetime import datetime
from typing import List, Dict, Optional
from sqlalchemy import select, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

import logging

from app.models.entity import Entity, ContentEntity, EntityRelationship, EntityExtractionStatus
from app.models.content_item import ContentItem, AIStatus
from app.services.ai_service import AIService
from app.core.config import settings

logger = logging.getLogger(__name__)


async def extract_entities_for_content(content_id: str, db: AsyncSession) -> List[Dict]:
    """
    Extract entities from a content item and store them in the knowledge graph.

    This is the main entry point for Phase 3 entity extraction.
    Called after AI processing (Phase 2) completes successfully.

    Args:
        content_id: UUID of the content item to process
        db: Database session

    Returns:
        List of created/updated entity dicts
    """
    # Load the content item
    stmt = select(ContentItem).where(ContentItem.id == content_id)
    result = await db.execute(stmt)
    content = result.scalar_one_or_none()

    if not content:
        logger.error(f"Content {content_id} not found")
        return []

    if content.ai_status != AIStatus.completed:
        logger.debug(f"Skipping entity extraction: AI not completed (status: {content.ai_status})")
        return []

    # Mark as processing
    content.entity_status = EntityExtractionStatus.processing
    content.entity_attempts = (content.entity_attempts or 0) + 1
    content.last_entity_processed_at = datetime.utcnow()
    await db.commit()
    logger.info(f"Entity extraction attempt #{content.entity_attempts} for {content_id}")

    try:
        ai_service = AIService()

        # Fetch existing entities for this user (for dedup)
        existing_entities = await _get_user_entities(str(content.user_id), db)

        # Build content text for extraction
        content_text = _build_content_text(content)

        # Determine content ownership context
        # Notes and images/videos from camera are user-created content.
        # URLs shared from other apps are curated/saved from external sources.
        content_type_val = content.content_type.value if content.content_type else 'url'
        is_user_created = content_type_val in ('note', 'image', 'video') and not content.url
        content_meta = {
            'content_type': str(content.content_type.value) if content.content_type else 'url',
            'source_app': content.source_app or 'unknown',
            'has_url': bool(content.url),
            'is_user_created': is_user_created,
        }

        # Call AI provider for entity extraction
        extraction_result = await ai_service.provider.extract_entities(
            title=content.title or '',
            summary=content.summary or '',
            content=content_text,
            existing_entities=existing_entities,
            content_meta=content_meta,
        )

        extracted_entities = extraction_result.get('entities', [])
        extracted_relationships = extraction_result.get('relationships', [])

        if not extracted_entities:
            logger.info(f"No entities found in content {content_id}")
            content.entity_status = EntityExtractionStatus.completed
            content.entity_error = None
            await db.commit()
            return []

        logger.info(f"AI extracted {len(extracted_entities)} entities and {len(extracted_relationships)} relationships")

        # Process each extracted entity: dedup, create/update, link
        created_entities = []
        entity_name_to_id = {}  # For relationship resolution

        for entity_data in extracted_entities:
            entity = await _upsert_entity(
                user_id=str(content.user_id),
                entity_data=entity_data,
                content_item=content,
                existing_entities=existing_entities,
                ai_service=ai_service,
                db=db
            )
            if entity:
                created_entities.append({
                    'id': str(entity.id),
                    'name': entity.name,
                    'type': entity.entity_type,
                })
                entity_name_to_id[entity.name.lower()] = entity.id
                # Also map aliases
                for alias in (entity.aliases or []):
                    entity_name_to_id[alias.lower()] = entity.id

        # Process relationships first (needed for subtopic discovery in wiki compilation)
        for rel_data in extracted_relationships:
            await _upsert_relationship(
                user_id=str(content.user_id),
                rel_data=rel_data,
                entity_name_to_id=entity_name_to_id,
                db=db
            )

        # Check if any entities now qualify for wiki pages
        # and immediately compile or patch affected pages
        wiki_pages_to_compile = []
        wiki_pages_to_patch = []
        for entity_info in created_entities:
            try:
                from app.services.wiki_compiler_service import check_and_create_wiki_page
                wiki_page = await check_and_create_wiki_page(
                    entity_id=entity_info['id'],
                    user_id=str(content.user_id),
                    db=db
                )
                if wiki_page and wiki_page.status in ('draft', 'stale'):
                    wiki_pages_to_compile.append(wiki_page)
                elif wiki_page and wiki_page.status == 'published' and wiki_page.content_markdown:
                    wiki_pages_to_patch.append(wiki_page)
            except Exception as wiki_err:
                logger.warning(f"Wiki check failed for entity '{entity_info['name']}': {wiki_err}")

        # Mark as completed
        content.entity_status = EntityExtractionStatus.completed
        content.entity_error = None
        await db.commit()

        # Incrementally patch published wiki pages with the new content item
        if wiki_pages_to_patch:
            from app.services.wiki_compiler_service import patch_wiki_page as wiki_patch
            for wiki_page in wiki_pages_to_patch[:3]:
                try:
                    await wiki_patch(str(wiki_page.id), str(content.id), db)
                except Exception as patch_err:
                    logger.warning(f"Wiki patch failed for '{wiki_page.title}': {patch_err}")

        # Immediately compile any draft or stale wiki pages (instead of waiting for background)
        if wiki_pages_to_compile:
            from app.services.wiki_compiler_service import compile_wiki_page as do_compile
            for wiki_page in wiki_pages_to_compile[:3]:  # Max 3 per extraction to avoid overload
                try:
                    logger.info(f"Immediately compiling wiki page '{wiki_page.title}'")
                    await do_compile(str(wiki_page.id), db)
                except Exception as compile_err:
                    logger.warning(f"Immediate wiki compile failed for '{wiki_page.title}': {compile_err}")

        logger.info(f"Entity extraction complete: {len(created_entities)} entities processed for {content_id}")
        return created_entities

    except Exception as e:
        logger.error(f"Entity extraction failed for {content_id}: {e}", exc_info=True)

        # Mark as failed
        try:
            content.entity_status = EntityExtractionStatus.failed
            content.entity_error = f"Entity extraction error: {str(e)[:500]}"
            await db.commit()
        except Exception as update_err:
            logger.error(f"Failed to update status: {update_err}")

        return []


async def _get_user_entities(user_id: str, db: AsyncSession) -> List[Dict]:
    """Fetch existing entities for a user (for dedup during extraction)."""
    from app.models.user_preferences import UserPreferences as UserPreferencesModel

    stmt = select(Entity).where(
        Entity.user_id == user_id
    ).order_by(Entity.mention_count.desc()).limit(100)

    result = await db.execute(stmt)
    entities = result.scalars().all()

    # Check if user has a self-entity
    prefs_stmt = select(UserPreferencesModel.self_entity_id).where(
        UserPreferencesModel.user_id == user_id
    )
    prefs_result = await db.execute(prefs_stmt)
    self_entity_id = prefs_result.scalar_one_or_none()

    return [
        {
            'name': e.name,
            'type': e.entity_type,
            'aliases': e.aliases or [],
            'id': str(e.id),
            'is_self': str(e.id) == str(self_entity_id) if self_entity_id else False,
        }
        for e in entities
    ]


def _build_content_text(content: ContentItem) -> str:
    """Build the text to send to the AI for entity extraction."""
    parts = []
    if content.extracted_content:
        parts.append(content.extracted_content[:3000])
    if content.ocr_text:
        parts.append(content.ocr_text[:1000])
    if content.notes:
        parts.append(content.notes)
    # Fallback to summary if no extracted content
    if not parts and content.summary:
        parts.append(content.summary)
    return '\n'.join(parts)


async def _find_existing_entity(
    user_id: str,
    name: str,
    entity_type: str,
    aliases: List[str],
    existing_entities: List[Dict],
    db: AsyncSession
) -> Optional[Entity]:
    """
    Find an existing entity that matches by name/alias (case-insensitive).

    Dedup strategy:
    1. Exact name match (case-insensitive) + same type
    2. Alias match against existing entity names or aliases
    """
    name_lower = name.lower().strip()
    all_names = [name_lower] + [a.lower().strip() for a in aliases]

    # Check against existing entities (in-memory, fast)
    for existing in existing_entities:
        existing_name_lower = existing['name'].lower()
        existing_aliases_lower = [a.lower() for a in existing.get('aliases', [])]
        existing_all = [existing_name_lower] + existing_aliases_lower

        # Check type match
        if existing['type'] != entity_type:
            continue

        # Check name/alias overlap
        if any(n in existing_all for n in all_names) or any(e in all_names for e in existing_all):
            # Found match, load from DB
            stmt = select(Entity).where(Entity.id == existing['id'])
            result = await db.execute(stmt)
            return result.scalar_one_or_none()

    return None


async def _upsert_entity(
    user_id: str,
    entity_data: Dict,
    content_item: ContentItem,
    existing_entities: List[Dict],
    ai_service: AIService,
    db: AsyncSession
) -> Optional[Entity]:
    """
    Create or update an entity and link it to the content item.

    If a matching entity exists (by name/alias), updates it.
    Otherwise creates a new entity.
    """
    name = entity_data['name']
    entity_type = entity_data['type']
    aliases = entity_data.get('aliases', [])

    # Try to find existing entity
    entity = await _find_existing_entity(
        user_id=user_id,
        name=name,
        entity_type=entity_type,
        aliases=aliases,
        existing_entities=existing_entities,
        db=db
    )

    if entity:
        # Update existing entity
        entity.mention_count = (entity.mention_count or 0) + 1
        entity.last_seen_at = datetime.utcnow()

        # Merge aliases
        current_aliases = set(a.lower() for a in (entity.aliases or []))
        new_aliases = set(a.lower() for a in aliases)
        merged = list(current_aliases | new_aliases)
        if merged != (entity.aliases or []):
            entity.aliases = merged

        # Update confidence (rolling average)
        new_confidence = entity_data.get('relevance', 0.5)
        old_count = entity.mention_count - 1
        if old_count > 0 and entity.confidence:
            entity.confidence = (entity.confidence * old_count + new_confidence) / entity.mention_count
        else:
            entity.confidence = new_confidence

        # Update description if the new one is longer/better
        new_desc = entity_data.get('description', '')
        if new_desc and (not entity.description or len(new_desc) > len(entity.description)):
            entity.description = new_desc

        logger.debug(f"Updated entity '{entity.name}' ({entity_type}) - now {entity.mention_count} mentions")

    else:
        # Create new entity
        entity = Entity(
            user_id=user_id,
            name=name,
            entity_type=entity_type,
            aliases=aliases,
            description=entity_data.get('description', ''),
            mention_count=1,
            confidence=entity_data.get('relevance', 0.5),
            first_seen_at=datetime.utcnow(),
            last_seen_at=datetime.utcnow(),
        )
        try:
            async with db.begin_nested():
                db.add(entity)
                await db.flush()  # Get the ID
        except IntegrityError:
            stmt = select(Entity).where(
                (Entity.user_id == user_id) &
                (func.lower(Entity.name) == name.lower()) &
                (Entity.entity_type == entity_type)
            )
            result = await db.execute(stmt)
            entity = result.scalar_one_or_none()
            if entity:
                entity.mention_count = (entity.mention_count or 0) + 1
                entity.last_seen_at = datetime.utcnow()
                new_desc = entity_data.get('description', '')
                if new_desc and (not entity.description or len(new_desc) > len(entity.description)):
                    entity.description = new_desc
                await db.flush()
                logger.debug(f"Dedup-recovered entity '{name}' ({entity_type}) - now {entity.mention_count} mentions")
            else:
                logger.error(f"IntegrityError but entity not found: '{name}' ({entity_type})")
                return None

            existing_entities.append({
                'name': entity.name,
                'type': entity.entity_type,
                'aliases': entity.aliases or [],
                'id': str(entity.id),
            })
            return entity

        # Generate embedding for the entity
        try:
            embedding_text = f"{name} ({entity_type}): {entity_data.get('description', '')}"
            embedding = await ai_service.generate_embedding(embedding_text)
            entity.embedding = embedding
        except Exception as e:
            logger.warning(f"Embedding generation failed for entity '{name}': {e}")

        # Add to existing_entities list for subsequent dedup in same batch
        existing_entities.append({
            'name': entity.name,
            'type': entity.entity_type,
            'aliases': entity.aliases or [],
            'id': str(entity.id),
        })

        logger.debug(f"Created entity '{name}' ({entity_type})")

    # Create content-entity link (skip if already exists)
    existing_link = await db.execute(
        select(ContentEntity).where(
            (ContentEntity.content_item_id == content_item.id) &
            (ContentEntity.entity_id == entity.id)
        )
    )
    if not existing_link.scalar_one_or_none():
        link = ContentEntity(
            content_item_id=content_item.id,
            entity_id=entity.id,
            relevance_score=entity_data.get('relevance', 0.5),
            context_snippet=entity_data.get('context', '')[:500],
            extraction_confidence=entity_data.get('relevance', 0.8),
        )
        db.add(link)

    await db.flush()
    return entity


async def _upsert_relationship(
    user_id: str,
    rel_data: Dict,
    entity_name_to_id: Dict[str, str],
    db: AsyncSession
) -> Optional[EntityRelationship]:
    """Create or strengthen an entity relationship."""
    source_name = rel_data['source'].lower()
    target_name = rel_data['target'].lower()
    rel_type = rel_data['type']

    source_id = entity_name_to_id.get(source_name)
    target_id = entity_name_to_id.get(target_name)

    if not source_id or not target_id:
        return None

    # Check if relationship already exists
    stmt = select(EntityRelationship).where(
        (EntityRelationship.user_id == user_id) &
        (EntityRelationship.source_entity_id == source_id) &
        (EntityRelationship.target_entity_id == target_id) &
        (EntityRelationship.relationship_type == rel_type)
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing:
        # Strengthen existing relationship
        existing.evidence_count = (existing.evidence_count or 1) + 1
        existing.last_seen_at = datetime.utcnow()
        # Increase strength with more evidence (cap at 1.0)
        existing.strength = min(1.0, (existing.strength or 0.5) + 0.1)
        logger.debug(f"Strengthened relationship '{rel_data['source']}' --{rel_type}--> '{rel_data['target']}' (evidence: {existing.evidence_count})")
        await db.flush()
        return existing
    else:
        # Create new relationship
        rel = EntityRelationship(
            user_id=user_id,
            source_entity_id=source_id,
            target_entity_id=target_id,
            relationship_type=rel_type,
            description=rel_data.get('description', ''),
            strength=0.5,
            evidence_count=1,
        )
        db.add(rel)
        await db.flush()
        logger.debug(f"Created relationship '{rel_data['source']}' --{rel_type}--> '{rel_data['target']}'")
        return rel
