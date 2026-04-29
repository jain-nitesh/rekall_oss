"""
Service for fetching content from JavaScript-heavy websites using Playwright.

This service handles platforms like Instagram, Pinterest, TikTok, etc. that require
JavaScript rendering to extract proper OpenGraph metadata.

Usage:
    fetcher = PlaywrightFetcher()
    metadata = await fetcher.fetch_url("https://www.instagram.com/p/ABC123/")
"""

from typing import Dict, Optional
from playwright.async_api import async_playwright, TimeoutError as PlaywrightTimeoutError
import logging

logger = logging.getLogger(__name__)


class PlaywrightFetcher:
    """
    Fetches content from JavaScript-heavy websites using a headless browser.

    This service is used when standard HTTP requests fail to retrieve proper
    metadata because the page requires JavaScript to render content.

    Instead of hardcoding platform lists, the ContentFetcherService
    dynamically detects when Playwright is needed based on metadata quality.
    """

    def __init__(self, pool: Optional["PlaywrightPool"] = None):
        """
        Initialize Playwright fetcher.

        Args:
            pool: Optional browser pool for reusing browser instances (performance optimization)
        """
        self.pool = pool

    async def fetch_url(self, url: str, timeout: int = 30000) -> Dict[str, Optional[str]]:
        """
        Fetch URL using headless browser and extract metadata.

        This method:
        1. Launches a headless Chromium browser
        2. Navigates to the URL
        3. Waits for the page to load
        4. Extracts OpenGraph and meta tags from the rendered HTML

        Args:
            url: The URL to fetch
            timeout: Maximum time to wait in milliseconds (default: 30s)

        Returns:
            Dictionary with extracted metadata:
            - title: Page title or og:title
            - description: Page description or og:description
            - thumbnail_url: og:image URL
            - site_name: og:site_name
            - type: og:type (article, video, etc.)

        Raises:
            Exception: If fetching fails or times out
        """
        # Increase timeout for Twitter/X specifically (they're slow to load)
        if 'twitter.com' in url or 'x.com' in url:
            timeout = 60000  # 60 seconds for Twitter/X
            logger.info(f"Detected Twitter/X URL, using extended timeout: {timeout}ms")

        logger.info(f"Starting Playwright fetch: {url}")
        logger.info(f"Timeout: {timeout}ms")

        # Use browser pool if available (performance optimization)
        if self.pool:
            logger.debug("Using browser pool")
            async with self.pool.acquire_browser() as browser:
                return await self._fetch_with_browser(browser, url, timeout)
        else:
            # Fallback: launch new browser for each request
            logger.debug("No pool available, launching new browser")
            async with async_playwright() as p:
                browser = await p.chromium.launch(headless=True)
                try:
                    return await self._fetch_with_browser(browser, url, timeout)
                finally:
                    await browser.close()

    async def _fetch_with_browser(self, browser, url: str, timeout: int) -> Dict[str, Optional[str]]:
        """
        Internal method to fetch URL using a provided browser instance.

        Args:
            browser: Playwright browser instance
            url: URL to fetch
            timeout: Timeout in milliseconds

        Returns:
            Dictionary with metadata
        """
        try:
            # Create new page with mobile viewport (some sites serve better metadata to mobile)
            page = await browser.new_page(
                user_agent='Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
                viewport={'width': 375, 'height': 667}  # iPhone viewport
            )

            # Navigate to URL with timeout
            try:
                logger.info(f"Navigating to URL...")
                await page.goto(url, wait_until='networkidle', timeout=timeout)
                logger.info(f"Page loaded successfully (networkidle)")
            except PlaywrightTimeoutError as e:
                logger.error(f"Playwright timeout for {url}: {str(e)}")
                logger.info(f"Timeout details: waited {timeout}ms")
                logger.warning(f"Continuing with partial content...")
                # Continue anyway - we might have enough content

            # Wait a bit for dynamic content to load
            logger.info(f"Waiting for dynamic content (2s)...")
            await page.wait_for_timeout(2000)  # 2 seconds

            # Extract metadata using JavaScript
            metadata = await page.evaluate('''() => {
                // Helper function to get meta tag content
                const getMeta = (property, attribute = 'property') => {
                    const tag = document.querySelector(`meta[${attribute}="${property}"]`);
                    return tag ? tag.getAttribute('content') : null;
                };

                // Extract OpenGraph and standard meta tags
                return {
                    og_title: getMeta('og:title'),
                    og_description: getMeta('og:description'),
                    og_image: getMeta('og:image'),
                    og_site_name: getMeta('og:site_name'),
                    og_type: getMeta('og:type'),
                    twitter_title: getMeta('twitter:title', 'name'),
                    twitter_description: getMeta('twitter:description', 'name'),
                    twitter_image: getMeta('twitter:image', 'name'),
                    meta_description: getMeta('description', 'name'),
                    page_title: document.title
                };
            }''')

            logger.info(f"Metadata extracted successfully")
            logger.info(f"  Title: {metadata.get('og_title') or metadata.get('twitter_title') or metadata.get('page_title', 'N/A')}")
            logger.info(f"  Has description: {bool(metadata.get('og_description') or metadata.get('twitter_description'))}")
            logger.info(f"  Has image: {bool(metadata.get('og_image') or metadata.get('twitter_image'))}")

            # Build response with fallback priority
            return {
                'title': (
                    metadata.get('og_title') or
                    metadata.get('twitter_title') or
                    metadata.get('page_title') or
                    'Untitled'
                ),
                'description': (
                    metadata.get('og_description') or
                    metadata.get('twitter_description') or
                    metadata.get('meta_description') or
                    None
                ),
                'thumbnail_url': (
                    metadata.get('og_image') or
                    metadata.get('twitter_image') or
                    None
                ),
                'site_name': metadata.get('og_site_name'),
                'type': metadata.get('og_type'),
            }

        finally:
            # Close the page to free resources
            # Note: Browser is managed by pool, so we don't close it here
            await page.close()

    async def fetch_with_fallback(self, url: str) -> Dict[str, Optional[str]]:
        """
        Fetch URL with error handling and fallback.

        If Playwright fails, returns minimal metadata extracted from URL.

        Args:
            url: The URL to fetch

        Returns:
            Dictionary with metadata (guaranteed to not raise exception)
        """
        try:
            return await self.fetch_url(url)
        except Exception as e:
            logger.error(f"Playwright fetch failed for {url}: {str(e)}")

            # Fallback: Extract minimal info from URL
            from urllib.parse import urlparse
            parsed = urlparse(url)
            path_parts = [p for p in parsed.path.split('/') if p]

            # Try to get a meaningful title from URL
            title = path_parts[-1] if path_parts else parsed.netloc
            title = title.replace('-', ' ').replace('_', ' ').title()

            return {
                'title': title,
                'description': None,
                'thumbnail_url': None,
                'site_name': parsed.netloc,
                'type': None,
            }
