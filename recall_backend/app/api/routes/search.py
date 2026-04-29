"""
Search API endpoints.

- GET /search/history - Get user's recent searches
- POST /search/history - Save a search to history
- DELETE /search/history - Clear all search history
- POST /search/semantic - Semantic search using embeddings
"""
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, delete, text
from typing import List

from app.db.session import get_db
from app.models.user import User
from app.models.content_item import ContentItem
from app.models.search_history import SearchHistory
from app.api.routes.auth import get_current_user
from app.api.schemas.search import (
    SearchHistoryItem,
    SearchHistoryCreate,
    SemanticSearchRequest,
    SmartSearchRequest,
    SmartSearchResult,
    SearchSuggestion,
)
from app.api.schemas.content import ContentResponse
from app.services.ai_service import AIService
from app.services.query_understanding_service import query_understanding_service
from app.core.config import settings
from datetime import datetime, timedelta
from typing import Optional

import logging

logger = logging.getLogger(__name__)

# Router for search endpoints
router = APIRouter(prefix="/search", tags=["Search"])


@router.get("/history", response_model=List[SearchHistoryItem])
async def get_search_history(
    limit: int = Query(10, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Get user's recent searches with timestamps."""
    query = select(SearchHistory).where(
        SearchHistory.user_id == current_user.id
    ).order_by(
        desc(SearchHistory.created_at)
    ).limit(limit)

    result = await db.execute(query)
    items = result.scalars().all()

    return [SearchHistoryItem.model_validate(item) for item in items]


@router.post("/history", response_model=SearchHistoryItem, status_code=status.HTTP_201_CREATED)
async def save_search(
    request: SearchHistoryCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Save a search to history."""
    search_entry = SearchHistory(
        user_id=current_user.id,
        query=request.query
    )

    db.add(search_entry)
    await db.commit()
    await db.refresh(search_entry)

    return SearchHistoryItem.model_validate(search_entry)


@router.delete("/history", status_code=status.HTTP_204_NO_CONTENT)
async def clear_search_history(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Clear all search history for the current user."""
    stmt = delete(SearchHistory).where(
        SearchHistory.user_id == current_user.id
    )
    await db.execute(stmt)
    await db.commit()

    return None


@router.post("/semantic", response_model=List[ContentResponse])
async def semantic_search(
    request: SemanticSearchRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Semantic search using vector embeddings.

    Generates an embedding for the query and finds similar content
    using pgvector cosine distance. Falls back to full-text search
    if embedding generation fails.
    """
    semantic_results = []
    use_semantic = False

    # Try generating embedding for the search query
    try:
        ai_service = AIService()
        query_embedding = await ai_service.generate_embedding(request.query)
        use_semantic = True
    except Exception as e:
        logger.warning(f"Semantic search embedding failed: {e}")

    if use_semantic:
        # Convert embedding to string format for pgvector
        embedding_str = '[' + ','.join(str(x) for x in query_embedding) + ']'

        sql = text("""
            SELECT *, 1 - (embedding <=> :query_embedding) as similarity
            FROM content_items
            WHERE user_id = :user_id
              AND embedding IS NOT NULL
              AND 1 - (embedding <=> :query_embedding) >= :threshold
            ORDER BY embedding <=> :query_embedding
            LIMIT :limit
        """)

        result = await db.execute(sql, {
            'query_embedding': embedding_str,
            'user_id': str(current_user.id),
            'threshold': request.threshold,
            'limit': request.limit,
        })

        rows = result.fetchall()
        semantic_results = [
            ContentResponse.model_validate(dict(row._mapping))
            for row in rows
        ]

    # If semantic search returned results, use them
    if semantic_results:
        return semantic_results

    # Fallback: full-text search when semantic fails or returns nothing
    logger.info(f"Semantic returned 0 results for '{request.query}', falling back to full-text search")

    fts_sql = text("""
        SELECT *,
            ts_rank(
                to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, '') || ' ' || coalesce(extracted_content, '') || ' ' || coalesce(ocr_text, '') || ' ' || coalesce(tags::text, '') || ' ' || coalesce(notes, '') || ' ' || coalesce(detailed_summary, '') || ' ' || coalesce(key_takeaways::text, '')),
                plainto_tsquery('english', :search_query)
            ) as text_rank
        FROM content_items
        WHERE user_id = :user_id
          AND (
            to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, '') || ' ' || coalesce(extracted_content, '') || ' ' || coalesce(ocr_text, '') || ' ' || coalesce(tags::text, '') || ' ' || coalesce(notes, '') || ' ' || coalesce(detailed_summary, '') || ' ' || coalesce(key_takeaways::text, ''))
            @@ plainto_tsquery('english', :search_query)
            OR title ILIKE :search_term
            OR summary ILIKE :search_term
            OR notes ILIKE :search_term
          )
        ORDER BY text_rank DESC, created_at DESC
        LIMIT :limit
    """)

    result = await db.execute(fts_sql, {
        'user_id': str(current_user.id),
        'search_query': request.query,
        'search_term': f"%{request.query}%",
        'limit': request.limit,
    })

    rows = result.fetchall()
    return [
        ContentResponse.model_validate(dict(row._mapping))
        for row in rows
    ]


def _normalize_scores(results: dict) -> dict:
    """Min-max normalize scores to 0.0-1.0. Returns {id: normalized_score}."""
    if not results:
        return {}
    scores = list(results.values())
    min_s = min(scores)
    max_s = max(scores)
    if max_s == min_s:
        return {k: 1.0 for k in results}
    return {k: (v - min_s) / (max_s - min_s) for k, v in results.items()}


def _fuse_scores(vector_scores: dict, fts_scores: dict,
                 vector_weight: float = 0.7, fts_weight: float = 0.3) -> dict:
    """Weighted fusion of normalized vector and FTS scores by content_item_id."""
    all_ids = set(vector_scores.keys()) | set(fts_scores.keys())
    fused = {}
    for cid in all_ids:
        v = vector_scores.get(cid, 0.0) * vector_weight
        f = fts_scores.get(cid, 0.0) * fts_weight
        fused[cid] = v + f
    return fused


def _apply_temporal_decay(score: float, created_at, now, half_life_days: float = 30.0) -> float:
    """Apply exponential temporal decay. Recent content scores higher."""
    if not created_at:
        return score * 0.7
    age_days = max(0, (now - created_at).total_seconds() / 86400)
    decay = 0.5 ** (age_days / half_life_days)
    return score * (0.7 + 0.3 * decay)


def _apply_mmr(rows_with_scores: list, threshold: float = 0.9) -> list:
    """Remove near-duplicate results using stored embeddings. O(n^2) but n is small (<50)."""
    if not rows_with_scores:
        return []
    kept = [rows_with_scores[0]]
    for candidate in rows_with_scores[1:]:
        c_emb = candidate[0].get("embedding")
        if c_emb is None:
            kept.append(candidate)
            continue
        is_dup = False
        for existing in kept:
            e_emb = existing[0].get("embedding")
            if e_emb is None:
                continue
            # Cosine similarity from pgvector embeddings (already unit vectors)
            dot = sum(a * b for a, b in zip(c_emb[:50], e_emb[:50]))  # Approximate with first 50 dims
            if dot > threshold:
                is_dup = True
                break
        if not is_dup:
            kept.append(candidate)
    return kept


@router.post("/smart", response_model=List[SmartSearchResult])
async def smart_search(
    request: SmartSearchRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Hybrid search: parallel vector + full-text retrieval with score fusion.
    """
    # Step 1: Parse query for intent
    parsed = await query_understanding_service.parse_query(request.query)
    logger.info(f"Smart search: '{request.query}' -> refined='{parsed.refined_query}', "
                f"type={parsed.content_type_hint}, days={parsed.date_hint_days}")

    user_id = str(current_user.id)
    limit = min(request.limit, 50)
    content_type_filter = request.content_type or parsed.content_type_hint
    date_filter_days = parsed.date_hint_days
    now = datetime.utcnow()

    # Build shared WHERE conditions
    conditions = ["user_id = :user_id"]
    params = {"user_id": user_id}
    if content_type_filter:
        conditions.append("content_type = :content_type")
        params["content_type"] = content_type_filter
    if date_filter_days:
        conditions.append("created_at >= :date_from")
        params["date_from"] = now - timedelta(days=date_filter_days)
    where_clause = " AND ".join(conditions)

    # Step 2: Run vector + FTS in parallel (sequential SQL but both run)
    vector_rows = {}
    vector_scores = {}

    # --- Vector path ---
    ai_service = AIService()
    try:
        query_embedding = await ai_service.generate_embedding(parsed.refined_query)
        embedding_str = '[' + ','.join(str(x) for x in query_embedding) + ']'
        vector_sql = text(f"""
            SELECT *, 1 - (embedding <=> :query_embedding) as similarity
            FROM content_items
            WHERE {where_clause} AND embedding IS NOT NULL
              AND 1 - (embedding <=> :query_embedding) >= 0.15
            ORDER BY embedding <=> :query_embedding
            LIMIT :limit
        """)
        v_params = {**params, "query_embedding": embedding_str, "limit": limit}
        v_result = await db.execute(vector_sql, v_params)
        for row in v_result.fetchall():
            rd = dict(row._mapping)
            cid = str(rd["id"])
            vector_rows[cid] = rd
            vector_scores[cid] = float(rd["similarity"])
    except Exception as e:
        logger.warning(f"Vector search failed, FTS-only mode: {e}")

    # --- FTS path ---
    fts_rows = {}
    fts_scores = {}
    fts_sql = text(f"""
        SELECT *, ts_rank_cd(
            to_tsvector('english', coalesce(title,'') || ' ' || coalesce(summary,'') || ' ' ||
            coalesce(extracted_content,'') || ' ' || coalesce(ocr_text,'') || ' ' ||
            coalesce(tags::text,'') || ' ' || coalesce(notes,'') || ' ' ||
            coalesce(detailed_summary,'') || ' ' || coalesce(key_takeaways::text,'')),
            plainto_tsquery('english', :query)
        ) as fts_rank
        FROM content_items
        WHERE {where_clause}
          AND (
            to_tsvector('english', coalesce(title,'') || ' ' || coalesce(summary,'') || ' ' ||
            coalesce(extracted_content,'') || ' ' || coalesce(ocr_text,'') || ' ' ||
            coalesce(tags::text,'') || ' ' || coalesce(notes,'') || ' ' ||
            coalesce(detailed_summary,'') || ' ' || coalesce(key_takeaways::text,''))
            @@ plainto_tsquery('english', :query)
            OR title ILIKE :search_term
            OR summary ILIKE :search_term
          )
        ORDER BY fts_rank DESC
        LIMIT :limit
    """)
    fts_params = {**params, "query": parsed.refined_query,
                  "search_term": f"%{request.query}%", "limit": limit}
    f_result = await db.execute(fts_sql, fts_params)
    for row in f_result.fetchall():
        rd = dict(row._mapping)
        cid = str(rd["id"])
        fts_rows[cid] = rd
        fts_scores[cid] = float(rd["fts_rank"])

    # Step 3: Normalize + fuse
    v_norm = _normalize_scores(vector_scores)
    f_norm = _normalize_scores(fts_scores)
    fused = _fuse_scores(v_norm, f_norm)

    if not fused:
        return []

    # Merge row data (prefer vector row if both exist, it has similarity)
    all_rows = {}
    for cid, rd in fts_rows.items():
        all_rows[cid] = rd
    for cid, rd in vector_rows.items():
        all_rows[cid] = rd  # vector overwrites fts if both

    # Step 4: Post-processing boosts
    scored_rows = []
    for cid, base_score in fused.items():
        rd = all_rows[cid]
        # Temporal decay
        score = _apply_temporal_decay(base_score, rd.get("created_at"), now)
        # Interaction boost
        if rd.get("is_favorite"):
            score = min(1.0, score + 0.05)
        # Type match boost
        if content_type_filter and rd.get("content_type") == content_type_filter:
            score = min(1.0, score + 0.05)
        # Determine match type
        in_vector = cid in vector_scores
        in_fts = cid in fts_scores
        match_type = "hybrid" if (in_vector and in_fts) else ("vector" if in_vector else "fts")
        scored_rows.append((rd, score, match_type))

    # Sort by score descending
    scored_rows.sort(key=lambda x: x[1], reverse=True)

    # Step 5: MMR dedup
    scored_rows = _apply_mmr(scored_rows)

    # Build response
    results = []
    for rd, score, match_type in scored_rows[:limit]:
        content = ContentResponse.model_validate(rd)
        results.append(SmartSearchResult(
            content=content,
            score=round(score, 4),
            match_reason=None,
            match_type=match_type,
        ))
    return results


