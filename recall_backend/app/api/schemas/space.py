"""
Pydantic schemas for space requests and responses.

These schemas define the structure of data sent to and received from
the Spaces API endpoints. They provide automatic validation and
documentation for the API.
"""
from pydantic import BaseModel, Field, EmailStr, field_validator
from datetime import datetime
from uuid import UUID
from typing import Optional, List
from enum import Enum


class SpaceMemberRoleEnum(str, Enum):
    """
    Member role enum for API requests/responses.

    Must match the database enum type space_member_role.
    """
    owner = "owner"
    admin = "admin"
    member = "member"
    viewer = "viewer"


# ===== Request Schemas =====

class SpaceCreateRequest(BaseModel):
    """
    Request to create a new space.

    Example:
        {
            "name": "Machine Learning Resources",
            "description": "Collaborative space for ML articles and papers"
        }
    """
    name: str = Field(..., min_length=1, max_length=255, description="Space name")
    description: Optional[str] = Field(None, max_length=5000, description="Space description")
    emoji: Optional[str] = Field(None, max_length=10, description="Emoji icon for space")
    accent_color: Optional[str] = Field(None, max_length=7, description="Hex accent color e.g. #FF5733")

    class Config:
        json_schema_extra = {
            "example": {
                "name": "Machine Learning Resources",
                "description": "Collaborative space for ML articles and papers",
                "emoji": "🧠",
                "accent_color": "#6C5CE7"
            }
        }


class SpaceUpdateRequest(BaseModel):
    """
    Request to update space details.

    All fields are optional - only provided fields will be updated.
    """
    name: Optional[str] = Field(None, min_length=1, max_length=255)
    description: Optional[str] = Field(None, max_length=5000)
    emoji: Optional[str] = Field(None, max_length=10)
    accent_color: Optional[str] = Field(None, max_length=7)

    class Config:
        json_schema_extra = {
            "example": {
                "name": "Updated Space Name",
                "description": "Updated description",
                "emoji": "🚀",
                "accent_color": "#00B894"
            }
        }


class SpaceInviteRequest(BaseModel):
    """
    Request to invite a user to space via email.

    For existing users: They receive email and can join immediately
    For new users: They receive magic link to signup + auto-join
    """
    email: EmailStr = Field(..., description="Email address of person to invite")
    role: SpaceMemberRoleEnum = Field(default=SpaceMemberRoleEnum.member, description="Role to assign")

    @field_validator('role')
    @classmethod
    def role_cannot_be_owner(cls, v):
        """Validate that role is not owner (only one owner per space)."""
        if v == SpaceMemberRoleEnum.owner:
            raise ValueError("Cannot invite as owner role. Transfer ownership instead.")
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "email": "colleague@example.com",
                "role": "member"
            }
        }


class SpaceMemberUpdateRequest(BaseModel):
    """
    Request to update member role.

    Only owner can change roles.
    """
    role: SpaceMemberRoleEnum = Field(..., description="New role to assign")

    @field_validator('role')
    @classmethod
    def role_cannot_be_owner(cls, v):
        """Validate that role is not owner (use transfer ownership instead)."""
        if v == SpaceMemberRoleEnum.owner:
            raise ValueError("Cannot change role to owner. Use transfer ownership endpoint instead.")
        return v

    class Config:
        json_schema_extra = {
            "example": {
                "role": "admin"
            }
        }


class SpaceContentAddRequest(BaseModel):
    """
    Request to add content to space.

    Content must exist and user must have access to it.
    """
    content_id: UUID = Field(..., description="ID of content item to add")

    class Config:
        json_schema_extra = {
            "example": {
                "content_id": "550e8400-e29b-41d4-a716-446655440000"
            }
        }


# ===== Response Schemas =====

class SpaceMemberResponse(BaseModel):
    """
    Member information in space.

    Includes user details and their role/join date.
    """
    user_id: UUID = Field(..., description="User's unique ID")
    name: str = Field(..., description="User's display name")
    email: str = Field(..., description="User's email address")
    role: SpaceMemberRoleEnum = Field(..., description="User's role in this space")
    joined_at: datetime = Field(..., description="When user joined this space")

    class Config:
        from_attributes = True
        json_schema_extra = {
            "example": {
                "user_id": "550e8400-e29b-41d4-a716-446655440000",
                "name": "John Doe",
                "email": "john@example.com",
                "role": "member",
                "joined_at": "2025-01-01T00:00:00Z"
            }
        }


