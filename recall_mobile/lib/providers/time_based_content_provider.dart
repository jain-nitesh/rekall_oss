import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../services/api_service.dart';

/// State for time-based content sections (JUST IN, YESTERDAY)
class TimeBasedContentState {
  final List<ContentItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final int totalItems;
  final int currentPage;
  final bool hasMore;

  TimeBasedContentState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.totalItems = 0,
    this.currentPage = 1,
    this.hasMore = false,
  });

  TimeBasedContentState copyWith({
    List<ContentItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    int? totalItems,
    int? currentPage,
    bool? hasMore,
  }) {
    return TimeBasedContentState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage,
      totalItems: totalItems ?? this.totalItems,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// Notifier for time-based content
class TimeBasedContentNotifier extends StateNotifier<TimeBasedContentState> {
  final String section; // 'just_in', 'yesterday', 'this_week', etc.
  final ApiService _apiService = ApiService();
  String? _readStatus = 'unread';

  TimeBasedContentNotifier(this.section) : super(TimeBasedContentState()) {
    loadContent();
  }

  /// Set read status filter and reload
  Future<void> setReadStatus(String? readStatus) async {
    if (_readStatus == readStatus) return;
    _readStatus = readStatus;
    await refresh();
  }

  /// Remove an item from local state (optimistic removal for done/delete)
  void removeItem(String contentId) {
    state = state.copyWith(
      items: state.items.where((item) => item.id != contentId).toList(),
    );
  }

  Future<void> loadContent() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.getContentTimeline(
        sections: [section],
        page: 1,
        pageSize: 20,
        readStatus: _readStatus,
      );

      final sectionData = response[section];
      if (sectionData != null) {
        final content = (sectionData['content'] as List)
            .map((json) => ContentItem.fromJson(json))
            .toList();

        state = TimeBasedContentState(
          items: content,
          isLoading: false,
          totalItems: sectionData['total'] ?? 0,
          currentPage: sectionData['page'] ?? 1,
          hasMore: sectionData['has_more'] ?? false,
        );
      } else {
        state = TimeBasedContentState(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final nextPage = state.currentPage + 1;
      final response = await _apiService.getContentTimeline(
        sections: [section],
        page: nextPage,
        pageSize: 20,
        readStatus: _readStatus,
      );

      final sectionData = response[section];
      if (sectionData != null) {
        final newContent = (sectionData['content'] as List)
            .map((json) => ContentItem.fromJson(json))
            .toList();

        state = state.copyWith(
          items: [...state.items, ...newContent],
          isLoadingMore: false,
          currentPage: sectionData['page'] ?? nextPage,
          hasMore: sectionData['has_more'] ?? false,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    // Keep existing items visible while refreshing (prevents empty flash)
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final response = await _apiService.getContentTimeline(
        sections: [section],
        page: 1,
        pageSize: 20,
        readStatus: _readStatus,
      );
      final sectionData = response[section];
      if (sectionData != null) {
        final content = (sectionData['content'] as List)
            .map((json) => ContentItem.fromJson(json))
            .toList();
        state = TimeBasedContentState(
          items: content,
          isLoading: false,
          totalItems: sectionData['total'] ?? 0,
          currentPage: sectionData['page'] ?? 1,
          hasMore: sectionData['has_more'] ?? false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

/// Provider for "JUST IN" content (last 3 hours)
final justInContentProvider =
    StateNotifierProvider<TimeBasedContentNotifier, TimeBasedContentState>(
  (ref) => TimeBasedContentNotifier('just_in'),
);

/// Provider for "TODAY" content (midnight to now, excluding just_in)
final todayContentProvider =
    StateNotifierProvider<TimeBasedContentNotifier, TimeBasedContentState>(
  (ref) => TimeBasedContentNotifier('today'),
);

/// Provider for "YESTERDAY" content (previous calendar date)
final yesterdayContentProvider =
    StateNotifierProvider<TimeBasedContentNotifier, TimeBasedContentState>(
  (ref) => TimeBasedContentNotifier('yesterday'),
);

/// Provider for "OLDER" content (everything beyond yesterday)
final olderContentProvider =
    StateNotifierProvider<TimeBasedContentNotifier, TimeBasedContentState>(
  (ref) => TimeBasedContentNotifier('older'),
);
