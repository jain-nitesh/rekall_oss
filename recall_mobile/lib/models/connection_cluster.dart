class ClusterPreviewItem {
  final String id;
  final String title;
  final String? thumbnailUrl;
  final String? category;
  final String? sourceApp;

  ClusterPreviewItem({required this.id, required this.title, this.thumbnailUrl, this.category, this.sourceApp});

  factory ClusterPreviewItem.fromJson(Map<String, dynamic> json) {
    return ClusterPreviewItem(
      id: json['id'] as String,
      title: json['title'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      category: json['category'] as String?,
      sourceApp: json['source_app'] as String?,
    );
  }
}

class ConnectionCluster {
  final String id;
  final String label;
  final String? description;
  final int itemCount;
  final double? avgSimilarity;
  final List<ClusterPreviewItem> previewItems;
  final List<String> sourceApps;
  final DateTime createdAt;

  ConnectionCluster({
    required this.id,
    required this.label,
    this.description,
    required this.itemCount,
    this.avgSimilarity,
    required this.previewItems,
    this.sourceApps = const [],
    required this.createdAt,
  });

  factory ConnectionCluster.fromJson(Map<String, dynamic> json) {
    return ConnectionCluster(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      itemCount: json['item_count'] as int,
      avgSimilarity: (json['avg_similarity'] as num?)?.toDouble(),
      previewItems: (json['preview_items'] as List?)
          ?.map((e) => ClusterPreviewItem.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      sourceApps: (json['source_apps'] as List?)
          ?.map((e) => e as String)
          .toList() ?? [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ClusterDetailItem {
  final String id;
  final String title;
  final String? summary;
  final String url;
  final String? thumbnailUrl;
  final String? sourceApp;
  final String? category;

  ClusterDetailItem({
    required this.id,
    required this.title,
    this.summary,
    required this.url,
    this.thumbnailUrl,
    this.sourceApp,
    this.category,
  });

  factory ClusterDetailItem.fromJson(Map<String, dynamic> json) {
    return ClusterDetailItem(
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

class ClusterConnection {
  final String sourceItemId;
  final String targetItemId;
  final double similarityScore;
  final String? aiExplanation;

  ClusterConnection({
    required this.sourceItemId,
    required this.targetItemId,
    required this.similarityScore,
    this.aiExplanation,
  });

  factory ClusterConnection.fromJson(Map<String, dynamic> json) {
    return ClusterConnection(
      sourceItemId: json['source_item_id'] as String,
      targetItemId: json['target_item_id'] as String,
      similarityScore: (json['similarity_score'] as num).toDouble(),
      aiExplanation: json['ai_explanation'] as String?,
    );
  }
}

class ConnectionClusterDetail {
  final String id;
  final String label;
  final String? description;
  final List<ClusterDetailItem> items;
  final List<ClusterConnection> connections;
  final double? avgSimilarity;

  ConnectionClusterDetail({
    required this.id,
    required this.label,
    this.description,
    required this.items,
    required this.connections,
    this.avgSimilarity,
  });

  factory ConnectionClusterDetail.fromJson(Map<String, dynamic> json) {
    return ConnectionClusterDetail(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      items: (json['items'] as List)
          .map((e) => ClusterDetailItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      connections: (json['connections'] as List)
          .map((e) => ClusterConnection.fromJson(e as Map<String, dynamic>))
          .toList(),
      avgSimilarity: (json['avg_similarity'] as num?)?.toDouble(),
    );
  }
}
