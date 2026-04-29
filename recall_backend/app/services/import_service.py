"""
Bookmark import service.

Parses bookmark exports from Chrome, Pocket, and Raindrop.io,
then queues them for ingestion as content items.
"""
import csv
import io
import logging
import uuid
from datetime import datetime
from typing import List, Dict, Optional
from bs4 import BeautifulSoup
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.content_item import ContentItem, IngestionStatus, AIStatus

logger = logging.getLogger(__name__)


def parse_chrome_html(html_content: str) -> List[Dict]:
    """
    Parse Chrome/Netscape bookmark HTML export format.

    Returns list of dicts with 'url', 'title', 'add_date' fields.
    """
    soup = BeautifulSoup(html_content, 'html.parser')
    bookmarks = []

    for link in soup.find_all('a'):
        url = link.get('href', '')
        title = link.get_text(strip=True)
        add_date = link.get('add_date', '')

        if url and url.startswith(('http://', 'https://')):
            bookmark = {
                'url': url,
                'title': title or 'Untitled',
            }
            if add_date:
                try:
                    bookmark['add_date'] = datetime.fromtimestamp(int(add_date))
                except (ValueError, OSError):
                    pass
            bookmarks.append(bookmark)

    logger.info(f"Parsed {len(bookmarks)} bookmarks from Chrome HTML")
    return bookmarks


def parse_pocket_csv(csv_content: str) -> List[Dict]:
    """
    Parse Pocket export (CSV or HTML format).

    Pocket exports can be HTML (similar to Netscape format) or CSV.
    """
    # Try CSV first
    bookmarks = []

    try:
        reader = csv.DictReader(io.StringIO(csv_content))
        for row in reader:
            url = row.get('url', row.get('URL', ''))
            title = row.get('title', row.get('Title', 'Untitled'))

            if url and url.startswith(('http://', 'https://')):
                bookmarks.append({
                    'url': url,
                    'title': title,
                })
    except csv.Error:
        pass

    # If CSV parsing yielded nothing, try HTML
    if not bookmarks:
        bookmarks = parse_chrome_html(csv_content)

    logger.info(f"Parsed {len(bookmarks)} bookmarks from Pocket export")
    return bookmarks


def parse_raindrop_csv(csv_content: str) -> List[Dict]:
    """
    Parse Raindrop.io CSV export format.

    Raindrop exports with columns: id, title, note, excerpt, url, folder, tags, created, cover, highlights, favorite
    """
    bookmarks = []

    try:
        reader = csv.DictReader(io.StringIO(csv_content))
        for row in reader:
            url = row.get('url', '')
            title = row.get('title', 'Untitled')

            if url and url.startswith(('http://', 'https://')):
                bookmark = {
                    'url': url,
                    'title': title,
                }
                # Parse tags if available
                tags = row.get('tags', '')
                if tags:
                    bookmark['tags'] = [t.strip() for t in tags.split(',') if t.strip()]
                bookmarks.append(bookmark)
    except csv.Error as e:
        logger.error(f"Failed to parse Raindrop CSV: {e}")

    logger.info(f"Parsed {len(bookmarks)} bookmarks from Raindrop export")
    return bookmarks


async def queue_bookmarks(
    bookmarks: List[Dict],
    user_id: str,
    db: AsyncSession
) -> Dict[str, int]:
    """
    Bulk create content_items from parsed bookmarks.

    Deduplicates by URL - skips bookmarks already in user's library.

    Returns:
        Dict with 'created', 'skipped' counts
    """
    # Get existing URLs for deduplication
    existing_result = await db.execute(
        select(ContentItem.url).where(ContentItem.user_id == user_id)
    )
    existing_urls = {row[0] for row in existing_result.fetchall()}

    created = 0
    skipped = 0

    for bookmark in bookmarks:
        url = bookmark['url']

        # Skip if already exists
        if url in existing_urls:
            skipped += 1
            continue

        content_item = ContentItem(
            id=uuid.uuid4(),
            user_id=user_id,
            url=url,
            title=bookmark.get('title', 'Untitled'),
            summary='Imported bookmark — processing...',
            tags=bookmark.get('tags', []),
            source_app='other',
            category='other',
            ingestion_status=IngestionStatus.pending,
            ai_status=AIStatus.pending,
        )
        db.add(content_item)
        existing_urls.add(url)
        created += 1

    await db.commit()
    logger.info(f"Queued {created} bookmarks, skipped {skipped} duplicates")

    return {'created': created, 'skipped': skipped}
