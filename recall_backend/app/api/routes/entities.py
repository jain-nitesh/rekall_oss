"""
Entity API endpoints for the knowledge graph.

Provides CRUD operations for entities (people, companies, technologies, etc.)
extracted from content items. Part of the Second Brain feature.
"""
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from app.db.session import get_db
from app.models.user import User
from app.models.entity import Entity, ContentEntity, EntityRelationship
from app.api.routes.auth import get_current_user

router = APIRouter(prefix="/entities", tags=["Entities"])


# ===== Response Models =====

class EntitySummary(BaseModel):
    """Brief entity info for list views."""
    id: str
    name: str
    entity_type: str
    description: Optional[str] = None
    mention_count: int = 0
    confidence: Optional[float] = None
    first_seen_at: Optional[datetime] = None
    last_seen_at: Optional[datetime] = None


class ContentItemRef(BaseModel):
    """Brief content item reference within entity detail."""
    id: str
    title: Optional[str] = None
    content_type: str = "url"
    category: str = "other"
    relevance_score: float = 0.5
    context_snippet: Optional[str] = None
    created_at: Optional[datetime] = None


class RelatedEntity(BaseModel):
    """Related entity with relationship info."""
    id: str
    name: str
    entity_type: str
    relationship_type: str
    relationship_description: Optional[str] = None
    strength: float = 0.5
    evidence_count: int = 1


class EntityDetail(BaseModel):
    """Full entity detail with content and relationships."""
    id: str
    name: str
    entity_type: str
    aliases: List[str] = []
    description: Optional[str] = None
    mention_count: int = 0
    confidence: Optional[float] = None
    metadata: Optional[dict] = None
    first_seen_at: Optional[datetime] = None
    last_seen_at: Optional[datetime] = None
    content_items: List[ContentItemRef] = []
    related_entities: List[RelatedEntity] = []


class EntityListResponse(BaseModel):
    """Paginated entity list."""
    entities: List[EntitySummary]
    total: int
    page: int
    page_size: int


class EntityUpdateRequest(BaseModel):
    """Request to update an entity."""
    name: Optional[str] = None
    entity_type: Optional[str] = None
    description: Optional[str] = None


class EntityMergeRequest(BaseModel):
    """Request to merge two entities."""
    source_id: str
    target_id: str


# ===== Endpoints =====

