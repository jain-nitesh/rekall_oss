import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'analytics_service.dart';

/// Background sync service for handling immediate content uploads
class BackgroundSyncService {
  static final AnalyticsService _analytics = AnalyticsService();

  /// Initialize background sync service
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) {
      debugPrint('[BackgroundSync] Platform not supported (only Android) - skipping');
      return;
    }

    try {
      // Initialize WorkManager (Flutter wrapper for native WorkManager)
      await Workmanager().initialize(
        _callbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      debugPrint('[BackgroundSync] WorkManager initialized successfully');

      // Log initialization
      await _analytics.logBackgroundSyncInitialized(
        platform: _getPlatformName(),
      );
    } catch (e) {
      debugPrint('[BackgroundSync] Failed to initialize: $e');
    }
  }

  /// Cancel all pending work
  static Future<void> cancelAllWork() async {
    await Workmanager().cancelAll();
    debugPrint('[BackgroundSync] All background work cancelled');

    // Log cancellation
    await _analytics.logBackgroundSyncCancelled(
      platform: _getPlatformName(),
    );
  }

  /// Get platform name for analytics
  static String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}

/// Top-level callback dispatcher for WorkManager
/// This runs in a separate isolate
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[BackgroundSync] Task executed: $task');

    final startTime = DateTime.now();

    try {
      // Native layer handles actual sync (ContentSyncWorker on Android)
      // This callback is just for logging/monitoring

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[BackgroundSync] Task completed in ${duration}ms');

      return true;
    } catch (e) {
      debugPrint('[BackgroundSync] Task failed: $e');

      final duration = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[BackgroundSync] Task failed after ${duration}ms');

      return false;
    }
  });
}
