/// Wiki page model for AI-compiled knowledge pages.
class WikiPage {
  final String id;
  final String title;
  final String slug;
  final String? entityId;
  final String? entityType;
  final String? contentMarkdown;
  final String status;
  final int sourceCount;
  final double confidenceScore;
  final DateTime? lastCompiledAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<WikiBacklink> backlinks;
  final List<WikiContradiction> contradictions;

  const WikiPage({
    required this.id,
    required this.title,
    required this.slug,
    this.entityId,
    this.entityType,
    this.contentMarkdown,
    this.status = 'draft',
    this.sourceCount = 0,
    this.confidenceScore = 0.0,
    this.lastCompiledAt,
    this.createdAt,
    this.updatedAt,
    this.backlinks = const [],
    this.contradictions = const [],
  });

  factory WikiPage.fromJson(Map<String, dynamic> json) {
    return WikiPage(
      id: json['id'] as String,
      title: json['title'] as String,
      slug: json['slug'] as String,
      entityId: json['entity_id'] as String?,
      entityType: json['entity_type'] as String?,
      contentMarkdown: json['content_markdown'] as String?,
      status: json['status'] as String? ?? 'draft',
      sourceCount: json['source_count'] as int? ?? 0,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      lastCompiledAt: json['last_compiled_at'] != null
          ? DateTime.tryParse(json['last_compiled_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      backlinks: (json['backlinks'] as List<dynamic>?)
              ?.map((b) => WikiBacklink.fromJson(b as Map<String, dynamic>))
              .toList() ??
          [],
      contradictions: (json['contradictions'] as List<dynamic>?)
              ?.map((c) => WikiContradiction.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  bool get isPublished => status == 'published';
  bool get isStale => status == 'stale';
  bool get isDraft => status == 'draft';
}

class WikiBacklink {
  final String id;
  final String sourceType;
  final String sourceId;
  final String? contextSnippet;

  const WikiBacklink({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    this.contextSnippet,
  });

  factory WikiBacklink.fromJson(Map<String, dynamic> json) {
    return WikiBacklink(
      id: json['id'] as String,
      sourceType: json['source_type'] as String,
      sourceId: json['source_id'] as String,
      contextSnippet: json['context_snippet'] as String?,
    );
  }
}

class WikiContradiction {
  final String id;
  final String claimA;
  final String? sourceAId;
  final String claimB;
  final String? sourceBId;
  final String? resolution;
  final String status;

  const WikiContradiction({
    required this.id,
    required this.claimA,
    this.sourceAId,
    required this.claimB,
    this.sourceBId,
    this.resolution,
    this.status = 'open',
  });

  factory WikiContradiction.fromJson(Map<String, dynamic> json) {
    return WikiContradiction(
      id: json['id'] as String,
      claimA: json['claim_a'] as String,
      sourceAId: json['source_a_id'] as String?,
      claimB: json['claim_b'] as String,
      sourceBId: json['source_b_id'] as String?,
      resolution: json['resolution'] as String?,
      status: json['status'] as String? ?? 'open',
    );
  }

  bool get isOpen => status == 'open';
}
