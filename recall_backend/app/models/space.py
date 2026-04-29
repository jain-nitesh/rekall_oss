"""
Space database models.
Represents shared spaces and their relationships for collaborative content sharing.

This module defines 4 models:
1. Space - Main shared space
2. SpaceMember - User membership in spaces (with roles)
3. SpaceContent - Content items shared in spaces
4. SpaceInvitation - Pending invitations to join spaces
"""
from sqlalchemy import Column, String, DateTime, Boolean, Text, ForeignKey, Enum as SQLEnum
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
import uuid
from datetime import datetime, timedelta
from enum import Enum
from app.db.session import Base
import secrets


class SpaceMemberRole(str, Enum):
    """
    Member roles in a shared space.

    Permissions hierarchy (lowest to highest):
    - viewer: Read-only access to space content
    - member: Can add content to space
    - admin: Can manage members (invite/remove), add/remove content
    - owner: Full control (delete space, manage all members, transfer ownership)
    """
    viewer = "viewer"
    member = "member"
    admin = "admin"
    owner = "owner"


class Space(Base):
    """
    Shared space model for collaborative content organization.

    A space is a collaborative environment where multiple users can:
    - Share content items
    - Organize resources together
    - Invite others to collaborate

    Access is controlled through role-based permissions (SpaceMemberRole).
    """
    __tablename__ = "spaces"

    # Primary key
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Space details
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)

    # Owner reference (nullable to handle owner deletion)
    # ON DELETE SET NULL allows space to persist if owner deletes account
    # First admin can claim ownership of orphaned spaces
    created_by = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )

    # Visual identity
    emoji = Column(String(10), nullable=True)
    accent_color = Column(String(7), nullable=True)  # Hex color e.g. #FF5733

    # Invite token for sharing
    # Generated using secrets.token_urlsafe(32) for cryptographic security
    invite_token = Column(String(255), unique=True, nullable=False, index=True)

    # Optional expiration for invite links (e.g., time-limited invitations)
    invite_token_expires_at = Column(DateTime, nullable=True)

    # Soft delete flag
    # Allows archiving spaces without losing data
    is_active = Column(Boolean, default=True, index=True)

    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    # Relationships
    # back_populates creates bidirectional relationships
    # cascade="all, delete-orphan" means deleting space deletes all related records
    creator = relationship("User", foreign_keys=[created_by])
    members = relationship("SpaceMember", back_populates="space", cascade="all, delete-orphan")
    content_items = relationship("SpaceContent", back_populates="space", cascade="all, delete-orphan")
    invitations = relationship("SpaceInvitation", back_populates="space", cascade="all, delete-orphan")

    @staticmethod
    def generate_invite_token() -> str:
        """
        Generate a cryptographically secure invite token.

        Uses secrets.token_urlsafe(32) which generates a URL-safe token
        that is suitable for security-sensitive applications.

        Returns:
            str: A 32-character URL-safe token
        """
        return secrets.token_urlsafe(32)

    def regenerate_invite_token(self):
        """
        Regenerate the invite token for this space.

        Useful for security purposes (e.g., if token is compromised)
        or to invalidate all outstanding invitations.

        Updates the invite_token and updated_at fields.
        """
        self.invite_token = self.generate_invite_token()
        self.updated_at = datetime.utcnow()

    def __repr__(self):
        """String representation for debugging"""
        return f"<Space(id={self.id}, name={self.name}, active={self.is_active})>"


