import 'package:flutter/foundation.dart';

enum SourceApp {
  linkedin,
  reddit,
  twitter,
  medium,
  youtube,
  hackerNews,
  productHunt,
  github,
  news,
  other,
}

enum ContentCategory {
  technology,
  design,
  business,
  science,
  productivity,
  education,
  entertainment,
  other,
}

enum AIStatus {
  pending,
  processing,
  completed,
  failed,
  disabled,
}

enum FetchErrorType {
  none,
  authRequired,
  network,
  notFound,
  serverError,
  blocked,
  other,
}

enum ContentType {
  url,
  image,
  video,
  note,
}

extension ContentCategoryExtension on ContentCategory {
  String get label {
    switch (this) {
      case ContentCategory.technology:
        return 'Technology';
      case ContentCategory.design:
        return 'Design';
      case ContentCategory.business:
        return 'Business';
      case ContentCategory.science:
        return 'Science';
      case ContentCategory.productivity:
        return 'Productivity';
      case ContentCategory.education:
        return 'Education';
      case ContentCategory.entertainment:
        return 'Entertainment';
      case ContentCategory.other:
        return 'Other';
    }
  }
}

class ContentItem {
  final String id;
  final String userId;
  final ContentType contentType;
  final String? url;
  final String title;
  final String summary;
  final List<String> tags;
  final SourceApp sourceApp;
  final String? sourceAppName;
  final String? sourceAppPackage;
  final ContentCategory category;
  final String? categoryName; // backend-provided dynamic category name
  final String? categoryColor;
  final String? categoryId;
  final DateTime createdAt;
  final String? thumbnailUrl;
  final String? heroImageUrl;
  final List<String>? keyTakeaways;
  final int? readingTimeMinutes;
  final String? notes;
  final bool isDone;
  final bool isFavorite;
  final AIStatus? aiStatus; // AI processing status
  final FetchErrorType? fetchErrorType; // Type of fetch error (for auth banner, etc.)
  final int connectionCount; // Number of AI-discovered connections

  // Media fields (Phase 6: Memory Engine)
  final String? mediaUrl; // R2/S3 URL of uploaded media file
  final String? mediaMimeType; // e.g., image/jpeg, video/mp4
  final double? mediaDurationSeconds; // Duration for videos
  final String? ocrText; // Text extracted via OCR

  /// Whether this content item is a media capture (image or video)
  bool get isMedia => contentType == ContentType.image || contentType == ContentType.video;

  ContentItem({
    required this.id,
    required this.userId,
    this.contentType = ContentType.url,
    this.url,
    required this.title,
    required this.summary,
    required this.tags,
    required this.sourceApp,
    this.sourceAppName,
    this.sourceAppPackage,
    required this.category,
    this.categoryName,
    this.categoryColor,
    this.categoryId,
    required this.createdAt,
    this.thumbnailUrl,
    this.heroImageUrl,
    this.keyTakeaways,
    this.readingTimeMinutes,
    this.notes,
    this.isDone = false,
    this.isFavorite = false,
    this.aiStatus,
    this.fetchErrorType,
    this.connectionCount = 0,
    this.mediaUrl,
    this.mediaMimeType,
    this.mediaDurationSeconds,
    this.ocrText,
  });

  bool isSavedXDaysAgo(int days) {
    final difference = DateTime.now().difference(createdAt).inDays;
    return difference >= days - 1 && difference <= days + 1;
  }

