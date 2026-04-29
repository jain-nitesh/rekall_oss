import 'content_item.dart';

/// Represents a shared space for collaborative content organization
class SharedSpace {
  final String id;
  final String name;
  final String description;
  final String? createdBy;
  final String inviteToken;
  final String? emoji;
  final String? accentColor;
  final int memberCount;
  final int contentCount;
  final SpaceMemberRole? currentUserRole;
  final List<SpaceMember> members;
  final List<SpaceContentItem> contentItems;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isPinned;
  final bool isPublic;
  final bool aiReady;

  // Pagination fields for content items
  final int contentPage;
  final int contentPageSize;
  final int contentTotal;
  final bool contentHasMore;

  const SharedSpace({
    required this.id,
    required this.name,
    required this.description,
    this.createdBy,
    required this.inviteToken,
    this.emoji,
    this.accentColor,
    required this.memberCount,
    required this.contentCount,
    this.currentUserRole,
    required this.members,
    required this.contentItems,
    required this.createdAt,
    this.updatedAt,
    this.isPinned = false,
    this.isPublic = false,
    this.aiReady = false,
    this.contentPage = 1,
    this.contentPageSize = 20,
    this.contentTotal = 0,
    this.contentHasMore = false,
  });

  factory SharedSpace.fromJson(Map<String, dynamic> json) {
    return SharedSpace(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      createdBy: json['created_by'] as String?,
      inviteToken: json['invite_token'] as String,
      emoji: json['emoji'] as String?,
      accentColor: json['accent_color'] as String?,
      memberCount: json['member_count'] as int? ?? 0,
      contentCount: json['content_count'] as int? ?? 0,
      currentUserRole: json['current_user_role'] != null
          ? SpaceMemberRole.values.firstWhere(
              (r) => r.name == json['current_user_role'],
              orElse: () => SpaceMemberRole.member,
            )
          : null,
      members: (json['members'] as List<dynamic>? ?? [])
          .map((m) => SpaceMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      contentItems: (json['content_items'] as List<dynamic>? ?? [])
          .map((c) => SpaceContentItem.fromJson(c as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      isPinned: json['is_pinned'] as bool? ?? false,
      isPublic: json['is_public'] as bool? ?? false,
      aiReady: json['ai_ready'] as bool? ?? false,
      contentPage: json['content_page'] as int? ?? 1,
      contentPageSize: json['content_page_size'] as int? ?? 20,
      contentTotal: json['content_total'] as int? ?? 0,
      contentHasMore: json['content_has_more'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'created_by': createdBy,
      'invite_token': inviteToken,
      'emoji': emoji,
      'accent_color': accentColor,
      'member_count': memberCount,
      'content_count': contentCount,
      'current_user_role': currentUserRole?.name,
      'members': members.map((m) => m.toJson()).toList(),
      'content_items': contentItems.map((c) => c.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_pinned': isPinned,
      'is_public': isPublic,
      'ai_ready': aiReady,
      'content_page': contentPage,
      'content_page_size': contentPageSize,
      'content_total': contentTotal,
      'content_has_more': contentHasMore,
    };
  }

  SharedSpace copyWith({
    String? id,
    String? name,
    String? description,
    String? createdBy,
    String? inviteToken,
    String? emoji,
    String? accentColor,
    int? memberCount,
    int? contentCount,
    SpaceMemberRole? currentUserRole,
    List<SpaceMember>? members,
    List<SpaceContentItem>? contentItems,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    bool? isPublic,
    bool? aiReady,
    int? contentPage,
    int? contentPageSize,
    int? contentTotal,
    bool? contentHasMore,
  }) {
    return SharedSpace(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      inviteToken: inviteToken ?? this.inviteToken,
      emoji: emoji ?? this.emoji,
      accentColor: accentColor ?? this.accentColor,
      memberCount: memberCount ?? this.memberCount,
      contentCount: contentCount ?? this.contentCount,
      currentUserRole: currentUserRole ?? this.currentUserRole,
      members: members ?? this.members,
      contentItems: contentItems ?? this.contentItems,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      isPublic: isPublic ?? this.isPublic,
      aiReady: aiReady ?? this.aiReady,
      contentPage: contentPage ?? this.contentPage,
      contentPageSize: contentPageSize ?? this.contentPageSize,
      contentTotal: contentTotal ?? this.contentTotal,
      contentHasMore: contentHasMore ?? this.contentHasMore,
    );
  }

  // Helper methods
  bool isOwner(String userId) {
    return createdBy == userId;
  }

  bool isMember(String userId) {
    return members.any((m) => m.userId == userId);
  }

  String getRelativeTime() {
    final now = DateTime.now();
    final updateTime = updatedAt ?? createdAt;
    final diff = now.difference(updateTime);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()}w ago';
    } else if (diff.inDays < 365) {
      return '${(diff.inDays / 30).floor()}mo ago';
    } else {
      return '${(diff.inDays / 365).floor()}y ago';
    }
  }

  SpaceMemberRole? getMemberRole(String userId) {
    final member = members.firstWhere(
      (m) => m.userId == userId,
      orElse: () => SpaceMember(
        userId: '',
        name: '',
        email: '',
        role: SpaceMemberRole.member,
        joinedAt: DateTime.now(),
      ),
    );
    return member.userId.isEmpty ? null : member.role;
  }

  // Permission helpers based on current user's role
  bool get canInviteMembers => currentUserRole?.canInvite ?? false;
  bool get canRemoveMembers => currentUserRole?.canRemoveMembers ?? false;
  bool get canDeleteSpace => currentUserRole?.canDeleteSpace ?? false;
  bool get canAddContent => currentUserRole?.canAddContent ?? false;
  bool get canUpdateSpace => currentUserRole?.canUpdateSpace ?? false;
}

/// Represents a member of a shared space
class SpaceMember {
  final String userId;
  final String name;
  final String email;
  final SpaceMemberRole role;
  final DateTime joinedAt;

  const SpaceMember({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
  });

  factory SpaceMember.fromJson(Map<String, dynamic> json) {
    return SpaceMember(
      userId: json['user_id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: SpaceMemberRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => SpaceMemberRole.member,
      ),
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'email': email,
      'role': role.name,
      'joined_at': joinedAt.toIso8601String(),
    };
  }

  SpaceMember copyWith({
    String? userId,
    String? name,
    String? email,
    SpaceMemberRole? role,
    DateTime? joinedAt,
  }) {
    return SpaceMember(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }
}

/// Roles for space members
enum SpaceMemberRole {
  viewer,
  member,
  admin,
  owner;

  String get displayName {
    switch (this) {
      case SpaceMemberRole.viewer:
        return 'Viewer';
      case SpaceMemberRole.member:
        return 'Member';
      case SpaceMemberRole.admin:
        return 'Admin';
      case SpaceMemberRole.owner:
        return 'Owner';
    }
  }

  // Permission getters
  bool get canInvite => this == SpaceMemberRole.admin || this == SpaceMemberRole.owner;
  bool get canRemoveMembers => this == SpaceMemberRole.admin || this == SpaceMemberRole.owner;
  bool get canDeleteSpace => this == SpaceMemberRole.owner;
  bool get canAddContent => this != SpaceMemberRole.viewer;
  bool get canUpdateSpace => this == SpaceMemberRole.admin || this == SpaceMemberRole.owner;

  // Role hierarchy value for comparison
  int get hierarchyValue {
    switch (this) {
      case SpaceMemberRole.viewer:
        return 0;
      case SpaceMemberRole.member:
        return 1;
      case SpaceMemberRole.admin:
        return 2;
      case SpaceMemberRole.owner:
        return 3;
    }
  }

  // Check if this role has equal or higher permissions than another role
  bool hasPermissionLevel(SpaceMemberRole required) {
    return hierarchyValue >= required.hierarchyValue;
  }
}

/// Represents a content item within a space
class SpaceContentItem {
  final String id;
  final String title;
  final String url;
  final String summary;
  final String category;
  final DateTime addedAt;
  final String? addedByName;

  const SpaceContentItem({
    required this.id,
    required this.title,
    required this.url,
    required this.summary,
    required this.category,
    required this.addedAt,
    this.addedByName,
  });

  factory SpaceContentItem.fromJson(Map<String, dynamic> json) {
    return SpaceContentItem(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      summary: json['summary'] as String,
      category: json['category'] as String,
      addedAt: DateTime.parse(json['added_at'] as String),
      addedByName: json['added_by_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'summary': summary,
      'category': category,
      'added_at': addedAt.toIso8601String(),
      'added_by_name': addedByName,
    };
  }

  SpaceContentItem copyWith({
    String? id,
    String? title,
    String? url,
    String? summary,
    String? category,
    DateTime? addedAt,
    String? addedByName,
  }) {
    return SpaceContentItem(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      summary: summary ?? this.summary,
      category: category ?? this.category,
      addedAt: addedAt ?? this.addedAt,
      addedByName: addedByName ?? this.addedByName,
    );
  }

  /// Convert SpaceContentItem to ContentItem for use with ContentCard widget
  ContentItem toContentItem() {
    // Parse category string to ContentCategory enum
    ContentCategory contentCategory;
    try {
      contentCategory = ContentCategory.values.firstWhere(
        (c) => c.name.toLowerCase() == category.toLowerCase(),
        orElse: () => ContentCategory.other,
      );
    } catch (e) {
      contentCategory = ContentCategory.other;
    }

    return ContentItem(
      id: id,
      userId: '', // Not available in SpaceContentItem
      url: url,
      title: title,
      summary: summary,
      tags: [], // Not available in SpaceContentItem
      sourceApp: _inferSourceAppFromUrl(url),
      sourceAppName: addedByName,
      category: contentCategory,
      categoryName: category,
      createdAt: addedAt,
      isDone: false,
      isFavorite: false,
    );
  }

  /// Infer source app from URL
  SourceApp _inferSourceAppFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return SourceApp.other;

    final host = uri.host.toLowerCase();
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return SourceApp.youtube;
    } else if (host.contains('linkedin.com')) {
      return SourceApp.linkedin;
    } else if (host.contains('reddit.com')) {
      return SourceApp.reddit;
    } else if (host.contains('twitter.com') || host.contains('x.com')) {
      return SourceApp.twitter;
    } else if (host.contains('medium.com')) {
      return SourceApp.medium;
    } else if (host.contains('github.com')) {
      return SourceApp.github;
    } else if (host.contains('producthunt.com')) {
      return SourceApp.productHunt;
    } else if (host.contains('news.ycombinator.com')) {
      return SourceApp.hackerNews;
    }
    return SourceApp.other;
  }
}