class SpaceMember(Base):
    """
    Space membership model (junction table with role).

    Links users to spaces with specific roles, creating many-to-many
    relationship between users and spaces with additional role metadata.

    Unique constraint on (space_id, user_id) prevents duplicate memberships.
    """
    __tablename__ = "space_members"

    # Primary key
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Foreign keys (CASCADE delete - if space or user deleted, membership removed)
    space_id = Column(
        UUID(as_uuid=True),
        ForeignKey("spaces.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    user_id = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Role in space (with default value)
    # Using SQLEnum maps to PostgreSQL ENUM type created in migration
    # name='space_member_role' must match the enum type name in the database
    # create_type=False because the ENUM type is created by Alembic migrations
    role = Column(
        SQLEnum(SpaceMemberRole, name='space_member_role', create_type=False),
        nullable=False,
        default=SpaceMemberRole.member,
        index=True
    )

    # Metadata
    joined_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Track who invited this member (for audit trails)
    # ON DELETE SET NULL preserves membership even if inviter deletes account
    invited_by = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True
    )

    # Relationships
    space = relationship("Space", back_populates="members")
    user = relationship("User", foreign_keys=[user_id])
    inviter = relationship("User", foreign_keys=[invited_by])

    def __repr__(self):
        """String representation for debugging"""
        return f"<SpaceMember(space_id={self.space_id}, user_id={self.user_id}, role={self.role})>"


class SpaceContent(Base):
    """
    Space-Content junction table (many-to-many).

    Tracks which content is shared in which spaces.

    Key features:
    - One content item can exist in multiple spaces (multi-space support)
    - Unique constraint prevents adding same content twice to same space
    - Tracks who added the content and when
    - ON DELETE CASCADE ensures cleanup when space or content is deleted
    """
    __tablename__ = "space_content"

    # Primary key
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Foreign keys (CASCADE delete)
    space_id = Column(
        UUID(as_uuid=True),
        ForeignKey("spaces.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    content_id = Column(
        UUID(as_uuid=True),
        ForeignKey("content_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Audit trail: who added this content to the space
    # ON DELETE SET NULL preserves the content in space even if adder deletes account
    added_by = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True
    )

    # When was this content added to the space
    added_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    # Relationships
    space = relationship("Space", back_populates="content_items")
    content = relationship("ContentItem")
    adder = relationship("User", foreign_keys=[added_by])

    def __repr__(self):
        """String representation for debugging"""
        return f"<SpaceContent(space_id={self.space_id}, content_id={self.content_id})>"


class SpaceInvitation(Base):
    """
    Space invitation model for tracking pending invites.

    When a user invites someone to a space:
    1. SpaceInvitation record is created
    2. Email with magic link is sent
    3. Recipient clicks link and authenticates
    4. Invitation is accepted and SpaceMember record is created

    Features:
    - Expiration (default 7 days)
    - Single-use (tracked via accepted_at)
    - Unique constraint prevents duplicate invitations to same email
    """
    __tablename__ = "space_invitations"

    # Primary key
    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    # Space being invited to
    space_id = Column(
        UUID(as_uuid=True),
        ForeignKey("spaces.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Email of invitee (can be existing user or new signup)
    email = Column(String(255), nullable=False, index=True)

    # Who sent the invitation
    invited_by = Column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False
    )

    # Role to assign when invitation is accepted
    # name='space_member_role' must match the enum type name in the database
    # create_type=False because the ENUM type is created by Alembic migrations
    role = Column(
        SQLEnum(SpaceMemberRole, name='space_member_role', create_type=False),
        nullable=False,
        default=SpaceMemberRole.member
    )

    # Invitation token (URL-safe, cryptographically secure)
    token = Column(String(255), unique=True, nullable=False, index=True)

    # Expiration and acceptance tracking
    expires_at = Column(DateTime, nullable=False)
    accepted_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    # Relationships
    space = relationship("Space", back_populates="invitations")
    inviter = relationship("User", foreign_keys=[invited_by])

    def is_expired(self) -> bool:
        """
        Check if invitation has expired.

        Returns:
            bool: True if current time is past expires_at
        """
        return datetime.utcnow() > self.expires_at

    def is_accepted(self) -> bool:
        """
        Check if invitation has been accepted.

        Returns:
            bool: True if accepted_at is set
        """
        return self.accepted_at is not None

    def is_valid(self) -> bool:
        """
        Check if invitation is valid (not expired and not accepted).

        Returns:
            bool: True if invitation can still be used
        """
        return not self.is_expired() and not self.is_accepted()

    @staticmethod
    def create_expires_at(days: int = 7) -> datetime:
        """
        Create expiration timestamp for invitation.

        Args:
            days: Number of days until expiration (default: 7)

        Returns:
            datetime: Expiration timestamp (current time + days)
        """
        return datetime.utcnow() + timedelta(days=days)

    def __repr__(self):
        """String representation for debugging"""
        return f"<SpaceInvitation(id={self.id}, email={self.email}, space_id={self.space_id}, valid={self.is_valid()})>"
