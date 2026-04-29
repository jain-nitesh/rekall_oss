"""
OCR service for extracting text from images.
Uses GPT-4o-mini vision (OpenAI) or LLaVA (Ollama) as primary,
with Tesseract OCR as offline fallback.
"""
import base64
import logging
from typing import Optional, Dict

from app.core.config import settings

logger = logging.getLogger(__name__)


class OCRService:
    """Extract text and descriptions from images using AI vision or Tesseract."""

    async def extract_text(self, image_bytes: bytes, mime_type: str) -> str:
        """
        Extract all visible text from an image.
        Returns the raw extracted text string (may be empty if no text found).
        """
        try:
            if settings.ai_provider == "openai":
                return await self._extract_text_openai(image_bytes, mime_type)
            else:
                return await self._extract_text_ollama(image_bytes, mime_type)
        except Exception as e:
            logger.warning(f"AI OCR failed, trying Tesseract fallback: {e}")
            if settings.ocr_fallback_to_tesseract:
                return self._extract_text_tesseract(image_bytes)
            return ""

    async def describe_image(self, image_bytes: bytes, mime_type: str) -> Dict:
        """
        Get an AI description of the image content.
        Returns: {'description': str, 'objects': list, 'scene': str}
        """
        try:
            if settings.ai_provider == "openai":
                return await self._describe_image_openai(image_bytes, mime_type)
            else:
                return await self._describe_image_ollama(image_bytes, mime_type)
        except Exception as e:
            logger.error(f"Image description failed: {e}")
            return {"description": "", "objects": [], "scene": "unknown"}

    async def _extract_text_openai(self, image_bytes: bytes, mime_type: str) -> str:
        """Extract text using GPT-4o-mini vision."""
        import openai

        client = openai.AsyncOpenAI(api_key=settings.openai_api_key)
        b64_image = base64.b64encode(image_bytes).decode("utf-8")

        response = await client.chat.completions.create(
            model=settings.openai_extraction_model,
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": (
                            "Extract ALL text visible in this image. "
                            "Return only the raw text, preserving layout where possible. "
                            "If no text is visible, return 'NO_TEXT_FOUND'."
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
            }],
            max_tokens=2000,
        )

        text = response.choices[0].message.content.strip()
        return "" if text == "NO_TEXT_FOUND" else text

    async def _extract_text_ollama(self, image_bytes: bytes, mime_type: str) -> str:
        """Extract text using Ollama LLaVA model."""
        import ollama

        client = ollama.AsyncClient(host=settings.ollama_base_url)
        b64_image = base64.b64encode(image_bytes).decode("utf-8")

        response = await client.chat(
            model=settings.ollama_vision_model,
            messages=[{
                "role": "user",
                "content": (
                    "Extract ALL text visible in this image. "
                    "Return only the raw text. If no text, return 'NO_TEXT_FOUND'."
                ),
                "images": [b64_image],
            }],
        )

        text = response["message"]["content"].strip()
        return "" if text == "NO_TEXT_FOUND" else text

    def _extract_text_tesseract(self, image_bytes: bytes) -> str:
        """Fallback OCR using Tesseract."""
        try:
            from PIL import Image
            from io import BytesIO
            import pytesseract

            img = Image.open(BytesIO(image_bytes))
            text = pytesseract.image_to_string(img)
            return text.strip()
        except Exception as e:
            logger.error(f"Tesseract OCR failed: {e}")
            return ""

    async def _describe_image_openai(self, image_bytes: bytes, mime_type: str) -> Dict:
        """Describe image content using GPT-4o-mini vision."""
        import openai
        import json

        client = openai.AsyncOpenAI(api_key=settings.openai_api_key)
        b64_image = base64.b64encode(image_bytes).decode("utf-8")

        response = await client.chat.completions.create(
            model=settings.openai_extraction_model,
            messages=[{
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": (
                            "Describe this image in detail. Return JSON with:\n"
                            '{"description": "2-3 sentence description", '
                            '"objects": ["list", "of", "key", "objects"], '
                            '"scene": "one word scene type like: whiteboard, menu, book, screenshot, photo, document"}'
                        ),
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime_type};base64,{b64_image}",
                            "detail": "low",
                        },
                    },
                ],
            }],
            max_tokens=500,
            response_format={"type": "json_object"},
        )

        try:
            return json.loads(response.choices[0].message.content)
        except json.JSONDecodeError:
            return {
                "description": response.choices[0].message.content.strip(),
                "objects": [],
                "scene": "unknown",
            }

    async def _describe_image_ollama(self, image_bytes: bytes, mime_type: str) -> Dict:
        """Describe image content using Ollama LLaVA."""
        import ollama
        import json

        client = ollama.AsyncClient(host=settings.ollama_base_url)
        b64_image = base64.b64encode(image_bytes).decode("utf-8")

        response = await client.chat(
            model=settings.ollama_vision_model,
            messages=[{
                "role": "user",
                "content": (
                    "Describe this image. Return JSON: "
                    '{"description": "2-3 sentences", "objects": ["list"], "scene": "type"}'
                ),
                "images": [b64_image],
            }],
        )

        text = response["message"]["content"].strip()
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return {"description": text, "objects": [], "scene": "unknown"}


# Singleton
ocr_service = OCRService()
