/// Entity model for knowledge graph nodes.
class Entity {
  final String id;
  final String name;
  final String entityType;
  final String? description;
  final int mentionCount;
  final double? confidence;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  const Entity({
    required this.id,
    required this.name,
    required this.entityType,
    this.description,
    this.mentionCount = 0,
    this.confidence,
    this.firstSeenAt,
    this.lastSeenAt,
  });

  factory Entity.fromJson(Map<String, dynamic> json) {
    return Entity(
      id: json['id'] as String,
      name: json['name'] as String,
      entityType: json['entity_type'] as String? ?? 'concept',
      description: json['description'] as String?,
      mentionCount: json['mention_count'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble(),
      firstSeenAt: json['first_seen_at'] != null
          ? DateTime.tryParse(json['first_seen_at'] as String)
          : null,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
    );
  }

  String get typeEmoji {
    switch (entityType) {
      case 'person':
        return '\u{1F464}';
      case 'company':
        return '\u{1F3E2}';
      case 'technology':
        return '\u{1F4BB}';
      case 'concept':
        return '\u{1F4A1}';
      case 'topic':
        return '\u{1F4DA}';
      case 'place':
        return '\u{1F4CD}';
      case 'event':
        return '\u{1F4C5}';
      default:
        return '\u{1F50D}';
    }
  }
}
