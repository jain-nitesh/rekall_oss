import uuid
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.models.content_item import ContentItem, IngestionStatus, AIStatus, ContentType, FetchErrorType


def _make_content_item(user_id):
    item = MagicMock(spec=ContentItem)
    item.id = uuid.uuid4()
    item.user_id = user_id
    item.title = "Test Article"
    item.summary = "Test summary"
    item.url = "https://example.com"
    item.tags = []
    item.source_app = "other"
    item.source_app_name = None
    item.source_app_package = None
    item.category = "technology"
    item.content_type = ContentType.url
    item.ingestion_status = IngestionStatus.pending
    item.ai_status = AIStatus.pending
    item.fetch_error_type = FetchErrorType.none
    item.is_done = False
    item.is_favorite = False
    item.thumbnail_url = None
    item.hero_image_url = None
    item.media_url = None
    item.media_mime_type = None
    item.media_duration_seconds = None
    item.ocr_text = None
    item.reading_time_minutes = 5
    item.key_takeaways = None
    item.detailed_summary = None
    item.notes = None
    item.connection_count = 0
    item.created_at = datetime.utcnow()
    item.updated_at = datetime.utcnow()
    item.user_category_id = None
    return item


# ---------- POST /api/content/ingest ----------

def test_ingest_with_auth_returns_200(authenticated_client, mock_db, mock_user):
    content_item = _make_content_item(mock_user.id)

    # db.add / commit / refresh cycle for creating placeholder
    async def fake_refresh(obj):
        # copy fields from content_item onto obj so model_validate works
        for attr in ('id', 'user_id', 'title', 'summary', 'url', 'tags',
                     'source_app', 'source_app_name', 'source_app_package',
                     'category', 'content_type', 'ingestion_status', 'ai_status',
                     'fetch_error_type', 'is_done', 'is_favorite', 'thumbnail_url',
                     'hero_image_url', 'media_url', 'media_mime_type',
                     'media_duration_seconds', 'ocr_text', 'reading_time_minutes',
                     'key_takeaways', 'detailed_summary', 'notes', 'created_at',
                     'user_category_id'):
            setattr(obj, attr, getattr(content_item, attr))

    mock_db.refresh = AsyncMock(side_effect=fake_refresh)

    with patch('app.api.routes.content.ingest_content_async') as mock_ingest:
        response = authenticated_client.post(
            "/api/content/ingest",
            json={"url": "https://example.com"}
        )

    assert response.status_code == 200
    data = response.json()
    assert "id" in data
    assert "ingestion_status" in data
    mock_ingest.assert_called_once()


def test_ingest_without_auth_returns_403(test_client):
    response = test_client.post(
        "/api/content/ingest",
        json={"url": "https://example.com"}
    )
    assert response.status_code == 403


# ---------- GET /api/content ----------

def test_get_content_with_auth_returns_own_items_only(authenticated_client, mock_db, mock_user):
    content_item = _make_content_item(mock_user.id)

    count_result = MagicMock()
    count_result.scalar.return_value = 1

    items_result = MagicMock()
    items_result.scalars.return_value.all.return_value = [content_item]

    mock_db.execute.side_effect = [count_result, items_result]

    response = authenticated_client.get("/api/content")

    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 1
    assert len(data["content"]) == 1
    assert str(data["content"][0]["user_id"]) == str(mock_user.id)


def test_get_content_without_auth_returns_403(test_client):
    response = test_client.get("/api/content")
    assert response.status_code == 403


# ---------- DELETE /api/content/{id} ----------

def test_delete_own_item_returns_200(authenticated_client, mock_db, mock_user):
    content_item = _make_content_item(mock_user.id)

    query_result = MagicMock()
    query_result.scalar_one_or_none.return_value = content_item
    mock_db.execute.return_value = query_result

    response = authenticated_client.delete(f"/api/content/{content_item.id}")

    assert response.status_code == 200
    assert response.json() == {"message": "Content deleted successfully"}


def test_delete_another_users_item_returns_404(authenticated_client, mock_db):
    other_user_id = uuid.uuid4()

    query_result = MagicMock()
    query_result.scalar_one_or_none.return_value = None  # filtered out by user_id
    mock_db.execute.return_value = query_result

    response = authenticated_client.delete(f"/api/content/{other_user_id}")

    assert response.status_code == 404


def test_delete_nonexistent_item_returns_404(authenticated_client, mock_db):
    query_result = MagicMock()
    query_result.scalar_one_or_none.return_value = None
    mock_db.execute.return_value = query_result

    response = authenticated_client.delete(f"/api/content/{uuid.uuid4()}")

    assert response.status_code == 404
