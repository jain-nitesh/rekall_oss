"""
Request size limit middleware for DoS protection.

Prevents large payloads from consuming server resources.
Limits the maximum size of request bodies to prevent:
- Memory exhaustion attacks
- Bandwidth consumption attacks
- Slow upload attacks
"""
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response, JSONResponse
from typing import Callable
import logging

logger = logging.getLogger(__name__)

# Default maximum request size: 10MB
# This is reasonable for:
# - Content ingestion with shared_text (up to 10,000 chars ≈ 10KB)
# - API requests with metadata
# - JSON payloads with embedded content
DEFAULT_MAX_SIZE = 10 * 1024 * 1024  # 10 MB in bytes


class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """
    Middleware that limits the maximum size of HTTP request bodies.

    This prevents attackers from sending extremely large payloads that could:
    - Exhaust server memory
    - Consume excessive bandwidth
    - Cause denial of service

    Requests exceeding the limit are rejected with HTTP 413 (Payload Too Large).
    """

    def __init__(self, app, max_upload_size: int = DEFAULT_MAX_SIZE):
        """
        Initialize request size limit middleware.

        Args:
            app: FastAPI application
            max_upload_size: Maximum request body size in bytes (default: 10MB)
        """
        super().__init__(app)
        self.max_upload_size = max_upload_size
        logger.info(f"Request size limit middleware initialized: {max_upload_size / 1024 / 1024:.1f} MB")

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """
        Check request size before processing.

        Args:
            request: Incoming HTTP request
            call_next: Next middleware/route handler

        Returns:
            Response (413 if too large, otherwise normal response)
        """
        # Get Content-Length header (provided by client)
        content_length = request.headers.get('content-length')

        if content_length:
            try:
                content_length = int(content_length)

                # Check if request exceeds size limit
                if content_length > self.max_upload_size:
                    logger.warning(
                        f"Request rejected: size {content_length / 1024 / 1024:.1f} MB "
                        f"exceeds limit {self.max_upload_size / 1024 / 1024:.1f} MB "
                        f"(path: {request.url.path})"
                    )
                    return JSONResponse(
                        status_code=413,
                        content={
                            "detail": f"Request payload too large. Maximum size: {self.max_upload_size / 1024 / 1024:.1f} MB"
                        }
                    )

            except ValueError:
                # Invalid Content-Length header - let it proceed
                # (will fail with different error if malformed)
                logger.warning(f"Invalid Content-Length header: {content_length}")

        # Request size is acceptable, proceed
        response = await call_next(request)
        return response
