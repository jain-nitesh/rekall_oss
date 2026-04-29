"""
Query understanding service for natural language search.
Transforms user queries like "that pasta place last week" into structured search intents.
"""
import json
import logging
from dataclasses import dataclass
from typing import Optional, List

from app.core.config import settings

logger = logging.getLogger(__name__)


@dataclass
class ParsedQuery:
    """Structured representation of a natural language search query."""
    refined_query: str  # Semantically enriched query for embedding
    content_type_hint: Optional[str] = None  # 'url', 'image', 'video', or None
    date_hint_days: Optional[int] = None  # Filter to last N days
    category_hint: Optional[str] = None  # Suggested category filter


class QueryUnderstandingService:
    """Parse natural language queries into structured search intents."""

    async def parse_query(self, raw_query: str) -> ParsedQuery:
        """
        Parse a natural language query into structured intent.

        Examples:
          "that pricing slide" → refined="pricing slide presentation", type_hint="image"
          "pasta place last week" → refined="pasta restaurant menu", date_hint=7
          "videos about fitness" → refined="fitness workout", type_hint="video"
          "python tutorial" → refined="python tutorial", type_hint=None (no enhancement needed)
        """
        # Short queries don't need AI parsing
        if len(raw_query.split()) <= 2 and not self._has_temporal_hint(raw_query):
            return ParsedQuery(refined_query=raw_query)

        try:
            if settings.ai_provider == "openai":
                return await self._parse_openai(raw_query)
            else:
                return await self._parse_ollama(raw_query)
        except Exception as e:
            logger.warning(f"Query understanding failed, using raw query: {e}")
            return ParsedQuery(refined_query=raw_query)

    def _has_temporal_hint(self, query: str) -> bool:
        """Check if query contains time references."""
        temporal_words = [
            "yesterday", "last week", "last month", "today",
            "recent", "this week", "this month", "ago",
        ]
        q = query.lower()
        return any(w in q for w in temporal_words)

    async def _parse_openai(self, raw_query: str) -> ParsedQuery:
        """Parse query using OpenAI."""
        import openai

        client = openai.AsyncOpenAI(api_key=settings.openai_api_key)

        response = await client.chat.completions.create(
            model=settings.openai_extraction_model,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You parse natural language search queries into structured intents. "
                        "Return ONLY valid JSON."
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        f'Parse this search query: "{raw_query}"\n\n'
                        "Return JSON:\n"
                        "{\n"
                        '  "refined_query": "semantically enriched version of the query for vector search",\n'
                        '  "content_type_hint": "image" or "video" or "url" or null,\n'
                        '  "date_hint_days": number of days to look back or null,\n'
                        '  "category_hint": category or null\n'
                        "}\n\n"
                        "Rules:\n"
                        '- refined_query should expand abbreviations and add synonyms (e.g., "that pasta place" → "pasta restaurant menu food")\n'
                        '- content_type_hint: set to "image" if query implies photos/screenshots/whiteboards, "video" for video content\n'
                        '- date_hint_days: "last week"=7, "yesterday"=1, "last month"=30, "this week"=7\n'
                        "- category_hint: one of technology, design, business, science, productivity, education, entertainment, or null"
                    ),
                },
            ],
            temperature=0.1,
            max_tokens=200,
            response_format={"type": "json_object"},
        )

        result = json.loads(response.choices[0].message.content)
        return ParsedQuery(
            refined_query=result.get("refined_query", raw_query),
            content_type_hint=result.get("content_type_hint"),
            date_hint_days=result.get("date_hint_days"),
            category_hint=result.get("category_hint"),
        )

    async def _parse_ollama(self, raw_query: str) -> ParsedQuery:
        """Parse query using Ollama."""
        import ollama

        client = ollama.AsyncClient(host=settings.ollama_base_url)

        response = await client.chat(
            model=settings.ollama_extraction_model,
            messages=[{
                "role": "user",
                "content": (
                    f'Parse this search query: "{raw_query}"\n'
                    "Return JSON with: refined_query (enriched version), "
                    "content_type_hint (image/video/url/null), "
                    "date_hint_days (number or null), "
                    "category_hint (category or null)"
                ),
            }],
        )

        text = response["message"]["content"].strip()
        if "{" in text:
            start = text.find("{")
            end = text.rfind("}") + 1
            result = json.loads(text[start:end])
            return ParsedQuery(
                refined_query=result.get("refined_query", raw_query),
                content_type_hint=result.get("content_type_hint"),
                date_hint_days=result.get("date_hint_days"),
                category_hint=result.get("category_hint"),
            )

        return ParsedQuery(refined_query=raw_query)


# Singleton
query_understanding_service = QueryUnderstandingService()
