"""
Knowledge Graph API endpoint.
Returns nodes (content items and entities) and edges (connections and relationships)
for graph visualization.

Supports two views:
- "content" (default): Content items as nodes, semantic connections as edges
- "entities": Entities as nodes, typed relationships as edges, with content items as satellites
"""
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from pydantic import BaseModel
from typing import List, Optional
from uuid import UUID

from app.db.session import get_db
from app.models.user import User
from app.api.routes.auth import get_current_user

router = APIRouter(prefix="/knowledge-graph", tags=["Knowledge Graph"])


class GraphNode(BaseModel):
    """A node in the knowledge graph."""
    id: str
    title: str
    node_type: str = "content"  # "content" or "entity"
    content_type: Optional[str] = None  # url/image/video/note (for content nodes)
    entity_type: Optional[str] = None   # person/company/technology/etc (for entity nodes)
    category: Optional[str] = None
    connections: int = 0
    mention_count: Optional[int] = None  # For entity nodes
    thumbnail_url: Optional[str] = None


class GraphEdge(BaseModel):
    """An edge in the knowledge graph."""
    source: str
    target: str
    weight: float
    edge_type: str = "semantic"  # "semantic", "entity", "relationship"
    relationship_type: Optional[str] = None  # For entity relationship edges (works_at, etc.)
    explanation: Optional[str] = None


class GraphCluster(BaseModel):
    """A cluster grouping in the knowledge graph."""
    id: str
    label: str
    node_ids: List[str]


class KnowledgeGraphResponse(BaseModel):
    """Complete knowledge graph data for visualization."""
    nodes: List[GraphNode]
    edges: List[GraphEdge]
    clusters: List[GraphCluster]
    view: str = "content"


