"""
Media storage service for uploading/managing files in S3-compatible storage.
Supports Cloudflare R2 (production) and MinIO (local development).
"""
import uuid
import logging
from io import BytesIO
from typing import Optional

import aioboto3
from PIL import Image

from app.core.config import settings

logger = logging.getLogger(__name__)

# Thumbnail dimensions
THUMBNAIL_MAX_SIZE = (400, 400)


class MediaStorageService:
    """Handles media file uploads, thumbnails, and deletion via S3-compatible API."""

    def __init__(self):
        self._session = aioboto3.Session()

    def _get_client_kwargs(self) -> dict:
        """Build S3 client connection kwargs from config."""
        kwargs = {
            "service_name": "s3",
            "region_name": settings.s3_region,
            "aws_access_key_id": settings.s3_access_key_id,
            "aws_secret_access_key": settings.s3_secret_access_key,
        }
        if settings.s3_endpoint_url:
            kwargs["endpoint_url"] = settings.s3_endpoint_url
        return kwargs

    async def upload_media(
        self,
        file_bytes: bytes,
        mime_type: str,
        user_id: str,
        content_id: str,
        filename: str,
    ) -> str:
        """
        Upload a media file to object storage.

        Returns the public URL of the uploaded file.
        Path structure: {user_id}/{content_id}/{filename}
        """
        object_key = f"{user_id}/{content_id}/{filename}"

        async with self._session.client(**self._get_client_kwargs()) as s3:
            await s3.put_object(
                Bucket=settings.s3_bucket_name,
                Key=object_key,
                Body=file_bytes,
                ContentType=mime_type,
            )

        # Build the public URL
        if settings.s3_endpoint_url:
            # R2/MinIO: endpoint/bucket/key
            base = settings.s3_endpoint_url.rstrip("/")
            url = f"{base}/{settings.s3_bucket_name}/{object_key}"
        else:
            # AWS S3
            url = f"https://{settings.s3_bucket_name}.s3.{settings.s3_region}.amazonaws.com/{object_key}"

        logger.info(f"Uploaded media: {object_key} ({len(file_bytes)} bytes)")
        return url

    async def generate_thumbnail(
        self,
        file_bytes: bytes,
        mime_type: str,
        user_id: str,
        content_id: str,
    ) -> Optional[str]:
        """
        Generate and upload a thumbnail for an image.
        Returns the thumbnail URL, or None if generation fails.
        """
        if not mime_type.startswith("image/"):
            return None

        try:
            img = Image.open(BytesIO(file_bytes))
            img.thumbnail(THUMBNAIL_MAX_SIZE)

            # Convert to RGB if necessary (e.g., RGBA PNGs)
            if img.mode in ("RGBA", "P"):
                img = img.convert("RGB")

            thumb_buffer = BytesIO()
            img.save(thumb_buffer, format="JPEG", quality=80)
            thumb_bytes = thumb_buffer.getvalue()

            thumb_url = await self.upload_media(
                file_bytes=thumb_bytes,
                mime_type="image/jpeg",
                user_id=user_id,
                content_id=content_id,
                filename="thumbnail.jpg",
            )
            return thumb_url
        except Exception as e:
            logger.error(f"Thumbnail generation failed: {e}")
            return None

    async def delete_media(self, media_url: str) -> None:
        """Delete a media file from object storage by its URL."""
        object_key = self._url_to_key(media_url)
        if not object_key:
            return

        try:
            async with self._session.client(**self._get_client_kwargs()) as s3:
                await s3.delete_object(
                    Bucket=settings.s3_bucket_name,
                    Key=object_key,
                )
            logger.info(f"Deleted media: {object_key}")
        except Exception as e:
            logger.error(f"Failed to delete media {object_key}: {e}")

    async def download_media(self, media_url: str) -> bytes:
        """Download media file bytes from object storage using authenticated S3 client."""
        object_key = self._url_to_key(media_url)
        if not object_key:
            raise ValueError(f"Cannot extract object key from URL: {media_url}")

        async with self._session.client(**self._get_client_kwargs()) as s3:
            resp = await s3.get_object(
                Bucket=settings.s3_bucket_name,
                Key=object_key,
            )
            return await resp["Body"].read()

    async def get_presigned_url(self, media_url: str, expiry: int = 3600) -> Optional[str]:
        """Generate a presigned URL for private media access."""
        object_key = self._url_to_key(media_url)
        if not object_key:
            return None

        async with self._session.client(**self._get_client_kwargs()) as s3:
            url = await s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": settings.s3_bucket_name, "Key": object_key},
                ExpiresIn=expiry,
            )
        return url

    def _url_to_key(self, media_url: str) -> Optional[str]:
        """Extract object key from a media URL."""
        if not media_url:
            return None
        # Try to extract key after bucket name
        bucket = settings.s3_bucket_name
        if f"/{bucket}/" in media_url:
            return media_url.split(f"/{bucket}/", 1)[1]
        if f"{bucket}.s3." in media_url:
            return media_url.split(".amazonaws.com/", 1)[-1]
        return None

    def validate_upload(self, file_bytes: bytes, mime_type: str) -> Optional[str]:
        """
        Validate file size and type before upload.
        Returns error message if invalid, None if valid.
        """
        max_bytes = settings.media_max_upload_size_mb * 1024 * 1024
        if len(file_bytes) > max_bytes:
            return f"File too large. Maximum size: {settings.media_max_upload_size_mb}MB"

        if mime_type not in settings.media_allowed_types_list:
            return f"File type '{mime_type}' not allowed. Allowed: {settings.media_allowed_types}"

        return None


# Singleton instance
media_storage_service = MediaStorageService()
