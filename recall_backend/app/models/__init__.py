"""
Models package.
Exports all database models for easy importing.
"""
from app.models.user import User
from app.models.content_item import ContentItem, ContentType
from app.models.user_category import UserCategory
from app.models.magic_link_token import MagicLinkToken
from app.models.notification_settings import (
    UserNotificationSettings,
    UserDevice,
    NotificationHistory
)
from app.models.space import (
    Space,
    SpaceMember,
    SpaceContent,
    SpaceInvitation,
    SpaceMemberRole
)
from app.models.content_connection import ContentConnection
from app.models.connection_cluster import ConnectionCluster, ConnectionClusterItem
from app.models.entity import Entity, ContentEntity, EntityRelationship, EntityType, EntityExtractionStatus
from app.models.wiki import WikiPage, WikiBacklink, WikiContradiction, WikiPageStatus, ContradictionStatus
from app.models.conversation import Conversation, ConversationMessage, MessageRole
from app.models.health_check import KnowledgeHealthCheck, HealthCheckType, HealthCheckPriority

__all__ = [
    "User",
    "ContentItem",
    "ContentType",
    "UserCategory",
    "MagicLinkToken",
    "UserNotificationSettings",
    "UserDevice",
    "NotificationHistory",
    "Space",
    "SpaceMember",
    "SpaceContent",
    "SpaceInvitation",
    "SpaceMemberRole",
    "ContentConnection",
    "ConnectionCluster",
    "ConnectionClusterItem",
    "Entity",
    "ContentEntity",
    "EntityRelationship",
    "EntityType",
    "EntityExtractionStatus",
    "WikiPage",
    "WikiBacklink",
    "WikiContradiction",
    "WikiPageStatus",
    "ContradictionStatus",
    "Conversation",
    "ConversationMessage",
    "MessageRole",
    "KnowledgeHealthCheck",
    "HealthCheckType",
    "HealthCheckPriority",
]
