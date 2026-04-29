/// Knowledge health check model for proactive intelligence insights.
class HealthCheck {
  final String id;
  final String checkType;
  final String title;
  final String? description;
  final String priority;
  final String? relatedEntityId;
  final String? relatedWikiPageId;
  final bool isDismissed;
  final bool isActedOn;
  final DateTime? createdAt;

  const HealthCheck({
    required this.id,
    required this.checkType,
    required this.title,
    this.description,
    this.priority = 'medium',
    this.relatedEntityId,
    this.relatedWikiPageId,
    this.isDismissed = false,
    this.isActedOn = false,
    this.createdAt,
  });

  factory HealthCheck.fromJson(Map<String, dynamic> json) {
    return HealthCheck(
      id: json['id'] as String,
      checkType: json['check_type'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      priority: json['priority'] as String? ?? 'medium',
      relatedEntityId: json['related_entity_id'] as String?,
      relatedWikiPageId: json['related_wiki_page_id'] as String?,
      isDismissed: json['is_dismissed'] as bool? ?? false,
      isActedOn: json['is_acted_on'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  String get typeIcon {
    switch (checkType) {
      case 'gap':
        return '\u{1F50D}';
      case 'stale':
        return '\u{23F3}';
      case 'contradiction':
        return '\u{26A0}';
      case 'trend':
        return '\u{1F4C8}';
      case 'suggestion':
        return '\u{1F4A1}';
      default:
        return '\u{2139}';
    }
  }

  bool get isHighPriority => priority == 'high';
}
