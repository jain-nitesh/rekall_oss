"""
Embedding backfill service.

Generates embeddings for existing content items that don't have them yet.
Processes in batches with rate limiting to avoid overwhelming the AI provider.
"""
import asyncio
import logging
from sqlalchemy import select, and_
from app.db.session import AsyncSessionLocal
from app.models.content_item import ContentItem, AIStatus
from app.services.ai_service import AIService
from app.core.config import settings

logger = logging.getLogger(__name__)


async def backfill_embeddings(batch_size: int = 50, delay_seconds: float = 1.0):
    """
    Backfill embeddings for content items that have completed AI processing
    but don't have embeddings yet.

    Args:
        batch_size: Number of items to process per batch
        delay_seconds: Delay between batches to avoid rate limiting
    """
    ai_service = AIService()
    total_processed = 0
    total_failed = 0

    logger.info(f"Starting embedding backfill (batch_size={batch_size}, delay={delay_seconds}s)")

    while True:
        async with AsyncSessionLocal() as db:
            # Find items needing embeddings
            query = select(ContentItem).where(
                and_(
                    ContentItem.embedding == None,
                    ContentItem.ai_status == AIStatus.completed
                )
            ).limit(batch_size)

            result = await db.execute(query)
            items = result.scalars().all()

            if not items:
                logger.info(f"Backfill complete. Processed: {total_processed}, Failed: {total_failed}")
                break

            logger.info(f"Processing batch of {len(items)} items...")

            for item in items:
                try:
                    # Generate embedding from title + summary
                    embedding_text = f"{item.title} {item.summary or ''}"
                    embedding = await ai_service.generate_embedding(embedding_text)

                    item.embedding = embedding
                    item.embedding_model = settings.embedding_model

                    total_processed += 1
                except Exception as e:
                    logger.error(f"Failed to generate embedding for {item.id}: {e}")
                    total_failed += 1

            await db.commit()
            logger.info(f"Batch committed. Total processed: {total_processed}")

        # Rate limit between batches
        await asyncio.sleep(delay_seconds)


async def backfill_connections(batch_size: int = 50, delay_seconds: float = 0.5):
    """
    Discover connections for content items that have embeddings but no connections yet.

    Runs after embedding backfill to ensure all items with embeddings
    have had connection discovery performed.

    Args:
        batch_size: Number of items to process per batch
        delay_seconds: Delay between batches to avoid overwhelming the DB
    """
    from app.services.connections_service import discover_connections

    total_processed = 0
    total_connections = 0

    logger.info("Starting connection discovery backfill...")

    # Collect all item IDs needing connection discovery upfront
    # to avoid infinite loop when items have no similar matches
    item_ids = []
    async with AsyncSessionLocal() as db:
        query = select(ContentItem.id, ContentItem.user_id).where(
            and_(
                ContentItem.embedding != None,
                ContentItem.ai_status == AIStatus.completed,
            )
        )
        result = await db.execute(query)
        item_ids = [(str(row.id), str(row.user_id)) for row in result.fetchall()]

    if not item_ids:
        logger.info("Connection backfill: no items need processing")
        return

    logger.info(f"Connection backfill: {len(item_ids)} items to process")

    # Process in batches
    for i in range(0, len(item_ids), batch_size):
        batch = item_ids[i:i + batch_size]

        async with AsyncSessionLocal() as db:
            for content_id, user_id in batch:
                try:
                    connections = await discover_connections(
                        content_id=content_id,
                        user_id=user_id,
                        db=db,
                    )
                    if connections:
                        total_connections += len(connections)

                    total_processed += 1
                except Exception as e:
                    logger.error(f"Failed connection discovery for {content_id}: {e}")
                    total_processed += 1

        logger.info(f"Connection backfill progress: {total_processed}/{len(item_ids)}")
        await asyncio.sleep(delay_seconds)

    logger.info(
        f"Connection backfill complete. "
        f"Items processed: {total_processed}, Connections created: {total_connections}"
    )


async def run_startup_backfill():
    """
    Run embedding backfill followed by connection discovery.

    Intended to be launched as a background task during app startup.
    Non-fatal: all errors are caught and logged.
    """
    try:
        logger.info("Startup backfill: Phase 1 - Embedding backfill")
        await backfill_embeddings(batch_size=50, delay_seconds=1.0)
    except Exception as e:
        logger.error(f"Startup embedding backfill failed: {e}")
        import traceback
        traceback.print_exc()

    try:
        logger.info("Startup backfill: Phase 2 - Connection discovery")
        await backfill_connections(batch_size=20, delay_seconds=0.5)
    except Exception as e:
        logger.error(f"Startup connection backfill failed: {e}")
        import traceback
        traceback.print_exc()

    logger.info("Startup backfill complete")


if __name__ == "__main__":
    asyncio.run(backfill_embeddings())
