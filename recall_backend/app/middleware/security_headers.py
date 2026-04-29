"""
Security headers middleware for production security.

Adds important security headers to all HTTP responses to protect against
common web vulnerabilities:
- HSTS: Forces HTTPS connections
- X-Content-Type-Options: Prevents MIME-type sniffing
- X-Frame-Options: Prevents clickjacking attacks
- X-XSS-Protection: Enables XSS filter in older browsers
- Referrer-Policy: Controls referrer information
"""
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from typing import Callable
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """
    Middleware that adds security headers to all HTTP responses.

    Headers are only added in production to avoid interfering with
    local development (e.g., HSTS can cause issues with localhost).
    """

    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """
        Add security headers to the response.

        Args:
            request: Incoming HTTP request
            call_next: Next middleware/route handler in the chain

        Returns:
            Response with security headers added
        """
        # Call the next middleware/route handler
        response = await call_next(request)

        # Check if this is the invite page (needs inline styles/scripts)
        is_invite_page = request.url.path.startswith('/invite/')

        # Only add strict security headers in production
        if settings.is_production:
            # HSTS (HTTP Strict Transport Security)
            # Forces browsers to only use HTTPS for the next year
            # Protects against: SSL stripping attacks, protocol downgrade attacks
            response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'

            # X-Content-Type-Options
            # Prevents browsers from MIME-sniffing a response away from declared content-type
            # Protects against: MIME confusion attacks, drive-by downloads
            response.headers['X-Content-Type-Options'] = 'nosniff'

            # X-Frame-Options
            # Prevents the page from being displayed in an iframe
            # Protects against: Clickjacking attacks
            response.headers['X-Frame-Options'] = 'DENY'

            # X-XSS-Protection
            # Enables XSS filter in older browsers (modern browsers use CSP instead)
            # Protects against: Cross-site scripting attacks
            response.headers['X-XSS-Protection'] = '1; mode=block'

            # Referrer-Policy
            # Controls how much referrer information is sent with requests
            # Protects against: Information leakage via referrer header
            response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'

            # Content-Security-Policy (CSP)
            # Controls which resources can be loaded (scripts, styles, images, etc.)
            # Protects against: XSS attacks, data injection attacks
            # Note: This is a basic CSP. Adjust based on your needs.
            # For API-only backend, a restrictive policy is appropriate
            if is_invite_page:
                # For invite page: Allow inline styles and scripts since it's a self-contained HTML page
                response.headers['Content-Security-Policy'] = "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'"
            else:
                # For API endpoints: Strict CSP
                response.headers['Content-Security-Policy'] = "default-src 'self'; frame-ancestors 'none'"

            # Permissions-Policy (formerly Feature-Policy)
            # Controls which browser features can be used
            # Protects against: Unauthorized use of device features (camera, microphone, etc.)
            response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'

            logger.debug("Added production security headers")

        else:
            # In development/staging, add minimal headers
            response.headers['X-Content-Type-Options'] = 'nosniff'
            response.headers['X-Frame-Options'] = 'DENY'

        return response
