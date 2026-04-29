"""
Cluster service - builds and manages clusters of semantically related content.

Algorithm:
1. Load all non-dismissed connections for a user
2. Build adjacency graph (nodes = item IDs, edges weighted by similarity)
3. Find connected components using networkx
4. For large components (>8 items), split using Louvain community detection
5. For each cluster of 2+ items, compute avg similarity and generate AI label
6. Upsert into DB (replace old clusters)
"""
import logging
from typing import List, Optional, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func, delete
from sqlalchemy.orm import selectinload
import networkx as nx
from networkx.algorithms.community import louvain_communities

from app.models.content_connection import ContentConnection
from app.models.content_item import ContentItem
from app.models.connection_cluster import ConnectionCluster, ConnectionClusterItem
from app.services.ai_service import AIService

logger = logging.getLogger(__name__)


async def _generate_cluster_label(item_titles: List[str], item_summaries: Optional[List[str]] = None, item_categories: Optional[List[str]] = None) -> dict:
    """
    Use AI to generate a theme label and description for a cluster
    based on the titles and summaries of the items in it.
    """
    try:
        ai_service = AIService()
        result = await ai_service.provider.generate_cluster_description(
            item_titles=item_titles,
            item_summaries=item_summaries or [],
            item_categories=item_categories,
        )

        label = result.get("label", "").strip()
        if not label or len(label) < 2:
            raise ValueError("AI returned empty label")

        return {
            "label": label[:200],
            "description": result.get("description"),
            "category": result.get("category"),
        }

    except Exception as e:
        logger.warning(f"AI label generation failed: {e}")
        # Deterministic fallback from item categories
        label = "Related Items"
        description = None

        if item_categories:
            freq: Dict[str, int] = {}
            for cat in item_categories:
                if cat:
                    freq[cat] = freq.get(cat, 0) + 1
            if freq:
                top_category = max(freq, key=freq.get)
                label = f"{top_category} Collection"

        if len(item_titles) >= 2:
            shown = ", ".join(item_titles[:2])
            remaining = len(item_titles) - 2
            description = f"Includes {shown}, and {remaining} more" if remaining > 0 else f"Includes {shown}"
        elif item_titles:
            description = f"Includes {item_titles[0]}"

        return {"label": label, "description": description, "category": None}


async def rebuild_clusters(user_id: str, db: AsyncSession) -> List[ConnectionCluster]:
    """
    Full rebuild of clusters for a user.

    1. Load all non-dismissed connections
    2. Build graph and find communities
    3. Generate AI labels
    4. Replace old clusters with new ones
    """
    logger.info(f"Rebuilding clusters for user {user_id}")

    # Step 1: Load all non-dismissed connections for user
    result = await db.execute(
        select(ContentConnection).where(
            and_(
                ContentConnection.user_id == user_id,
                ContentConnection.is_dismissed == False,
            )
        )
    )
    connections = result.scalars().all()

    if not connections:
        # No connections - delete any existing clusters and return empty
        await db.execute(
            delete(ConnectionCluster).where(ConnectionCluster.user_id == user_id)
        )
        await db.commit()
        logger.info(f"No connections found for user {user_id}, cleared clusters")
        return []

    # Step 2: Build adjacency graph
    G = nx.Graph()
    for conn in connections:
        source_id = str(conn.source_item_id)
        target_id = str(conn.target_item_id)
        G.add_edge(source_id, target_id, weight=conn.similarity_score)

    # Step 3: Find connected components
    components = list(nx.connected_components(G))

    # Step 4: Split large components using Louvain community detection
    all_communities = []
    for component in components:
        if len(component) > 8:
            subgraph = G.subgraph(component)
            try:
                sub_communities = louvain_communities(subgraph, seed=42)
                for comm in sub_communities:
                    if len(comm) >= 2:
                        all_communities.append(comm)
            except Exception as e:
                logger.warning(f"Louvain failed on component of size {len(component)}: {e}")
                if len(component) >= 2:
                    all_communities.append(component)
        else:
            if len(component) >= 2:
                all_communities.append(component)

    # Use a savepoint so that if anything fails after deleting old clusters,
    # the transaction rolls back to here, preserving the old clusters.
    async with db.begin_nested():
        # Step 5: Delete old clusters for this user
        await db.execute(
            delete(ConnectionCluster).where(ConnectionCluster.user_id == user_id)
        )
        await db.flush()

        # Step 6: Create new clusters
        new_clusters = []
        for community_items in all_communities:
            item_ids = list(community_items)

            # Compute average similarity from internal edges
            internal_edges = [
                G[u][v]["weight"]
                for u in item_ids
                for v in item_ids
                if u < v and G.has_edge(u, v)
            ]
            avg_sim = sum(internal_edges) / len(internal_edges) if internal_edges else None

            # Fetch item titles for AI labeling
            item_result = await db.execute(
                select(ContentItem).where(ContentItem.id.in_(item_ids))
            )
            items = item_result.scalars().all()
            titles = [item.title for item in items if item.title]
            summaries = [item.summary for item in items if item.summary]
            categories = [item.category for item in items if getattr(item, 'category', None)]

            # Generate AI label
            label_data = await _generate_cluster_label(titles, item_summaries=summaries, item_categories=categories)

            # Create cluster
            cluster = ConnectionCluster(
                user_id=user_id,
                label=label_data["label"],
                description=label_data["description"],
                item_count=len(item_ids),
                avg_similarity=avg_sim,
                is_stale=False,
            )
            db.add(cluster)
            await db.flush()  # Get the cluster ID

            # Create cluster items
            for item_id in item_ids:
                cluster_item = ConnectionClusterItem(
                    cluster_id=cluster.id,
                    content_item_id=item_id,
                )
                db.add(cluster_item)

            new_clusters.append(cluster)

    await db.commit()

    # Refresh clusters to get relationships loaded
    for cluster in new_clusters:
        await db.refresh(cluster)

    logger.info(f"Built {len(new_clusters)} clusters for user {user_id}")
    return new_clusters


