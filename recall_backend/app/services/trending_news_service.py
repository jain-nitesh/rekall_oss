"""
Trending News Service — fetches real trending tech/AI news from Google News RSS
and uses AI to generate concise summaries.

Cache is in-memory and shared across all users. Refreshed every `news_cache_ttl_seconds`.
"""
import json
import time
import logging
from typing import Dict, List, Optional
from xml.etree import ElementTree

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

# In-memory cache (shared across all requests)
_cache: Optional[List[Dict]] = None
_cache_timestamp: float = 0.0

# Google News RSS URLs for tech/AI content
_RSS_FEEDS = [
    # Google News — Technology topic
    "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGRqTVhZU0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en",
    # Google News — AI search
    "https://news.google.com/rss/search?q=artificial+intelligence+trending&hl=en-US&gl=US&ceid=US:en",
]

# AI prompt to summarise fetched articles
_SUMMARIZE_PROMPT = (
    "Below are real news articles from RSS feeds. "
    "Pick the 5 most interesting and diverse stories. "
    "Return a JSON array where each item has: "
    "title (string, max 80 chars — rewrite for clarity), "
    "summary (string, max 120 chars — concise hook), "
    "url (string — use EXACTLY the url provided, do NOT change it), "
    "source (string — publication name from the source field). "
    "Return ONLY a valid JSON array, no explanation.\n\n"
    "Articles:\n{articles}"
)

# Static fallback when everything is unavailable
_FALLBACK_NEWS: List[Dict] = [
    {
        "title": "Getting Started: Share Your First Link",
        "summary": "Use the share button in any app to save content to ReKall. AI will summarize it automatically.",
        "url": "",
        "source": "ReKall Tips",
    },
    {
        "title": "Discover Hidden Connections",
        "summary": "ReKall finds surprising links between things you've saved. The more you share, the smarter it gets.",
        "url": "",
        "source": "ReKall Tips",
    },
    {
        "title": "Organize with Spaces",
        "summary": "Create Spaces to group content by topic and collaborate with friends or teammates.",
        "url": "",
        "source": "ReKall Tips",
    },
    {
        "title": "Search by Meaning",
        "summary": "Describe what you remember and AI search will find the right article — no exact keywords needed.",
        "url": "",
        "source": "ReKall Tips",
    },
    {
        "title": "Never Forget What You Read",
        "summary": "ReKall resurfaces content from 7 days, 30 days, and 1 year ago so great ideas stay fresh.",
        "url": "",
        "source": "ReKall Tips",
    },
]


async def get_trending_news() -> List[Dict]:
    """
    Return cached trending news, or fetch fresh news if cache is stale.

    Pipeline:
    1. Fetch real articles from Google News RSS (real URLs guaranteed)
    2. Optionally use AI to pick top 5 and write summaries
    3. Fall back to raw RSS items if AI is unavailable

    Returns a list of 5 news items, each with: title, summary, url, source.
    """
    global _cache, _cache_timestamp

    now = time.time()
    if _cache is not None and (now - _cache_timestamp) < settings.news_cache_ttl_seconds:
        return _cache

    try:
        # Step 1: Fetch real articles from RSS
        raw_articles = await _fetch_rss_articles()

        if not raw_articles:
            logger.warning("No articles fetched from RSS feeds")
            return _cache if _cache is not None else _FALLBACK_NEWS

        # Step 2: Use AI to pick and summarize (optional)
        news = None
        if settings.ai_enabled:
            try:
                news = await _summarize_with_ai(raw_articles)
            except Exception as e:
                logger.warning("AI summarization failed, using raw RSS: %s", e)

        # Step 3: Fall back to raw RSS articles (already have real URLs)
        if not news:
            news = raw_articles[:5]

        _cache = news[:5]
        _cache_timestamp = now
        logger.info("Trending news cache refreshed (%d items)", len(_cache))
        return _cache

    except Exception as e:
        logger.warning("Failed to fetch trending news: %s", e)

    # Return stale cache or fallback
    if _cache is not None:
        return _cache
    return _FALLBACK_NEWS


