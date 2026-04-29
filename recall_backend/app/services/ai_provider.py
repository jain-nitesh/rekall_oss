"""
Abstract base class for AI providers.
Allows switching between Ollama (local) and OpenAI (production).
"""
from abc import ABC, abstractmethod
from typing import List, Dict, Optional


class AIProvider(ABC):
    """Base interface for AI providers"""

    @abstractmethod
    async def extract_content(self, url: str, title: str, content: str, provided_source_app: Optional[str] = None) -> Dict:
        """
        Extract structured information from web content.

        Args:
            url: The URL of the content
            title: The page title
            content: The main text content
            provided_source_app: Optional source app name from mobile share intent

        Returns:
            Dictionary with extracted fields:
            {
                'title': str,           # Clean, concise title (max 100 chars)
                'summary': str,         # 2-3 sentence summary
                'category': str,        # One of: technology, design, business, etc.
                'tags': List[str],      # 3-5 relevant keywords
                'reading_time': int,    # Estimated minutes to read
                'source_app': str       # Optional, inferred source app if not provided
            }
        """
        pass

    @abstractmethod
    async def generate_embedding(self, text: str) -> List[float]:
        """
        Generate embedding vector for text.

        Args:
            text: Text to embed (will be truncated to model's max length)

        Returns:
            List of floats representing the embedding vector
            - Ollama (nomic-embed-text): 768 dimensions
            - OpenAI (text-embedding-3-small): 1536 dimensions
        """
        pass

    @abstractmethod
    async def generate_connection_explanation(self, source_title: str, source_summary: str, target_title: str, target_summary: str) -> Dict:
        """
        Evaluate whether two content items share an insightful connection
        and generate a brief explanation.

        Returns:
            {'verdict': 'INSIGHTFUL' or 'OBVIOUS', 'explanation': str or None}
        """
        pass

    @abstractmethod
    async def generate_cluster_description(self, item_titles: List[str], item_summaries: List[str], item_categories: Optional[List[str]] = None) -> Dict:
        """
        Generate a thematic label and description for a cluster of related items.

        Returns:
            {'label': str, 'description': str, 'category': str}
        """
        pass

    @abstractmethod
    async def extract_visual_content(self, image_bytes: bytes, mime_type: str, context: Optional[str] = None) -> Dict:
        """
        Extract structured information from an image (photo, whiteboard, screenshot, etc.).

        Args:
            image_bytes: Raw image bytes
            mime_type: Image MIME type (e.g., image/jpeg)
            context: Optional additional context (e.g., user-provided notes)

        Returns:
            {
                'title': str,
                'summary': str,
                'category': str,
                'tags': List[str],
                'ocr_text': str,
                'description': str,
            }
        """
        pass

    @abstractmethod
    async def extract_entities(self, title: str, summary: str, content: str, existing_entities: List[Dict], content_meta: Optional[Dict] = None) -> Dict:
        """
        Extract named entities and relationships from content.

        Phase 3 of the processing pipeline. Identifies people, companies,
        technologies, concepts, topics, places, and events mentioned in the content.

        Args:
            title: Content title
            summary: Content summary
            content: Full extracted text content
            existing_entities: List of user's existing entities for dedup/linking.
                Each dict has: {'name': str, 'type': str, 'aliases': List[str]}

        Returns:
            {
                'entities': [
                    {
                        'name': str,          # Canonical name
                        'type': str,          # person, company, technology, concept, topic, place, event
                        'aliases': List[str], # Alternative names/spellings
                        'relevance': float,   # 0.0-1.0, how central to the content
                        'context': str,       # Sentence/passage mentioning the entity
                        'description': str    # Brief description of the entity
                    }
                ],
                'relationships': [
                    {
                        'source': str,        # Source entity name
                        'target': str,        # Target entity name
                        'type': str,          # Relationship type (works_at, competes_with, built_with, etc.)
                        'description': str    # Brief explanation
                    }
                ]
            }
        """
        pass

    @abstractmethod
    async def compile_wiki_page(self, entity_name: str, entity_type: str,
                                sources: List[Dict],
                                existing_wiki_content: Optional[str] = None,
                                self_entity_name: Optional[str] = None,
                                subtopics: Optional[List[Dict]] = None) -> Dict:
        """
        Compile a wiki page by synthesizing knowledge across multiple content items.

        Args:
            entity_name: Name of the topic/concept this wiki page is about
            entity_type: Type of entity (topic or concept)
            sources: List of source content items, each with:
                {'title': str, 'summary': str, 'content': str, 'created_at': str,
                 'subtopic': str (optional - which subtopic this source relates to)}
            existing_wiki_content: Previous wiki content if recompiling (for continuity)
            self_entity_name: Name of the user's self-entity for ownership context
            subtopics: List of related subtopics, each with:
                {'name': str, 'type': str, 'description': str, 'mention_count': int}

        Returns:
            {
                'content_markdown': str,    # Synthesized markdown organized by subtopics
                'confidence_score': float,  # 0.0-1.0 overall confidence
                'contradictions': [         # Conflicting claims detected
                    {'claim_a': str, 'claim_b': str, 'source_a_idx': int, 'source_b_idx': int}
                ],
                'backlinks': [str],         # Entity names referenced in the content
                'key_facts': [str]          # Top 5-10 key facts extracted
            }
        """
        pass

    @abstractmethod
    async def patch_wiki_page(self, existing_content: str, new_source: Dict,
                              entity_name: str) -> Dict:
        """
        Incrementally patch an existing wiki page with a single new source.

        Args:
            existing_content: Current wiki markdown content
            new_source: Single source dict with 'title', 'summary', 'content', 'created_at'
            entity_name: Name of the entity this wiki is about

        Returns:
            {
                'content_markdown': str,      # Patched markdown
                'changed_sections': [str]     # Names of sections that were modified
            }
        """
        pass

    @abstractmethod
    async def chat_with_context(self, question: str, context_chunks: List[Dict],
                                conversation_history: List[Dict]) -> Dict:
        """
        Answer a user question using retrieved context from their memory.

        Args:
            question: The user's question
            context_chunks: Retrieved context, each with:
                {'type': str, 'title': str, 'content': str, 'id': str, 'similarity': float}
                type is one of: 'content_item', 'entity', 'wiki_page'
            conversation_history: Recent messages [{'role': str, 'content': str}]

        Returns:
            {
                'answer': str,               # The AI's response with citations
                'cited_source_ids': [str],    # IDs of sources cited
                'confidence': float,          # 0.0-1.0
                'follow_up_suggestions': [str] # 2-3 suggested follow-up questions
            }
        """
        pass

    @abstractmethod
    async def analyze_video_frames(self, frames: List[bytes], duration_seconds: float, context: Optional[str] = None) -> Dict:
        """
        Analyze video key frames and produce a summary.

        Args:
            frames: List of JPEG-encoded key frame bytes
            duration_seconds: Video duration
            context: Optional user-provided notes

        Returns:
            {
                'title': str,
                'summary': str,
                'category': str,
                'tags': List[str],
                'ocr_text': str,
            }
        """
        pass
