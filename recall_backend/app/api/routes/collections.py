"""
Public collections API endpoints.

- POST /collections - create collection
- GET /collections - list my collections
- GET /collections/explore - public discovery (no auth)
- GET /collections/{slug} - get collection (no auth for public)
- POST /collections/{id}/items - add item
- DELETE /collections/{id}/items/{item_id} - remove item
- POST /collections/{id}/fork - copy to user's library
"""
import re
import uuid
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, status, Query
from fastapi.responses import HTMLResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc, delete, update, and_, text as sql_text
from typing import Optional

from app.db.session import get_db
from app.models.user import User
from app.models.content_item import ContentItem, IngestionStatus, AIStatus
from app.api.routes.auth import get_current_user
from app.core.config import settings

import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/collections", tags=["Collections"])


def _slugify(title: str) -> str:
    """Generate URL-safe slug from title."""
    slug = title.lower().strip()
    slug = re.sub(r'[^a-z0-9\s-]', '', slug)
    slug = re.sub(r'[\s-]+', '-', slug)
    slug = slug[:80]
    return f"{slug}-{uuid.uuid4().hex[:6]}"


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_collection(
    title: str,
    description: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Create a new collection."""
    slug = _slugify(title)

    collection_id = str(uuid.uuid4())
    await db.execute(
        sql_text("""
            INSERT INTO public_collections (id, user_id, title, description, slug, is_published)
            VALUES (:id, :user_id, :title, :description, :slug, false)
        """),
        {
            'id': collection_id,
            'user_id': str(current_user.id),
            'title': title,
            'description': description,
            'slug': slug,
        }
    )
    await db.commit()

    return {
        'id': collection_id,
        'title': title,
        'description': description,
        'slug': slug,
        'is_published': False,
    }


@router.get("")
async def list_my_collections(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """List current user's collections."""
    result = await db.execute(
        sql_text("""
            SELECT pc.*, COUNT(ci.id) as item_count
            FROM public_collections pc
            LEFT JOIN collection_items ci ON ci.collection_id = pc.id
            WHERE pc.user_id = :user_id
            GROUP BY pc.id
            ORDER BY pc.created_at DESC
        """),
        {'user_id': str(current_user.id)}
    )

    collections = []
    for row in result.fetchall():
        collections.append({
            'id': str(row.id),
            'title': row.title,
            'description': row.description,
            'slug': row.slug,
            'is_published': row.is_published,
            'view_count': row.view_count,
            'fork_count': row.fork_count,
            'item_count': row.item_count,
            'created_at': row.created_at.isoformat() if row.created_at else None,
        })

    return collections


@router.get("/explore")
async def explore_collections(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Discover public collections."""
    offset = (page - 1) * page_size

    result = await db.execute(
        sql_text("""
            SELECT pc.*, u.name as creator_name, COUNT(ci.id) as item_count
            FROM public_collections pc
            JOIN users u ON u.id = pc.user_id
            LEFT JOIN collection_items ci ON ci.collection_id = pc.id
            WHERE pc.is_published = true
            GROUP BY pc.id, u.name
            ORDER BY pc.view_count DESC, pc.created_at DESC
            LIMIT :limit OFFSET :offset
        """),
        {'limit': page_size, 'offset': offset}
    )

    collections = []
    for row in result.fetchall():
        collections.append({
            'id': str(row.id),
            'title': row.title,
            'description': row.description,
            'slug': row.slug,
            'creator_name': row.creator_name,
            'view_count': row.view_count,
            'fork_count': row.fork_count,
            'item_count': row.item_count,
        })

    return collections


@router.get("/{slug}")
async def get_collection(
    slug: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get a collection by slug."""
    result = await db.execute(
        sql_text("""
            SELECT pc.*, u.name as creator_name
            FROM public_collections pc
            JOIN users u ON u.id = pc.user_id
            WHERE pc.slug = :slug
        """),
        {'slug': slug}
    )

    row = result.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Collection not found")

    if not row.is_published:
        raise HTTPException(status_code=404, detail="Collection not found")

    # Increment view count
    await db.execute(
        sql_text("UPDATE public_collections SET view_count = view_count + 1 WHERE slug = :slug"),
        {'slug': slug}
    )

    # Get items
    items_result = await db.execute(
        sql_text("""
            SELECT ci.*, co.title, co.summary, co.url, co.thumbnail_url, co.source_app, co.category
            FROM collection_items ci
            JOIN content_items co ON co.id = ci.content_item_id
            WHERE ci.collection_id = :collection_id
            ORDER BY ci.position, ci.created_at
        """),
        {'collection_id': str(row.id)}
    )

    items = []
    for item_row in items_result.fetchall():
        items.append({
            'id': str(item_row.id),
            'content_item_id': str(item_row.content_item_id),
            'title': item_row.title,
            'summary': item_row.summary,
            'url': item_row.url,
            'thumbnail_url': item_row.thumbnail_url,
            'source_app': item_row.source_app,
            'category': item_row.category,
            'curator_note': item_row.curator_note,
            'position': item_row.position,
        })

    await db.commit()

    return {
        'id': str(row.id),
        'title': row.title,
        'description': row.description,
        'slug': row.slug,
        'creator_name': row.creator_name,
        'is_published': row.is_published,
        'view_count': row.view_count + 1,
        'fork_count': row.fork_count,
        'items': items,
        'created_at': row.created_at.isoformat() if row.created_at else None,
    }


@router.post("/{collection_id}/items")
async def add_item_to_collection(
    collection_id: str,
    content_item_id: str,
    curator_note: Optional[str] = None,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Add a content item to a collection."""
    # Verify ownership
    result = await db.execute(
        sql_text("SELECT id FROM public_collections WHERE id = :id AND user_id = :user_id"),
        {'id': collection_id, 'user_id': str(current_user.id)}
    )
    if not result.fetchone():
        raise HTTPException(status_code=404, detail="Collection not found")

    # Get next position
    pos_result = await db.execute(
        sql_text("SELECT COALESCE(MAX(position), 0) + 1 FROM collection_items WHERE collection_id = :id"),
        {'id': collection_id}
    )
    next_pos = pos_result.scalar() or 1

    item_id = str(uuid.uuid4())
    await db.execute(
        sql_text("""
            INSERT INTO collection_items (id, collection_id, content_item_id, curator_note, position)
            VALUES (:id, :collection_id, :content_item_id, :curator_note, :position)
        """),
        {
            'id': item_id,
            'collection_id': collection_id,
            'content_item_id': content_item_id,
            'curator_note': curator_note,
            'position': next_pos,
        }
    )
    await db.commit()

    return {"id": item_id, "status": "added"}


@router.delete("/{collection_id}/items/{item_id}")
async def remove_item_from_collection(
    collection_id: str,
    item_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Remove a content item from a collection."""
    # Verify ownership
    result = await db.execute(
        sql_text("SELECT id FROM public_collections WHERE id = :id AND user_id = :user_id"),
        {'id': collection_id, 'user_id': str(current_user.id)}
    )
    if not result.fetchone():
        raise HTTPException(status_code=404, detail="Collection not found")

    await db.execute(
        sql_text("DELETE FROM collection_items WHERE id = :id AND collection_id = :collection_id"),
        {'id': item_id, 'collection_id': collection_id}
    )
    await db.commit()

    return {"status": "removed"}


@router.post("/{collection_id}/fork")
async def fork_collection(
    collection_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Fork a public collection — copies all items to user's library."""
    # Get collection
    result = await db.execute(
        sql_text("SELECT * FROM public_collections WHERE id = :id AND is_published = true"),
        {'id': collection_id}
    )
    collection = result.fetchone()
    if not collection:
        raise HTTPException(status_code=404, detail="Collection not found")

    # Get collection items
    items_result = await db.execute(
        sql_text("""
            SELECT co.url, co.title, co.summary, co.tags, co.source_app, co.category
            FROM collection_items ci
            JOIN content_items co ON co.id = ci.content_item_id
            WHERE ci.collection_id = :collection_id
        """),
        {'collection_id': collection_id}
    )

    # Get user's existing URLs
    existing_result = await db.execute(
        sql_text("SELECT url FROM content_items WHERE user_id = :user_id"),
        {'user_id': str(current_user.id)}
    )
    existing_urls = {row[0] for row in existing_result.fetchall()}

    created = 0
    for item in items_result.fetchall():
        if item.url in existing_urls:
            continue

        new_id = str(uuid.uuid4())
        await db.execute(
            sql_text("""
                INSERT INTO content_items (id, user_id, url, title, summary, tags, source_app, category,
                    ingestion_status, ai_status)
                VALUES (:id, :user_id, :url, :title, :summary, :tags, :source_app, :category,
                    :ingestion_status, :ai_status)
            """),
            {
                'id': new_id,
                'user_id': str(current_user.id),
                'url': item.url,
                'title': item.title,
                'summary': item.summary or 'Forked from collection',
                'tags': item.tags or [],
                'source_app': item.source_app or 'other',
                'category': item.category or 'other',
                'ingestion_status': 'pending',
                'ai_status': 'pending',
            }
        )
        existing_urls.add(item.url)
        created += 1

    # Increment fork count
    await db.execute(
        sql_text("UPDATE public_collections SET fork_count = fork_count + 1 WHERE id = :id"),
        {'id': collection_id}
    )
    await db.commit()

    return {
        'forked_items': created,
        'collection_title': collection.title,
    }
