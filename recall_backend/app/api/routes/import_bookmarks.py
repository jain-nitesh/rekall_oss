"""
Bookmark import API endpoints.

- POST /import/chrome - Upload Chrome bookmarks HTML
- POST /import/pocket - Upload Pocket export (CSV/HTML)
- POST /import/raindrop - Upload Raindrop.io export (CSV)
- GET /import/status/{import_id} - Check import progress
"""
import uuid
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.models.user import User
from app.api.routes.auth import get_current_user
from app.services.import_service import (
    parse_chrome_html,
    parse_pocket_csv,
    parse_raindrop_csv,
    queue_bookmarks
)

import logging

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/import", tags=["Import"])


async def _process_import(
    file: UploadFile,
    source: str,
    parser_fn,
    current_user,
    db: AsyncSession
):
    """Common import processing logic."""
    # Read file content
    content = await file.read()
    try:
        text_content = content.decode('utf-8')
    except UnicodeDecodeError:
        text_content = content.decode('latin-1')

    # Parse bookmarks
    bookmarks = parser_fn(text_content)

    if not bookmarks:
        raise HTTPException(
            status_code=400,
            detail=f"No bookmarks found in the uploaded {source} file"
        )

    # Create import job record
    from sqlalchemy import text as sql_text
    import_id = str(uuid.uuid4())

    await db.execute(
        sql_text("""
            INSERT INTO import_jobs (id, user_id, source, total_items, status)
            VALUES (:id, :user_id, :source, :total_items, 'processing')
        """),
        {
            'id': import_id,
            'user_id': str(current_user.id),
            'source': source,
            'total_items': len(bookmarks),
        }
    )
    await db.commit()

    # Queue bookmarks for processing
    result = await queue_bookmarks(bookmarks, str(current_user.id), db)

    # Update import job
    await db.execute(
        sql_text("""
            UPDATE import_jobs
            SET processed_items = :processed, failed_items = :failed,
                status = 'completed', completed_at = :completed_at
            WHERE id = :id
        """),
        {
            'id': import_id,
            'processed': result['created'],
            'failed': result['skipped'],
            'completed_at': datetime.utcnow(),
        }
    )
    await db.commit()

    return {
        'import_id': import_id,
        'source': source,
        'total_items': len(bookmarks),
        'created': result['created'],
        'skipped_duplicates': result['skipped'],
        'status': 'completed',
    }


@router.post("/chrome", status_code=status.HTTP_202_ACCEPTED)
async def import_chrome_bookmarks(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Import Chrome bookmarks from HTML file."""
    return await _process_import(file, 'chrome', parse_chrome_html, current_user, db)


@router.post("/pocket", status_code=status.HTTP_202_ACCEPTED)
async def import_pocket_bookmarks(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Import Pocket export (CSV or HTML format)."""
    return await _process_import(file, 'pocket', parse_pocket_csv, current_user, db)


@router.post("/raindrop", status_code=status.HTTP_202_ACCEPTED)
async def import_raindrop_bookmarks(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Import Raindrop.io export (CSV format)."""
    return await _process_import(file, 'raindrop', parse_raindrop_csv, current_user, db)


@router.get("/status/{import_id}")
async def get_import_status(
    import_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """Check import job progress."""
    from sqlalchemy import text as sql_text

    result = await db.execute(
        sql_text("""
            SELECT id, source, total_items, processed_items, failed_items,
                   status, created_at, completed_at
            FROM import_jobs
            WHERE id = :id AND user_id = :user_id
        """),
        {'id': import_id, 'user_id': str(current_user.id)}
    )

    row = result.fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Import job not found")

    return {
        'import_id': str(row.id),
        'source': row.source,
        'total_items': row.total_items,
        'processed_items': row.processed_items,
        'failed_items': row.failed_items,
        'status': row.status,
        'created_at': row.created_at.isoformat() if row.created_at else None,
        'completed_at': row.completed_at.isoformat() if row.completed_at else None,
    }
