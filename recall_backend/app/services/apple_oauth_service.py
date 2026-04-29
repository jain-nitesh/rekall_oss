"""
Apple Sign-In service for verifying identity tokens.

Uses PyJWT to verify tokens issued by Apple, fetching Apple's public keys (JWKS).
"""
import jwt
import time
import logging
from typing import Optional
import httpx
from app.core.config import settings

logger = logging.getLogger(__name__)

# Apple's JWKS endpoint
APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys"
APPLE_ISSUER = "https://appleid.apple.com"

# Cache for Apple's public keys
_jwks_cache: Optional[dict] = None
_jwks_cache_time: float = 0
JWKS_CACHE_TTL = 3600  # 1 hour


def _get_apple_public_keys() -> dict:
    """
    Fetch Apple's public keys from their JWKS endpoint.
    Caches keys for 1 hour to avoid unnecessary network requests.
    """
    global _jwks_cache, _jwks_cache_time

    now = time.time()
    if _jwks_cache and (now - _jwks_cache_time) < JWKS_CACHE_TTL:
        return _jwks_cache

    try:
        response = httpx.get(APPLE_JWKS_URL, timeout=10)
        response.raise_for_status()
        _jwks_cache = response.json()
        _jwks_cache_time = now
        logger.info("Fetched Apple JWKS public keys")
        return _jwks_cache
    except Exception as e:
        logger.error(f"Failed to fetch Apple JWKS: {e}")
        if _jwks_cache:
            return _jwks_cache
        raise


class AppleOAuthService:
    """Service for Apple Sign-In operations."""

    def __init__(self):
        self.bundle_id = settings.apple_bundle_id

    def verify_id_token(self, token: str) -> Optional[dict]:
        """
        Verify Apple identity token and extract user information.

        Args:
            token: Apple identity token (JWT) from mobile client

        Returns:
            Dictionary with user info:
            {
                "apple_id": "001234.abcdef...",
                "email": "user@example.com",
                "email_verified": True,
                "is_private_email": False
            }

            Returns None if verification fails.
        """
        try:
            # Get Apple's public keys
            jwks = _get_apple_public_keys()

            # Decode the token header to find the key ID (kid)
            unverified_header = jwt.get_unverified_header(token)
            kid = unverified_header.get("kid")

            if not kid:
                logger.error("Apple token missing 'kid' in header")
                return None

            # Find the matching public key
            matching_key = None
            for key in jwks.get("keys", []):
                if key["kid"] == kid:
                    matching_key = key
                    break

            if not matching_key:
                # Key not found - clear cache and retry once
                global _jwks_cache_time
                _jwks_cache_time = 0
                jwks = _get_apple_public_keys()
                for key in jwks.get("keys", []):
                    if key["kid"] == kid:
                        matching_key = key
                        break

            if not matching_key:
                logger.error(f"No matching Apple public key found for kid: {kid}")
                return None

            # Convert JWK to PEM public key
            public_key = jwt.algorithms.RSAAlgorithm.from_jwk(matching_key)

            # Verify and decode the token
            claims = jwt.decode(
                token,
                public_key,
                algorithms=["RS256"],
                audience=self.bundle_id,
                issuer=APPLE_ISSUER,
            )

            # Extract user information
            return {
                "apple_id": claims["sub"],
                "email": claims.get("email", ""),
                "email_verified": claims.get("email_verified", False),
                "is_private_email": claims.get("is_private_email", False),
            }

        except jwt.ExpiredSignatureError:
            logger.error("Apple token has expired")
            return None
        except jwt.InvalidAudienceError:
            logger.error("Apple token has invalid audience")
            return None
        except jwt.InvalidIssuerError:
            logger.error("Apple token has invalid issuer")
            return None
        except jwt.PyJWTError as e:
            logger.error(f"Apple token verification failed: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error verifying Apple token: {e}")
            return None


# Singleton instance
apple_oauth_service = AppleOAuthService()
