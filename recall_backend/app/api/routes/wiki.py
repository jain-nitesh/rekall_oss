"""
Wiki API endpoints for the LLM Wiki knowledge layer.

Provides CRUD operations for AI-compiled wiki pages, contradiction management,
and semantic search across compiled knowledge.
"""
from fastapi import APIRouter, Depends, Query, HTTPException, Body
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, text
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID
from datetime import datetime

from app.db.session import get_db
from app.models.user import User
from app.models.wiki import WikiPage, WikiBacklink, WikiContradiction
from app.models.entity import Entity
from app.api.routes.auth import get_current_user

router = APIRouter(prefix="/wiki", tags=["Wiki"])


# ===== Response Models =====

class WikiPageSummary(BaseModel):
    """Brief wiki page info for list views."""
    id: str
    title: str
    slug: str
    entity_id: Optional[str] = None
    entity_type: Optional[str] = None
    status: str = "draft"
    source_count: int = 0
    confidence_score: float = 0.0
    last_compiled_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class BacklinkRef(BaseModel):
    """Backlink reference."""
    id: str
    source_type: str
    source_id: str
    context_snippet: Optional[str] = None


class ContradictionRef(BaseModel):
    """Contradiction reference."""
    id: str
    claim_a: str
    source_a_id: Optional[str] = None
    claim_b: str
    source_b_id: Optional[str] = None
    resolution: Optional[str] = None
    status: str = "open"


class WikiPageDetail(BaseModel):
    """Full wiki page with content, backlinks, and contradictions."""
    id: str
    title: str
    slug: str
    entity_id: Optional[str] = None
    entity_type: Optional[str] = None
    content_markdown: Optional[str] = None
    status: str = "draft"
    source_count: int = 0
    confidence_score: float = 0.0
    last_compiled_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    backlinks: List[BacklinkRef] = []
    contradictions: List[ContradictionRef] = []


class WikiListResponse(BaseModel):
    """Paginated wiki page list."""
    items: List[WikiPageSummary]
    total: int
    page: int
    page_size: int


class WikiSearchResult(BaseModel):
    """Search result with similarity score."""
    id: str
    title: str
    slug: str
    snippet: Optional[str] = None
    similarity: float = 0.0
    status: str = "draft"


# ===== Endpoints =====