class SpaceContentItemResponse(BaseModel):
    """
    Content item in space (simplified view).

    Shows basic content info plus who added it to the space.
    """
    id: UUID = Field(..., description="Content item ID")
    title: str = Field(..., description="Content title")
    url: str = Field(..., description="Content URL")
    summary: str = Field(..., description="AI-generated summary")
    category: str = Field(..., description="Content category")
    added_at: datetime = Field(..., description="When content was added to space")
    added_by_name: Optional[str] = Field(None, description="Name of user who added content")

    class Config:
        from_attributes = True
        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "title": "Introduction to Transformers",
                "url": "https://example.com/article",
                "summary": "A comprehensive guide to transformer architectures...",
                "category": "technology",
                "added_at": "2025-01-15T10:30:00Z",
                "added_by_name": "Jane Smith"
            }
        }


class SpaceResponse(BaseModel):
    """
    Basic space information.

    Includes metadata and counts but not full member/content lists.
    Used in list views and after create/update operations.
    """
    id: UUID = Field(..., description="Space unique ID")
    name: str = Field(..., description="Space name")
    description: Optional[str] = Field(None, description="Space description")
    created_by: Optional[UUID] = Field(None, description="ID of user who created space")
    invite_token: str = Field(..., description="Token for sharing space invite link")
    emoji: Optional[str] = Field(None, description="Emoji icon for space")
    accent_color: Optional[str] = Field(None, description="Hex accent color")
    member_count: int = Field(..., description="Number of members in space")
    content_count: int = Field(..., description="Number of content items in space")
    current_user_role: Optional[SpaceMemberRoleEnum] = Field(None, description="Current user's role in space")
    created_at: datetime = Field(..., description="When space was created")
    updated_at: Optional[datetime] = Field(None, description="When space was last updated")

    class Config:
        from_attributes = True
        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "name": "ML Resources",
                "description": "Machine learning articles",
                "created_by": "550e8400-e29b-41d4-a716-446655440001",
                "invite_token": "abc123def456...",
                "member_count": 5,
                "content_count": 23,
                "current_user_role": "owner",
                "created_at": "2025-01-01T00:00:00Z",
                "updated_at": "2025-01-15T10:00:00Z"
            }
        }


class SpaceDetailResponse(SpaceResponse):
    """
    Detailed space response with full members and paginated content list.

    Extends SpaceResponse with complete member and paginated content information.
    Used in space detail view.
    
    Content pagination:
    - content_items: Current page of content items
    - content_page: Current page number (1-indexed)
    - content_page_size: Items per page
    - content_total: Total number of content items
    - content_has_more: Whether more pages are available
    """
    members: List[SpaceMemberResponse] = Field(default_factory=list, description="List of space members")
    content_items: List[SpaceContentItemResponse] = Field(default_factory=list, description="List of content in space (paginated)")
    content_page: int = Field(1, description="Current page number for content (1-indexed)")
    content_page_size: int = Field(20, description="Items per page for content")
    content_total: int = Field(..., description="Total number of content items")
    content_has_more: bool = Field(False, description="Whether more content pages are available")

    class Config:
        from_attributes = True


class SpaceListResponse(BaseModel):
    """
    List of spaces response.

    Used for GET /spaces endpoint.
    """
    spaces: List[SpaceResponse] = Field(default_factory=list, description="List of spaces")
    total: int = Field(..., description="Total number of spaces")

    class Config:
        json_schema_extra = {
            "example": {
                "spaces": [],
                "total": 0
            }
        }


class SpaceInvitationResponse(BaseModel):
    """
    Space invitation response.

    Shows pending invitation details.
    """
    id: UUID = Field(..., description="Invitation ID")
    space_id: UUID = Field(..., description="Space ID")
    space_name: str = Field(..., description="Space name")
    email: str = Field(..., description="Invited email address")
    role: SpaceMemberRoleEnum = Field(..., description="Role to be assigned")
    expires_at: datetime = Field(..., description="When invitation expires")
    created_at: datetime = Field(..., description="When invitation was created")

    class Config:
        from_attributes = True
        json_schema_extra = {
            "example": {
                "id": "550e8400-e29b-41d4-a716-446655440000",
                "space_id": "550e8400-e29b-41d4-a716-446655440001",
                "space_name": "ML Resources",
                "email": "colleague@example.com",
                "role": "member",
                "expires_at": "2025-01-08T00:00:00Z",
                "created_at": "2025-01-01T00:00:00Z"
            }
        }
