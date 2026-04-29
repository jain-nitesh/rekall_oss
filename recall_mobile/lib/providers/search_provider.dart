import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../models/filter_option.dart';
import '../services/api_service.dart';
import '../services/analytics_service.dart';

/// Date range filter options
enum DateRange {
  lastWeek,
  lastMonth,
  lastYear,
  allTime;

  String get displayName {
    switch (this) {
      case DateRange.lastWeek:
        return 'Last Week';
      case DateRange.lastMonth:
        return 'Last Month';
      case DateRange.lastYear:
        return 'Last Year';
      case DateRange.allTime:
        return 'All Time';
    }
  }

  int? get days {
    switch (this) {
      case DateRange.lastWeek:
        return 7;
      case DateRange.lastMonth:
        return 30;
      case DateRange.lastYear:
        return 365;
      case DateRange.allTime:
        return null;
    }
  }
}

/// Search state with multi-select support
class SearchState {
  final String query;
  final List<String> categoryFilters;
  final List<String> userCategoryFilters;
  final List<String> sourceAppFilters;
  final DateRange dateRangeFilter;

  const SearchState({
    this.query = '',
    this.categoryFilters = const [],
    this.userCategoryFilters = const [],
    this.sourceAppFilters = const [],
    this.dateRangeFilter = DateRange.allTime,
  });

  SearchState copyWith({
    String? query,
    List<String>? categoryFilters,
    List<String>? userCategoryFilters,
    List<String>? sourceAppFilters,
    DateRange? dateRangeFilter,
  }) {
    return SearchState(
      query: query ?? this.query,
      categoryFilters: categoryFilters ?? this.categoryFilters,
      userCategoryFilters: userCategoryFilters ?? this.userCategoryFilters,
      sourceAppFilters: sourceAppFilters ?? this.sourceAppFilters,
      dateRangeFilter: dateRangeFilter ?? this.dateRangeFilter,
    );
  }

  bool get hasFilters {
    return categoryFilters.isNotEmpty ||
           userCategoryFilters.isNotEmpty ||
           sourceAppFilters.isNotEmpty ||
           dateRangeFilter != DateRange.allTime;
  }

  bool get hasQuery => query.isNotEmpty;
}

/// Search provider notifier
class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(const SearchState());

  void setQuery(String query) {
    state = state.copyWith(query: query);

    // Log analytics event if query is not empty
    if (query.isNotEmpty) {
      AnalyticsService().logSearchQuerySubmitted(
        query,
        categoryFilters: state.categoryFilters.isNotEmpty || state.userCategoryFilters.isNotEmpty
            ? [...state.categoryFilters, ...state.userCategoryFilters]
            : null,
        sourceFilters: state.sourceAppFilters.isNotEmpty ? state.sourceAppFilters : null,
        dateRange: state.dateRangeFilter != DateRange.allTime ? state.dateRangeFilter.name : null,
      );
    }
  }

  void toggleCategoryFilter(String category) {
    final current = state.categoryFilters;
    final updated = current.contains(category)
        ? current.where((c) => c != category).toList()
        : [...current, category];
    state = state.copyWith(categoryFilters: updated);

    // Log analytics event
    AnalyticsService().logSearchFilterApplied('category', category);
  }

  void toggleUserCategoryFilter(String categoryId) {
    final current = state.userCategoryFilters;
    final updated = current.contains(categoryId)
        ? current.where((c) => c != categoryId).toList()
        : [...current, categoryId];
    state = state.copyWith(userCategoryFilters: updated);
  }

  void toggleSourceAppFilter(String sourceApp) {
    final current = state.sourceAppFilters;
    final updated = current.contains(sourceApp)
        ? current.where((s) => s != sourceApp).toList()
        : [...current, sourceApp];
    state = state.copyWith(sourceAppFilters: updated);

    // Log analytics event
    AnalyticsService().logSearchFilterApplied('source_app', sourceApp);
  }

  void setDateRangeFilter(DateRange dateRange) {
    state = state.copyWith(dateRangeFilter: dateRange);

    // Log analytics event
    AnalyticsService().logSearchFilterApplied('date_range', dateRange.name);
  }

  void clearFilters() {
    state = const SearchState();
  }

  void clearQuery() {
    state = state.copyWith(query: '');
  }
}

/// Search provider
final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier();
});

/// Filter options provider (fetches from backend)
final filterOptionsProvider = FutureProvider<FilterOptions>((ref) async {
  final apiService = ApiService();
  return await apiService.getFilterOptions();
});

/// Search results provider (backend-powered with multi-select)
/// Uses semantic search when query has text, keyword/filter search otherwise
final searchResultsProvider = FutureProvider.autoDispose<List<ContentItem>>((ref) async {
  final searchState = ref.watch(searchProvider);

  // If no query and no filters, return empty list
  if (!searchState.hasQuery && !searchState.hasFilters) {
    return [];
  }

  final apiService = ApiService();

  // Use semantic search when there's a text query and no filters
  if (searchState.hasQuery && !searchState.hasFilters) {
    try {
      return await apiService.semanticSearch(searchState.query);
    } catch (e) {
      // Fall back to keyword search if semantic search fails
      debugPrint('[Search] Semantic search failed, falling back to keyword: $e');
    }
  }

  // Fall back to keyword/filter search
  final result = await apiService.searchContent(
    query: searchState.query.isNotEmpty ? searchState.query : null,
    categories: searchState.categoryFilters.isNotEmpty
        ? searchState.categoryFilters
        : null,
    userCategoryIds: searchState.userCategoryFilters.isNotEmpty
        ? searchState.userCategoryFilters
        : null,
    sourceApps: searchState.sourceAppFilters.isNotEmpty
        ? searchState.sourceAppFilters
        : null,
    days: searchState.dateRangeFilter.days,
  );

  return result['content'] as List<ContentItem>;
});

/// Search query provider (convenience)
final searchQueryProvider = Provider<String>((ref) {
  return ref.watch(searchProvider).query;
});

/// Has search results provider
final hasSearchResultsProvider = Provider<bool>((ref) {
  final resultsAsync = ref.watch(searchResultsProvider);
  return resultsAsync.maybeWhen(
    data: (results) => results.isNotEmpty,
    orElse: () => false,
  );
});
