import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Syncs auth token and API base URL to iOS app group UserDefaults
/// so the Share Extension can access them for background uploads.
/// No-op on Android (Android's ContentSyncWorker reads from SharedPreferences directly).
class SharedStorageService {
  static const _channel = MethodChannel('com.rekallhq/shared_storage');

  /// Write auth token + API base URL to app group UserDefaults (iOS only).
  static Future<void> syncToAppGroup(String token, String apiBaseUrl) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('syncToAppGroup', {
        'auth_token': token,
        'api_base_url': apiBaseUrl,
      });
      debugPrint('[SharedStorage] Synced token + API URL to app group');
    } catch (e) {
      debugPrint('[SharedStorage] Failed to sync to app group: $e');
    }
  }

  /// Clear auth token from app group UserDefaults (iOS only).
  static Future<void> clearFromAppGroup() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('clearFromAppGroup');
      debugPrint('[SharedStorage] Cleared token from app group');
    } catch (e) {
      debugPrint('[SharedStorage] Failed to clear from app group: $e');
    }
  }
}
