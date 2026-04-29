"""
Spaces API endpoints.

Handles all operations related to shared spaces including:
- Space CRUD (create, read, update, delete)
- Member management (invite, remove, update roles)
- Content management (add, remove content from spaces)
- Invitation handling (accept invitations)

All endpoints require authentication via JWT token.
Permission checks enforce role-based access control.
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_
from typing import List
import secrets
import logging

from app.db.session import get_db
from app.models.user import User
from app.models.space import Space, SpaceMember, SpaceContent, SpaceInvitation, SpaceMemberRole
from app.models.content_item import ContentItem
from app.api.routes.auth import get_current_user
from app.api.schemas.space import (
    SpaceCreateRequest,
    SpaceUpdateRequest,
    SpaceInviteRequest,
    SpaceMemberUpdateRequest,
    SpaceContentAddRequest,
    SpaceResponse,
    SpaceDetailResponse,
    SpaceListResponse,
    SpaceMemberResponse,
    SpaceContentItemResponse,
    SpaceMemberRoleEnum
)
from datetime import datetime
from app.services.email_service import email_service
from app.core.config import settings

router = APIRouter(prefix="/spaces", tags=["Spaces"])
logger = logging.getLogger(__name__)


# ===== Permission Helpers =====

async def get_space_or_404(space_id: str, db: AsyncSession) -> Space:
    """
    Get space by ID or raise 404 if not found.

    Only returns active spaces (is_active=True).
    """
    result = await db.execute(
        select(Space).where(
            Space.id == space_id,
            Space.is_active == True
        )
    )
    space = result.scalar_one_or_none()
    if not space:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Space not found"
        )
    return space


async def get_user_membership(space_id: str, user_id: str, db: AsyncSession) -> SpaceMember:
    """
    Get user's membership in space or raise 403 if not a member.

    Returns:
        SpaceMember: The user's membership record

    Raises:
        HTTPException: 403 if user is not a member of the space
    """
    result = await db.execute(
        select(SpaceMember).where(
            SpaceMember.space_id == space_id,
            SpaceMember.user_id == user_id
        )
    )
    membership = result.scalar_one_or_none()
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this space"
        )
    return membership


def check_permission(membership: SpaceMember, required_role: SpaceMemberRole):
    """
    Check if user has required permission level.

    Role hierarchy (lowest to highest):
        viewer (0) < member (1) < admin (2) < owner (3)

    Args:
        membership: User's membership record
        required_role: Minimum required role

    Raises:
        HTTPException: 403 if user doesn't have sufficient permissions
    """
    role_hierarchy = {
        SpaceMemberRole.viewer: 0,
        SpaceMemberRole.member: 1,
        SpaceMemberRole.admin: 2,
        SpaceMemberRole.owner: 3
    }

    if role_hierarchy[membership.role] < role_hierarchy[required_role]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Insufficient permissions for this operation"
        )


# ===== Space CRUD =====

@router.post("", response_model=SpaceResponse, status_code=status.HTTP_201_CREATED)
async def create_space(
    request: SpaceCreateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Create a new shared space.

    The current user automatically becomes the owner of the space.
    A unique invite token is generated for sharing the space.
    """
    # Create space with generated invite token
    space = Space(
        name=request.name,
        description=request.description,
        emoji=request.emoji,
        accent_color=request.accent_color,
        created_by=current_user.id,
        invite_token=Space.generate_invite_token()
    )

    db.add(space)
    await db.flush()  # Get space.id before creating membership

    # Add creator as owner
    member = SpaceMember(
        space_id=space.id,
        user_id=current_user.id,
        role=SpaceMemberRole.owner
    )

    db.add(member)
    await db.commit()
    await db.refresh(space)

    # Build response
    return SpaceResponse(
        id=space.id,
        name=space.name,
        description=space.description,
        created_by=space.created_by,
        invite_token=space.invite_token,
        emoji=space.emoji,
        accent_color=space.accent_color,
        member_count=1,
        content_count=0,
        current_user_role=SpaceMemberRoleEnum.owner,
        created_at=space.created_at,
        updated_at=space.updated_at
    )