  String getRelativeTime() {
    final difference = DateTime.now().difference(createdAt);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return '1d ago';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? '1mo ago' : '${months}mo ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return years == 1 ? '1y ago' : '${years}y ago';
    }
  }

  /// Get thumbnail URL with fallback for YouTube videos and media content
  String? get effectiveThumbnailUrl {
    // If we have a thumbnail URL, use it
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return thumbnailUrl;
    }

    // If we have a hero image URL, use it
    if (heroImageUrl != null && heroImageUrl!.isNotEmpty) {
      return heroImageUrl;
    }

    // For image content, use the media URL itself as thumbnail
    if (contentType == ContentType.image && mediaUrl != null) {
      return mediaUrl;
    }

    // For YouTube videos, generate thumbnail from video URL
    if (sourceApp == SourceApp.youtube && url != null) {
      final videoId = _extractYouTubeVideoId(url!);
      if (videoId != null) {
        return 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
      }
    }

    return null;
  }

  /// Extract YouTube video ID from various URL formats
  static String? _extractYouTubeVideoId(String url) {
    // Handle different YouTube URL formats:
    // - https://www.youtube.com/watch?v=VIDEO_ID
    // - https://youtu.be/VIDEO_ID
    // - https://m.youtube.com/watch?v=VIDEO_ID
    // - https://youtube.com/watch?v=VIDEO_ID

    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // youtu.be format
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : null;
    }

    // youtube.com format
    if (uri.host.contains('youtube.com')) {
      return uri.queryParameters['v'];
    }

    return null;
  }

  factory ContentItem.fromJson(Map<String, dynamic> json) {
    // Parse created_at timestamp - backend always sends UTC time
    // FastAPI serializes datetime to ISO8601 format with timezone
    // We need to parse it as UTC and convert to local time for display
    String createdAtStr = json['created_at'] as String;
    DateTime createdAt;
    try {
      // Parse the datetime string
      DateTime parsed = DateTime.parse(createdAtStr);
      
      // Backend always sends UTC time, so ensure we treat it as UTC
      // If the parsed datetime is not marked as UTC, create a UTC datetime from its components
      if (parsed.isUtc) {
        // Already UTC, convert to local time
        createdAt = parsed.toLocal();
      } else {
        // Not marked as UTC, but backend sends UTC - treat as UTC and convert to local
        // Create a UTC datetime from the parsed components
        final utcDateTime = DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
          parsed.millisecond,
          parsed.microsecond,
        );
        createdAt = utcDateTime.toLocal();
      }
    } catch (e) {
      // Fallback to current time if parsing fails
      debugPrint('Error parsing created_at: $createdAtStr, error: $e');
      createdAt = DateTime.now();
    }
    
    return ContentItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      contentType: ContentType.values.firstWhere(
        (t) => t.name == (json['content_type'] as String? ?? 'url'),
        orElse: () => ContentType.url,
      ),
      url: json['url'] as String?,
      title: (json['title'] as String?) ?? 'Untitled',
      summary: (json['summary'] as String?) ?? '',
      tags: (json['tags'] as List<dynamic>).map((t) => t as String).toList(),
      sourceApp: SourceApp.values.firstWhere(
        (s) => s.name == json['source_app'],
        orElse: () => SourceApp.other,
      ),
      sourceAppName: json['source_app_name'] as String?,
      sourceAppPackage: json['source_app_package'] as String?,
      category: ContentCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => ContentCategory.other,
      ),
      categoryName: json['category_name'] as String?,
      categoryColor: json['category_color'] as String?,
      categoryId: json['category_id'] as String?,
      createdAt: createdAt,
      thumbnailUrl: json['thumbnail_url'] as String?,
      heroImageUrl: json['hero_image_url'] as String?,
      keyTakeaways: json['key_takeaways'] != null
          ? (json['key_takeaways'] as List<dynamic>).map((t) => t as String).toList()
          : null,
      readingTimeMinutes: json['reading_time_minutes'] as int?,
      notes: json['notes'] as String?,
      isDone: json['is_done'] as bool? ?? false,
      isFavorite: json['is_favorite'] as bool? ?? false,
      aiStatus: json['ai_status'] != null
          ? AIStatus.values.firstWhere(
              (s) => s.name == json['ai_status'],
              orElse: () => AIStatus.completed,
            )
          : null,
      fetchErrorType: json['fetch_error_type'] != null
          ? _parseFetchErrorType(json['fetch_error_type'] as String)
          : null,
      connectionCount: json['connection_count'] as int? ?? 0,
      mediaUrl: json['media_url'] as String?,
      mediaMimeType: json['media_mime_type'] as String?,
      mediaDurationSeconds: (json['media_duration_seconds'] as num?)?.toDouble(),
      ocrText: json['ocr_text'] as String?,
    );
  }

  // Helper method to parse fetch_error_type (snake_case) to FetchErrorType enum (camelCase)
  static FetchErrorType? _parseFetchErrorType(String value) {
    // Convert snake_case to camelCase for enum matching
    // e.g., "auth_required" -> "authRequired"
    final camelCase = value.replaceAllMapped(
      RegExp(r'_([a-z])'),
      (match) => match.group(1)!.toUpperCase(),
    );

    try {
      return FetchErrorType.values.firstWhere(
        (e) => e.name == camelCase,
        orElse: () => FetchErrorType.none,
      );
    } catch (e) {
      debugPrint('Failed to parse fetch_error_type: $value');
      return FetchErrorType.none;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'content_type': contentType.name,
      if (url != null) 'url': url,
      'title': title,
      'summary': summary,
      'tags': tags,
      'source_app': sourceApp.name,
      if (sourceAppName != null) 'source_app_name': sourceAppName,
      if (sourceAppPackage != null) 'source_app_package': sourceAppPackage,
      'category': category.name,
      if (categoryName != null) 'category_name': categoryName,
      if (categoryColor != null) 'category_color': categoryColor,
      if (categoryId != null) 'category_id': categoryId,
      'created_at': createdAt.toIso8601String(),
      'thumbnail_url': thumbnailUrl,
      if (heroImageUrl != null) 'hero_image_url': heroImageUrl,
      if (keyTakeaways != null) 'key_takeaways': keyTakeaways,
      'reading_time_minutes': readingTimeMinutes,
      if (notes != null) 'notes': notes,
      'is_done': isDone,
      'is_favorite': isFavorite,
      if (aiStatus != null) 'ai_status': aiStatus!.name,
      'connection_count': connectionCount,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (mediaMimeType != null) 'media_mime_type': mediaMimeType,
      if (mediaDurationSeconds != null) 'media_duration_seconds': mediaDurationSeconds,
      if (ocrText != null) 'ocr_text': ocrText,
    };
  }

  ContentItem copyWith({
    String? id,
    String? userId,
    ContentType? contentType,
    String? url,
    String? title,
    String? summary,
    List<String>? tags,
    SourceApp? sourceApp,
    String? sourceAppName,
    String? sourceAppPackage,
    ContentCategory? category,
    String? categoryName,
    String? categoryColor,
    String? categoryId,
    DateTime? createdAt,
    String? thumbnailUrl,
    String? heroImageUrl,
    List<String>? keyTakeaways,
    int? readingTimeMinutes,
    String? notes,
    bool? isDone,
    bool? isFavorite,
    AIStatus? aiStatus,
    int? connectionCount,
    String? mediaUrl,
    String? mediaMimeType,
    double? mediaDurationSeconds,
    String? ocrText,
  }) {
    return ContentItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      contentType: contentType ?? this.contentType,
      url: url ?? this.url,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      sourceApp: sourceApp ?? this.sourceApp,
      sourceAppName: sourceAppName ?? this.sourceAppName,
      sourceAppPackage: sourceAppPackage ?? this.sourceAppPackage,
      category: category ?? this.category,
      categoryName: categoryName ?? this.categoryName,
      categoryColor: categoryColor ?? this.categoryColor,
      categoryId: categoryId ?? this.categoryId,
      createdAt: createdAt ?? this.createdAt,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      keyTakeaways: keyTakeaways ?? this.keyTakeaways,
      readingTimeMinutes: readingTimeMinutes ?? this.readingTimeMinutes,
      notes: notes ?? this.notes,
      isDone: isDone ?? this.isDone,
      isFavorite: isFavorite ?? this.isFavorite,
      aiStatus: aiStatus ?? this.aiStatus,
      connectionCount: connectionCount ?? this.connectionCount,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaMimeType: mediaMimeType ?? this.mediaMimeType,
      mediaDurationSeconds: mediaDurationSeconds ?? this.mediaDurationSeconds,
      ocrText: ocrText ?? this.ocrText,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ContentItem &&
        other.id == id &&
        other.userId == userId &&
        other.url == url &&
        other.title == title &&
        other.summary == summary &&
        _listEquals(other.tags, tags) &&
        other.sourceApp == sourceApp &&
        other.sourceAppName == sourceAppName &&
        other.sourceAppPackage == sourceAppPackage &&
        other.category == category &&
        other.categoryName == categoryName &&
        other.categoryColor == categoryColor &&
        other.categoryId == categoryId &&
        other.createdAt == createdAt &&
        other.thumbnailUrl == thumbnailUrl &&
        other.readingTimeMinutes == readingTimeMinutes &&
        other.isDone == isDone &&
        other.isFavorite == isFavorite;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        userId.hashCode ^
        url.hashCode ^
        title.hashCode ^
        summary.hashCode ^
        tags.hashCode ^
        sourceApp.hashCode ^
        sourceAppName.hashCode ^
        sourceAppPackage.hashCode ^
        category.hashCode ^
        categoryName.hashCode ^
        categoryColor.hashCode ^
        categoryId.hashCode ^
        createdAt.hashCode ^
        thumbnailUrl.hashCode ^
        readingTimeMinutes.hashCode ^
        isDone.hashCode ^
        isFavorite.hashCode;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
