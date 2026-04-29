"""
Service for fetching URL content and extracting metadata.

For beginners:
- This service fetches web pages and extracts useful information
- Uses httpx for async HTTP requests (like requests but async)
- Uses BeautifulSoup for HTML parsing (extracting title, description, etc.)
- Uses Playwright for JavaScript-heavy sites (Instagram, Pinterest, etc.)
- Phase 2: Basic extraction without AI
- Phase 3: Will add AI-powered extraction
"""
import httpx
import re
from bs4 import BeautifulSoup
from typing import Optional, Dict, List
from urllib.parse import urlparse, parse_qsl, urlencode, urlunparse
import logging

from .playwright_fetcher import PlaywrightFetcher
from ..utils.title_cleaner import clean_title
from ..utils.playwright_detector import JS_HEAVY_DOMAINS
from ..utils.url_validator import validate_url_or_raise
from ..core.config import settings

logger = logging.getLogger(__name__)


class ContentFetcherService:
    """
    Service for fetching and parsing web content.

    Responsibilities:
    - Fetch HTML from URLs
    - Extract metadata (title, description, thumbnail)
    - Extract main text content
    - Handle errors gracefully
    """

    def __init__(self, playwright_pool: Optional["PlaywrightPool"] = None, selective_mode: bool = False):
        """
        Initialize content fetcher.

        Args:
            playwright_pool: Optional browser pool for performance optimization
            selective_mode: If True, only use Playwright for known JS-heavy domains
        """
        self.playwright_pool = playwright_pool
        self.selective_mode = selective_mode

    @staticmethod
    def _domain_matches(domain: str, configured_domains: set[str]) -> bool:
        """Return True if domain matches configured domain or its subdomain."""
        return domain in configured_domains or any(domain.endswith('.' + base_domain) for base_domain in configured_domains)

    def _requires_playwright_for_url(self, url: str) -> bool:
        """
        Determine Playwright usage with configurable domain policies.

        Priority:
        1. PLAYWRIGHT_SKIP_DOMAINS => always False
        2. PLAYWRIGHT_FORCE_DOMAINS => always True
        3. Built-in JS-heavy domains => True
        """
        try:
            domain = urlparse(url).netloc.lower().replace('www.', '')
            skip_domains = set(settings.playwright_skip_domains_list)
            force_domains = set(settings.playwright_force_domains_list)
            default_domains = {d.replace('www.', '') for d in JS_HEAVY_DOMAINS}

            if self._domain_matches(domain, skip_domains):
                return False
            if self._domain_matches(domain, force_domains):
                return True
            return self._domain_matches(domain, default_domains)
        except Exception:
            return False

    def _is_playwright_skipped_for_url(self, url: str) -> bool:
        """Return True if URL domain is configured to skip Playwright."""
        try:
            domain = urlparse(url).netloc.lower().replace('www.', '')
            skip_domains = set(settings.playwright_skip_domains_list)
            return self._domain_matches(domain, skip_domains)
        except Exception:
            return False

    @staticmethod
    def _is_myntra_url(url: str) -> bool:
        """Check if URL belongs to Myntra."""
        try:
            domain = urlparse(url).netloc.lower().replace('www.', '')
            return domain == 'myntra.com' or domain.endswith('.myntra.com')
        except Exception:
            return False

    @staticmethod
    def _looks_like_maintenance_page(result: Dict[str, Optional[str]]) -> bool:
        """Detect common maintenance/interstitial responses."""
        content = " ".join([
            str(result.get('title') or ''),
            str(result.get('description') or ''),
            str(result.get('main_content') or ''),
        ]).lower()
        markers = [
            'site maintenance',
            'oops! something went wrong',
            'please contact your administrator',
            'contact your administrator',
            'please wait for verification',
        ]
        return any(marker in content for marker in markers)

    @staticmethod
    def _build_myntra_clean_url(url: str) -> str:
        """
        Create a cleaner Myntra URL by dropping tracking params and trailing /buy.
        This avoids deeplink/interstitial variants that sometimes return maintenance pages.
        """
        parsed = urlparse(url)
        path = parsed.path[:-4] if parsed.path.endswith('/buy') else parsed.path
        filtered_query = [
            (k, v) for k, v in parse_qsl(parsed.query, keep_blank_values=True)
            if not k.lower().startswith('utm_') and k.lower() not in {'shared'}
        ]
        clean_query = urlencode(filtered_query, doseq=True)
        return urlunparse((parsed.scheme, parsed.netloc, path, parsed.params, clean_query, parsed.fragment))

    @staticmethod
    def is_twitter_url(url: str) -> bool:
        """Check if URL is a Twitter/X post URL."""
        try:
            parsed = urlparse(url)
            domain = parsed.netloc.lower().replace('www.', '')
            return domain in ('twitter.com', 'x.com', 't.co')
        except Exception:
            return False

    async def fetch_twitter_oembed(self, url: str) -> Optional[Dict[str, Optional[str]]]:
        """
        Fetch tweet content via Twitter's free oEmbed API.

        Returns metadata dict on success, None on failure.
        The oEmbed endpoint requires no authentication and returns
        the tweet text, author name, and author URL.
        """
        oembed_url = f"https://publish.twitter.com/oembed?url={url}"
        try:
            async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
                response = await client.get(oembed_url)
                response.raise_for_status()
                data = response.json()

            # Extract clean text from the HTML blockquote
            html = data.get('html', '')
            soup = BeautifulSoup(html, 'html.parser')
            # The tweet text is inside the <p> tag within the blockquote
            p_tag = soup.find('p')
            tweet_text = p_tag.get_text(separator=' ').strip() if p_tag else ''

            author_name = data.get('author_name', '')
            author_url = data.get('author_url', '')

            # Build a clean title: "Author: first ~80 chars of tweet"
            if tweet_text:
                title_text = tweet_text[:80] + ('...' if len(tweet_text) > 80 else '')
                title = f"{author_name}: {title_text}" if author_name else title_text
            else:
                title = f"Post by {author_name}" if author_name else 'Twitter Post'

            # Build description with full tweet text
            description = tweet_text if tweet_text else f"Post by {author_name}"

            # Main content combines author + tweet for AI processing
            main_content = f"{author_name} (@{author_url.split('/')[-1] if author_url else ''}): {tweet_text}"

            logger.info(f"oEmbed fetched tweet by {author_name}: {tweet_text[:100]}")

            return {
                'error_type': 'none',
                'title': title,
                'description': description,
                'thumbnail_url': None,
                'main_content': main_content,
                'meta_keywords': [],
                'meta_tags': [],
                'og_tags': {
                    'site_name': 'X (Twitter)',
                    'type': 'article',
                    'title': title,
                    'description': description,
                },
            }

        except Exception as e:
            logger.warning(f"oEmbed fetch failed for {url}: {e}")
            return None

    async def fetch_url(self, url: str) -> Dict[str, Optional[str]]:
        """
        Fetch URL and extract basic metadata.

        Uses intelligent detection: tries HTTP first, then automatically retries
        with Playwright if metadata quality is poor (e.g., title looks like content ID).

        Returns a dictionary with:
        - title: Page title
        - description: Meta description or first paragraph
        - thumbnail_url: Open Graph image
        - main_content: Main text content (first 5000 chars)

        Args:
            url: The URL to fetch

        Returns:
            Dictionary with extracted metadata

        Raises:
            ValueError: If URL is unsafe (SSRF protection)
            httpx.HTTPError: If request fails
        """
        # Security: Validate URL to prevent SSRF attacks
        validate_url_or_raise(url)

        # Twitter/X: Use oEmbed API (free, no auth, returns actual tweet text)
        if self.is_twitter_url(url):
            logger.info(f"Twitter/X URL detected, trying oEmbed: {url}")
            oembed_result = await self.fetch_twitter_oembed(url)
            if oembed_result:
                return oembed_result
            logger.info(f"oEmbed failed, falling back to standard fetch")

        # Selective mode: Only use Playwright for known JS-heavy domains
        if self.selective_mode and self._requires_playwright_for_url(url):
            logger.info(f"Selective mode: Known JS-heavy domain detected, using Playwright: {url}")
            result = await self._fetch_with_playwright(url)
        else:
            # Always try HTTP first (fast, works for 80% of sites)
            logger.info(f"Fetching URL with HTTP: {url}")
            result = await self._fetch_with_httpx(url)

            # Myntra can intermittently return maintenance/interstitial pages.
            # Retry once with a cleaned URL variant before AI processing.
            if self._is_myntra_url(url) and self._looks_like_maintenance_page(result):
                clean_url = self._build_myntra_clean_url(url)
                if clean_url != url:
                    logger.info(f"Myntra maintenance-like response detected, retrying with cleaned URL: {clean_url}")
                    clean_result = await self._fetch_with_httpx(clean_url)
                    if not self._looks_like_maintenance_page(clean_result):
                        result = clean_result

            # Check if metadata quality is poor (indicates JS rendering needed)
            # Skip this check in selective mode to save resources
            if not self.selective_mode and self._needs_playwright_retry(result, url):
                if self._is_playwright_skipped_for_url(url):
                    logger.info(f"Playwright retry skipped by domain policy: {url}")
                    return result
                logger.info(f"Poor metadata quality detected, retrying with Playwright: {url}")
                logger.info(f"  HTTP title: '{result.get('title')}'")
                result = await self._fetch_with_playwright(url)

        # Clean up title (remove verbose prefixes, truncate, remove hashtags)
        raw_title = result.get('title', '')
        cleaned_title = clean_title(raw_title, url)

        if cleaned_title != raw_title:
            logger.info(f"Title cleaned: '{raw_title[:100]}...' → '{cleaned_title}'")

        result['title'] = cleaned_title

        logger.info(f"Final title: '{result.get('title')}'")
        return result

    async def _fetch_with_httpx(self, url: str) -> Dict[str, Optional[str]]:
        """
        Fetch URL using standard HTTP client (for regular websites).

        Args:
            url: The URL to fetch

        Returns:
            Dictionary with extracted metadata + error_type field
        """
        try:
            # Create async HTTP client
            # timeout=30.0: Wait up to 30 seconds for response
            # follow_redirects=True: Automatically follow 301/302 redirects
            async with httpx.AsyncClient(
                timeout=30.0,
                follow_redirects=True,
                headers={
                    # Set User-Agent to avoid being blocked by some sites
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            ) as client:
                # Fetch the URL
                response = await client.get(url)

                # DETECTION LOGIC 1: Check status codes BEFORE raise_for_status()
                if response.status_code in [401, 403]:
                    # Auth required status codes
                    logger.info(f"Auth required for {url}: HTTP {response.status_code}")
                    return {
                        'error_type': 'auth_required',
                        'error_message': f'Authentication required (HTTP {response.status_code})',
                        'title': None,
                        'description': None,
                        'thumbnail_url': None,
                        'main_content': None,
                        'meta_keywords': [],
                        'meta_tags': [],
                        'og_tags': {},
                    }

                # DETECTION LOGIC 2: Check if redirect chain led to login page
                if len(response.history) > 0:
                    final_url = str(response.url)
                    auth_patterns = [
                        'login', 'signin', 'sign-in', 'auth', 'oauth',
                        'authenticate', 'sso', 'account/login'
                    ]
                    if any(pattern in final_url.lower() for pattern in auth_patterns):
                        logger.info(f"Detected login page redirect: {url} → {final_url}")
                        return {
                            'error_type': 'auth_required',
                            'error_message': f'Redirected to login page: {final_url}',
                            'title': None,
                            'description': None,
                            'thumbnail_url': None,
                            'main_content': None,
                            'meta_keywords': [],
                            'meta_tags': [],
                            'og_tags': {},
                        }

                # Check other status codes
                if response.status_code == 404:
                    return {
                        'error_type': 'not_found',
                        'error_message': 'Page not found',
                        'title': None,
                        'description': None,
                        'thumbnail_url': None,
                        'main_content': None,
                        'meta_keywords': [],
                        'meta_tags': [],
                        'og_tags': {},
                    }
                elif response.status_code >= 500:
                    return {
                        'error_type': 'server_error',
                        'error_message': f'Server error ({response.status_code})',
                        'title': None,
                        'description': None,
                        'thumbnail_url': None,
                        'main_content': None,
                        'meta_keywords': [],
                        'meta_tags': [],
                        'og_tags': {},
                    }

                response.raise_for_status()  # Raise error if other 4xx or 5xx status

                # Parse HTML with BeautifulSoup
                # 'html.parser' is Python's built-in parser (reliable, no extra dependencies)
                soup = BeautifulSoup(response.text, 'html.parser')

                # Extract all metadata
                og_tags = self._extract_opengraph_tags(soup)
                return {
                    'error_type': 'none',  # Success
                    'title': self._extract_title(soup, url),
                    'description': self._extract_description(soup),
                    'thumbnail_url': self._extract_og_image(soup),
                    'main_content': self._extract_text_content(soup),
                    'meta_keywords': self._extract_meta_keywords(soup),
                    'meta_tags': self._extract_meta_tags(soup),
                    'og_tags': og_tags,
                }

        except httpx.TimeoutException as e:
            logger.error(f"Timeout fetching {url}: {str(e)}")
            return {
                'error_type': 'network',
                'error_message': f'Request timeout: {str(e)}',
                'title': None,
                'description': None,
                'thumbnail_url': None,
                'main_content': None,
                'meta_keywords': [],
                'meta_tags': [],
                'og_tags': {},
            }
        except httpx.NetworkError as e:
            logger.error(f"Network error fetching {url}: {str(e)}")
            return {
                'error_type': 'network',
                'error_message': f'Network error: {str(e)}',
                'title': None,
                'description': None,
                'thumbnail_url': None,
                'main_content': None,
                'meta_keywords': [],
                'meta_tags': [],
                'og_tags': {},
            }
        except httpx.HTTPStatusError as e:
            # This catches errors from raise_for_status()
            if e.response.status_code in [401, 403]:
                return {
                    'error_type': 'auth_required',
                    'error_message': f'Authentication required (HTTP {e.response.status_code})',
                    'title': None,
                    'description': None,
                    'thumbnail_url': None,
                    'main_content': None,
                    'meta_keywords': [],
                    'meta_tags': [],
                    'og_tags': {},
                }
            elif e.response.status_code == 404:
                return {
                    'error_type': 'not_found',
                    'error_message': 'Page not found',
                    'title': None,
                    'description': None,
                    'thumbnail_url': None,
                    'main_content': None,
                    'meta_keywords': [],
                    'meta_tags': [],
                    'og_tags': {},
                }
            elif e.response.status_code == 429:
                return {
                    'error_type': 'blocked',
                    'error_message': 'Rate limited',
                    'title': None,
                    'description': None,
                    'thumbnail_url': None,
                    'main_content': None,
                    'meta_keywords': [],
                    'meta_tags': [],
                    'og_tags': {},
                }
            else:
                return {
                    'error_type': 'other',
                    'error_message': str(e),
                    'title': None,
                    'description': None,
                    'thumbnail_url': None,
                    'main_content': None,
                    'meta_keywords': [],
                    'meta_tags': [],
                    'og_tags': {},
                }
        except Exception as e:
            logger.error(f"Unexpected error fetching {url}: {str(e)}")
            return {
                'error_type': 'other',
                'error_message': str(e),
                'title': None,
                'description': None,
                'thumbnail_url': None,
                'main_content': None,
                'meta_keywords': [],
                'meta_tags': [],
                'og_tags': {},
            }

    async def _fetch_with_playwright(self, url: str) -> Dict[str, Optional[str]]:
        """
        Fetch URL using Playwright headless browser (for JavaScript-heavy sites).

        This method is used for platforms like Instagram, Pinterest, TikTok, etc.
        that require JavaScript to render OpenGraph tags.

        Args:
            url: The URL to fetch

        Returns:
            Dictionary with extracted metadata
        """
        playwright_fetcher = PlaywrightFetcher(pool=self.playwright_pool)

        try:
            # Fetch with Playwright (strict mode). If transport fails, fall back to HTTP.
            playwright_result = await playwright_fetcher.fetch_url(url)

            logger.info(f"Playwright extracted title: {playwright_result.get('title')}")

            # Return in the same format as httpx fetch
            return {
                'title': playwright_result.get('title', 'Untitled'),
                'description': playwright_result.get('description'),
                'thumbnail_url': playwright_result.get('thumbnail_url'),
                'main_content': playwright_result.get('description', ''),  # Use description as content
                'meta_keywords': [],  # Playwright doesn't extract these separately
                'meta_tags': [],
                'og_tags': {
                    'title': playwright_result.get('title'),
                    'description': playwright_result.get('description'),
                    'image': playwright_result.get('thumbnail_url'),
                    'site_name': playwright_result.get('site_name'),
                    'type': playwright_result.get('type'),
                },
            }

        except Exception as e:
            logger.error(f"Playwright fetch failed for {url}: {str(e)}")
            # Fallback to httpx if Playwright fails
            logger.info("Falling back to standard HTTP fetch")
            return await self._fetch_with_httpx(url)

    def _needs_playwright_retry(self, result: Dict[str, Optional[str]], url: str) -> bool:
        """
        Determine if we should retry with Playwright based on metadata quality.

        Indicators of poor metadata (JavaScript rendering needed):
        1. Title looks like a content ID (short alphanumeric string)
        2. Title matches URL path segment (fallback was used)
        3. Missing OpenGraph metadata entirely
        4. Description is generic fallback message
        5. Title is generic/unhelpful

        Args:
            result: Result from HTTP fetch
            url: Original URL

        Returns:
            True if we should retry with Playwright
        """
        title = (result.get('title') or '').strip()
        description = (result.get('description') or '').strip()
        og_tags = result.get('og_tags', {})

        # Extract last URL segment for comparison
        url_segments = [s for s in url.split('/') if s and s not in ['http:', 'https:']]
        last_segment = url_segments[-1] if url_segments else ''

        # Indicator 1: Title looks like content ID (short alphanumeric, possibly with hyphens/underscores)
        # Examples: "C12345abcd", "p-ABC123", "123456789"
        clean_title = title.replace('-', '').replace('_', '').replace(' ', '')
        if len(title) < 20 and clean_title.isalnum() and not title.lower().startswith('http'):
            logger.debug(f"Title looks like content ID: '{title}'")
            return True

        # Indicator 2: Title matches last URL segment (fallback extraction was used)
        # This means we failed to get og:title or <title>, so we parsed the URL
        if last_segment:
            # Compare normalized versions
            normalized_title = title.lower().replace(' ', '').replace('-', '').replace('_', '')
            normalized_segment = last_segment.lower().replace('-', '').replace('_', '')
            if normalized_title == normalized_segment:
                logger.debug(f"Title matches URL segment: '{title}' ~ '{last_segment}'")
                return True

        # Indicator 3: Missing OpenGraph title (but URL suggests social media)
        # Social media platforms should always have og:title
        social_indicators = settings.playwright_retry_social_domains_list
        is_social_media = any(domain in url.lower() for domain in social_indicators)

        if is_social_media and not og_tags.get('title'):
            logger.debug(f"Social media URL missing og:title")
            return True

        # Indicator 4: Description is generic fallback
        if description == "No description available.":
            # If description is fallback AND title is short, probably needs JS
            if len(title) < 30:
                logger.debug(f"Generic description with short title")
                return True

        # Indicator 5: Title is "Untitled" (total extraction failure)
        if title.lower() in ['untitled', 'no title', '']:
            logger.debug(f"Title is generic or empty: '{title}'")
            return True

        # If we got here, metadata quality seems acceptable
        return False

    def _extract_title(self, soup: BeautifulSoup, fallback_url: str) -> str:
        """
        Extract page title from HTML.

        Priority order:
        1. Open Graph title (og:title) - used by social media
        2. Regular <title> tag
        3. Fallback to last part of URL

        Example:
            <meta property="og:title" content="Article Title" />
            <title>Article Title - Site Name</title>
        """
        # Try Open Graph title first (most accurate)
        og_title = soup.find('meta', property='og:title')
        if og_title and og_title.get('content'):
            return og_title['content'].strip()

        # Try regular title tag
        if soup.title and soup.title.string:
            return soup.title.string.strip()

        # Fallback: use last part of URL
        # Example: "https://example.com/my-article" → "my article"
        return fallback_url.split('/')[-1].replace('-', ' ').replace('_', ' ').title()

    def _extract_description(self, soup: BeautifulSoup) -> str:
        """
        Extract page description.

        Priority order:
        1. Open Graph description (og:description)
        2. Meta description tag
        3. First paragraph text
        4. Fallback message

        Example:
            <meta property="og:description" content="Article summary..." />
            <meta name="description" content="Article summary..." />
        """
        # Try Open Graph description
        og_desc = soup.find('meta', property='og:description')
        if og_desc and og_desc.get('content'):
            return og_desc['content'].strip()

        # Try meta description
        meta_desc = soup.find('meta', attrs={'name': 'description'})
        if meta_desc and meta_desc.get('content'):
            return meta_desc['content'].strip()

        # Try first paragraph
        first_p = soup.find('p')
        if first_p and first_p.string:
            return first_p.string.strip()

        return "No description available."

    def _extract_og_image(self, soup: BeautifulSoup) -> Optional[str]:
        """
        Extract thumbnail image URL.

        Priority order:
        1. Open Graph image (og:image)
        2. Twitter image (twitter:image)
        3. None

        Example:
            <meta property="og:image" content="https://example.com/image.jpg" />
        """
        # Try Open Graph image
        og_image = soup.find('meta', property='og:image')
        if og_image and og_image.get('content'):
            return og_image['content']

        # Try Twitter image
        twitter_image = soup.find('meta', attrs={'name': 'twitter:image'})
        if twitter_image and twitter_image.get('content'):
            return twitter_image['content']

        return None

    def _extract_text_content(self, soup: BeautifulSoup) -> str:
        """
        Extract main text content from page.

        Process:
        1. Remove script and style tags (they're not content)
        2. Get all text
        3. Clean up whitespace
        4. Limit to first 5000 characters

        This is used for:
        - Phase 2: Basic categorization
        - Phase 3: AI summarization and embedding

        Returns:
            Cleaned text content
        """
        # Remove script and style elements (not user-visible content)
        for script in soup(['script', 'style', 'nav', 'header', 'footer']):
            script.decompose()

        # Get all text
        text = soup.get_text()

        # Clean up whitespace
        # Split by newlines, strip each line, remove empty lines
        lines = (line.strip() for line in text.splitlines())

        # Split by multiple spaces, strip each chunk
        chunks = (phrase.strip() for line in lines for phrase in line.split("  "))

        # Join back together, removing empty chunks
        text = ' '.join(chunk for chunk in chunks if chunk)

        # Limit to first 5000 characters (enough for categorization/summarization)
        return text[:5000]

    def _extract_meta_keywords(self, soup: BeautifulSoup) -> List[str]:
        """
        Extract keywords from HTML meta tags.

        Priority order:
        1. Meta keywords tag (name="keywords")
        2. Open Graph keywords (property="og:keywords")
        3. Article tags (property="article:tag" and og:article:tag)
        4. Empty list if none found

        Example:
            <meta name="keywords" content="python, programming, tutorial" />
            <meta property="og:keywords" content="python, programming" />
            <meta property="article:tag" content="python" />
            <meta property="og:article:tag" content="python" />
        """
        keywords = []

        # Try meta keywords tag
        meta_keywords = soup.find('meta', attrs={'name': 'keywords'})
        if meta_keywords and meta_keywords.get('content'):
            keywords_str = meta_keywords['content'].strip()
            # Split by comma and clean
            keywords.extend([kw.strip().lower() for kw in keywords_str.split(',') if kw.strip()])

        # Try Open Graph keywords
        og_keywords = soup.find('meta', property='og:keywords')
        if og_keywords and og_keywords.get('content'):
            keywords_str = og_keywords['content'].strip()
            keywords.extend([kw.strip().lower() for kw in keywords_str.split(',') if kw.strip()])

        # Try article tags (multiple tags possible) - both standard and OpenGraph
        article_tags = soup.find_all('meta', property='article:tag')
        for tag in article_tags:
            if tag.get('content'):
                keywords.append(tag['content'].strip().lower())

        # Try OpenGraph article tags
        og_article_tags = soup.find_all('meta', property='og:article:tag')
        for tag in og_article_tags:
            if tag.get('content'):
                keywords.append(tag['content'].strip().lower())

        # Remove duplicates while preserving order
        seen = set()
        unique_keywords = []
        for kw in keywords:
            if kw and kw not in seen:
                seen.add(kw)
                unique_keywords.append(kw)

        return unique_keywords[:10]  # Limit to 10 keywords

    def _extract_meta_tags(self, soup: BeautifulSoup) -> List[str]:
        """
        Extract tags from various HTML meta tags and attributes.

        Sources:
        1. Article tags (article:tag and og:article:tag)
        2. Twitter card tags
        3. Schema.org tags
        4. OpenGraph article tags

        Returns:
            List of tag strings
        """
        tags = []

        # Get article tags (standard)
        article_tags = soup.find_all('meta', property='article:tag')
        for tag in article_tags:
            if tag.get('content'):
                tags.append(tag['content'].strip().lower())

        # Get OpenGraph article tags
        og_article_tags = soup.find_all('meta', property='og:article:tag')
        for tag in og_article_tags:
            if tag.get('content'):
                tags.append(tag['content'].strip().lower())

        # Get Twitter card tags
        twitter_tags = soup.find_all('meta', attrs={'name': lambda x: x and 'twitter:tag' in x.lower()})
        for tag in twitter_tags:
            if tag.get('content'):
                tags.append(tag['content'].strip().lower())

        # Try to find tags in schema.org markup
        schema_tags = soup.find_all(attrs={'itemprop': 'keywords'})
        for tag_elem in schema_tags:
            if tag_elem.get('content'):
                tags.append(tag_elem['content'].strip().lower())
            elif tag_elem.string:
                tags.append(tag_elem.string.strip().lower())

        # Remove duplicates while preserving order
        seen = set()
        unique_tags = []
        for tag in tags:
            if tag and tag not in seen:
                seen.add(tag)
                unique_tags.append(tag)

        return unique_tags[:10]  # Limit to 10 tags

    def _extract_opengraph_tags(self, soup: BeautifulSoup) -> Dict[str, Optional[str]]:
        """
        Extract comprehensive OpenGraph metadata.

        Extracts all relevant OpenGraph tags including:
        - og:title, og:description, og:image (already used elsewhere)
        - og:type, og:url, og:site_name
        - og:article:tag, og:article:author, og:article:published_time, og:article:section
        - og:locale, og:video, og:audio

        Returns:
            Dictionary with OpenGraph tag values
        """
        og_tags = {}

        # Basic OpenGraph tags
        og_properties = [
            'og:title', 'og:description', 'og:image', 'og:url', 'og:type',
            'og:site_name', 'og:locale', 'og:video', 'og:audio'
        ]

        for prop in og_properties:
            meta = soup.find('meta', property=prop)
            if meta and meta.get('content'):
                # Store without 'og:' prefix for cleaner keys
                key = prop.replace('og:', '')
                og_tags[key] = meta['content'].strip()

        # Article-specific OpenGraph tags
        article_properties = [
            'og:article:tag', 'og:article:author', 'og:article:published_time',
            'og:article:modified_time', 'og:article:section', 'og:article:expiration_time'
        ]

        for prop in article_properties:
            # Some article tags can appear multiple times (like tags)
            if prop == 'og:article:tag':
                # Collect all article tags
                article_tags = soup.find_all('meta', property=prop)
                if article_tags:
                    tags_list = [tag['content'].strip().lower() for tag in article_tags if tag.get('content')]
                    if tags_list:
                        og_tags['article_tags'] = tags_list
            else:
                meta = soup.find('meta', property=prop)
                if meta and meta.get('content'):
                    # Store without 'og:article:' prefix
                    key = prop.replace('og:article:', '')
                    og_tags[key] = meta['content'].strip()

        return og_tags