async def _fetch_rss_articles() -> List[Dict]:
    """Fetch real articles from Google News RSS feeds."""
    articles = []
    seen_urls = set()

    async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
        for feed_url in _RSS_FEEDS:
            try:
                resp = await client.get(feed_url, headers={
                    "User-Agent": "Mozilla/5.0 (compatible; ReKall/1.0)"
                })
                resp.raise_for_status()

                root = ElementTree.fromstring(resp.text)
                channel = root.find("channel")
                if channel is None:
                    continue

                for item in channel.findall("item"):
                    title = (item.findtext("title") or "").strip()
                    link = (item.findtext("link") or "").strip()
                    source_el = item.find("source")
                    source = source_el.text.strip() if source_el is not None and source_el.text else ""
                    description = (item.findtext("description") or "").strip()

                    # Clean description — Google News wraps in HTML
                    if "<" in description:
                        from bs4 import BeautifulSoup
                        description = BeautifulSoup(description, "html.parser").get_text(strip=True)

                    if not link or link in seen_urls:
                        continue

                    seen_urls.add(link)
                    articles.append({
                        "title": title[:80],
                        "summary": description[:120] if description else title[:120],
                        "url": link,
                        "source": source or "Google News",
                    })

                    if len(articles) >= 15:
                        break

            except Exception as e:
                logger.warning("Failed to fetch RSS feed %s: %s", feed_url, e)
                continue

            if len(articles) >= 15:
                break

    logger.info("Fetched %d real articles from RSS feeds", len(articles))
    return articles


async def _summarize_with_ai(articles: List[Dict]) -> List[Dict]:
    """Use AI to pick the best 5 articles and write concise summaries."""
    # Format articles for the prompt
    articles_text = "\n".join(
        f"- Title: {a['title']}\n  URL: {a['url']}\n  Source: {a['source']}\n  Description: {a['summary']}"
        for a in articles[:15]
    )

    prompt = _SUMMARIZE_PROMPT.format(articles=articles_text)

    if settings.is_openai:
        return await _summarize_openai(prompt)
    else:
        return await _summarize_ollama(prompt)


async def _summarize_openai(prompt: str) -> List[Dict]:
    from app.core.provider_manager import get_openai_provider

    provider = get_openai_provider()
    if provider.client is None:
        raise RuntimeError("OpenAI client not initialized")

    response = await provider.client.chat.completions.create(
        model=settings.openai_extraction_model,
        messages=[
            {"role": "system", "content": "You are a news curator. Pick the best articles and return valid JSON. NEVER modify the URLs — use them exactly as provided."},
            {"role": "user", "content": prompt},
        ],
        max_tokens=600,
        temperature=0.3,
    )

    text = response.choices[0].message.content.strip()
    return _parse_response(text)


async def _summarize_ollama(prompt: str) -> List[Dict]:
    import ollama

    response = ollama.chat(
        model=settings.ollama_extraction_model,
        messages=[
            {"role": "system", "content": "You are a news curator. Pick the best articles and return valid JSON. NEVER modify the URLs — use them exactly as provided."},
            {"role": "user", "content": prompt},
        ],
        options={"temperature": 0.3},
    )

    text = response["message"]["content"].strip()
    return _parse_response(text)


def _parse_response(text: str) -> List[Dict]:
    """Parse AI response into a list of news dicts. Handles markdown fences."""
    if text.startswith("```"):
        text = text.split("\n", 1)[-1]
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()

    data = json.loads(text)
    if not isinstance(data, list):
        raise ValueError("Expected JSON array")

    result = []
    for item in data[:5]:
        url = str(item.get("url", "")).strip()
        if not url:
            continue
        result.append({
            "title": str(item.get("title", ""))[:80],
            "summary": str(item.get("summary", ""))[:120],
            "url": url,
            "source": str(item.get("source", "")),
        })
    return result
