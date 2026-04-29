class PublicCollection {
  final String id;
  final String title;
  final String? description;
  final String slug;
  final bool isPublished;
  final int viewCount;
  final int forkCount;
  final int itemCount;
  final String? creatorName;
  final String? createdAt;
  final List<CollectionItem> items;

  PublicCollection({
    required this.id,
    required this.title,
    this.description,
    required this.slug,
    this.isPublished = false,
    this.viewCount = 0,
    this.forkCount = 0,
    this.itemCount = 0,
    this.creatorName,
    this.createdAt,
    this.items = const [],
  });

  factory PublicCollection.fromJson(Map<String, dynamic> json) {
    return PublicCollection(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      slug: json['slug'] as String,
      isPublished: json['is_published'] as bool? ?? false,
      viewCount: json['view_count'] as int? ?? 0,
      forkCount: json['fork_count'] as int? ?? 0,
      itemCount: json['item_count'] as int? ?? 0,
      creatorName: json['creator_name'] as String?,
      createdAt: json['created_at'] as String?,
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => CollectionItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'slug': slug,
        'is_published': isPublished,
        'view_count': viewCount,
        'fork_count': forkCount,
        'item_count': itemCount,
        'creator_name': creatorName,
        'created_at': createdAt,
      };
}

class CollectionItem {
  final String id;
  final String contentItemId;
  final String? title;
  final String? summary;
  final String? url;
  final String? thumbnailUrl;
  final String? sourceApp;
  final String? category;
  final String? curatorNote;
  final int position;

  CollectionItem({
    required this.id,
    required this.contentItemId,
    this.title,
    this.summary,
    this.url,
    this.thumbnailUrl,
    this.sourceApp,
    this.category,
    this.curatorNote,
    this.position = 0,
  });

  factory CollectionItem.fromJson(Map<String, dynamic> json) {
    return CollectionItem(
      id: json['id'] as String,
      contentItemId: json['content_item_id'] as String,
      title: json['title'] as String?,
      summary: json['summary'] as String?,
      url: json['url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      sourceApp: json['source_app'] as String?,
      category: json['category'] as String?,
      curatorNote: json['curator_note'] as String?,
      position: json['position'] as int? ?? 0,
    );
  }
}
