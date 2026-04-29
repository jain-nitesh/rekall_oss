import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_history.dart';
import '../services/api_service.dart';

/// State for search history
class SearchHistoryState {
  final List<SearchHistoryItem> items;
  final bool isLoading;
  final String? errorMessage;

  SearchHistoryState({
    this.items = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  SearchHistoryState copyWith({
    List<SearchHistoryItem>? items,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SearchHistoryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Notifier for search history
class SearchHistoryNotifier extends StateNotifier<SearchHistoryState> {
  final ApiService _apiService = ApiService();

  SearchHistoryNotifier() : super(SearchHistoryState()) {
    loadHistory();
  }

  Future<void> loadHistory({int limit = 10}) async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.getSearchHistory(limit: limit);
      final history = response
          .map((json) => SearchHistoryItem.fromJson(json))
          .toList();

      state = SearchHistoryState(
        items: history,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> saveSearch(String query) async {
    try {
      await _apiService.saveSearch(query);
      // Reload history to include new search
      await loadHistory();
    } catch (e) {
      // Silently fail - search history is not critical
    }
  }

  Future<void> clearHistory() async {
    try {
      await _apiService.clearSearchHistory();
      state = SearchHistoryState(items: [], isLoading: false);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    await loadHistory();
  }
}

/// Provider for search history
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, SearchHistoryState>(
  (ref) => SearchHistoryNotifier(),
);
