"""
Entity backfill service.

Processes existing content items that have completed AI processing
but haven't had entity extraction run yet.

Usage:
    Run as a management command or one-time background task after
    deploying the entity extraction feature.

    python -m app.services.entity_backfill
"""
import asyncio
from datetime import datetime
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_item import ContentItem, AIStatus
from app.models.entity import EntityExtractionStatus
from app.db.session import AsyncSessionLocal
from app.services.entity_extraction_service import extract_entities_for_content


async def backfill_entities(
    batch_size: int = 10,
    rate_limit_delay: float = 3.0,
    max_items: int = 0,
):
    """
    Backfill entity extraction for existing content items.

    Finds all content items where:
    - ai_status = 'completed' (has AI-generated content to extract from)
    - entity_status = 'pending' (hasn't been processed for entities yet)

    Args:
        batch_size: Number of items to process per batch
        rate_limit_delay: Seconds to wait between items (API rate limiting)
        max_items: Maximum items to process (0 = unlimited)
    """
    print("=" * 60)
    print("  ENTITY BACKFILL: Processing existing content items")
    print("=" * 60)

    async with AsyncSessionLocal() as db:
        # Count total items to process
        count_stmt = select(func.count(ContentItem.id)).where(
            (ContentItem.ai_status == AIStatus.completed) &
            (ContentItem.entity_status == EntityExtractionStatus.pending)
        )
        result = await db.execute(count_stmt)
        total = result.scalar() or 0

        if max_items > 0:
            total = min(total, max_items)

        print(f"  Found {total} items to process")

        if total == 0:
            print("  Nothing to backfill!")
            return

        processed = 0
        failed = 0
        offset = 0

        while processed + failed < total:
            # Fetch next batch
            stmt = select(ContentItem).where(
                (ContentItem.ai_status == AIStatus.completed) &
                (ContentItem.entity_status == EntityExtractionStatus.pending)
            ).order_by(ContentItem.created_at.desc()).limit(batch_size).offset(0)

            result = await db.execute(stmt)
            items = result.scalars().all()

            if not items:
                break

            print(f"\n  Batch: processing {len(items)} items ({processed + failed}/{total})")

            for item in items:
                try:
                    # Process in a fresh session to isolate failures
                    async with AsyncSessionLocal() as item_db:
                        entities = await extract_entities_for_content(
                            content_id=str(item.id),
                            db=item_db
                        )
                        if entities:
                            print(f"    [OK] {item.title[:50] if item.title else 'Untitled'}: {len(entities)} entities")
                        else:
                            print(f"    [OK] {item.title[:50] if item.title else 'Untitled'}: no entities")
                        processed += 1

                except Exception as e:
                    print(f"    [FAIL] {item.title[:50] if item.title else 'Untitled'}: {e}")
                    failed += 1

                # Rate limit
                if rate_limit_delay > 0:
                    await asyncio.sleep(rate_limit_delay)

                if max_items > 0 and processed + failed >= max_items:
                    break

        print(f"\n{'=' * 60}")
        print(f"  BACKFILL COMPLETE")
        print(f"  Processed: {processed}, Failed: {failed}, Total: {processed + failed}")
        print(f"{'=' * 60}")


# Allow running as a script
if __name__ == "__main__":
    import sys

    batch_size = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    max_items = int(sys.argv[2]) if len(sys.argv) > 2 else 0

    asyncio.run(backfill_entities(batch_size=batch_size, max_items=max_items))
