"""
User-related schemas for request/response validation.
"""
from pydantic import BaseModel, Field
from typing import Optional, List, Dict
from datetime import datetime


class UsageStats(BaseModel):
    """User's AI usage statistics"""
    ai_summaries_used: int
    monthly_limit: int
    plan: str  # "free", "pro", "enterprise"

    model_config = {
        "from_attributes": True
    }


class UserPreferences(BaseModel):
    """User preferences"""
    summary_style: str  # "bullet_points", "paragraph", "concise"
    auto_categorize: bool
    connected_sources: Optional[List[str]] = None  # ["twitter", "reddit", etc.]
    daily_gems_enabled: bool = False
    daily_gems_time: str = "9:00 AM"

    model_config = {
        "from_attributes": True
    }


class DeleteAccountRequest(BaseModel):
    """Request to delete user account. Requires email confirmation."""
    confirmation_email: str = Field(..., description="User's email to confirm deletion intent")


class UserPreferencesUpdate(BaseModel):
    """Request to update user preferences"""
    summary_style: Optional[str] = None
    auto_categorize: Optional[bool] = None
    connected_sources: Optional[List[str]] = None
    daily_gems_enabled: Optional[bool] = None
    daily_gems_time: Optional[str] = None


class SeedPersonalInfoRequest(BaseModel):
    """Request to seed personal information about the user."""
    bio: Optional[str] = Field(None, max_length=2000, description="Free text bio about the user")
    social_links: Optional[Dict[str, str]] = Field(
        None,
        description="Social media links: {'linkedin': 'url', 'twitter': 'url', 'facebook': 'url', 'instagram': 'url', 'github': 'url', 'website': 'url'}"
    )


class PersonalInfoResponse(BaseModel):
    """Response with user's personal information."""
    entity_id: Optional[str] = None
    name: str
    bio: Optional[str] = None
    social_links: Optional[Dict[str, str]] = None
    enriched_data: Optional[Dict[str, dict]] = None
    last_refreshed_at: Optional[datetime] = None
