import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wiki_page.dart';
import '../models/entity.dart';
import '../models/conversation.dart';
import '../models/health_check.dart';
import '../services/api_service.dart';

// ===== Wiki Pages =====

class WikiPagesState {
  final List<WikiPage> pages;
  final bool isLoading;
  final String? error;
  final int total;

  const WikiPagesState({
    this.pages = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
  });

  WikiPagesState copyWith({
    List<WikiPage>? pages,
    bool? isLoading,
    String? error,
    int? total,
  }) {
    return WikiPagesState(
      pages: pages ?? this.pages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      total: total ?? this.total,
    );
  }
}

class WikiPagesNotifier extends StateNotifier<WikiPagesState> {
  final ApiService _api = ApiService();

  WikiPagesNotifier() : super(const WikiPagesState());

  Future<void> loadPages({String? status, String? search, int pageSize = 50}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.getWikiPages(status: status, search: search, pageSize: pageSize);
      final items = (data['items'] as List<dynamic>)
          .map((j) => WikiPage.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        pages: items,
        total: data['total'] as int? ?? items.length,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final wikiPagesProvider =
    StateNotifierProvider<WikiPagesNotifier, WikiPagesState>((ref) {
  return WikiPagesNotifier();
});

// Detail provider for a single wiki page by slug
final wikiPageDetailProvider =
    FutureProvider.family<WikiPage?, String>((ref, slug) async {
  try {
    final data = await ApiService().getWikiPage(slug);
    return WikiPage.fromJson(data);
  } catch (e) {
    debugPrint('[Wiki] Failed to load page $slug: $e');
    return null;
  }
});

// ===== Entities =====

class EntitiesState {
  final List<Entity> entities;
  final bool isLoading;
  final String? error;
  final int total;

  const EntitiesState({
    this.entities = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
  });

  EntitiesState copyWith({
    List<Entity>? entities,
    bool? isLoading,
    String? error,
    int? total,
  }) {
    return EntitiesState(
      entities: entities ?? this.entities,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      total: total ?? this.total,
    );
  }
}

class EntitiesNotifier extends StateNotifier<EntitiesState> {
  final ApiService _api = ApiService();

  EntitiesNotifier() : super(const EntitiesState());

  Future<void> loadEntities({String? entityType, String? search}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.getEntities(entityType: entityType, pageSize: 50, search: search);
      final items = (data['entities'] as List<dynamic>)
          .map((j) => Entity.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        entities: items,
        total: data['total'] as int? ?? items.length,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final entitiesProvider =
    StateNotifierProvider<EntitiesNotifier, EntitiesState>((ref) {
  return EntitiesNotifier();
});

// ===== Conversations =====

class ConversationsState {
  final List<Conversation> conversations;
  final bool isLoading;
  final String? error;
  final int total;
  final int maxAllowed;

  const ConversationsState({
    this.conversations = const [],
    this.isLoading = false,
    this.error,
    this.total = 0,
    this.maxAllowed = 50,
  });

  bool get isAtLimit => total >= maxAllowed;

  ConversationsState copyWith({
    List<Conversation>? conversations,
    bool? isLoading,
    String? error,
    int? total,
    int? maxAllowed,
  }) {
    return ConversationsState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      total: total ?? this.total,
      maxAllowed: maxAllowed ?? this.maxAllowed,
    );
  }
}

class ConversationsNotifier extends StateNotifier<ConversationsState> {
  final ApiService _api = ApiService();

  ConversationsNotifier() : super(const ConversationsState());

  Future<void> loadConversations() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.getConversations();
      final convList = data['conversations'] as List<dynamic>? ?? [];
      final items = convList
          .map((j) => Conversation.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        conversations: items,
        total: data['total'] as int? ?? items.length,
        maxAllowed: data['max_allowed'] as int? ?? 50,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> deleteConversation(String id) async {
    try {
      await _api.deleteConversation(id);
      state = state.copyWith(
        conversations:
            state.conversations.where((c) => c.id != id).toList(),
        total: (state.total - 1).clamp(0, state.maxAllowed),
      );
    } catch (e) {
      debugPrint('[Chat] Failed to delete conversation: $e');
    }
  }
}

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, ConversationsState>((ref) {
  return ConversationsNotifier();
});

// ===== Health Checks =====

class HealthChecksState {
  final List<HealthCheck> checks;
  final bool isLoading;
  final String? error;

  const HealthChecksState({
    this.checks = const [],
    this.isLoading = false,
    this.error,
  });

  HealthChecksState copyWith({
    List<HealthCheck>? checks,
    bool? isLoading,
    String? error,
  }) {
    return HealthChecksState(
      checks: checks ?? this.checks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class HealthChecksNotifier extends StateNotifier<HealthChecksState> {
  final ApiService _api = ApiService();

  HealthChecksNotifier() : super(const HealthChecksState());

  Future<void> loadChecks() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _api.getHealthChecks();
      final items = data
          .map((j) => HealthCheck.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(checks: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> dismiss(String id) async {
    try {
      await _api.dismissHealthCheck(id);
      state = state.copyWith(
        checks: state.checks.where((c) => c.id != id).toList(),
      );
    } catch (e) {
      debugPrint('[Health] Failed to dismiss: $e');
    }
  }
}

final healthChecksProvider =
    StateNotifierProvider<HealthChecksNotifier, HealthChecksState>((ref) {
  return HealthChecksNotifier();
});
