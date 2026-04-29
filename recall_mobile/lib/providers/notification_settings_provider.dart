import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_settings.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Notification settings state
class NotificationSettingsState {
  final NotificationSettings? settings;
  final bool isLoading;
  final String? errorMessage;

  const NotificationSettingsState({
    this.settings,
    required this.isLoading,
    this.errorMessage,
  });

  factory NotificationSettingsState.initial() {
    return const NotificationSettingsState(isLoading: false);
  }

  factory NotificationSettingsState.loading() {
    return const NotificationSettingsState(isLoading: true);
  }

  factory NotificationSettingsState.loaded(NotificationSettings settings) {
    return NotificationSettingsState(
      settings: settings,
      isLoading: false,
    );
  }

  factory NotificationSettingsState.error(String message) {
    return NotificationSettingsState(
      isLoading: false,
      errorMessage: message,
    );
  }

  NotificationSettingsState copyWith({
    NotificationSettings? settings,
    bool? isLoading,
    String? errorMessage,
  }) {
    return NotificationSettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Notification settings provider notifier
class NotificationSettingsNotifier
    extends StateNotifier<NotificationSettingsState> {
  final ApiService _apiService = ApiService();

  NotificationSettingsNotifier() : super(NotificationSettingsState.initial());

  /// Load notification settings from backend.
  ///
  /// Automatically called when accessing the provider.
  /// Creates default settings if they don't exist.
  Future<void> loadSettings() async {
    if (state.isLoading) return; // Prevent duplicate loads

    state = NotificationSettingsState.loading();

    try {
      final response = await _apiService.getNotificationSettings();
      final settings = NotificationSettings.fromJson(response);

      state = NotificationSettingsState.loaded(settings);
    } catch (e) {
      state = NotificationSettingsState.error('Failed to load settings: $e');
    }
  }

  /// Update notification enabled state.
  Future<void> setEnabled(bool enabled) async {
    if (state.settings == null) return;

    // Optimistic update
    final previousSettings = state.settings!;
    state = state.copyWith(
      settings: previousSettings.copyWith(isEnabled: enabled),
    );

    try {
      final response = await _apiService.updateNotificationSettings(
        isEnabled: enabled,
      );
      final updatedSettings = NotificationSettings.fromJson(response);

      state = NotificationSettingsState.loaded(updatedSettings);
    } catch (e) {
      // Revert on error
      state = state.copyWith(
        settings: previousSettings,
        errorMessage: 'Failed to update settings: $e',
      );
    }
  }

  /// Update notification time.
  ///
  /// Parameters:
  /// - localTime: Local time in "HH:MM" format (e.g., "09:30")
  /// - utcOffsetMinutes: UTC offset in minutes (e.g., -300 for EST)
  Future<void> setNotificationTime({
    required String localTime,
    required int utcOffsetMinutes,
  }) async {
    if (state.settings == null) return;

    // Optimistic update
    final previousSettings = state.settings!;
    state = state.copyWith(
      settings: previousSettings.copyWith(
        notificationTimeLocal: localTime,
        utcOffsetMinutes: utcOffsetMinutes,
      ),
    );

    try {
      final response = await _apiService.updateNotificationSettings(
        notificationTimeLocal: localTime,
        utcOffsetMinutes: utcOffsetMinutes,
      );
      final updatedSettings = NotificationSettings.fromJson(response);

      state = NotificationSettingsState.loaded(updatedSettings);
    } catch (e) {
      // Revert on error
      state = state.copyWith(
        settings: previousSettings,
        errorMessage: 'Failed to update time: $e',
      );
    }
  }

  /// Refresh settings from backend.
  Future<void> refresh() async {
    await loadSettings();
  }
}

/// Notification settings provider
final notificationSettingsProvider = StateNotifierProvider<
    NotificationSettingsNotifier, NotificationSettingsState>((ref) {
  final notifier = NotificationSettingsNotifier();

  // Auto-load settings when user is authenticated
  final authState = ref.watch(authProvider);
  if (authState.status == AuthStatus.authenticated) {
    notifier.loadSettings();
  }

  return notifier;
});

/// Convenience provider: Is notifications enabled?
final isNotificationsEnabledProvider = Provider<bool>((ref) {
  final settingsState = ref.watch(notificationSettingsProvider);
  return settingsState.settings?.isEnabled ?? false;
});

/// Convenience provider: Notification time (local)
final notificationTimeProvider = Provider<String?>((ref) {
  final settingsState = ref.watch(notificationSettingsProvider);
  return settingsState.settings?.notificationTimeLocal;
});