async def get_clusters(
    user_id: str,
    db: AsyncSession,
    search: str = None,
    category: str = None,
) -> dict:
    """
    List clusters for a user with optional filters.

    Args:
        user_id: The user's ID
        db: Database session
        search: Optional search query to filter by label/description (ILIKE)
        category: Optional category filter (clusters containing items with this category)

    Returns:
        {"clusters": [...], "total": int}
    """
    query = select(ConnectionCluster).where(
        ConnectionCluster.user_id == user_id
    )

    # Apply search filter
    if search:
        search_pattern = f"%{search}%"
        query = query.where(
            or_(
                ConnectionCluster.label.ilike(search_pattern),
                ConnectionCluster.description.ilike(search_pattern),
            )
        )

    # Apply category filter - find clusters that contain items with the given category
    if category:
        query = query.where(
            ConnectionCluster.id.in_(
                select(ConnectionClusterItem.cluster_id).join(
                    ContentItem,
                    ConnectionClusterItem.content_item_id == ContentItem.id
                ).where(
                    ContentItem.category == category
                ).distinct()
            )
        )

    query = query.order_by(ConnectionCluster.item_count.desc())

    result = await db.execute(query)
    clusters = result.scalars().all()

    # Build response with preview items
    cluster_responses = []
    for cluster in clusters:
        # Get up to 4 preview items
        preview_result = await db.execute(
            select(ContentItem).join(
                ConnectionClusterItem,
                ConnectionClusterItem.content_item_id == ContentItem.id
            ).where(
                ConnectionClusterItem.cluster_id == cluster.id
            ).limit(4)
        )
        preview_items = preview_result.scalars().all()

        # Query distinct source_app values for ALL items in the cluster
        source_apps_result = await db.execute(
            select(ContentItem.source_app).join(
                ConnectionClusterItem,
                ConnectionClusterItem.content_item_id == ContentItem.id
            ).where(
                and_(
                    ConnectionClusterItem.cluster_id == cluster.id,
                    ContentItem.source_app != None,
                    ContentItem.source_app != "",
                )
            ).distinct()
        )
        source_apps = [row[0] for row in source_apps_result.all()]

        cluster_responses.append({
            "id": str(cluster.id),
            "label": cluster.label,
            "description": cluster.description,
            "item_count": cluster.item_count,
            "avg_similarity": cluster.avg_similarity,
            "preview_items": [
                {
                    "id": str(item.id),
                    "title": item.title,
                    "thumbnail_url": item.thumbnail_url,
                    "category": item.category,
                    "source_app": item.source_app,
                }
                for item in preview_items
            ],
            "source_apps": source_apps,
            "created_at": cluster.created_at,
        })

    return {"clusters": cluster_responses, "total": len(cluster_responses)}


async def get_cluster_detail(
    cluster_id: str,
    user_id: str,
    db: AsyncSession,
) -> Optional[dict]:
    """
    Get detailed view of a cluster including all items and internal connections.

    Returns:
        Dict with cluster info, items, and connections, or None if not found.
    """
    # Get the cluster
    result = await db.execute(
        select(ConnectionCluster).where(
            and_(
                ConnectionCluster.id == cluster_id,
                ConnectionCluster.user_id == user_id,
            )
        )
    )
    cluster = result.scalar_one_or_none()

    if not cluster:
        return None

    # Get all items in this cluster
    items_result = await db.execute(
        select(ContentItem).join(
            ConnectionClusterItem,
            ConnectionClusterItem.content_item_id == ContentItem.id
        ).where(
            ConnectionClusterItem.cluster_id == cluster.id
        )
    )
    items = items_result.scalars().all()
    item_ids = [str(item.id) for item in items]

    # Get internal connections (connections where both items are in this cluster)
    if len(item_ids) >= 2:
        conn_result = await db.execute(
            select(ContentConnection).where(
                and_(
                    ContentConnection.user_id == user_id,
                    ContentConnection.is_dismissed == False,
                    ContentConnection.source_item_id.in_(item_ids),
                    ContentConnection.target_item_id.in_(item_ids),
                )
            ).order_by(ContentConnection.similarity_score.desc())
        )
        internal_connections = conn_result.scalars().all()
    else:
        internal_connections = []

    return {
        "id": str(cluster.id),
        "label": cluster.label,
        "description": cluster.description,
        "items": [
            {
                "id": str(item.id),
                "title": item.title,
                "summary": item.summary,
                "url": item.url,
                "thumbnail_url": item.thumbnail_url,
                "source_app": item.source_app,
                "category": item.category,
            }
            for item in items
        ],
        "connections": [
            {
                "source_item_id": str(conn.source_item_id),
                "target_item_id": str(conn.target_item_id),
                "similarity_score": conn.similarity_score,
                "ai_explanation": conn.ai_explanation,
            }
            for conn in internal_connections
        ],
        "avg_similarity": cluster.avg_similarity,
    }
