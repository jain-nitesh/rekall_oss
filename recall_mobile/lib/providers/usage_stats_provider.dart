import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/usage_stats.dart';
import '../services/api_service.dart';

/// State for usage stats
class UsageStatsState {
  final UsageStats? stats;
  final bool isLoading;
  final String? errorMessage;

  UsageStatsState({
    this.stats,
    this.isLoading = false,
    this.errorMessage,
  });

  UsageStatsState copyWith({
    UsageStats? stats,
    bool? isLoading,
    String? errorMessage,
  }) {
    return UsageStatsState(
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Notifier for usage stats
class UsageStatsNotifier extends StateNotifier<UsageStatsState> {
  final ApiService _apiService = ApiService();

  UsageStatsNotifier() : super(UsageStatsState()) {
    loadStats();
  }

  Future<void> loadStats() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.getUsageStats();
      final stats = UsageStats.fromJson(response);

      state = UsageStatsState(
        stats: stats,
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
    await loadStats();
  }
}

/// Provider for user's AI usage statistics
final usageStatsProvider =
    StateNotifierProvider<UsageStatsNotifier, UsageStatsState>(
  (ref) => UsageStatsNotifier(),
);