@router.get("", response_model=WikiListResponse)
async def list_wiki_pages(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    status: Optional[str] = Query(None, description="Filter by status: draft, published, stale"),
    search: Optional[str] = Query(None, description="Search by title"),
    sort_by: str = Query("updated_at", description="Sort field: updated_at, title, confidence_score, source_count"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """List wiki pages for the current user."""
    base_query = select(WikiPage).where(WikiPage.user_id == current_user.id)

    if status:
        base_query = base_query.where(WikiPage.status == status)
    if search:
        base_query = base_query.where(WikiPage.title.ilike(f"%{search}%"))

    # Count total
    count_stmt = select(func.count()).select_from(base_query.subquery())
    total = (await db.execute(count_stmt)).scalar() or 0

    # Sort
    sort_map = {
        "updated_at": WikiPage.updated_at.desc(),
        "title": WikiPage.title.asc(),
        "confidence_score": WikiPage.confidence_score.desc(),
        "source_count": WikiPage.source_count.desc(),
    }
    order = sort_map.get(sort_by, WikiPage.updated_at.desc())
    base_query = base_query.order_by(order)

    # Paginate
    offset = (page - 1) * page_size
    stmt = base_query.offset(offset).limit(page_size)
    result = await db.execute(stmt)
    pages = result.scalars().all()

    # Load entity types for display
    entity_ids = [str(p.entity_id) for p in pages if p.entity_id]
    entity_types = {}
    if entity_ids:
        e_stmt = select(Entity.id, Entity.entity_type).where(Entity.id.in_(entity_ids))
        e_result = await db.execute(e_stmt)
        entity_types = {str(row[0]): row[1] for row in e_result.all()}

    items = []
    for p in pages:
        items.append(WikiPageSummary(
            id=str(p.id),
            title=p.title,
            slug=p.slug,
            entity_id=str(p.entity_id) if p.entity_id else None,
            entity_type=entity_types.get(str(p.entity_id)),
            status=p.status,
            source_count=p.source_count or 0,
            confidence_score=p.confidence_score or 0.0,
            last_compiled_at=p.last_compiled_at,
            created_at=p.created_at,
            updated_at=p.updated_at,
        ))

    return WikiListResponse(items=items, total=total, page=page, page_size=page_size)


@router.post("/generate")
async def generate_wiki_page(
    entity_id: str = Body(..., embed=True),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Manually trigger wiki page generation for an entity."""
    from app.models.entity import Entity
    from app.services.wiki_compiler_service import check_and_create_wiki_page, compile_wiki_page

    entity = await db.get(Entity, entity_id)
    if not entity or str(entity.user_id) != str(current_user.id):
        raise HTTPException(status_code=404, detail="Entity not found")

    # Check if wiki already exists
    stmt = select(WikiPage).where(
        (WikiPage.entity_id == entity_id) &
        (WikiPage.user_id == str(current_user.id))
    )
    result = await db.execute(stmt)
    existing = result.scalar_one_or_none()

    if existing and existing.status == 'published':
        return {"status": "exists", "slug": existing.slug, "message": "Wiki page already exists"}

    if existing:
        # Draft or stale — compile it
        wiki_page = existing
    else:
        # Create new wiki page (bypass mention threshold for manual trigger)
        slug = entity.name.lower().replace(' ', '-')[:300]
        wiki_page = WikiPage(
            user_id=str(current_user.id),
            entity_id=entity_id,
            title=entity.name,
            slug=slug,
            status='draft',
            source_count=0,
            confidence_score=0.0,
        )
        db.add(wiki_page)
        await db.commit()
        await db.refresh(wiki_page)

    # Compile immediately
    success = await compile_wiki_page(str(wiki_page.id), db)
    if success:
        return {"status": "created", "slug": wiki_page.slug, "message": "Wiki page generated"}
    else:
        raise HTTPException(status_code=500, detail="Wiki compilation failed")


@router.get("/search", response_model=List[WikiSearchResult])
async def search_wiki_pages(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(10, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Semantic search across wiki pages using embeddings."""
    from app.services.ai_service import AIService

    ai_service = AIService()
    query_embedding = await ai_service.generate_embedding(q)

    stmt = text("""
        SELECT id, title, slug, status,
               LEFT(content_markdown, 200) as snippet,
               1 - (content_embedding <=> :embedding::vector) as similarity
        FROM wiki_pages
        WHERE user_id = :user_id
          AND content_embedding IS NOT NULL
          AND status = 'published'
        ORDER BY content_embedding <=> :embedding::vector
        LIMIT :limit
    """)

    result = await db.execute(stmt, {
        'user_id': str(current_user.id),
        'embedding': str(query_embedding),
        'limit': limit,
    })
    rows = result.all()

    return [
        WikiSearchResult(
            id=str(row[0]),
            title=row[1],
            slug=row[2],
            status=row[3],
            snippet=row[4],
            similarity=round(float(row[5]), 4) if row[5] else 0.0,
        )
        for row in rows
    ]


@router.get("/{slug}", response_model=WikiPageDetail)
async def get_wiki_page(
    slug: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get a wiki page by slug, including backlinks and contradictions."""
    stmt = select(WikiPage).where(
        (WikiPage.user_id == current_user.id) &
        (WikiPage.slug == slug)
    )
    result = await db.execute(stmt)
    page = result.scalar_one_or_none()

    if not page:
        raise HTTPException(status_code=404, detail="Wiki page not found")

    # Load entity type
    entity_type = None
    if page.entity_id:
        entity = await db.get(Entity, page.entity_id)
        if entity:
            entity_type = entity.entity_type

    # Load backlinks
    bl_stmt = select(WikiBacklink).where(WikiBacklink.wiki_page_id == page.id)
    bl_result = await db.execute(bl_stmt)
    backlinks = [
        BacklinkRef(
            id=str(bl.id),
            source_type=bl.source_type,
            source_id=str(bl.source_id),
            context_snippet=bl.context_snippet,
        )
        for bl in bl_result.scalars().all()
    ]

    # Load contradictions
    c_stmt = select(WikiContradiction).where(WikiContradiction.wiki_page_id == page.id)
    c_result = await db.execute(c_stmt)
    contradictions = [
        ContradictionRef(
            id=str(c.id),
            claim_a=c.claim_a,
            source_a_id=str(c.source_a_id) if c.source_a_id else None,
            claim_b=c.claim_b,
            source_b_id=str(c.source_b_id) if c.source_b_id else None,
            resolution=c.resolution,
            status=c.status,
        )
        for c in c_result.scalars().all()
    ]

    return WikiPageDetail(
        id=str(page.id),
        title=page.title,
        slug=page.slug,
        entity_id=str(page.entity_id) if page.entity_id else None,
        entity_type=entity_type,
        content_markdown=page.content_markdown,
        status=page.status,
        source_count=page.source_count or 0,
        confidence_score=page.confidence_score or 0.0,
        last_compiled_at=page.last_compiled_at,
        created_at=page.created_at,
        updated_at=page.updated_at,
        backlinks=backlinks,
        contradictions=contradictions,
    )


@router.get("/{wiki_id}/sources")
async def get_wiki_sources(
    wiki_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get source content items for a wiki page."""
    page = await db.get(WikiPage, wiki_id)
    if not page or str(page.user_id) != str(current_user.id):
        raise HTTPException(status_code=404, detail="Wiki page not found")

    if not page.entity_id:
        return {"sources": []}

    from app.models.entity import ContentEntity
    from app.models.content_item import ContentItem

    stmt = (
        select(ContentItem, ContentEntity.relevance_score)
        .join(ContentEntity, ContentEntity.content_item_id == ContentItem.id)
        .where(ContentEntity.entity_id == page.entity_id)
        .order_by(ContentItem.created_at.desc())
        .limit(50)
    )
    result = await db.execute(stmt)
    rows = result.all()

    sources = []
    for item, relevance in rows:
        sources.append({
            "id": str(item.id),
            "title": item.title,
            "content_type": item.content_type,
            "category": item.category,
            "relevance_score": relevance or 0.5,
            "created_at": item.created_at.isoformat() if item.created_at else None,
        })

    return {"sources": sources}


@router.get("/{wiki_id}/contradictions", response_model=List[ContradictionRef])
async def get_wiki_contradictions(
    wiki_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get contradictions for a wiki page."""
    page = await db.get(WikiPage, wiki_id)
    if not page or str(page.user_id) != str(current_user.id):
        raise HTTPException(status_code=404, detail="Wiki page not found")

    stmt = select(WikiContradiction).where(WikiContradiction.wiki_page_id == wiki_id)
    result = await db.execute(stmt)

    return [
        ContradictionRef(
            id=str(c.id),
            claim_a=c.claim_a,
            source_a_id=str(c.source_a_id) if c.source_a_id else None,
            claim_b=c.claim_b,
            source_b_id=str(c.source_b_id) if c.source_b_id else None,
            resolution=c.resolution,
            status=c.status,
        )
        for c in result.scalars().all()
    ]


@router.delete("/{wiki_id}")
async def delete_wiki_page(
    wiki_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Delete a wiki page."""
    page = await db.get(WikiPage, wiki_id)
    if not page or str(page.user_id) != str(current_user.id):
        raise HTTPException(status_code=404, detail="Wiki page not found")

    await db.delete(page)
    await db.commit()
    return {"detail": "Wiki page deleted"}


@router.patch("/contradictions/{contradiction_id}")
async def resolve_contradiction(
    contradiction_id: UUID,
    status: str = Query(..., description="New status: resolved or dismissed"),
    resolution: Optional[str] = Query(None, description="Resolution text"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Resolve or dismiss a contradiction."""
    if status not in ('resolved', 'dismissed'):
        raise HTTPException(status_code=400, detail="Status must be 'resolved' or 'dismissed'")

    contradiction = await db.get(WikiContradiction, contradiction_id)
    if not contradiction:
        raise HTTPException(status_code=404, detail="Contradiction not found")

    # Verify ownership via wiki page
    page = await db.get(WikiPage, contradiction.wiki_page_id)
    if not page or str(page.user_id) != str(current_user.id):
        raise HTTPException(status_code=404, detail="Contradiction not found")

    contradiction.status = status
    if resolution:
        contradiction.resolution = resolution

    await db.commit()
    return {"status": status, "id": str(contradiction_id)}