@router.get("", response_model=KnowledgeGraphResponse)
async def get_knowledge_graph(
    limit: int = Query(100, ge=10, le=500, description="Max nodes to return"),
    view: str = Query("content", description="Graph view: 'content' or 'entities'"),
    content_type: Optional[str] = Query(None, description="Filter by content type"),
    entity_type: Optional[str] = Query(None, description="Filter entities by type (person, company, etc.)"),
    cluster_id: Optional[str] = Query(None, description="Focus on specific cluster"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get knowledge graph data for visualization.

    Two views available:
    - **content**: Content items as nodes, semantic connections as edges (original behavior)
    - **entities**: Entities as primary nodes, typed relationships as edges,
      content items as smaller satellite nodes connected to their entities
    """
    user_id = str(current_user.id)

    if view == "entities":
        return await _get_entity_graph(user_id, limit, entity_type, db)
    else:
        return await _get_content_graph(user_id, limit, content_type, cluster_id, db)


async def _get_content_graph(
    user_id: str, limit: int, content_type: Optional[str],
    cluster_id: Optional[str], db: AsyncSession
) -> KnowledgeGraphResponse:
    """Original content-centric graph view."""
    conditions = ["ci.user_id = :user_id", "ci.connection_count > 0"]
    params = {"user_id": user_id, "limit": limit}

    if content_type:
        conditions.append("ci.content_type = :content_type")
        params["content_type"] = content_type

    if cluster_id:
        conditions.append("""ci.id IN (
            SELECT content_item_id FROM connection_cluster_items
            WHERE cluster_id = :cluster_id
        )""")
        params["cluster_id"] = cluster_id

    where_clause = " AND ".join(conditions)

    nodes_sql = text(f"""
        SELECT ci.id, ci.title, ci.content_type, ci.category,
               ci.connection_count, ci.thumbnail_url
        FROM content_items ci
        WHERE {where_clause}
        ORDER BY ci.connection_count DESC
        LIMIT :limit
    """)

    result = await db.execute(nodes_sql, params)
    node_rows = result.fetchall()

    node_ids = [str(row[0]) for row in node_rows]
    nodes = [
        GraphNode(
            id=str(row[0]),
            title=row[1] or "Untitled",
            node_type="content",
            content_type=str(row[2]) if row[2] else "url",
            category=row[3] or "other",
            connections=row[4] or 0,
            thumbnail_url=row[5],
        )
        for row in node_rows
    ]

    if not node_ids:
        return KnowledgeGraphResponse(nodes=[], edges=[], clusters=[], view="content")

    # Get edges
    edges_sql = text("""
        SELECT cc.source_item_id, cc.target_item_id, cc.similarity_score,
               cc.connection_type, cc.ai_explanation
        FROM content_connections cc
        JOIN content_items ci_src ON ci_src.id = cc.source_item_id AND ci_src.user_id = :user_id
        WHERE cc.source_item_id = ANY(:node_ids)
          AND cc.target_item_id = ANY(:node_ids)
          AND cc.is_dismissed = false
        ORDER BY cc.similarity_score DESC
        LIMIT 1000
    """)

    result = await db.execute(edges_sql, {"node_ids": node_ids, "user_id": user_id})
    edge_rows = result.fetchall()

    edges = [
        GraphEdge(
            source=str(row[0]),
            target=str(row[1]),
            weight=float(row[2]) if row[2] else 0.5,
            edge_type=row[3] or "semantic",
            explanation=row[4],
        )
        for row in edge_rows
    ]

    # Get clusters
    clusters_sql = text("""
        SELECT cc.id, cc.label, array_agg(cci.content_item_id::text) as node_ids
        FROM connection_clusters cc
        JOIN connection_cluster_items cci ON cci.cluster_id = cc.id
        WHERE cc.user_id = :user_id
          AND cci.content_item_id = ANY(:node_ids)
        GROUP BY cc.id, cc.label
    """)

    result = await db.execute(clusters_sql, {"user_id": user_id, "node_ids": node_ids})
    cluster_rows = result.fetchall()

    clusters = [
        GraphCluster(
            id=str(row[0]),
            label=row[1] or "Cluster",
            node_ids=row[2] or [],
        )
        for row in cluster_rows
    ]

    return KnowledgeGraphResponse(nodes=nodes, edges=edges, clusters=clusters, view="content")


async def _get_entity_graph(
    user_id: str, limit: int, entity_type: Optional[str], db: AsyncSession
) -> KnowledgeGraphResponse:
    """Entity-centric graph view with typed relationships."""
    nodes = []
    edges = []

    # Get entity nodes (most mentioned entities)
    entity_conditions = ["e.user_id = :user_id", "e.mention_count > 0"]
    params = {"user_id": user_id, "limit": limit}

    if entity_type:
        entity_conditions.append("e.entity_type = :entity_type")
        params["entity_type"] = entity_type

    entity_where = " AND ".join(entity_conditions)

    entities_sql = text(f"""
        SELECT e.id, e.name, e.entity_type, e.mention_count, e.description
        FROM entities e
        WHERE {entity_where}
        ORDER BY e.mention_count DESC
        LIMIT :limit
    """)

    result = await db.execute(entities_sql, params)
    entity_rows = result.fetchall()

    entity_ids = [str(row[0]) for row in entity_rows]

    for row in entity_rows:
        nodes.append(GraphNode(
            id=str(row[0]),
            title=row[1] or "Unknown",
            node_type="entity",
            entity_type=row[2],
            mention_count=row[3] or 0,
            connections=0,  # Will be updated below
        ))

    if not entity_ids:
        return KnowledgeGraphResponse(nodes=[], edges=[], clusters=[], view="entities")

    # Get relationship edges between entities
    rel_sql = text("""
        SELECT er.source_entity_id, er.target_entity_id,
               er.strength, er.relationship_type, er.description
        FROM entity_relationships er
        WHERE er.user_id = :user_id
          AND er.source_entity_id = ANY(:entity_ids)
          AND er.target_entity_id = ANY(:entity_ids)
        ORDER BY er.strength DESC
        LIMIT 500
    """)

    result = await db.execute(rel_sql, {"user_id": user_id, "entity_ids": entity_ids})
    rel_rows = result.fetchall()

    for row in rel_rows:
        edges.append(GraphEdge(
            source=str(row[0]),
            target=str(row[1]),
            weight=float(row[2]) if row[2] else 0.5,
            edge_type="relationship",
            relationship_type=row[3],
            explanation=row[4],
        ))

    # Optionally add content items as satellite nodes connected to entities
    # Get top content items for each entity (limited to avoid graph explosion)
    content_sql = text("""
        SELECT DISTINCT ON (ci.id)
            ci.id, ci.title, ci.content_type, ci.category, ci.thumbnail_url,
            ce.entity_id, ce.relevance_score
        FROM content_entities ce
        JOIN content_items ci ON ci.id = ce.content_item_id
        WHERE ce.entity_id = ANY(:entity_ids)
        ORDER BY ci.id, ce.relevance_score DESC
        LIMIT :content_limit
    """)

    content_limit = min(limit * 2, 200)  # Up to 2x entity nodes worth of content
    result = await db.execute(content_sql, {"entity_ids": entity_ids, "content_limit": content_limit})
    content_rows = result.fetchall()

    content_node_ids = set()
    for row in content_rows:
        content_id = str(row[0])
        if content_id not in content_node_ids:
            content_node_ids.add(content_id)
            nodes.append(GraphNode(
                id=content_id,
                title=row[1] or "Untitled",
                node_type="content",
                content_type=str(row[2]) if row[2] else "url",
                category=row[3] or "other",
                thumbnail_url=row[4],
            ))

        # Edge from content to entity
        edges.append(GraphEdge(
            source=content_id,
            target=str(row[5]),
            weight=float(row[6]) if row[6] else 0.5,
            edge_type="entity",
        ))

    return KnowledgeGraphResponse(nodes=nodes, edges=edges, clusters=[], view="entities")