@router.get("", response_model=EntityListResponse)
async def list_entities(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    entity_type: Optional[str] = Query(None, description="Filter by type (person, company, technology, etc.)"),
    sort_by: str = Query("mention_count", description="Sort field: mention_count, name, last_seen_at"),
    search: Optional[str] = Query(None, description="Search entities by name"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List user's entities with pagination, filtering, and sorting."""
    user_id = str(current_user.id)

    # Build query
    query = select(Entity).where(Entity.user_id == user_id)
    count_query = select(func.count(Entity.id)).where(Entity.user_id == user_id)

    if entity_type:
        query = query.where(Entity.entity_type == entity_type)
        count_query = count_query.where(Entity.entity_type == entity_type)

    if search:
        search_pattern = f"%{search.lower()}%"
        query = query.where(func.lower(Entity.name).like(search_pattern))
        count_query = count_query.where(func.lower(Entity.name).like(search_pattern))

    # Sorting
    if sort_by == "name":
        query = query.order_by(Entity.name)
    elif sort_by == "last_seen_at":
        query = query.order_by(Entity.last_seen_at.desc())
    else:  # default: mention_count
        query = query.order_by(Entity.mention_count.desc())

    # Pagination
    offset = (page - 1) * page_size
    query = query.offset(offset).limit(page_size)

    # Execute
    result = await db.execute(query)
    entities = result.scalars().all()

    count_result = await db.execute(count_query)
    total = count_result.scalar() or 0

    return EntityListResponse(
        entities=[
            EntitySummary(
                id=str(e.id),
                name=e.name,
                entity_type=e.entity_type,
                description=e.description[:200] if e.description else None,
                mention_count=e.mention_count or 0,
                confidence=e.confidence,
                first_seen_at=e.first_seen_at,
                last_seen_at=e.last_seen_at,
            )
            for e in entities
        ],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get("/{entity_id}", response_model=EntityDetail)
async def get_entity(
    entity_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get full entity detail with content items and related entities."""
    user_id = str(current_user.id)

    # Load entity
    stmt = select(Entity).where(
        (Entity.id == entity_id) & (Entity.user_id == user_id)
    )
    result = await db.execute(stmt)
    entity = result.scalar_one_or_none()

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    # Get content items linked to this entity
    content_sql = text("""
        SELECT ci.id, ci.title, ci.content_type, ci.category,
               ce.relevance_score, ce.context_snippet, ci.created_at
        FROM content_entities ce
        JOIN content_items ci ON ci.id = ce.content_item_id
        WHERE ce.entity_id = :entity_id
        ORDER BY ce.relevance_score DESC, ci.created_at DESC
        LIMIT 50
    """)
    result = await db.execute(content_sql, {"entity_id": entity_id})
    content_rows = result.fetchall()

    content_items = [
        ContentItemRef(
            id=str(row[0]),
            title=row[1],
            content_type=str(row[2]) if row[2] else "url",
            category=row[3] or "other",
            relevance_score=float(row[4]) if row[4] else 0.5,
            context_snippet=row[5],
            created_at=row[6],
        )
        for row in content_rows
    ]

    # Get related entities (both directions)
    related_sql = text("""
        SELECT e.id, e.name, e.entity_type,
               er.relationship_type, er.description, er.strength, er.evidence_count
        FROM entity_relationships er
        JOIN entities e ON (
            (er.target_entity_id = e.id AND er.source_entity_id = :entity_id)
            OR (er.source_entity_id = e.id AND er.target_entity_id = :entity_id)
        )
        WHERE er.user_id = :user_id
          AND e.id != :entity_id
        ORDER BY er.strength DESC, er.evidence_count DESC
        LIMIT 30
    """)
    result = await db.execute(related_sql, {"entity_id": entity_id, "user_id": user_id})
    related_rows = result.fetchall()

    related_entities = [
        RelatedEntity(
            id=str(row[0]),
            name=row[1],
            entity_type=row[2],
            relationship_type=row[3],
            relationship_description=row[4],
            strength=float(row[5]) if row[5] else 0.5,
            evidence_count=row[6] or 1,
        )
        for row in related_rows
    ]

    return EntityDetail(
        id=str(entity.id),
        name=entity.name,
        entity_type=entity.entity_type,
        aliases=entity.aliases or [],
        description=entity.description,
        mention_count=entity.mention_count or 0,
        confidence=entity.confidence,
        metadata=entity.entity_metadata,
        first_seen_at=entity.first_seen_at,
        last_seen_at=entity.last_seen_at,
        content_items=content_items,
        related_entities=related_entities,
    )


@router.get("/{entity_id}/content", response_model=List[ContentItemRef])
async def get_entity_content(
    entity_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get content items that reference this entity."""
    user_id = str(current_user.id)

    # Verify entity belongs to user
    entity_check = await db.execute(
        select(Entity.id).where((Entity.id == entity_id) & (Entity.user_id == user_id))
    )
    if not entity_check.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Entity not found")

    offset = (page - 1) * page_size
    sql = text("""
        SELECT ci.id, ci.title, ci.content_type, ci.category,
               ce.relevance_score, ce.context_snippet, ci.created_at
        FROM content_entities ce
        JOIN content_items ci ON ci.id = ce.content_item_id
        WHERE ce.entity_id = :entity_id
        ORDER BY ci.created_at DESC
        OFFSET :offset LIMIT :limit
    """)
    result = await db.execute(sql, {"entity_id": entity_id, "offset": offset, "limit": page_size})
    rows = result.fetchall()

    return [
        ContentItemRef(
            id=str(row[0]),
            title=row[1],
            content_type=str(row[2]) if row[2] else "url",
            category=row[3] or "other",
            relevance_score=float(row[4]) if row[4] else 0.5,
            context_snippet=row[5],
            created_at=row[6],
        )
        for row in rows
    ]


@router.get("/{entity_id}/related", response_model=List[RelatedEntity])
async def get_related_entities(
    entity_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get entities related to this entity via typed relationships."""
    user_id = str(current_user.id)

    # Verify entity belongs to user
    entity_check = await db.execute(
        select(Entity.id).where((Entity.id == entity_id) & (Entity.user_id == user_id))
    )
    if not entity_check.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="Entity not found")

    sql = text("""
        SELECT e.id, e.name, e.entity_type,
               er.relationship_type, er.description, er.strength, er.evidence_count
        FROM entity_relationships er
        JOIN entities e ON (
            (er.target_entity_id = e.id AND er.source_entity_id = :entity_id)
            OR (er.source_entity_id = e.id AND er.target_entity_id = :entity_id)
        )
        WHERE er.user_id = :user_id
          AND e.id != :entity_id
        ORDER BY er.strength DESC
        LIMIT 50
    """)
    result = await db.execute(sql, {"entity_id": entity_id, "user_id": user_id})
    rows = result.fetchall()

    return [
        RelatedEntity(
            id=str(row[0]),
            name=row[1],
            entity_type=row[2],
            relationship_type=row[3],
            relationship_description=row[4],
            strength=float(row[5]) if row[5] else 0.5,
            evidence_count=row[6] or 1,
        )
        for row in rows
    ]


@router.patch("/{entity_id}", response_model=EntitySummary)
async def update_entity(
    entity_id: str,
    update: EntityUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Update an entity's name, type, or description."""
    user_id = str(current_user.id)

    stmt = select(Entity).where(
        (Entity.id == entity_id) & (Entity.user_id == user_id)
    )
    result = await db.execute(stmt)
    entity = result.scalar_one_or_none()

    if not entity:
        raise HTTPException(status_code=404, detail="Entity not found")

    if update.name is not None:
        entity.name = update.name.strip()
    if update.entity_type is not None:
        valid_types = ['person', 'company', 'technology', 'concept', 'topic', 'place', 'event']
        if update.entity_type not in valid_types:
            raise HTTPException(status_code=400, detail=f"Invalid entity type. Must be one of: {valid_types}")
        entity.entity_type = update.entity_type
    if update.description is not None:
        entity.description = update.description

    entity.updated_at = datetime.utcnow()
    await db.commit()

    return EntitySummary(
        id=str(entity.id),
        name=entity.name,
        entity_type=entity.entity_type,
        description=entity.description[:200] if entity.description else None,
        mention_count=entity.mention_count or 0,
        confidence=entity.confidence,
        first_seen_at=entity.first_seen_at,
        last_seen_at=entity.last_seen_at,
    )


@router.post("/merge")
async def merge_entities(
    request: EntityMergeRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Merge two entities: transfers all content links and relationships
    from the source entity to the target entity, then deletes the source.
    """
    user_id = str(current_user.id)

    # Load both entities
    source = await db.execute(
        select(Entity).where((Entity.id == request.source_id) & (Entity.user_id == user_id))
    )
    source_entity = source.scalar_one_or_none()

    target = await db.execute(
        select(Entity).where((Entity.id == request.target_id) & (Entity.user_id == user_id))
    )
    target_entity = target.scalar_one_or_none()

    if not source_entity or not target_entity:
        raise HTTPException(status_code=404, detail="One or both entities not found")

    if str(source_entity.id) == str(target_entity.id):
        raise HTTPException(status_code=400, detail="Cannot merge entity with itself")

    # Transfer content_entity links from source to target
    transfer_links_sql = text("""
        UPDATE content_entities
        SET entity_id = :target_id
        WHERE entity_id = :source_id
          AND content_item_id NOT IN (
              SELECT content_item_id FROM content_entities WHERE entity_id = :target_id
          )
    """)
    await db.execute(transfer_links_sql, {"source_id": request.source_id, "target_id": request.target_id})

    # Delete duplicate content_entity links (those that now exist for both)
    delete_dup_links_sql = text("""
        DELETE FROM content_entities WHERE entity_id = :source_id
    """)
    await db.execute(delete_dup_links_sql, {"source_id": request.source_id})

    # Transfer relationships (update source_entity_id and target_entity_id references)
    await db.execute(text("""
        UPDATE entity_relationships SET source_entity_id = :target_id
        WHERE source_entity_id = :source_id
          AND NOT EXISTS (
              SELECT 1 FROM entity_relationships er2
              WHERE er2.source_entity_id = :target_id
                AND er2.target_entity_id = entity_relationships.target_entity_id
                AND er2.relationship_type = entity_relationships.relationship_type
          )
    """), {"source_id": request.source_id, "target_id": request.target_id})

    await db.execute(text("""
        UPDATE entity_relationships SET target_entity_id = :target_id
        WHERE target_entity_id = :source_id
          AND NOT EXISTS (
              SELECT 1 FROM entity_relationships er2
              WHERE er2.target_entity_id = :target_id
                AND er2.source_entity_id = entity_relationships.source_entity_id
                AND er2.relationship_type = entity_relationships.relationship_type
          )
    """), {"source_id": request.source_id, "target_id": request.target_id})

    # Clean up remaining source relationships
    await db.execute(text("""
        DELETE FROM entity_relationships
        WHERE source_entity_id = :source_id OR target_entity_id = :source_id
    """), {"source_id": request.source_id})

    # Merge aliases
    merged_aliases = list(set(
        (target_entity.aliases or []) +
        (source_entity.aliases or []) +
        [source_entity.name.lower()]
    ))
    target_entity.aliases = merged_aliases

    # Update mention count
    target_entity.mention_count = (target_entity.mention_count or 0) + (source_entity.mention_count or 0)

    # Update temporal bounds
    if source_entity.first_seen_at and (not target_entity.first_seen_at or source_entity.first_seen_at < target_entity.first_seen_at):
        target_entity.first_seen_at = source_entity.first_seen_at
    if source_entity.last_seen_at and (not target_entity.last_seen_at or source_entity.last_seen_at > target_entity.last_seen_at):
        target_entity.last_seen_at = source_entity.last_seen_at

    # Delete source entity
    await db.delete(source_entity)
    await db.commit()

    return {
        "message": f"Merged '{source_entity.name}' into '{target_entity.name}'",
        "target_id": str(target_entity.id),
        "new_mention_count": target_entity.mention_count,
    }
