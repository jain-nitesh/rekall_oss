// Conversation models for RAG chat.

class Conversation {
  final String id;
  final String? title;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<ChatMessage> messages;

  const Conversation({
    required this.id,
    this.title,
    this.createdAt,
    this.updatedAt,
    this.messages = const [],
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      messages: (json['messages'] as List<dynamic>?)
              ?.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ChatMessage {
  final String? id;
  final String role;
  final String content;
  final List<SourceRef> referencedItems;
  final List<WikiRef> referencedWikiPages;
  final Map<String, CitationRef> citationMap;
  final DateTime? createdAt;

  const ChatMessage({
    this.id,
    required this.role,
    required this.content,
    this.referencedItems = const [],
    this.referencedWikiPages = const [],
    this.citationMap = const {},
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String?,
      role: json['role'] as String,
      content: json['content'] as String,
      referencedItems: (json['referenced_items'] as List<dynamic>?)
              ?.map((r) => SourceRef.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      referencedWikiPages: (json['referenced_wiki_pages'] as List<dynamic>?)
              ?.map((r) => WikiRef.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      citationMap: _parseCitationMap(json['citation_map']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  static Map<String, CitationRef> _parseCitationMap(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    final map = <String, CitationRef>{};
    for (final entry in raw.entries) {
      try {
        map[entry.key as String] =
            CitationRef.fromJson(entry.value as Map<String, dynamic>);
      } catch (_) {}
    }
    return map;
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
}

class ChatResponse {
  final String conversationId;
  final String answer;
  final List<SourceRef> citedSources;
  final List<WikiRef> citedWikiPages;
  final Map<String, CitationRef> citationMap;
  final double confidence;
  final List<String> followUpSuggestions;

  const ChatResponse({
    required this.conversationId,
    required this.answer,
    this.citedSources = const [],
    this.citedWikiPages = const [],
    this.citationMap = const {},
    this.confidence = 0.5,
    this.followUpSuggestions = const [],
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      conversationId: json['conversation_id'] as String,
      answer: json['answer'] as String,
      citedSources: (json['cited_sources'] as List<dynamic>?)
              ?.map((r) => SourceRef.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      citedWikiPages: (json['cited_wiki_pages'] as List<dynamic>?)
              ?.map((r) => WikiRef.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      citationMap: ChatMessage._parseCitationMap(json['citation_map']),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      followUpSuggestions: (json['follow_up_suggestions'] as List<dynamic>?)
              ?.map((s) => s as String)
              .toList() ??
          [],
    );
  }
}

class CitationRef {
  final String id;
  final String title;
  final String type;
  final String slug;

  const CitationRef({
    required this.id,
    required this.title,
    required this.type,
    this.slug = '',
  });

  factory CitationRef.fromJson(Map<String, dynamic> json) {
    return CitationRef(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'content_item',
      slug: json['slug'] as String? ?? '',
    );
  }
}

class SourceRef {
  final String id;
  final String title;
  final String type;

  const SourceRef({required this.id, required this.title, required this.type});

  factory SourceRef.fromJson(Map<String, dynamic> json) {
    return SourceRef(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'content_item',
    );
  }
}

class WikiRef {
  final String id;
  final String title;
  final String slug;

  const WikiRef({required this.id, required this.title, this.slug = ''});

  factory WikiRef.fromJson(Map<String, dynamic> json) {
    return WikiRef(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      slug: json['slug'] as String? ?? '',
    );
  }
}
