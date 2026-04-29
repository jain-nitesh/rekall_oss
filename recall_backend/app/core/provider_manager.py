"""
OpenAI Provider Singleton Manager.

Manages the lifecycle of the OpenAI provider to prevent HTTP connection leaks.
The provider is initialized at application startup and cleaned up at shutdown.
"""
import logging
from typing import Optional
from app.services.openai_provider import OpenAIProvider

logger = logging.getLogger(__name__)

# Global singleton instance
_openai_provider_instance: Optional[OpenAIProvider] = None


async def initialize_openai_provider() -> None:
    """
    Initialize the OpenAI provider singleton.
    Called at application startup.
    """
    global _openai_provider_instance

    if _openai_provider_instance is not None:
        logger.warning("OpenAI provider already initialized")
        return

    logger.info("Initializing OpenAI provider singleton...")
    _openai_provider_instance = OpenAIProvider()
    await _openai_provider_instance.__aenter__()
    logger.info("OpenAI provider initialized successfully")


async def cleanup_openai_provider() -> None:
    """
    Cleanup the OpenAI provider singleton.
    Called at application shutdown.
    """
    global _openai_provider_instance

    if _openai_provider_instance is None:
        logger.warning("OpenAI provider not initialized, nothing to cleanup")
        return

    logger.info("Cleaning up OpenAI provider...")
    try:
        await _openai_provider_instance.__aexit__(None, None, None)
        _openai_provider_instance = None
        logger.info("OpenAI provider cleaned up successfully")
    except Exception as e:
        logger.error(f"Error cleaning up OpenAI provider: {e}", exc_info=True)
        raise


def get_openai_provider() -> OpenAIProvider:
    """
    Get the OpenAI provider singleton instance.

    Returns:
        OpenAIProvider: The initialized provider instance

    Raises:
        RuntimeError: If provider not initialized (startup not called)
    """
    if _openai_provider_instance is None:
        raise RuntimeError(
            "OpenAI provider not initialized. "
            "Ensure initialize_openai_provider() is called at startup."
        )

    return _openai_provider_instance
