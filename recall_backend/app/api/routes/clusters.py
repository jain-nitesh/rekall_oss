"""
Clusters API endpoints.

- GET /clusters - list clusters (auto-rebuilds if stale)
- GET /clusters/{cluster_id} - cluster detail with items and connections
- POST /clusters/rebuild - force rebuild
- DELETE /clusters/{cluster_id}/dismiss - delete a cluster
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, delete, func

from app.db.session import get_db
from app.models.user import User
from app.models.connection_cluster import ConnectionCluster
from app.api.routes.auth import get_current_user
from app.api.schemas.cluster import (
    ClusterListResponse,
    ClusterDetailResponse,
)
from app.services.cluster_service import rebuild_clusters, get_clusters, get_cluster_detail

import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/clusters", tags=["Clusters"])


@router.get("", response_model=ClusterListResponse)
async def list_clusters(
    search: str = Query(default=None, description="Search clusters by label/description"),
    category: str = Query(default=None, description="Filter clusters by item category"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    List all clusters for the current user.

    On first call or if any cluster is stale, triggers a rebuild automatically.
    """
    user_id = str(current_user.id)

    # Check if we need to rebuild (no clusters or any stale clusters)
    count_result = await db.execute(
        select(func.count()).select_from(ConnectionCluster).where(
            ConnectionCluster.user_id == user_id
        )
    )
    total_clusters = count_result.scalar() or 0

    stale_result = await db.execute(
        select(func.count()).select_from(ConnectionCluster).where(
            and_(
                ConnectionCluster.user_id == user_id,
                ConnectionCluster.is_stale == True,
            )
        )
    )
    stale_count = stale_result.scalar() or 0

    if total_clusters == 0 or stale_count > 0:
        logger.info(f"Auto-rebuilding clusters for user {user_id} (total={total_clusters}, stale={stale_count})")
        try:
            await rebuild_clusters(user_id, db)
        except Exception as e:
            logger.error(f"Cluster rebuild failed: {e}")
            await db.rollback()
            # Continue with whatever clusters exist

    result = await get_clusters(user_id, db, search=search, category=category)
    return ClusterListResponse(**result)


@router.get("/{cluster_id}", response_model=ClusterDetailResponse)
async def cluster_detail(
    cluster_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get detailed view of a cluster including all items and internal connections."""
    user_id = str(current_user.id)

    result = await get_cluster_detail(cluster_id, user_id, db)
    if not result:
        raise HTTPException(status_code=404, detail="Cluster not found")

    return ClusterDetailResponse(**result)


@router.post("/rebuild")
async def force_rebuild(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Force a full rebuild of all clusters for the current user."""
    user_id = str(current_user.id)

    clusters = await rebuild_clusters(user_id, db)
    return {"status": "rebuilt", "cluster_count": len(clusters)}


@router.delete("/{cluster_id}/dismiss")
async def dismiss_cluster(
    cluster_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete/dismiss a cluster."""
    user_id = str(current_user.id)

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
        raise HTTPException(status_code=404, detail="Cluster not found")

    await db.delete(cluster)
    await db.commit()

    return {"status": "dismissed"}
