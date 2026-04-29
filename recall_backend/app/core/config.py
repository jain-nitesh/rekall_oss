from typing import Literal
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """
    Application settings managed by pydantic-settings.
    Reads from environment variables and .env file.
    """
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore"
    )

    # Application Settings
    app_name: str = "ReKall"
    app_version: str = "1.0.0"
    debug: bool = False
    environment: Literal["development", "staging", "production"] = "development"

    # Database Settings
    database_url: str = "postgresql://postgres:postgres@localhost:5432/recall"

    # AI Provider Configuration (CORE FEATURE)
    ai_provider: Literal["ollama", "openai"] = "ollama"
    ai_enabled: bool = True  # Feature flag: Enable/disable AI processing

    # Embedding & Semantic Search Settings
    embedding_dimensions: int = 1536
    semantic_search_threshold: float = 0.3

    # Ollama Settings
    ollama_base_url: str = "http://localhost:11434"
    ollama_extraction_model: str = "llama3"
    ollama_embedding_model: str = "nomic-embed-text"

    # OpenAI Settings
    openai_api_key: str = ""
    openai_extraction_model: str = "gpt-4o-mini"
    openai_embedding_model: str = "text-embedding-3-small"

    # JWT Settings
    jwt_secret_key: str = "your-secret-key-change-in-production"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 60 * 24 * 3  # 3 days (reduced from 7)
    jwt_refresh_token_expire_minutes: int = 60 * 24 * 30  # 30 days

    # Google OAuth Settings
    google_oauth_client_id_android: str = ""
    google_oauth_client_id_ios: str = ""
    google_oauth_client_id_web: str = ""

    # Apple Sign-In Settings
    apple_bundle_id: str = "com.rekallhq.rekall"

    # Server Settings
    host: str = "0.0.0.0"
    port: int = 8000

    # Firebase Settings
    firebase_service_account_path: str = "./firebase-service-account.json"

    # CORS Settings
    cors_origins: str = "*"  # Comma-separated list, or "*" for all

    # Rate Limiting
    rate_limit_enabled: bool = True
    rate_limit_per_minute: int = 60  # Requests per minute per IP

    # AI Processing Settings
    ai_rate_limit_delay: int = 5  # Seconds to wait between AI processing tasks
    ai_max_retries: int = 5       # Max AI retry attempts before giving up (increased for exponential backoff)
    ai_exponential_backoff_enabled: bool = True  # Enable exponential backoff for AI retries
    ai_base_retry_delay_minutes: int = 2  # Base delay for exponential backoff (doubles each attempt)

    # Content Ingestion Settings
    ingestion_max_retries: int = 5  # Max ingestion retry attempts (increased for exponential backoff)
    ingestion_exponential_backoff_enabled: bool = True  # Enable exponential backoff for ingestion retries
    ingestion_base_retry_delay_minutes: int = 2  # Base delay for exponential backoff

    # Trending News Cache Settings
    news_cache_ttl_seconds: int = 21600  # 6 hours

    # Background Processing Settings
    retry_interval_seconds: int = 30  # Interval for periodic retry task (default: 30 seconds)

    # Task Concurrency Settings (Memory Leak Prevention)
    max_concurrent_ingestion_tasks: int = 10  # Max concurrent content ingestion tasks
    max_concurrent_ai_tasks: int = 5          # Max concurrent AI processing tasks (lower due to cost/memory)

    # Playwright Browser Pool Settings (Performance Optimization)
    playwright_pool_size: int = 2  # Number of browser instances in pool (2 optimal for 512MB RAM)
    playwright_enabled: bool = True  # Feature flag to disable browser pooling if needed
    playwright_selective_mode: bool = False  # Only use Playwright for known JS-heavy domains (reduces usage by 70-80%)
    playwright_force_domains: str = ""  # Comma-separated domains that should always use Playwright
    playwright_skip_domains: str = ""  # Comma-separated domains that should never use Playwright
    playwright_retry_social_domains: str = "instagram.com,pinterest.com,tiktok.com,twitter.com,facebook.com,snapchat.com,x.com,reddit.com"

    # Social Enrichment Settings
    social_refresh_interval_days: int = 7  # How often to re-scrape social links for self-entity

    # Email Settings (for magic links)
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from_email: str = "noreply@<YOUR_DOMAIN>.com"
    smtp_use_tls: bool = True

    # Media Storage Settings (Cloudflare R2 / S3-compatible)
    media_storage_provider: Literal["local", "s3"] = "local"
    s3_bucket_name: str = "recall-media"
    s3_region: str = "auto"
    s3_endpoint_url: str = ""  # R2/MinIO endpoint URL
    s3_access_key_id: str = ""
    s3_secret_access_key: str = ""
    media_max_upload_size_mb: int = 50
    media_allowed_types: str = "image/jpeg,image/png,image/webp,video/mp4,video/quicktime"

    # Vision/OCR Settings
    ocr_fallback_to_tesseract: bool = True
    ollama_vision_model: str = "llava"
    video_max_key_frames: int = 3

    # Backend base URL (for magic link callbacks)
    backend_base_url: str = "http://localhost:8000"

    # Mobile app deep link URL (for space invitations)
    app_deep_link_url: str = "https://YOUR_DEEP_LINK_URL"

    # App Store URLs (for invite fallback page)
    app_store_url: str = "https://apps.apple.com/app/rekall"
    play_store_url: str = "https://play.google.com/store/apps/details?id=com.rekallhq.rekall"

    # Attribution Settings
    attribution_match_window_hours: int = 168  # 7 days
    attribution_desktop_fallback_url: str = "https://YOUR_DOMAIN.com"
    admin_emails: str = ""  # Comma-separated list of admin emails

    @property
    def cors_origins_list(self) -> list[str]:
        """
        Parse CORS origins from comma-separated string.

        Security: Wildcard (*) is blocked in production to prevent
        unauthorized cross-origin requests.
        """
        if self.cors_origins == "*":
            if self.is_production:
                raise ValueError(
                    "CORS wildcard (*) is not allowed in production. "
                    "Set CORS_ORIGINS to specific allowed origins (e.g., 'https://YOUR_DOMAIN.com,https://app.YOUR_DOMAIN.com')"
                )
            return ["*"]
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @property
    def is_ollama(self) -> bool:
        """Check if Ollama is the active provider."""
        return self.ai_provider == "ollama"

    @property
    def is_openai(self) -> bool:
        """Check if OpenAI is the active provider."""
        return self.ai_provider == "openai"

    @property
    def extraction_model(self) -> str:
        """Get the extraction model based on active provider."""
        return self.ollama_extraction_model if self.is_ollama else self.openai_extraction_model

    @property
    def embedding_model(self) -> str:
        """Get the embedding model based on active provider."""
        return self.ollama_embedding_model if self.is_ollama else self.openai_embedding_model

    @property
    def is_production(self) -> bool:
        """Check if running in production environment."""
        return self.environment == "production"

    @property
    def admin_emails_list(self) -> list[str]:
        """Parse admin emails from comma-separated string."""
        return [e.strip().lower() for e in self.admin_emails.split(",") if e.strip()]

    @property
    def media_allowed_types_list(self) -> list[str]:
        """Parse allowed media types from comma-separated string."""
        return [t.strip() for t in self.media_allowed_types.split(",") if t.strip()]

    @property
    def playwright_force_domains_list(self) -> list[str]:
        """Parse force-Playwright domains from comma-separated string."""
        return [d.strip().lower() for d in self.playwright_force_domains.split(",") if d.strip()]

    @property
    def playwright_skip_domains_list(self) -> list[str]:
        """Parse skip-Playwright domains from comma-separated string."""
        return [d.strip().lower() for d in self.playwright_skip_domains.split(",") if d.strip()]

    @property
    def playwright_retry_social_domains_list(self) -> list[str]:
        """Parse social domains that should trigger Playwright retry checks."""
        return [d.strip().lower() for d in self.playwright_retry_social_domains.split(",") if d.strip()]



# Global settings instance
settings = Settings()