@router.get("", response_model=SpaceListResponse)
async def list_spaces(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    List all spaces the current user is a member of.

    Returns spaces ordered by creation date (newest first).
    Includes member and content counts for each space.
    """
    # Get spaces where user is a member
    result = await db.execute(
        select(Space)
        .join(SpaceMember, SpaceMember.space_id == Space.id)
        .where(
            SpaceMember.user_id == current_user.id,
            Space.is_active == True
        )
        .order_by(Space.created_at.desc())
    )
    spaces = result.scalars().all()

    # Build responses with member/content counts
    space_responses = []
    for space in spaces:
        # Get member count
        member_count_result = await db.execute(
            select(func.count(SpaceMember.id)).where(SpaceMember.space_id == space.id)
        )
        member_count = member_count_result.scalar()

        # Get content count
        content_count_result = await db.execute(
            select(func.count(SpaceContent.id)).where(SpaceContent.space_id == space.id)
        )
        content_count = content_count_result.scalar()

        # Get current user's role
        membership_result = await db.execute(
            select(SpaceMember.role).where(
                SpaceMember.space_id == space.id,
                SpaceMember.user_id == current_user.id
            )
        )
        role = membership_result.scalar()

        space_responses.append(SpaceResponse(
            id=space.id,
            name=space.name,
            description=space.description,
            created_by=space.created_by,
            invite_token=space.invite_token,
            emoji=space.emoji,
            accent_color=space.accent_color,
            member_count=member_count,
            content_count=content_count,
            current_user_role=SpaceMemberRoleEnum(role),
            created_at=space.created_at,
            updated_at=space.updated_at
        ))

    return SpaceListResponse(spaces=space_responses, total=len(space_responses))


@router.get("/explore", response_model=SpaceListResponse)
async def get_explore_spaces(
    limit: int = Query(20, ge=1, le=100, description="Number of spaces to return"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get recommended/trending public spaces for the Explore Spaces feature.

    Returns public spaces (is_public=True) ordered by member count (popularity).
    Used in the Search screen's "Explore Spaces" section.

    Query parameters:
    - limit: Maximum number of spaces to return (default: 20, max: 100)

    Example:
        GET /api/spaces/explore?limit=20

    Returns:
        SpaceListResponse with public spaces sorted by popularity
    """
    # Get public spaces ordered by member count (cached)
    query = select(Space).where(
        Space.is_public == True,
        Space.is_active == True
    ).order_by(
        Space.member_count.desc(),  # Most popular first
        Space.created_at.desc()  # Then newest
    ).limit(limit)

    result = await db.execute(query)
    spaces = result.scalars().all()

    space_responses = []
    for space in spaces:
        # Get actual member count (in case cache is stale)
        member_count_result = await db.execute(
            select(func.count(SpaceMember.id)).where(SpaceMember.space_id == space.id)
        )
        member_count = member_count_result.scalar()

        # Get content count
        content_count_result = await db.execute(
            select(func.count(SpaceContent.id)).where(SpaceContent.space_id == space.id)
        )
        content_count = content_count_result.scalar()

        # Check if current user is a member
        membership_result = await db.execute(
            select(SpaceMember.role).where(
                SpaceMember.space_id == space.id,
                SpaceMember.user_id == current_user.id
            )
        )
        role = membership_result.scalar_one_or_none()

        space_responses.append(SpaceResponse(
            id=space.id,
            name=space.name,
            description=space.description,
            created_by=space.created_by,
            invite_token=space.invite_token,
            emoji=space.emoji,
            accent_color=space.accent_color,
            member_count=member_count,
            content_count=content_count,
            current_user_role=SpaceMemberRoleEnum(role) if role else None,
            created_at=space.created_at,
            updated_at=space.updated_at
        ))

    return SpaceListResponse(spaces=space_responses, total=len(space_responses))


@router.get("/{space_id}", response_model=SpaceDetailResponse)
async def get_space(
    space_id: str,
    content_page: int = Query(1, ge=1, description="Page number for content items"),
    content_page_size: int = Query(20, ge=1, le=100, description="Items per page for content"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get detailed space information including members and content.

    Requires membership in the space.
    Returns full list of members and paginated content items.
    
    Content pagination:
    - Default: 20 items per page
    - Maximum: 100 items per page
    - Ordered by added_at descending (newest first)
    """
    space = await get_space_or_404(space_id, db)
    membership = await get_user_membership(space_id, current_user.id, db)

    # Get all members with user details
    members_result = await db.execute(
        select(SpaceMember, User)
        .join(User, SpaceMember.user_id == User.id)
        .where(SpaceMember.space_id == space_id)
        .order_by(SpaceMember.joined_at)
    )
    members_data = members_result.all()

    members = [
        SpaceMemberResponse(
            user_id=member.user_id,
            name=user.name,
            email=user.email,
            role=SpaceMemberRoleEnum(member.role),
            joined_at=member.joined_at
        )
        for member, user in members_data
    ]

    # Get total content count
    content_count_result = await db.execute(
        select(func.count(SpaceContent.id)).where(SpaceContent.space_id == space_id)
    )
    total_content_count = content_count_result.scalar()

    # Get paginated content with details
    offset = (content_page - 1) * content_page_size
    content_result = await db.execute(
        select(SpaceContent, ContentItem, User)
        .join(ContentItem, SpaceContent.content_id == ContentItem.id)
        .outerjoin(User, SpaceContent.added_by == User.id)
        .where(SpaceContent.space_id == space_id)
        .order_by(SpaceContent.added_at.desc())
        .limit(content_page_size)
        .offset(offset)
    )
    content_data = content_result.all()

    content_items = [
        SpaceContentItemResponse(
            id=content.id,
            title=content.title,
            url=content.url,
            summary=content.summary,
            category=content.category,
            added_at=space_content.added_at,
            added_by_name=user.name if user else None
        )
        for space_content, content, user in content_data
    ]

    # Get member count
    member_count = len(members)

    return SpaceDetailResponse(
        id=space.id,
        name=space.name,
        description=space.description,
        created_by=space.created_by,
        invite_token=space.invite_token,
        emoji=space.emoji,
        accent_color=space.accent_color,
        member_count=member_count,
        content_count=total_content_count,
        current_user_role=SpaceMemberRoleEnum(membership.role),
        created_at=space.created_at,
        updated_at=space.updated_at,
        members=members,
        content_items=content_items,
        content_page=content_page,
        content_page_size=content_page_size,
        content_total=total_content_count,
        content_has_more=(offset + len(content_items)) < total_content_count
    )


@router.patch("/{space_id}", response_model=SpaceResponse)
async def update_space(
    space_id: str,
    request: SpaceUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update space name and/or description.

    Requires: Admin or Owner role
    """
    space = await get_space_or_404(space_id, db)
    membership = await get_user_membership(space_id, current_user.id, db)
    check_permission(membership, SpaceMemberRole.admin)

    # Update fields if provided
    if request.name is not None:
        space.name = request.name
    if request.description is not None:
        space.description = request.description
    if request.emoji is not None:
        space.emoji = request.emoji
    if request.accent_color is not None:
        space.accent_color = request.accent_color

    space.updated_at = datetime.utcnow()
    await db.commit()
    await db.refresh(space)

    # Get counts
    member_count_result = await db.execute(
        select(func.count(SpaceMember.id)).where(SpaceMember.space_id == space.id)
    )
    member_count = member_count_result.scalar()

    content_count_result = await db.execute(
        select(func.count(SpaceContent.id)).where(SpaceContent.space_id == space.id)
    )
    content_count = content_count_result.scalar()

    return SpaceResponse(
        id=space.id,
        name=space.name,
        description=space.description,
        created_by=space.created_by,
        invite_token=space.invite_token,
        member_count=member_count,
        content_count=content_count,
        current_user_role=SpaceMemberRoleEnum(membership.role),
        created_at=space.created_at,
        updated_at=space.updated_at
    )


@router.post("/{space_id}/regenerate-invite", status_code=status.HTTP_200_OK)
async def regenerate_invite_token(
    space_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Regenerate space invite token (invalidates old links).

    Requires: Admin or Owner role

    Use cases:
    - Security: Token compromised or leaked
    - Control: Want to revoke all outstanding invitations
    """
    space = await get_space_or_404(space_id, db)
    membership = await get_user_membership(space_id, current_user.id, db)
    check_permission(membership, SpaceMemberRole.admin)

    # Regenerate token
    space.regenerate_invite_token()
    await db.commit()
    await db.refresh(space)

    return {
        "message": "Invite link regenerated successfully",
        "invite_token": space.invite_token
    }


@router.get("/{space_id}/invite-link", status_code=status.HTTP_200_OK)
async def get_invite_link(
    space_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Get current invite link for space.

    Requires: Member role or higher

    Returns full deep link URL ready for sharing.
    """
    space = await get_space_or_404(space_id, db)
    membership = await get_user_membership(space_id, current_user.id, db)

    # Build full deep link URL
    from app.core.config import settings
    invite_link = f"{settings.app_deep_link_url}/invite/{space.invite_token}"

    return {
        "invite_link": invite_link,
        "invite_token": space.invite_token,
        "space_name": space.name
    }


@router.delete("/{space_id}", status_code=status.HTTP_200_OK)
async def delete_space(
    space_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Delete a space (soft delete).

    Requires: Owner role

    The space is marked as inactive rather than being permanently deleted.
    This allows for potential recovery if needed.
    """
    space = await get_space_or_404(space_id, db)
    membership = await get_user_membership(space_id, current_user.id, db)
    check_permission(membership, SpaceMemberRole.owner)

    # Soft delete
    space.is_active = False
    space.updated_at = datetime.utcnow()
    await db.commit()

    return {"message": "Space deleted successfully"}


# ===== Member Management =====

@router.post("/join/{invite_token}", response_model=SpaceResponse, status_code=status.HTTP_200_OK)
async def join_space_via_invitation(
    invite_token: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Join a space using invite token.

    Anyone with a valid invite link can join as member.
    No email verification required - token is sufficient.
    """
    # Find space by invite token
    result = await db.execute(
        select(Space).where(
            Space.invite_token == invite_token,
            Space.is_active == True
        )
    )
    space = result.scalar_one_or_none()

    if not space:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or expired invite link"
        )

    # Check if already a member
    member_check = await db.execute(
        select(SpaceMember).where(
            SpaceMember.space_id == space.id,
            SpaceMember.user_id == current_user.id
        )
    )
    if member_check.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You are already a member of this space"
        )

    # Add as member with default role
    member = SpaceMember(
        space_id=space.id,
        user_id=current_user.id,
        role=SpaceMemberRole.member,  # Default role
        invited_by=None  # No specific inviter for link-based joins
    )

    db.add(member)
    await db.commit()
    await db.refresh(space)

    # Get counts for response
    member_count_result = await db.execute(
        select(func.count(SpaceMember.id)).where(SpaceMember.space_id == space.id)
    )
    member_count = member_count_result.scalar()

    content_count_result = await db.execute(
        select(func.count(SpaceContent.id)).where(SpaceContent.space_id == space.id)
    )
    content_count = content_count_result.scalar()

    # Return full space response
    return SpaceResponse(
        id=space.id,
        name=space.name,
        description=space.description,
        created_by=space.created_by,
        invite_token=space.invite_token,
        member_count=member_count,
        content_count=content_count,
        current_user_role=SpaceMemberRoleEnum.member,
        created_at=space.created_at,
        updated_at=space.updated_at
    )


@router.delete("/{space_id}/members/{user_id}", status_code=status.HTTP_200_OK)
async def remove_member(
    space_id: str,
    user_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Remove a member from space.

    Requires: Admin or Owner role

    Rules:
    - Owner can remove anyone except themselves
    - Admin can remove Member/Viewer but not Owner/Admin
    - Cannot remove the owner
    """
    space = await get_space_or_404(space_id, db)
    requester_membership = await get_user_membership(space_id, current_user.id, db)
    check_permission(requester_membership, SpaceMemberRole.admin)

    # Get target member
    result = await db.execute(
        select(SpaceMember).where(
            SpaceMember.space_id == space_id,
            SpaceMember.user_id == user_id
        )
    )
    target_membership = result.scalar_one_or_none()

    if not target_membership:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found"
        )

    # Cannot remove owner
    if target_membership.role == SpaceMemberRole.owner:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot remove space owner"
        )

    # Admin can only remove member/viewer
    if requester_membership.role == SpaceMemberRole.admin:
        if target_membership.role in [SpaceMemberRole.owner, SpaceMemberRole.admin]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Admins can only remove members and viewers"
            )

    await db.delete(target_membership)
    await db.commit()

    return {"message": "Member removed successfully"}


@router.patch("/{space_id}/members/{user_id}", status_code=status.HTTP_200_OK)
async def update_member_role(
    space_id: str,
    user_id: str,
    request: SpaceMemberUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Update member role.

    Requires: Owner role

    Rules:
    - Only owner can change roles
    - Cannot change owner's role
    - Cannot promote to owner (use transfer ownership instead)
    """
    space = await get_space_or_404(space_id, db)
    requester_membership = await get_user_membership(space_id, current_user.id, db)
    check_permission(requester_membership, SpaceMemberRole.owner)

    # Get target member
    result = await db.execute(
        select(SpaceMember).where(
            SpaceMember.space_id == space_id,
            SpaceMember.user_id == user_id
        )
    )
    target_membership = result.scalar_one_or_none()

    if not target_membership:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found"
        )

    # Cannot change owner's role
    if target_membership.role == SpaceMemberRole.owner:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cannot change owner's role"
        )

    # Update role
    target_membership.role = SpaceMemberRole(request.role.value)
    await db.commit()

    return {"message": "Member role updated successfully"}


# ===== Content Management =====

@router.post("/{space_id}/content", status_code=status.HTTP_201_CREATED)
async def add_content_to_space(
    space_id: str,
    request: SpaceContentAddRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Add content to space.

    Requires: Member role or higher

    The content must exist in the system. Content ownership
    remains with the original creator, but it becomes visible
    to all space members.
    """
    space = await get_space_or_404(space_id, db)
    membership = await get_user_membership(space_id, current_user.id, db)
    check_permission(membership, SpaceMemberRole.member)

    # Verify content exists
    content_result = await db.execute(
        select(ContentItem).where(ContentItem.id == request.content_id)
    )
    content = content_result.scalar_one_or_none()

    if not content:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Content not found"
        )

    # Check if already added
    existing_result = await db.execute(
        select(SpaceContent).where(
            SpaceContent.space_id == space_id,
            SpaceContent.content_id == request.content_id
        )
    )
    if existing_result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Content already exists in this space"
        )

    # Add content
    space_content = SpaceContent(
        space_id=space.id,
        content_id=request.content_id,
        added_by=current_user.id
    )

    db.add(space_content)
    await db.commit()

    return {"message": "Content added to space successfully"}


@router.delete("/{space_id}/content/{content_id}", status_code=status.HTTP_200_OK)
async def remove_content_from_space(
    space_id: str,
    content_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    """
    Remove content from space.

    Requires: Admin role or higher, OR being the content owner

    This only removes the content from the space, it doesn't delete
    the content itself. The original content remains in the creator's library.
    """
    space = await get_space_or_404(space_id, db)
    membership = await get_user_membership(space_id, current_user.id, db)

    # Get space content
    result = await db.execute(
        select(SpaceContent, ContentItem)
        .join(ContentItem, SpaceContent.content_id == ContentItem.id)
        .where(
            SpaceContent.space_id == space_id,
            SpaceContent.content_id == content_id
        )
    )
    data = result.one_or_none()

    if not data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Content not found in this space"
        )

    space_content, content = data

    # Check permission: Admin/Owner OR content creator
    if membership.role not in [SpaceMemberRole.admin, SpaceMemberRole.owner]:
        if content.user_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only admins or content owner can remove content"
            )

    await db.delete(space_content)
    await db.commit()

    return {"message": "Content removed from space successfully"}
