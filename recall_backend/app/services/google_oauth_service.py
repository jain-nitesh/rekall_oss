"""
Google OAuth service for verifying ID tokens.

Uses google-auth library to verify tokens issued by Google.
"""
from google.oauth2 import id_token
from google.auth.transport import requests
from typing import Optional
import logging
from app.core.config import settings

logger = logging.getLogger(__name__)


class GoogleOAuthService:
    """Service for Google OAuth operations."""

    def __init__(self):
        # All valid client IDs (Android, iOS, Web)
        self.valid_client_ids = [
            settings.google_oauth_client_id_android,
            settings.google_oauth_client_id_ios,
            settings.google_oauth_client_id_web,
        ]
        # Filter out empty strings
        self.valid_client_ids = [cid for cid in self.valid_client_ids if cid]

    def verify_id_token(self, token: str) -> Optional[dict]:
        """
        Verify Google ID token and extract user information.

        Args:
            token: Google ID token from mobile client

        Returns:
            Dictionary with user info:
            {
                "google_id": "123456789",
                "email": "user@gmail.com",
                "name": "John Doe",
                "picture": "https://..."
            }

            Returns None if verification fails.
        """
        try:
            # Verify token with Google
            # This validates:
            # - Token signature (issued by Google)
            # - Token expiration
            # - Token audience (client ID)
            idinfo = id_token.verify_oauth2_token(
                token,
                requests.Request(),
                # Accept any of our configured client IDs
                clock_skew_in_seconds=10  # Allow small clock skew
            )

            # Verify audience (client ID)
            if idinfo.get('aud') not in self.valid_client_ids:
                logger.error(f"Invalid audience: {idinfo.get('aud')}")
                return None

            # Verify issuer (must be Google)
            if idinfo['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
                logger.error(f"Invalid issuer: {idinfo.get('iss')}")
                return None

            # Extract user information
            return {
                "google_id": idinfo['sub'],  # Unique Google user ID
                "email": idinfo['email'],
                "email_verified": idinfo.get('email_verified', False),
                "name": idinfo.get('name', ''),
                "picture": idinfo.get('picture', ''),
            }

        except ValueError as e:
            # Token verification failed
            logger.error(f"Google token verification failed: {e}")
            return None


# Singleton instance
google_oauth_service = GoogleOAuthService()
