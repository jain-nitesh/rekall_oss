/// Model for AI-discovered connections between content items.
class ConnectionItemSummary {
  final String id;
  final String title;
  final String? summary;
  final String url;
  final String? thumbnailUrl;
  final String? sourceApp;
  final String? category;

  ConnectionItemSummary({
    required this.id,
    required this.title,
    this.summary,
    required this.url,
    this.thumbnailUrl,
    this.sourceApp,
    this.category,
  });

  factory ConnectionItemSummary.fromJson(Map<String, dynamic> json) {
    return ConnectionItemSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String?,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      sourceApp: json['source_app'] as String?,
      category: json['category'] as String?,
    );
  }
}

class ContentConnection {
  final String id;
  final ConnectionItemSummary sourceItem;
  final ConnectionItemSummary targetItem;
  final double similarityScore;
  final String connectionType;
  final String? aiExplanation;
  final bool isDismissed;
  final DateTime createdAt;

  ContentConnection({
    required this.id,
    required this.sourceItem,
    required this.targetItem,
    required this.similarityScore,
    required this.connectionType,
    this.aiExplanation,
    this.isDismissed = false,
    required this.createdAt,
  });

  factory ContentConnection.fromJson(Map<String, dynamic> json) {
    return ContentConnection(
      id: json['id'] as String,
      sourceItem: ConnectionItemSummary.fromJson(json['source_item'] as Map<String, dynamic>),
      targetItem: ConnectionItemSummary.fromJson(json['target_item'] as Map<String, dynamic>),
      similarityScore: (json['similarity_score'] as num).toDouble(),
      connectionType: json['connection_type'] as String,
      aiExplanation: json['ai_explanation'] as String?,
      isDismissed: json['is_dismissed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Similarity as a percentage string
  String get similarityPercent => '${(similarityScore * 100).round()}%';
}
