"""
AI Service facade - provides a single interface for AI operations.
Automatically uses the correct provider (Ollama or OpenAI) based on settings.
"""
from app.services.ai_provider import AIProvider
from app.services.ollama_provider import OllamaProvider
from app.core.config import settings
from typing import List, Dict, Optional


class AIService:
    """Facade for AI operations"""

    def __init__(self):
        # Select provider based on configuration
        if settings.is_ollama:
            self.provider: AIProvider = OllamaProvider()
        else:
            # Use OpenAI provider singleton
            from app.core.provider_manager import get_openai_provider
            if not settings.openai_api_key or settings.openai_api_key == "your-openai-api-key-here":
                raise ValueError(
                    "OpenAI provider selected (AI_PROVIDER=openai) but OPENAI_API_KEY not configured. "
                    "Please set a valid API key in .env file or switch to AI_PROVIDER=ollama"
                )
            self.provider = get_openai_provider()

    async def process_content(self, url: str, title: str, content: str, provided_source_app: Optional[str] = None) -> Dict:
        """
        Process content through AI pipeline.

        This method:
        1. Extracts structured information (title, summary, category, tags, reading time, source app)
        2. Generates embedding vector for semantic search

        Args:
            url: The URL of the content
            title: The page title
            content: The main text content
            provided_source_app: Optional source app name from mobile share intent

        Returns:
            Dictionary with all extracted fields plus embedding
        """
        # Extract structured information
        extraction = await self.provider.extract_content(url, title, content, provided_source_app)

        # Generate embedding for semantic search
        # Use the richest available text for stronger semantic signal
        tags_str = ' '.join(extraction.get('tags', []))
        summary_text = extraction.get('detailed_summary') or extraction.get('summary', '')
        embedding_text = f"{extraction.get('title', '')} {summary_text} {tags_str} {extraction.get('category', '')}"
        embedding = await self.provider.generate_embedding(embedding_text)

        # Pad Ollama 768-dim vectors to 1536 dims with zeros
        # Cosine similarity ignores zero dimensions, so this is safe
        if settings.is_ollama and len(embedding) < settings.embedding_dimensions:
            embedding = embedding + [0.0] * (settings.embedding_dimensions - len(embedding))

        result = {
            'title': extraction['title'],
            'summary': extraction['summary'],
            'detailed_summary': extraction.get('detailed_summary', ''),
            'category': extraction['category'],
            'tags': extraction['tags'],
            'reading_time_minutes': extraction['reading_time'],
            'key_takeaways': extraction.get('key_takeaways', []),
            'embedding': embedding,
            'embedding_model': settings.embedding_model,
        }

        # Include source_app if AI inferred it
        if 'source_app' in extraction:
            result['source_app'] = extraction['source_app']

        return result

    async def process_visual_content(self, image_bytes: bytes, mime_type: str, context: Optional[str] = None) -> Dict:
        """
        Process image content through visual AI pipeline.

        Returns structured data + embedding for semantic search.
        The embedding is generated from the extracted text, making visual
        content searchable in the same vector space as text content.
        """
        extraction = await self.provider.extract_visual_content(image_bytes, mime_type, context)

        # Generate embedding from extracted text content
        embedding_parts = [
            extraction.get("title", ""),
            extraction.get("summary", ""),
            extraction.get("ocr_text", ""),
            " ".join(extraction.get("tags", [])),
            extraction.get("description", ""),
        ]
        embedding_text = " ".join(p for p in embedding_parts if p)

        embedding = await self.provider.generate_embedding(embedding_text)

        if settings.is_ollama and len(embedding) < settings.embedding_dimensions:
            embedding = embedding + [0.0] * (settings.embedding_dimensions - len(embedding))

        extraction["embedding"] = embedding
        extraction["embedding_model"] = settings.embedding_model
        return extraction

    async def process_video_content(self, frames: List[bytes], duration_seconds: float, context: Optional[str] = None) -> Dict:
        """
        Process video key frames through visual AI pipeline.

        Returns structured data + embedding for semantic search.
        """
        extraction = await self.provider.analyze_video_frames(frames, duration_seconds, context)

        embedding_parts = [
            extraction.get("title", ""),
            extraction.get("summary", ""),
            extraction.get("ocr_text", ""),
            " ".join(extraction.get("tags", [])),
        ]
        embedding_text = " ".join(p for p in embedding_parts if p)

        embedding = await self.provider.generate_embedding(embedding_text)

        if settings.is_ollama and len(embedding) < settings.embedding_dimensions:
            embedding = embedding + [0.0] * (settings.embedding_dimensions - len(embedding))

        extraction["embedding"] = embedding
        extraction["embedding_model"] = settings.embedding_model
        return extraction

    async def generate_embedding(self, text: str) -> List[float]:
        """Generate embedding for a given text. Used for search queries."""
        embedding = await self.provider.generate_embedding(text)

        # Pad Ollama vectors to 1536 dims
        if settings.is_ollama and len(embedding) < settings.embedding_dimensions:
            embedding = embedding + [0.0] * (settings.embedding_dimensions - len(embedding))

        # Detect zero vectors (provider returns these on failure)
        if all(v == 0.0 for v in embedding):
            raise ValueError("Embedding generation returned zero vector - AI provider may be unavailable")

        return embedding
