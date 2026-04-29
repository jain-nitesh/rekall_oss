import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shared_space.dart';
import '../services/api_service.dart';

/// State for explore spaces
class ExploreSpacesState {
  final List<SharedSpace> spaces;
  final bool isLoading;
  final String? errorMessage;

  ExploreSpacesState({
    this.spaces = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ExploreSpacesState copyWith({
    List<SharedSpace>? spaces,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ExploreSpacesState(
      spaces: spaces ?? this.spaces,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Notifier for explore spaces
class ExploreSpacesNotifier extends StateNotifier<ExploreSpacesState> {
  final ApiService _apiService = ApiService();

  ExploreSpacesNotifier() : super(ExploreSpacesState()) {
    loadSpaces();
  }

  Future<void> loadSpaces({int limit = 20}) async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.getExploreSpaces(limit: limit);
      final spaces = response
          .map((json) => SharedSpace.fromJson(json))
          .toList();

      state = ExploreSpacesState(
        spaces: spaces,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    await loadSpaces();
  }
}

/// Provider for explore spaces (trending/recommended public spaces)
final exploreSpacesProvider =
    StateNotifierProvider<ExploreSpacesNotifier, ExploreSpacesState>(
  (ref) => ExploreSpacesNotifier(),
);
