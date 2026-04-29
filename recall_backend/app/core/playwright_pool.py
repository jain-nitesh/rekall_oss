"""
Playwright Browser Pool Manager.

Manages a pool of browser instances to avoid the overhead of launching
a new browser for each request. Significant performance improvement for
social media URL fetching.
"""
import asyncio
import logging
from typing import List, Optional
from contextlib import asynccontextmanager
from playwright.async_api import async_playwright, Browser, Playwright

logger = logging.getLogger(__name__)


class PlaywrightPool:
    """
    Pool of Playwright browser instances.

    Benefits:
    - Reuses browsers instead of launching new ones (2-5s saved per request)
    - Limits concurrent browser instances (memory control)
    - Graceful cleanup on shutdown
    """

    def __init__(self, pool_size: int = 2):
        """
        Initialize browser pool.

        Args:
            pool_size: Number of browser instances to maintain (default: 2)
                      2 is optimal for 512MB RAM servers
        """
        self.pool_size = pool_size
        self.playwright: Optional[Playwright] = None
        self.browsers: List[Browser] = []
        self.semaphore = asyncio.Semaphore(pool_size)
        self._initialized = False
        self._current_index = 0  # For round-robin selection

        logger.info(f"PlaywrightPool created with pool_size={pool_size}")

    async def initialize(self):
        """
        Initialize the browser pool.
        Launches all browser instances.
        """
        if self._initialized:
            logger.warning("PlaywrightPool already initialized")
            return

        logger.info("Initializing Playwright browser pool...")

        try:
            # Start playwright
            self.playwright = await async_playwright().start()

            # Launch browser instances
            for i in range(self.pool_size):
                browser = await self.playwright.chromium.launch(
                    headless=True,
                    args=[
                        '--disable-dev-shm-usage',  # Avoid shared memory issues
                        '--no-sandbox',             # Required for some environments
                        '--disable-gpu',            # Reduce GPU memory usage
                        '--disable-software-rasterizer',  # Reduce rendering memory
                        '--disable-extensions',     # No extension overhead
                        '--disable-background-networking',  # Reduce background activity
                        '--disable-background-timer-throttling',
                        '--disable-backgrounding-occluded-windows',
                        '--disable-renderer-backgrounding',
                        '--max-old-space-size=512',  # Limit V8 heap to 512MB
                    ]
                )
                self.browsers.append(browser)
                logger.info(f"Browser {i+1}/{self.pool_size} launched")

            self._initialized = True
            logger.info(f"PlaywrightPool initialized successfully ({self.pool_size} browsers)")

        except Exception as e:
            logger.error(f"Failed to initialize PlaywrightPool: {e}", exc_info=True)
            await self.cleanup()
            raise

    @asynccontextmanager
    async def acquire_browser(self):
        """
        Acquire a browser from the pool.

        Returns a context manager that provides a browser instance.
        Uses semaphore to limit concurrent browser usage.

        Usage:
            async with pool.acquire_browser() as browser:
                page = await browser.new_page()
                await page.goto('https://example.com')
                await page.close()
        """
        # Wait for available slot
        await self.semaphore.acquire()

        try:
            # Ensure pool is initialized
            if not self._initialized:
                await self.initialize()

            # Round-robin browser selection
            browser = self.browsers[self._current_index]
            self._current_index = (self._current_index + 1) % self.pool_size

            logger.debug(f"Browser acquired (available: {self.semaphore._value}/{self.pool_size})")

            yield browser

        finally:
            self.semaphore.release()
            logger.debug(f"Browser released (available: {self.semaphore._value}/{self.pool_size})")

    async def cleanup(self):
        """
        Cleanup browser pool.
        Closes all browsers and stops playwright.
        """
        if not self._initialized and not self.browsers and not self.playwright:
            logger.info("PlaywrightPool not initialized, nothing to cleanup")
            return

        logger.info("Cleaning up Playwright browser pool...")

        # Close all browsers
        for i, browser in enumerate(self.browsers):
            try:
                await browser.close()
                logger.info(f"Browser {i+1}/{len(self.browsers)} closed")
            except Exception as e:
                logger.error(f"Error closing browser {i+1}: {e}")

        self.browsers.clear()

        # Stop playwright
        if self.playwright:
            try:
                await self.playwright.stop()
                logger.info("Playwright stopped")
            except Exception as e:
                logger.error(f"Error stopping playwright: {e}")

        self.playwright = None
        self._initialized = False

        logger.info("PlaywrightPool cleanup complete")

    def get_stats(self) -> dict:
        """
        Get current pool statistics.

        Returns:
            Dictionary with stats:
            {
                'initialized': bool,
                'pool_size': int,
                'browsers_active': int,
                'available_slots': int
            }
        """
        return {
            'initialized': self._initialized,
            'pool_size': self.pool_size,
            'browsers_active': len(self.browsers),
            'available_slots': self.semaphore._value
        }
