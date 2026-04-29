"""
OpenAI AI provider implementation.
Uses gpt-4o-mini for extraction and text-embedding-3-small for embeddings.
"""
from openai import AsyncOpenAI
import json
from typing import List, Dict, Optional
from app.services.ai_provider import AIProvider
from app.core.config import settings


class OpenAIProvider(AIProvider):
    """OpenAI implementation for production AI processing"""

    def __init__(self):
        self.api_key = settings.openai_api_key
        self.extraction_model = settings.openai_extraction_model
        self.embedding_model = settings.openai_embedding_model
        self.client: Optional[AsyncOpenAI] = None

    async def __aenter__(self):
        """
        Async context manager entry.
        Creates the AsyncOpenAI client with HTTP connection pool.
        """
        if self.client is None:
            self.client = AsyncOpenAI(api_key=self.api_key)
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """
        Async context manager exit.
        Closes the AsyncOpenAI client and releases HTTP connections.
        """
        if self.client is not None:
            await self.client.close()
            self.client = None

    async def extract_content(self, url: str, title: str, content: str, provided_source_app: Optional[str] = None) -> Dict:
        """
        Extract structured information using gpt-4o-mini.

        Uses a carefully crafted prompt to get consistent JSON output
        with title, summary (bullet points), category, tags, reading time, and source app.
        """

        # Handle None content gracefully
        if content is None:
            content = ''

        # Limit content length to avoid token limits
        content_preview = content[:5000]

        # Build prompt with optional source app inference
        source_app_instruction = ""
        if provided_source_app:
            source_app_instruction = f"\nNote: This content was shared from the '{provided_source_app}' app. Use this as the source_app value."
        else:
            source_app_instruction = "\n6. source_app: Infer the source app/platform from the URL and content. Common values: linkedin, reddit, twitter, medium, youtube, github, productHunt, hackerNews, news, myntra, or 'other' if unknown."

        # Prompt for OpenAI (with bullet point format + detailed summary)
        prompt = f"""Analyze the following web content and extract structured information.

URL: {url}
Title: {title}
Content: {content_preview}{source_app_instruction}

Extract the following in JSON format:
1. title: A concise, clear title (max 100 chars)
2. summary: A summary with 3-4 concise bullet points (use markdown format):
   - Each bullet should be 10-20 words maximum
   - Focus on key takeaways and main ideas
   - Use this exact format: "• Key point here"
   - DO NOT reproduce the full content verbatim
   - Be specific and informative, not generic
3. detailed_summary: A comprehensive narrative summary (200-300 words) that:
   - Captures the main arguments, findings, or ideas in depth
   - Includes important details, examples, and context
   - Is written as flowing prose (not bullet points)
   - Preserves key facts, numbers, names, and specific claims
   - Should be rich enough to understand the content without reading the original
4. category: Choose ONE from [technology, design, business, science, productivity, education, entertainment, other]
5. tags: 3-5 relevant keywords (single words or short phrases)
6. reading_time: Estimated minutes to read (integer)
7. key_takeaways: 3-5 key takeaway sentences (15-30 words each) that capture the most important actionable or memorable insights
8. source_app: The source app/platform (use provided value if given, otherwise infer from URL/content)

Return ONLY valid JSON with no additional text:
{{
  "title": "...",
  "summary": "• Point 1\\n• Point 2\\n• Point 3\\n• Point 4",
  "detailed_summary": "A comprehensive 200-300 word narrative summary...",
  "category": "...",
  "tags": ["tag1", "tag2", "tag3"],
  "reading_time": 5,
  "key_takeaways": ["Takeaway 1", "Takeaway 2", "Takeaway 3"],
  "source_app": "..."
}}"""

        try:
            # Call OpenAI API
            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        'role': 'system',
                        'content': 'You are a content analysis assistant. Extract structured information from web content and return ONLY valid JSON with no markdown formatting or additional text.'
                    },
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ],
                temperature=0.3,  # Lower temperature for more consistent output
                max_tokens=1000,  # Accommodate detailed_summary + key_takeaways
            )

            # Parse JSON response
            content_text = response.choices[0].message.content
            print(f"OpenAI raw response (first 500 chars): {content_text[:500]}")

            # Extract JSON from markdown code blocks if present
            if '```json' in content_text:
                content_text = content_text.split('```json', 1)[1].split('```', 1)[0].strip()
            elif '```' in content_text:
                content_text = content_text.split('```', 1)[1].split('```', 1)[0].strip()

            # If there is leading text (e.g., "Here is the JSON"), strip everything before the first '{'
            if '{' in content_text and '}' in content_text:
                start_idx = content_text.find('{')
                end_idx = content_text.rfind('}')
                if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                    content_text = content_text[start_idx:end_idx + 1]

            # If still empty, try to find a JSON object via regex
            if not content_text.strip():
                import re
                json_match = re.search(r'\{.*\}', content_text, re.DOTALL)
                if json_match:
                    content_text = json_match.group(0).strip()

            if not content_text.strip():
                raise ValueError("Empty response from OpenAI API")

            result = json.loads(content_text)

            # Validate required fields
            required_fields = ['title', 'summary', 'category', 'tags', 'reading_time']
            for field in required_fields:
                if field not in result:
                    raise ValueError(f"Missing field: {field}")

            # Validate summary format (should contain bullet points)
            if not self._validate_summary(result['summary'], content_preview):
                print("Warning: Summary validation failed, adjusting format")
                # Try to fix the summary if it's not in bullet format
                summary = result['summary']
                if '•' not in summary and '-' not in summary and not summary.strip().startswith(('1.', '2.', '3.')):
                    # Convert to bullet points (split by sentence or period)
                    sentences = [s.strip() for s in summary.split('.') if s.strip()]
                    result['summary'] = '\n'.join([f"• {s[:100]}" for s in sentences[:4]])

            # Use provided source app if available, otherwise use AI-inferred
            if provided_source_app:
                result['source_app'] = provided_source_app.lower().replace(' ', '')
            elif 'source_app' not in result:
                result['source_app'] = 'other'

            # Ensure tags is a list
            if not isinstance(result['tags'], list):
                result['tags'] = []

            # Ensure reading_time is an integer
            if not isinstance(result['reading_time'], int):
                result['reading_time'] = int(result['reading_time'])

            return result

        except Exception as e:
            # Fallback to basic extraction if OpenAI fails
            print(f"OpenAI extraction failed: {e}, using fallback")

            # Infer source app from URL as fallback - use domain name directly
            inferred_source_app = 'other'
            try:
                from urllib.parse import urlparse
                parsed = urlparse(url)
                netloc = parsed.netloc.lower().replace('www.', '')
                domain_parts = netloc.split('.')

                # Extract main domain name (e.g., "myntra" from "www.myntra.com")
                if len(domain_parts) >= 2:
                    main_domain = domain_parts[-2] if len(domain_parts) > 2 else domain_parts[0]
                    inferred_source_app = main_domain.lower()
                else:
                    inferred_source_app = netloc
            except Exception:
                pass

            # Generate fallback bullet point summary
            fallback_summary = self._generate_fallback_summary(content[:600])

            return {
                'title': title[:100] if title else 'Untitled',
                'summary': fallback_summary,
                'category': 'other',
                'tags': [],
                'reading_time': max(1, len(content.split()) // 200),  # Rough estimate: 200 words/min
                'source_app': provided_source_app.lower().replace(' ', '') if provided_source_app else inferred_source_app
            }

    def _validate_summary(self, summary: str, original_content: str) -> bool:
        """
        Validate summary quality:
        1. Length: 50-600 characters (not too short, not full content)
        2. Not > 50% of original content length
        3. Contains bullet points (•, -, or numbers)
        4. Not generic phrases
        """
        if not summary:
            return False

        # Check length
        if len(summary) < 50 or len(summary) > 600:
            return False

        # Check not too similar to original (not full content dump)
        if len(original_content) > 0 and len(summary) > 0.5 * len(original_content):
            return False

        # Check for bullet points or numbered format
        has_bullets = ('•' in summary or
                      summary.count('-') >= 2 or
                      any(summary.strip().startswith(f'{i}.') for i in range(1, 5)))

        if not has_bullets:
            return False

        # Check not generic
        generic_phrases = ['no description available', 'summary unavailable', 'content summary']
        if any(phrase in summary.lower() for phrase in generic_phrases):
            return False

        return True

    def _generate_fallback_summary(self, content: str) -> str:
        """
        Generate a simple bullet point summary from content when AI fails.
        Takes first 3-4 sentences and converts to bullet points.
        """
        # Split into sentences
        sentences = [s.strip() for s in content.split('.') if s.strip() and len(s.strip()) > 20]

        # Take first 3-4 sentences
        bullet_points = []
        for sentence in sentences[:4]:
            # Limit each bullet to 20 words
            words = sentence.split()
            if len(words) > 20:
                sentence = ' '.join(words[:20]) + '...'
            bullet_points.append(f"• {sentence}")

        # Return formatted bullet points
        if bullet_points:
            return '\n'.join(bullet_points)
        else:
            return '• ' + (content[:200] + '...' if len(content) > 200 else content)

    async def generate_connection_explanation(self, source_title: str, source_summary: str, target_title: str, target_summary: str) -> Dict:
        """Evaluate connection quality between two items using OpenAI."""
        prompt = (
            f"Article A: {source_title}\n"
            f"Summary: {source_summary if source_summary else 'N/A'}\n\n"
            f"Article B: {target_title}\n"
            f"Summary: {target_summary if target_summary else 'N/A'}\n\n"
            "Do these two articles share a surprising, non-obvious connection — "
            "such as shared underlying themes, contrasting perspectives, or unexpected parallels?\n\n"
            "Reply with EXACTLY this format:\n"
            "Line 1: INSIGHTFUL or OBVIOUS\n"
            "Line 2: A 1-2 sentence explanation of the connection (focus on WHY they connect, not WHAT they are about)."
        )

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        'role': 'system',
                        'content': 'You evaluate whether two saved articles share an insightful, non-obvious connection. Be selective — only say INSIGHTFUL if there is a genuine deeper link beyond surface-level topic overlap.'
                    },
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ],
                temperature=0.5,
                max_tokens=150,
            )

            response_text = response.choices[0].message.content.strip()
            lines = response_text.split('\n', 1)
            verdict = lines[0].strip().upper() if lines else ""

            if 'INSIGHTFUL' in verdict:
                verdict = 'INSIGHTFUL'
            elif 'OBVIOUS' in verdict:
                verdict = 'OBVIOUS'

            explanation = lines[1].strip() if len(lines) > 1 else None

            return {'verdict': verdict, 'explanation': explanation}

        except Exception as e:
            print(f"OpenAI connection explanation failed: {e}")
            return {'verdict': 'OBVIOUS', 'explanation': None}

    async def generate_cluster_description(self, item_titles: List[str], item_summaries: List[str], item_categories: Optional[List[str]] = None) -> Dict:
        """Generate a thematic label and description for a cluster using OpenAI."""
        items_text_parts = []
        for i, title in enumerate(item_titles[:20]):
            summary = item_summaries[i][:100] if i < len(item_summaries) and item_summaries[i] else ""
            items_text_parts.append(f"- {title}" + (f": {summary}" if summary else ""))
        items_text = "\n".join(items_text_parts)

        categories_hint = ""
        if item_categories:
            unique_cats = list(set(c for c in item_categories if c))
            if unique_cats:
                categories_hint = f"\nCategories represented: {', '.join(unique_cats)}"

        prompt = (
            f"Here are {len(item_titles)} saved articles in a topic cluster:\n\n"
            f"{items_text}{categories_hint}\n\n"
            "Generate a JSON object with:\n"
            '1. "label": A thematic label (max 80 chars) that captures the connecting thread — '
            "NOT a list of topics, but a unifying theme\n"
            '2. "description": 1-2 sentences explaining what ties these items together\n'
            '3. "category": The dominant category from [technology, design, business, science, productivity, education, entertainment, other]\n\n'
            "Return ONLY valid JSON:\n"
            '{"label": "...", "description": "...", "category": "..."}'
        )

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        'role': 'system',
                        'content': 'You generate concise thematic labels for clusters of saved articles. Return ONLY valid JSON with no markdown formatting.'
                    },
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ],
                temperature=0.4,
                max_tokens=200,
            )

            content_text = response.choices[0].message.content.strip()

            if '```json' in content_text:
                content_text = content_text.split('```json', 1)[1].split('```', 1)[0].strip()
            elif '```' in content_text:
                content_text = content_text.split('```', 1)[1].split('```', 1)[0].strip()

            if '{' in content_text and '}' in content_text:
                start_idx = content_text.find('{')
                end_idx = content_text.rfind('}')
                if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                    content_text = content_text[start_idx:end_idx + 1]

            result = json.loads(content_text)

            label = result.get('label', '').strip()
            if not label or len(label) < 2:
                raise ValueError("AI returned empty label")

            return {
                'label': label[:80],
                'description': result.get('description', '').strip() or None,
                'category': result.get('category', '').strip() or None,
            }

        except Exception as e:
            print(f"OpenAI cluster description failed: {e}")
            label = "Related Items"
            if item_categories:
                freq: Dict[str, int] = {}
                for cat in item_categories:
                    if cat:
                        freq[cat] = freq.get(cat, 0) + 1
                if freq:
                    label = f"{max(freq, key=freq.get)} Collection"

            description = None
            if len(item_titles) >= 2:
                shown = ", ".join(item_titles[:2])
                remaining = len(item_titles) - 2
                description = f"Includes {shown}, and {remaining} more" if remaining > 0 else f"Includes {shown}"
            elif item_titles:
                description = f"Includes {item_titles[0]}"

            return {'label': label, 'description': description, 'category': None}

    async def extract_visual_content(self, image_bytes: bytes, mime_type: str, context: Optional[str] = None) -> Dict:
        """Extract structured info from an image using GPT-4o-mini vision."""
        import base64

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            b64_image = base64.b64encode(image_bytes).decode("utf-8")
            context_hint = f"\nUser notes: {context}" if context else ""

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You analyze images and extract structured information. "
                            "Return ONLY valid JSON with no markdown formatting."
                        ),
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    f"Analyze this image and return JSON:{context_hint}\n\n"
                                    "1. Extract ALL visible text (OCR)\n"
                                    "2. Generate a concise title (max 100 chars)\n"
                                    "3. Write a 2-3 sentence summary of what's in the image\n"
                                    "4. Categorize: technology, design, business, science, productivity, education, entertainment, or other\n"
                                    "5. Generate 3-5 relevant tags\n"
                                    "6. Describe the image content\n\n"
                                    "Return JSON:\n"
                                    '{"title":"...","summary":"...","category":"...","tags":["..."],"ocr_text":"...","description":"..."}'
                                ),
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:{mime_type};base64,{b64_image}",
                                    "detail": "high",
                                },
                            },
                        ],
                    },
                ],
                temperature=0.3,
                max_tokens=1000,
            )

            content_text = response.choices[0].message.content.strip()

            # Clean markdown formatting
            if "```json" in content_text:
                content_text = content_text.split("```json", 1)[1].split("```", 1)[0].strip()
            elif "```" in content_text:
                content_text = content_text.split("```", 1)[1].split("```", 1)[0].strip()

            if "{" in content_text:
                start = content_text.find("{")
                end = content_text.rfind("}") + 1
                content_text = content_text[start:end]

            result = json.loads(content_text)

            return {
                "title": (result.get("title") or "Captured Image")[:100],
                "summary": result.get("summary") or "Image content",
                "category": result.get("category") or "other",
                "tags": result.get("tags") or [],
                "ocr_text": result.get("ocr_text") or "",
                "description": result.get("description") or "",
            }

        except Exception as e:
            print(f"OpenAI visual content extraction failed: {e}")
            return {
                "title": "Captured Image",
                "summary": "Image could not be analyzed",
                "category": "other",
                "tags": [],
                "ocr_text": "",
                "description": "",
            }

    async def analyze_video_frames(self, frames: List[bytes], duration_seconds: float, context: Optional[str] = None) -> Dict:
        """Analyze video key frames using GPT-4o-mini vision."""
        import base64

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            # Build image content parts for each frame
            image_parts = []
            for i, frame in enumerate(frames[:5]):  # Max 5 frames
                b64_frame = base64.b64encode(frame).decode("utf-8")
                image_parts.append({
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:image/jpeg;base64,{b64_frame}",
                        "detail": "low",
                    },
                })

            context_hint = f"\nUser notes: {context}" if context else ""

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        "role": "system",
                        "content": "You analyze video frames and extract structured information. Return ONLY valid JSON.",
                    },
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    f"These are {len(frames)} key frames from a {duration_seconds:.0f}-second video.{context_hint}\n\n"
                                    "1. Extract ALL visible text from all frames (OCR)\n"
                                    "2. Generate a concise title (max 100 chars)\n"
                                    "3. Write a 2-3 sentence summary of the video content\n"
                                    "4. Categorize: technology, design, business, science, productivity, education, entertainment, or other\n"
                                    "5. Generate 3-5 relevant tags\n\n"
                                    "Return JSON:\n"
                                    '{"title":"...","summary":"...","category":"...","tags":["..."],"ocr_text":"..."}'
                                ),
                            },
                            *image_parts,
                        ],
                    },
                ],
                temperature=0.3,
                max_tokens=1000,
            )

            content_text = response.choices[0].message.content.strip()

            if "```json" in content_text:
                content_text = content_text.split("```json", 1)[1].split("```", 1)[0].strip()
            elif "```" in content_text:
                content_text = content_text.split("```", 1)[1].split("```", 1)[0].strip()

            if "{" in content_text:
                start = content_text.find("{")
                end = content_text.rfind("}") + 1
                content_text = content_text[start:end]

            result = json.loads(content_text)

            return {
                "title": (result.get("title") or "Captured Video")[:100],
                "summary": result.get("summary") or "Video content",
                "category": result.get("category") or "other",
                "tags": result.get("tags") or [],
                "ocr_text": result.get("ocr_text") or "",
            }

        except Exception as e:
            print(f"OpenAI video analysis failed: {e}")
            return {
                "title": "Captured Video",
                "summary": f"A {duration_seconds:.0f}-second video",
                "category": "other",
                "tags": [],
                "ocr_text": "",
            }

    async def extract_entities(self, title: str, summary: str, content: str, existing_entities: List[Dict], content_meta: Optional[Dict] = None) -> Dict:
        """
        Extract named entities and relationships from content using gpt-4o-mini.

        Identifies people, companies, technologies, concepts, topics, places, and events.
        Also discovers relationships between entities mentioned in the same content.
        """
        # Prepare content for extraction
        content_preview = (content or '')[:4000]
        summary_text = summary or ''
        content_meta = content_meta or {}

        # Determine if this is the user's own content or curated from external sources
        is_user_created = content_meta.get('is_user_created', False)
        source_app = content_meta.get('source_app', 'unknown')
        has_url = content_meta.get('has_url', True)

        # Build self-entity hint (if user has seeded personal info)
        self_hint = ""
        if existing_entities:
            self_entity = next((e for e in existing_entities if e.get('is_self')), None)
            if self_entity:
                aliases_str = ", ".join(self_entity.get('aliases', []))
                if is_user_created:
                    # User's own content (notes, camera captures without URL)
                    self_hint = (
                        f"\n\nIMPORTANT: The content owner/user is '{self_entity['name']}'"
                        f"{f' (also known as: {aliases_str})' if aliases_str else ''}. "
                        f"This content was CREATED BY the user (it is their own note/content). "
                        f"First-person references ('I', 'my', 'me') refer to '{self_entity['name']}' and "
                        f"achievements/activities described are the user's own. "
                        f"If the content mentions '{self_entity['name']}' or any alias, use the EXACT name '{self_entity['name']}'."
                    )
                else:
                    # Curated/saved content from external sources
                    self_hint = (
                        f"\n\nCRITICAL OWNERSHIP CONTEXT: The app user is '{self_entity['name']}'"
                        f"{f' (also known as: {aliases_str})' if aliases_str else ''}. "
                        f"However, this content was SAVED/CURATED by the user from an external source "
                        f"(source: {source_app}). It was NOT created by the user. "
                        f"The user saved this content because they found it interesting or useful. "
                        f"DO NOT attribute the achievements, work, opinions, or activities described "
                        f"in this content to '{self_entity['name']}'. "
                        f"The people, companies, and accomplishments mentioned belong to the ORIGINAL "
                        f"CONTENT CREATORS, not to the app user. "
                        f"First-person references ('I', 'my', 'me') in this content refer to the "
                        f"ORIGINAL AUTHOR/CREATOR of this content, NOT to '{self_entity['name']}'. "
                        f"Only attribute something to '{self_entity['name']}' if the content explicitly "
                        f"names them as doing or achieving something. "
                        f"If the content mentions '{self_entity['name']}' or any alias, use the EXACT name '{self_entity['name']}'."
                    )

        # Build existing entities hint for dedup
        existing_hint = ""
        if existing_entities:
            entity_names = [f"- {e['name']} ({e['type']})" for e in existing_entities[:50]]
            existing_hint = (
                "\n\nIMPORTANT - The user already has these entities in their knowledge graph. "
                "If you find a match (same entity, possibly different spelling), use the EXACT existing name:\n"
                + "\n".join(entity_names)
            )

        prompt = f"""Analyze this content and extract all named entities and relationships between them.

Title: {title}
Summary: {summary_text}
Content: {content_preview}{self_hint}{existing_hint}

Extract entities of these types:
- person: Named individuals (e.g., "Elon Musk", "Sam Altman")
- company: Organizations and companies (e.g., "OpenAI", "Google")
- technology: Specific technologies, frameworks, languages (e.g., "Python", "GPT-4", "React")
- concept: Abstract ideas and methodologies (e.g., "machine learning", "agile development")
- topic: Broad subject areas (e.g., "artificial intelligence", "climate change")
- place: Geographic locations (e.g., "Silicon Valley", "London")
- event: Named events (e.g., "WWDC 2025", "CES")

For relationships, use types like: works_at, founded_by, competes_with, built_with, part_of, influences, acquired_by, invested_in, related_to

Rules:
- Only extract entities that are clearly identifiable, not generic terms
- Relevance score: 1.0 = main subject, 0.5 = mentioned, 0.2 = tangentially mentioned
- If an entity matches an existing one (even with different spelling), use the existing name exactly
- Extract 3-15 entities depending on content richness
- Extract relationships only between entities found in THIS content

Return ONLY valid JSON:
{{
  "entities": [
    {{"name": "...", "type": "...", "aliases": ["..."], "relevance": 0.8, "context": "...", "description": "..."}}
  ],
  "relationships": [
    {{"source": "...", "target": "...", "type": "...", "description": "..."}}
  ]
}}"""

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        'role': 'system',
                        'content': (
                            'You are a knowledge graph entity extraction system. '
                            'Extract named entities and their relationships from content. '
                            'Be precise and specific. Return ONLY valid JSON with no markdown formatting.'
                        )
                    },
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ],
                temperature=0.2,  # Low temperature for consistent extraction
                max_tokens=1500,
            )

            content_text = response.choices[0].message.content.strip()
            print(f"Entity extraction raw response (first 300 chars): {content_text[:300]}")

            # Clean markdown formatting
            if '```json' in content_text:
                content_text = content_text.split('```json', 1)[1].split('```', 1)[0].strip()
            elif '```' in content_text:
                content_text = content_text.split('```', 1)[1].split('```', 1)[0].strip()

            if '{' in content_text and '}' in content_text:
                start_idx = content_text.find('{')
                end_idx = content_text.rfind('}')
                if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                    content_text = content_text[start_idx:end_idx + 1]

            result = json.loads(content_text)

            # Validate and normalize entities
            entities = []
            for e in result.get('entities', []):
                if not e.get('name') or not e.get('type'):
                    continue
                entity_type = e['type'].lower().strip()
                valid_types = ['person', 'company', 'technology', 'concept', 'topic', 'place', 'event']
                if entity_type not in valid_types:
                    entity_type = 'concept'  # Default fallback
                entities.append({
                    'name': e['name'].strip(),
                    'type': entity_type,
                    'aliases': e.get('aliases', []),
                    'relevance': min(1.0, max(0.0, float(e.get('relevance', 0.5)))),
                    'context': (e.get('context') or '')[:500],
                    'description': (e.get('description') or '')[:300],
                })

            # Validate relationships
            entity_names = {e['name'].lower() for e in entities}
            relationships = []
            for r in result.get('relationships', []):
                if (r.get('source') and r.get('target') and r.get('type')
                        and r['source'].lower() in entity_names
                        and r['target'].lower() in entity_names):
                    relationships.append({
                        'source': r['source'].strip(),
                        'target': r['target'].strip(),
                        'type': r['type'].strip().lower().replace(' ', '_'),
                        'description': (r.get('description') or '')[:300],
                    })

            return {'entities': entities, 'relationships': relationships}

        except Exception as e:
            print(f"OpenAI entity extraction failed: {e}")
            return {'entities': [], 'relationships': []}

    async def chat_with_context(self, question: str, context_chunks: List[Dict],
                                conversation_history: List[Dict]) -> Dict:
        """Answer a user question using retrieved memory context via gpt-4o-mini."""
        # Build context block
        context_text = ""
        for i, chunk in enumerate(context_chunks[:15]):
            source_type = chunk.get('type', 'unknown')
            title = chunk.get('title', 'Untitled')
            content = chunk.get('content', '')[:500]
            source_id = chunk.get('id', '')
            similarity = chunk.get('similarity', 0.0)
            context_text += f"\n[{source_type.upper()} {i+1}] (id: {source_id}, relevance: {similarity:.2f}) {title}\n{content}\n"

        # Build conversation history
        history_messages = []
        for msg in conversation_history[-5:]:  # Last 5 messages
            history_messages.append({
                'role': msg['role'],
                'content': msg['content'][:500]
            })

        system_prompt = (
            "You are a personal memory assistant. The user is querying their saved knowledge base. "
            "Answer using ONLY the provided context. Cite sources using [TYPE N] notation "
            "(e.g., [WIKI_PAGE 1], [CONTENT_ITEM 3]). "
            "If the context doesn't contain enough information, say so honestly. "
            "Be concise and specific. After answering, suggest 2-3 follow-up questions.\n\n"
            "CRITICAL OWNERSHIP RULE: The user saves content from many external sources (YouTube, articles, "
            "social media, etc.). Content marked as '[Saved from ...]' is NOT the user's own work — it is content "
            "they found interesting. DO NOT attribute achievements, opinions, or activities from saved/curated "
            "content to the user. Only attribute things to the user from their own notes or content explicitly "
            "about them. Context marked '[THIS IS THE APP USER]' describes the actual user.\n\n"
            "Return ONLY valid JSON:\n"
            '{"answer": "...", "cited_source_ids": ["id1", "id2"], '
            '"confidence": 0.8, "follow_up_suggestions": ["Question 1?", "Question 2?"]}'
        )

        user_prompt = f"""CONTEXT FROM YOUR MEMORY:
{context_text}

QUESTION: {question}

Answer the question using the context above. Cite sources with [TYPE N] notation.
Return JSON with: answer, cited_source_ids (list of source IDs you cited), confidence (0-1), follow_up_suggestions (2-3 questions)."""

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            messages = [{'role': 'system', 'content': system_prompt}]
            messages.extend(history_messages)
            messages.append({'role': 'user', 'content': user_prompt})

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=messages,
                temperature=0.4,
                max_tokens=1500,
            )

            content_text = response.choices[0].message.content.strip()

            # Try to parse as JSON
            if '```json' in content_text:
                content_text = content_text.split('```json', 1)[1].split('```', 1)[0].strip()
            elif '```' in content_text:
                content_text = content_text.split('```', 1)[1].split('```', 1)[0].strip()

            if '{' in content_text and '}' in content_text:
                start_idx = content_text.find('{')
                end_idx = content_text.rfind('}')
                if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                    content_text = content_text[start_idx:end_idx + 1]

            result = json.loads(content_text)

            return {
                'answer': result.get('answer', 'I could not generate an answer.'),
                'cited_source_ids': result.get('cited_source_ids', []),
                'confidence': min(1.0, max(0.0, float(result.get('confidence', 0.5)))),
                'follow_up_suggestions': result.get('follow_up_suggestions', []),
            }

        except json.JSONDecodeError:
            # If JSON parsing fails, treat the whole response as the answer
            return {
                'answer': content_text if content_text else 'I could not generate an answer.',
                'cited_source_ids': [],
                'confidence': 0.3,
                'follow_up_suggestions': [],
            }
        except Exception as e:
            print(f"OpenAI chat failed: {e}")
            return {
                'answer': 'Sorry, I encountered an error processing your question.',
                'cited_source_ids': [],
                'confidence': 0.0,
                'follow_up_suggestions': [],
            }

    async def compile_wiki_page(self, entity_name: str, entity_type: str,
                                sources: List[Dict],
                                existing_wiki_content: Optional[str] = None,
                                self_entity_name: Optional[str] = None,
                                subtopics: Optional[List[Dict]] = None) -> Dict:
        """Compile a topic/concept wiki page organized by subtopics using gpt-4o-mini."""
        # Build sources text with indices for citation, including ownership labels
        sources_text = ""
        for i, src in enumerate(sources[:20]):  # Max 20 sources
            title = src.get('title', 'Untitled')
            summary = (src.get('summary') or '')[:300]
            content = (src.get('content') or '')[:500]
            created = src.get('created_at', 'unknown date')
            ownership = src.get('ownership', 'CURATED_FROM:external')
            subtopic_label = f" [Subtopic: {src['subtopic']}]" if src.get('subtopic') else ""
            sources_text += f"\n[Source {i+1}] ({created}) [{ownership}]{subtopic_label} {title}\nSummary: {summary}\nContent: {content}\n"

        existing_hint = ""
        if existing_wiki_content:
            existing_hint = (
                f"\n\nPrevious wiki content (update and expand, don't start from scratch):\n"
                f"{existing_wiki_content[:2000]}"
            )

        # Build subtopics hint
        subtopics_hint = ""
        if subtopics:
            subtopic_names = [f"- {s['name']} ({s['type']}, {s['mention_count']} mentions): {s['description'][:100]}" for s in subtopics[:10]]
            subtopics_hint = (
                f"\n\nRELATED SUBTOPICS (organize content by these where applicable):\n"
                + "\n".join(subtopic_names)
            )

        # Build ownership context instruction
        ownership_instruction = ""
        if self_entity_name:
            ownership_instruction = (
                f"\n\nCRITICAL OWNERSHIP RULE: The app user is '{self_entity_name}'. "
                f"Each source is labeled as either USER_CREATED (the user's own notes/content) "
                f"or CURATED_FROM:<source> (content saved from external sources like YouTube, articles, etc.). "
                f"You MUST distinguish between:\n"
                f"- Things '{self_entity_name}' personally did, built, or achieved (only from USER_CREATED sources "
                f"or sources that explicitly name '{self_entity_name}' as the doer)\n"
                f"- Things '{self_entity_name}' found interesting and saved for reference (CURATED_FROM sources)\n"
                f"DO NOT attribute accomplishments, work, or opinions from curated/external content to '{self_entity_name}'. "
                f"If the wiki is about '{self_entity_name}', clearly separate 'Own Work & Achievements' from "
                f"'Saved References & Interests'. "
                f"If the wiki is about another entity, describe what that entity did — the fact that "
                f"'{self_entity_name}' saved the content just means they were interested in the topic."
            )

        prompt = f"""You are compiling a knowledge wiki page about "{entity_name}" (type: {entity_type}).

Synthesize the following {len(sources)} sources into a well-structured wiki page.{existing_hint}{subtopics_hint}{ownership_instruction}

SOURCES:
{sources_text}

OUTPUT FORMAT (follow this template exactly):
# {entity_name}

## Overview
2-3 sentence summary of what this entity is and why it matters to the user.

## Key Facts
- Bullet list of 5-10 concrete, specific facts extracted from sources
- Each fact should cite its source: [Source N]

## [Subtopic sections]
One section per subtopic. Synthesize what the user has saved about each aspect.
Cite sources inline with [Source N].

## Sources
Numbered list of all sources used.

RULES:
1. Be specific and factual. No filler or generic statements.
2. Every claim must cite a source with [Source N].
3. If subtopics are provided above, use them as section headings.
4. Identify CONTRADICTIONS between sources.
5. Identify OTHER entities referenced across sources (for backlinks).
6. Respect ownership labels. Do not attribute curated content to the user.

Return ONLY valid JSON:
{{
  "content_markdown": "# {entity_name}\\n\\n## Overview\\n...",
  "confidence_score": 0.8,
  "contradictions": [
    {{"claim_a": "...", "claim_b": "...", "source_a_idx": 1, "source_b_idx": 3}}
  ],
  "backlinks": ["Entity Name 1", "Entity Name 2"],
  "key_facts": ["Fact 1", "Fact 2"]
}}"""

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        'role': 'system',
                        'content': (
                            'You are a knowledge compiler that synthesizes information from multiple sources '
                            'into well-structured wiki pages. Be thorough, cite sources, and flag contradictions. '
                            'Return ONLY valid JSON with no markdown formatting around the JSON.'
                        )
                    },
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ],
                temperature=0.3,
                max_tokens=4000,
            )

            content_text = response.choices[0].message.content.strip()

            # Clean markdown formatting
            if '```json' in content_text:
                content_text = content_text.split('```json', 1)[1].split('```', 1)[0].strip()
            elif '```' in content_text:
                content_text = content_text.split('```', 1)[1].split('```', 1)[0].strip()

            if '{' in content_text and '}' in content_text:
                start_idx = content_text.find('{')
                end_idx = content_text.rfind('}')
                if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                    content_text = content_text[start_idx:end_idx + 1]

            result = json.loads(content_text)

            return {
                'content_markdown': result.get('content_markdown', ''),
                'confidence_score': min(1.0, max(0.0, float(result.get('confidence_score', 0.5)))),
                'contradictions': result.get('contradictions', []),
                'backlinks': result.get('backlinks', []),
                'key_facts': result.get('key_facts', []),
            }

        except Exception as e:
            print(f"OpenAI wiki compilation failed: {e}")
            return {
                'content_markdown': f'# {entity_name}\n\nWiki compilation failed. Will retry later.',
                'confidence_score': 0.0,
                'contradictions': [],
                'backlinks': [],
                'key_facts': [],
            }

    async def patch_wiki_page(self, existing_content: str, new_source: Dict,
                              entity_name: str) -> Dict:
        """Incrementally patch a wiki page with one new source using gpt-4o-mini."""
        title = new_source.get('title', 'Untitled')
        summary = (new_source.get('summary') or '')[:300]
        content = (new_source.get('content') or '')[:1000]
        created = new_source.get('created_at', 'unknown date')

        prompt = f"""You are updating an existing wiki page about "{entity_name}" with new information from a single source.

EXISTING WIKI:
{existing_content[:3000]}

NEW SOURCE:
Title: {title}
Date: {created}
Summary: {summary}
Content: {content}

INSTRUCTIONS:
1. Merge the new information into the existing wiki. DO NOT rewrite sections that aren't affected.
2. Add new facts to the appropriate existing sections, or create a new section if needed.
3. Keep the existing structure (## headings) intact. Only modify sections where the new source adds info.
4. Update the Overview if the new source changes the big picture.
5. Add a [New] citation marker next to newly added information.
6. Maintain the existing ## Sources section — append the new source at the end.

Return ONLY valid JSON:
{{
  "content_markdown": "<full updated wiki markdown>",
  "changed_sections": ["Overview", "Section Name"]
}}"""

        try:
            if self.client is None:
                self.client = AsyncOpenAI(api_key=self.api_key)

            response = await self.client.chat.completions.create(
                model=self.extraction_model,
                messages=[
                    {
                        'role': 'system',
                        'content': 'You patch existing wiki pages with new information. Be surgical — only change what the new source affects. Return valid JSON only.'
                    },
                    {'role': 'user', 'content': prompt}
                ],
                temperature=0.3,
                max_tokens=2000,
            )

            content_text = response.choices[0].message.content.strip()
            if '```json' in content_text:
                content_text = content_text.split('```json', 1)[1].split('```', 1)[0].strip()
            elif '```' in content_text:
                content_text = content_text.split('```', 1)[1].split('```', 1)[0].strip()

            if '{' in content_text and '}' in content_text:
                start_idx = content_text.find('{')
                end_idx = content_text.rfind('}')
                if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
                    content_text = content_text[start_idx:end_idx + 1]

            result = json.loads(content_text)
            return {
                'content_markdown': result.get('content_markdown', existing_content),
                'changed_sections': result.get('changed_sections', []),
            }
        except Exception as e:
            print(f"OpenAI wiki patch failed: {e}")
            return {
                'content_markdown': existing_content,
                'changed_sections': [],
            }

    async def generate_embedding(self, text: str) -> List[float]:
        """
        Generate embedding using text-embedding-3-small (1536 dimensions).

        This creates a vector representation of the text that captures
        its semantic meaning. Similar texts will have similar embeddings.
        """

        try:
            # Limit text length to avoid token limits
            # text-embedding-3-small supports up to 8191 tokens
            text_preview = text[:8000]

            # Call OpenAI embeddings API
            response = await self.client.embeddings.create(
                model=self.embedding_model,
                input=text_preview
            )

            # Return embedding vector
            embedding = response.data[0].embedding

            # Verify it's the expected dimension (1536 for text-embedding-3-small)
            if len(embedding) != 1536:
                print(f"Warning: Expected 1536 dimensions, got {len(embedding)}")

            return embedding

        except Exception as e:
            # Return zero vector if embedding fails
            # This allows content to be saved even if embedding generation fails
            print(f"OpenAI embedding generation failed: {e}, using zero vector")
            return [0.0] * 1536  # text-embedding-3-small uses 1536 dimensions
