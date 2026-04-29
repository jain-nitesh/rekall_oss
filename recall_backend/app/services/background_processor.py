"""
Background content processor service.

Handles resilient async processing of content items with two-phase architecture:
- PHASE 1: Ingestion (fetch URL + metadata extraction)
- PHASE 2: AI processing (summarization + embeddings, rate-limited)
- Recovers stuck items on startup
- Retries failed items periodically
- Ensures all content eventually gets processed
"""
import asyncio
from datetime import datetime, timedelta
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content_item import ContentItem, ProcessingStatus, IngestionStatus, AIStatus
from app.models.entity import EntityExtractionStatus
from app.db.session import AsyncSessionLocal
from app.core.config import settings
from typing import Optional


class BackgroundProcessor:
    """
    Background processor for resilient two-phase content processing.

    Features:
    - Separate queues for ingestion vs AI processing
    - AI rate limiting (configurable delay between AI tasks)
    - Startup recovery: Reprocesses stuck items when backend starts
    - Periodic retry: Automatically retries failed items
    - Max attempts: Gives up after configurable number of retries
    """

    def __init__(
        self,
        ingestion_max_attempts: int = 3,
        ai_max_attempts: int = 3,
        entity_max_attempts: int = 3,
        ai_rate_limit_delay: int = 5,
        ingestion_task_manager: Optional["TaskManager"] = None,
        ai_task_manager: Optional["TaskManager"] = None,
        entity_task_manager: Optional["TaskManager"] = None
    ):
        """
        Initialize background processor.

        Args:
            ingestion_max_attempts: Maximum ingestion attempts before giving up
            ai_max_attempts: Maximum AI processing attempts before giving up
            ai_rate_limit_delay: Seconds to wait between AI processing tasks (rate limiting)
            ingestion_task_manager: Optional task manager for ingestion tasks (prevents memory leaks)
            ai_task_manager: Optional task manager for AI tasks (prevents memory leaks)
        """
        self.ingestion_max_attempts = ingestion_max_attempts
        self.ai_max_attempts = ai_max_attempts
        self.entity_max_attempts = entity_max_attempts
        self.ai_rate_limit_delay = ai_rate_limit_delay
        self.ingestion_task_manager = ingestion_task_manager
        self.ai_task_manager = ai_task_manager
        self.entity_task_manager = entity_task_manager
        self._running = False
        self._last_ai_process_time = None  # Track last AI task for rate limiting
        self._health_check_cycle_count = 0  # Track cycles for weekly health checks
        self._social_refresh_cycle_count = 0  # Track cycles for weekly social link refresh

        # DEPRECATED: Keep for backwards compatibility during migration
        self.max_attempts = ingestion_max_attempts

    def set_task_managers(self, ingestion_task_manager: "TaskManager", ai_task_manager: "TaskManager", entity_task_manager: Optional["TaskManager"] = None):
        """
        Set task managers after initialization.
        Called from main.py after task managers are created.
        """
        self.ingestion_task_manager = ingestion_task_manager
        self.ai_task_manager = ai_task_manager
        self.entity_task_manager = entity_task_manager

    def _calculate_exponential_backoff_delay(self, attempts: int, base_delay_minutes: int) -> timedelta:
        """
        Calculate exponential backoff delay based on attempt count.

        Formula: base_delay * (2 ^ attempts)
        Examples (with base_delay=2 minutes):
        - Attempt 0: 2 minutes
        - Attempt 1: 4 minutes
        - Attempt 2: 8 minutes
        - Attempt 3: 16 minutes
        - Attempt 4: 32 minutes

        Args:
            attempts: Number of attempts made so far
            base_delay_minutes: Base delay in minutes

        Returns:
            timedelta representing the backoff delay
        """
        delay_minutes = base_delay_minutes * (2 ** attempts)
        return timedelta(minutes=delay_minutes)

    async def recover_stuck_items(self):
        """
        Recover items stuck in 'fetching' or AI 'processing' status on startup.

        This handles the case where backend restarted while processing content.
        Two-phase recovery:
        - PHASE 1: Reset stuck ingestion items to 'pending'
        - PHASE 2: Reset stuck AI processing items to 'pending'

        MULTI-INSTANCE SAFE: Uses row-level locking to prevent race conditions
        when multiple backend instances start simultaneously.
        """
        print("=" * 55)
        print("  STARTUP: Recovering stuck content items (TWO-PHASE)")
        print("=" * 55)

        async with AsyncSessionLocal() as db:
            try:
                stuck_threshold = datetime.utcnow() - timedelta(minutes=5)

                # ===== PHASE 1: Recover stuck INGESTION items =====
                print("\nPhase 1: Checking stuck INGESTION items...")
                stmt_ingestion = select(ContentItem).where(
                    (ContentItem.ingestion_status == IngestionStatus.fetching) &
                    ((ContentItem.last_ingestion_at == None) | (ContentItem.last_ingestion_at < stuck_threshold))
                ).with_for_update(skip_locked=True).limit(50)

                result = await db.execute(stmt_ingestion)
                stuck_ingestion = result.scalars().all()

                if stuck_ingestion:
                    print(f"Found {len(stuck_ingestion)} stuck INGESTION item(s):")
                    for item in stuck_ingestion:
                        print(f"  - {item.id}: {item.url}")
                        print(f"    Attempts: {item.ingestion_attempts}")
                        print(f"    Last ingestion: {item.last_ingestion_at}")
                        item.ingestion_status = IngestionStatus.pending
                        item.ingestion_error = "Recovered after backend restart"
                        # BUGFIX: Reset attempt counter since backend restart is infrastructure failure, not content failure
                        item.ingestion_attempts = 0
                    await db.commit()
                    print(f"[OK] Reset {len(stuck_ingestion)} ingestion item(s) to PENDING (attempts reset)")
                else:
                    print("[OK] No stuck ingestion items found")

                # ===== PHASE 2: Recover stuck AI PROCESSING items =====
                print("\nPhase 2: Checking stuck AI PROCESSING items...")
                stmt_ai = select(ContentItem).where(
                    (ContentItem.ai_status == AIStatus.processing) &
                    ((ContentItem.last_ai_processed_at == None) | (ContentItem.last_ai_processed_at < stuck_threshold))
                ).with_for_update(skip_locked=True).limit(50)

                result = await db.execute(stmt_ai)
                stuck_ai = result.scalars().all()

                if stuck_ai:
                    print(f"Found {len(stuck_ai)} stuck AI PROCESSING item(s):")
                    for item in stuck_ai:
                        print(f"  - {item.id}: {item.url}")
                        print(f"    Attempts: {item.ai_attempts}")
                        print(f"    Last AI processed: {item.last_ai_processed_at}")
                        item.ai_status = AIStatus.pending
                        item.ai_error = "Recovered after backend restart"
                        # BUGFIX: Reset attempt counter since backend restart is infrastructure failure, not content failure
                        item.ai_attempts = 0
                    await db.commit()
                    print(f"[OK] Reset {len(stuck_ai)} AI item(s) to PENDING (attempts reset)")
                else:
                    print("[OK] No stuck AI items found")

                # ===== PHASE 3: Recover stuck ENTITY EXTRACTION items =====
                print("\nPhase 3: Checking stuck ENTITY EXTRACTION items...")
                stmt_entity = select(ContentItem).where(
                    (ContentItem.entity_status == EntityExtractionStatus.processing) &
                    ((ContentItem.last_entity_processed_at == None) | (ContentItem.last_entity_processed_at < stuck_threshold))
                ).with_for_update(skip_locked=True).limit(50)

                result = await db.execute(stmt_entity)
                stuck_entity = result.scalars().all()

                if stuck_entity:
                    print(f"Found {len(stuck_entity)} stuck ENTITY EXTRACTION item(s):")
                    for item in stuck_entity:
                        print(f"  - {item.id}: {item.title[:50] if item.title else 'N/A'}")
                        item.entity_status = EntityExtractionStatus.pending
                        item.entity_error = "Recovered after backend restart"
                        item.entity_attempts = 0
                    await db.commit()
                    print(f"[OK] Reset {len(stuck_entity)} entity item(s) to PENDING")
                else:
                    print("[OK] No stuck entity extraction items found")

                print("\nThese items will be retried by the periodic processor")
                print("Note: Other instances may have recovered additional items concurrently")

            except Exception as e:
                print(f"[ERROR] Error recovering stuck items: {e}")
                import traceback
                traceback.print_exc()

    async def retry_pending_ingestion(self):
        """
        Retry items with ingestion_status 'pending' or 'failed' (up to max_attempts).

        Features:
        - Exponential backoff: delay increases exponentially with each attempt
        - MULTI-INSTANCE SAFE: Uses row-level locking to distribute work across
          multiple backend instances without duplicating processing.
        """
        print("─────────────────────────────────────────────────")
        print("PERIODIC: Checking for pending INGESTION items")

        async with AsyncSessionLocal() as db:
            try:
                # Fetch all candidate items (we'll filter by exponential backoff in Python)
                stmt = select(ContentItem).where(
                    (ContentItem.ingestion_status.in_([IngestionStatus.pending, IngestionStatus.failed])) &
                    ((ContentItem.ingestion_attempts == None) | (ContentItem.ingestion_attempts < self.ingestion_max_attempts))
                ).with_for_update(skip_locked=True).limit(30)  # Fetch more candidates for filtering

                result = await db.execute(stmt)
                all_items = result.scalars().all()

                if not all_items:
                    print("[OK] No ingestion items needing retry")
                    return

                # Filter items based on exponential backoff delay
                items_to_retry = []
                now = datetime.utcnow()

                for item in all_items:
                    attempts = item.ingestion_attempts or 0

                    # Calculate exponential backoff delay based on attempts
                    if settings.ingestion_exponential_backoff_enabled:
                        backoff_delay = self._calculate_exponential_backoff_delay(
                            attempts,
                            settings.ingestion_base_retry_delay_minutes
                        )
                    else:
                        # Fallback to fixed delay if exponential backoff is disabled
                        backoff_delay = timedelta(minutes=2)

                    # Check if enough time has passed since last attempt
                    if item.last_ingestion_at is None:
                        # Never attempted, ready to retry immediately
                        items_to_retry.append(item)
                    elif now >= (item.last_ingestion_at + backoff_delay):
                        # Backoff period has elapsed
                        items_to_retry.append(item)

                # Limit batch size for ingestion processing
                items = items_to_retry[:10]

                if not items:
                    print("[OK] No ingestion items ready for retry (exponential backoff in effect)")
                    return

                print(f"Found {len(items)} ingestion item(s) to retry (exponential backoff):")
                for item in items:
                    attempts = item.ingestion_attempts or 0
                    next_delay_minutes = settings.ingestion_base_retry_delay_minutes * (2 ** attempts)
                    print(f"  - {item.id}: {item.url} (attempt {attempts}/{self.ingestion_max_attempts}, next retry: {next_delay_minutes}min)")

                await db.commit()

                # Process items
                from app.api.routes.content import ingest_content_async

                for item in items:
                    # Use task manager if available (prevents memory leaks)
                    if self.ingestion_task_manager:
                        await self.ingestion_task_manager.create_task(ingest_content_async(
                            content_id=str(item.id),
                            url=item.url,
                            user_id=str(item.user_id),
                            custom_title=item.title if item.title != item.url else None
                        ))
                    else:
                        # Fallback to direct task creation (backwards compatibility)
                        asyncio.create_task(ingest_content_async(
                            content_id=str(item.id),
                            url=item.url,
                            user_id=str(item.user_id),
                            custom_title=item.title if item.title != item.url else None
                        ))

                print(f"[OK] Scheduled {len(items)} ingestion item(s) for retry")

            except Exception as e:
                print(f"[ERROR] Error retrying ingestion: {e}")
                import traceback
                traceback.print_exc()

    async def retry_pending_ai(self):
        """
        Retry items with ai_status 'pending' or 'failed' (up to max_attempts).

        Features:
        - Only processes items where ingestion_status = 'ingested'
        - Exponential backoff: delay increases exponentially with each attempt
        - Rate limiting: waits ai_rate_limit_delay seconds between tasks
        - MULTI-INSTANCE SAFE: Uses row-level locking

        IMPORTANT: This method implements AI rate limiting to control costs.
        """
        print("─────────────────────────────────────────────────")
        print("PERIODIC: Checking for pending AI items")

        async with AsyncSessionLocal() as db:
            try:
                # Fetch all candidate items (we'll filter by exponential backoff in Python)
                # Only process AI for successfully ingested items
                stmt = select(ContentItem).where(
                    (ContentItem.ingestion_status == IngestionStatus.ingested) &
                    (ContentItem.ai_status.in_([AIStatus.pending, AIStatus.failed])) &
                    ((ContentItem.ai_attempts == None) | (ContentItem.ai_attempts < self.ai_max_attempts))
                ).with_for_update(skip_locked=True).limit(20)  # Fetch more candidates for filtering

                result = await db.execute(stmt)
                all_items = result.scalars().all()

                if not all_items:
                    print("[OK] No AI items needing retry")
                    return

                # Filter items based on exponential backoff delay
                items_to_retry = []
                now = datetime.utcnow()

                for item in all_items:
                    attempts = item.ai_attempts or 0

                    # Calculate exponential backoff delay based on attempts
                    if settings.ai_exponential_backoff_enabled:
                        backoff_delay = self._calculate_exponential_backoff_delay(
                            attempts,
                            settings.ai_base_retry_delay_minutes
                        )
                    else:
                        # Fallback to fixed delay if exponential backoff is disabled
                        backoff_delay = timedelta(minutes=2)

                    # Check if enough time has passed since last attempt
                    if item.last_ai_processed_at is None:
                        # Never attempted, ready to retry immediately
                        items_to_retry.append(item)
                    elif now >= (item.last_ai_processed_at + backoff_delay):
                        # Backoff period has elapsed
                        items_to_retry.append(item)

                # Limit batch size for AI processing
                items = items_to_retry[:5]

                if not items:
                    print("[OK] No AI items ready for retry (exponential backoff in effect)")
                    return

                print(f"Found {len(items)} AI item(s) to retry (exponential backoff):")
                for item in items:
                    attempts = item.ai_attempts or 0
                    next_delay_minutes = settings.ai_base_retry_delay_minutes * (2 ** attempts)
                    print(f"  - {item.id}: {item.url} (attempt {attempts}/{self.ai_max_attempts}, next retry: {next_delay_minutes}min)")

                await db.commit()

                # Process items with rate limiting
                from app.api.routes.content import process_ai_async

                for i, item in enumerate(items):
                    # Apply rate limiting (wait between AI tasks)
                    if i > 0:  # Don't delay first item
                        print(f"[RATE LIMIT] Waiting {self.ai_rate_limit_delay}s before next AI task...")
                        await asyncio.sleep(self.ai_rate_limit_delay)

                    # Use task manager if available (prevents memory leaks)
                    if self.ai_task_manager:
                        await self.ai_task_manager.create_task(process_ai_async(
                            content_id=str(item.id),
                            url=item.url
                        ))
                    else:
                        # Fallback to direct task creation (backwards compatibility)
                        asyncio.create_task(process_ai_async(
                            content_id=str(item.id),
                            url=item.url
                        ))

                print(f"[OK] Scheduled {len(items)} AI item(s) for retry (rate-limited)")

            except Exception as e:
                print(f"[ERROR] Error retrying AI: {e}")
                import traceback
                traceback.print_exc()

    async def retry_pending_entities(self):
        """
        Retry items with entity_status 'pending' or 'failed' (up to max_attempts).

        Only processes items where ai_status = 'completed' (entity extraction
        requires AI-generated content).
        Rate-limited to avoid overwhelming AI provider.
        """
        print("─────────────────────────────────────────────────")
        print("PERIODIC: Checking for pending ENTITY EXTRACTION items")

        async with AsyncSessionLocal() as db:
            try:
                stmt = select(ContentItem).where(
                    (ContentItem.ai_status == AIStatus.completed) &
                    (ContentItem.entity_status.in_([EntityExtractionStatus.pending, EntityExtractionStatus.failed])) &
                    ((ContentItem.entity_attempts == None) | (ContentItem.entity_attempts < self.entity_max_attempts))
                ).with_for_update(skip_locked=True).limit(10)

                result = await db.execute(stmt)
                all_items = result.scalars().all()

                if not all_items:
                    print("[OK] No entity extraction items needing retry")
                    return

                # Filter by exponential backoff
                items_to_retry = []
                now = datetime.utcnow()

                for item in all_items:
                    attempts = item.entity_attempts or 0
                    backoff_delay = self._calculate_exponential_backoff_delay(attempts, 2)

                    if item.last_entity_processed_at is None:
                        items_to_retry.append(item)
                    elif now >= (item.last_entity_processed_at + backoff_delay):
                        items_to_retry.append(item)

                items = items_to_retry[:3]  # Max 3 concurrent entity tasks

                if not items:
                    print("[OK] No entity items ready for retry (exponential backoff in effect)")
                    return

                print(f"Found {len(items)} entity extraction item(s) to retry:")
                for item in items:
                    attempts = item.entity_attempts or 0
                    print(f"  - {item.id}: {item.title[:50] if item.title else 'Untitled'} (attempt {attempts}/{self.entity_max_attempts})")

                await db.commit()

                # Process items
                from app.services.entity_extraction_service import extract_entities_for_content

                for i, item in enumerate(items):
                    if i > 0:
                        await asyncio.sleep(3)  # Rate limit between entity tasks

                    async def _process_entity(content_id):
                        async with AsyncSessionLocal() as entity_db:
                            await extract_entities_for_content(str(content_id), entity_db)

                    if self.entity_task_manager:
                        await self.entity_task_manager.create_task(_process_entity(item.id))
                    else:
                        asyncio.create_task(_process_entity(item.id))

                print(f"[OK] Scheduled {len(items)} entity extraction item(s) for retry")

            except Exception as e:
                print(f"[ERROR] Error retrying entity extraction: {e}")
                import traceback
                traceback.print_exc()

    async def run_health_checks(self):
        """Run proactive intelligence health checks for all eligible users."""
        try:
            from app.services.health_check_service import run_health_checks
            count = await run_health_checks()
            if count > 0:
                print(f"[HEALTH] Generated {count} proactive insight(s)")
        except Exception as e:
            print(f"[WARN] Health check cycle failed: {e}")

    async def compile_stale_wiki_pages(self):
        """
        Compile stale or draft wiki pages. Runs as part of the periodic cycle.
        Processes up to 2 pages per cycle to avoid overloading the AI provider.
        """
        try:
            from app.services.wiki_compiler_service import compile_stale_pages
            compiled = await compile_stale_pages(max_pages=5)
            if compiled > 0:
                print(f"[WIKI] Compiled {compiled} wiki page(s)")
        except Exception as e:
            print(f"[WARN] Wiki compilation cycle failed: {e}")

    async def create_missing_wiki_pages(self):
        """
        Safety net: find entities with 3+ mentions that don't have a wiki page yet
        and create draft pages for them. Catches any wikis missed by the inline check
        during entity extraction.
        """
        try:
            from app.db.session import AsyncSessionLocal
            from app.models.entity import Entity
            from app.models.wiki import WikiPage
            from sqlalchemy import select, and_

            async with AsyncSessionLocal() as db:
                # Find topic/concept entities with 2+ mentions that have no wiki page
                wiki_entity_ids = select(WikiPage.entity_id).where(WikiPage.entity_id.isnot(None))
                stmt = select(Entity).where(
                    and_(
                        Entity.mention_count >= 2,
                        Entity.entity_type.in_(['topic', 'concept']),
                        Entity.id.notin_(wiki_entity_ids)
                    )
                ).limit(5)

                result = await db.execute(stmt)
                entities = result.scalars().all()

                if not entities:
                    return

                from app.services.wiki_compiler_service import check_and_create_wiki_page
                created = 0
                for entity in entities:
                    try:
                        page = await check_and_create_wiki_page(
                            entity_id=str(entity.id),
                            user_id=str(entity.user_id),
                            db=db
                        )
                        if page:
                            created += 1
                    except Exception as e:
                        print(f"[WARN] Failed to create wiki for entity '{entity.name}': {e}")

                if created > 0:
                    print(f"[WIKI] Created {created} missing wiki page(s)")

                # Also expand search to include new entity types
                low_threshold_stmt = select(Entity).where(
                    and_(
                        Entity.mention_count >= 1,
                        Entity.entity_type.in_(['person', 'place', 'company', 'technology']),
                        Entity.id.notin_(wiki_entity_ids)
                    )
                ).limit(5)
                lt_result = await db.execute(low_threshold_stmt)
                lt_entities = lt_result.scalars().all()
                for entity in lt_entities:
                    try:
                        page = await check_and_create_wiki_page(
                            entity_id=str(entity.id),
                            user_id=str(entity.user_id),
                            db=db
                        )
                        if page:
                            created += 1
                    except Exception as e:
                        print(f"[WARN] Failed to create wiki for entity '{entity.name}': {e}")

        except Exception as e:
            print(f"[WARN] Missing wiki check failed: {e}")

    async def refresh_self_entities(self):
        """
        Refresh social profile data for users with self-entities.

        Queries users whose self-entity hasn't been refreshed within the
        configured interval and re-scrapes their social links.
        Processes max 5 users per cycle to avoid overloading.
        """
        try:
            from datetime import datetime, timedelta
            from sqlalchemy import or_
            from app.db.session import AsyncSessionLocal
            from app.models.user_preferences import UserPreferences as UserPreferencesModel
            from app.services.social_enrichment_service import enrich_self_entity

            refresh_threshold = datetime.utcnow() - timedelta(days=settings.social_refresh_interval_days)

            async with AsyncSessionLocal() as db:
                # Find users needing refresh
                stmt = select(UserPreferencesModel).where(
                    UserPreferencesModel.self_entity_id.isnot(None),
                    or_(
                        UserPreferencesModel.self_entity_last_refreshed_at.is_(None),
                        UserPreferencesModel.self_entity_last_refreshed_at < refresh_threshold,
                    )
                ).with_for_update(skip_locked=True).limit(5)

                result = await db.execute(stmt)
                prefs_list = result.scalars().all()

                if not prefs_list:
                    return

                print(f"[SOCIAL] Refreshing self-entities for {len(prefs_list)} user(s)")

                for prefs in prefs_list:
                    try:
                        await enrich_self_entity(
                            user_id=str(prefs.user_id),
                            db=db
                        )
                        # Rate limit between users
                        await asyncio.sleep(self.ai_rate_limit_delay)
                    except Exception as e:
                        print(f"[SOCIAL] Failed to refresh user {str(prefs.user_id)[:8]}: {e}")

        except Exception as e:
            print(f"[WARN] Social refresh cycle failed: {e}")

    async def retry_pending_items(self):
        """
        DEPRECATED: Use retry_pending_ingestion() and retry_pending_ai() instead.

        Kept for backwards compatibility during migration.
        """
        print("WARNING: Using deprecated retry_pending_items(). Update to use retry_pending_ingestion() and retry_pending_ai().")
        await self.retry_pending_ingestion()
        await self.retry_pending_ai()

    async def start_periodic_retry(self, interval_seconds: int = 30):
        """
        Start periodic retry task for BOTH ingestion and AI queues.

        Runs both retry queues in each cycle:
        1. Retry pending ingestion (fast, no rate limit)
        2. Retry pending AI (rate-limited between tasks)

        Args:
            interval_seconds: How often to check for items to retry (default: 30 seconds)
        """
        print(f"Starting periodic retry task (TWO-PHASE, interval: {interval_seconds}s)")
        self._running = True

        while self._running:
            try:
                await asyncio.sleep(interval_seconds)
                if self._running:  # Check again after sleep
                    # Run all three retry queues
                    await self.retry_pending_ingestion()
                    await self.retry_pending_ai()
                    await self.retry_pending_entities()
                    # Create wiki pages for entities that qualify but were missed
                    await self.create_missing_wiki_pages()
                    # Compile stale/draft wiki pages (every cycle, max 2 pages)
                    await self.compile_stale_wiki_pages()
                    # Run health checks roughly once per day (~2880 cycles at 30s)
                    self._health_check_cycle_count += 1
                    if self._health_check_cycle_count >= 2880:
                        self._health_check_cycle_count = 0
                        await self.run_health_checks()
                    # Refresh self-entity social profiles weekly
                    # Threshold based on config (default 7 days)
                    social_refresh_threshold = settings.social_refresh_interval_days * 2880
                    self._social_refresh_cycle_count += 1
                    if self._social_refresh_cycle_count >= social_refresh_threshold:
                        self._social_refresh_cycle_count = 0
                        await self.refresh_self_entities()
            except Exception as e:
                print(f"❌ Error in periodic retry task: {e}")
                import traceback
                traceback.print_exc()

    def stop_periodic_retry(self):
        """Stop the periodic retry task."""
        print("Stopping periodic retry task...")
        self._running = False


# Global instance with config values
background_processor = BackgroundProcessor(
    ingestion_max_attempts=settings.ingestion_max_retries,
    ai_max_attempts=settings.ai_max_retries,
    entity_max_attempts=getattr(settings, 'entity_max_retries', 3),
    ai_rate_limit_delay=settings.ai_rate_limit_delay
)