@router.get("/suggestions", response_model=List[SearchSuggestion])
async def get_search_suggestions(
    q: str = "",
    limit: int = Query(10, ge=1, le=50),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get search suggestions based on prefix matching.
    Returns recent searches, matching tags, and categories.
    """
    suggestions = []

    if not q:
        # Return recent searches
        history_sql = select(SearchHistory).where(
            SearchHistory.user_id == current_user.id
        ).order_by(desc(SearchHistory.created_at)).limit(limit)
        result = await db.execute(history_sql)
        for item in result.scalars().all():
            suggestions.append(SearchSuggestion(text=item.query, source="history"))
        return suggestions

    # Escape ILIKE wildcards in user input
    safe_q = q.replace('%', r'\%').replace('_', r'\_')

    # Recent searches matching prefix
    history_sql = select(SearchHistory).where(
        SearchHistory.user_id == current_user.id,
        SearchHistory.query.ilike(f"{safe_q}%"),
    ).order_by(desc(SearchHistory.created_at)).limit(5)
    result = await db.execute(history_sql)
    for item in result.scalars().all():
        suggestions.append(SearchSuggestion(text=item.query, source="history"))

    # Matching tags from user's content
    tag_sql = text("""
        SELECT DISTINCT unnest(tags) as tag
        FROM content_items
        WHERE user_id = :user_id
          AND EXISTS (
            SELECT 1 FROM unnest(tags) t WHERE t ILIKE :prefix
          )
        LIMIT 5
    """)
    result = await db.execute(tag_sql, {"user_id": str(current_user.id), "prefix": f"{q}%"})
    for row in result.fetchall():
        tag = row[0]
        if tag.lower().startswith(q.lower()):
            suggestions.append(SearchSuggestion(text=tag, source="tag"))

    return suggestions[:limit]
