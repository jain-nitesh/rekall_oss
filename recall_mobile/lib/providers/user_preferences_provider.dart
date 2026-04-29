import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_preferences.dart';
import '../services/api_service.dart';

/// State for user preferences
class UserPreferencesState {
  final UserPreferences? preferences;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  UserPreferencesState({
    this.preferences,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  UserPreferencesState copyWith({
    UserPreferences? preferences,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
  }) {
    return UserPreferencesState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
    );
  }
}

/// Notifier for user preferences
class UserPreferencesNotifier extends StateNotifier<UserPreferencesState> {
  final ApiService _apiService = ApiService();

  UserPreferencesNotifier() : super(UserPreferencesState()) {
    loadPreferences();
  }

  Future<void> loadPreferences() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.getUserPreferences();
      final prefs = UserPreferences.fromJson(response);

      state = UserPreferencesState(
        preferences: prefs,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> updatePreferences({
    String? summaryStyle,
    bool? autoCategorize,
    List<String>? connectedSources,
    bool? dailyGemsEnabled,
    String? dailyGemsTime,
  }) async {
    if (state.isSaving) return;

    state = state.copyWith(isSaving: true, errorMessage: null);

    try {
      final response = await _apiService.updateUserPreferences(
        summaryStyle: summaryStyle,
        autoCategorize: autoCategorize,
        connectedSources: connectedSources,
        dailyGemsEnabled: dailyGemsEnabled,
        dailyGemsTime: dailyGemsTime,
      );
      final prefs = UserPreferences.fromJson(response);

      state = UserPreferencesState(
        preferences: prefs,
        isSaving: false,
      );
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    await loadPreferences();
  }
}

/// Provider for user preferences (summary style, auto-categorize, etc.)
final userPreferencesProvider =
    StateNotifierProvider<UserPreferencesNotifier, UserPreferencesState>(
  (ref) => UserPreferencesNotifier(),
);
