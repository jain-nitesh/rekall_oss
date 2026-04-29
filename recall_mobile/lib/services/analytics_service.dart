import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

/// Analytics service for tracking app usage and user behavior.
///
/// This service provides a centralized interface for Firebase Analytics,
/// following the same singleton pattern as FCMService.
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Get the observer for automatic screen tracking with GoRouter
  FirebaseAnalyticsObserver get observer => FirebaseAnalyticsObserver(analytics: _analytics);

  bool _isInitialized = false;

  AnalyticsService._internal();

  /// Initialize Firebase Analytics.
  ///
  /// Call this once during app startup in main.dart.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _analytics.setAnalyticsCollectionEnabled(true);
    _isInitialized = true;
    debugPrint('[Analytics] Firebase Analytics initialized');
  }

  // ============================================================================
  // USER MANAGEMENT
  // ============================================================================

  /// Set the user ID for analytics tracking.
  ///
  /// This should be called after successful authentication.
  Future<void> setUserId(String userId) async {
    try {
      await _analytics.setUserId(id: userId);
      debugPrint('[Analytics]User ID set: $userId');
    } catch (e) {
      debugPrint('[Analytics]Error setting user ID: $e');
    }
  }

  /// Set user properties for segmentation and analysis.
  ///
  /// Call this after authentication to associate user metadata.
  Future<void> setUserProperties({String? email, String? name}) async {
    try {
      if (email != null) {
        // Extract domain for privacy (e.g., user@example.com -> example.com)
        final emailDomain = email.contains('@') ? email.split('@').last : 'unknown';
        await _analytics.setUserProperty(name: 'email_domain', value: emailDomain);
      }

      if (name != null) {
        await _analytics.setUserProperty(name: 'user_name', value: name);
      }

      debugPrint('[Analytics]User properties set');
    } catch (e) {
      debugPrint('[Analytics]Error setting user properties: $e');
    }
  }

  /// Clear user data on logout.
  ///
  /// This resets the user ID and should be called when the user logs out.
  Future<void> clearUser() async {
    try {
      await _analytics.setUserId(id: null);
      debugPrint('[Analytics]User data cleared');
    } catch (e) {
      debugPrint('[Analytics]Error clearing user: $e');
    }
  }

  // ============================================================================
  // SCREEN TRACKING
  // ============================================================================

  /// Manually log a screen view.
  ///
  /// This is typically handled automatically by FirebaseAnalyticsObserver,
  /// but can be called manually if needed.
  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
      debugPrint('[Analytics]Screen view: $screenName');
    } catch (e) {
      debugPrint('[Analytics]Error logging screen view: $e');
    }
  }

  // ============================================================================
  // AUTHENTICATION EVENTS
  // ============================================================================

  /// Log when a user requests a magic link for authentication.
  Future<void> logMagicLinkRequested(String email) async {
    try {
      final emailDomain = email.contains('@') ? email.split('@').last : 'unknown';
      await _analytics.logEvent(
        name: 'magic_link_requested',
        parameters: {
          'email_domain': emailDomain,
        },
      );
      debugPrint('[Analytics]Magic link requested: $emailDomain');
    } catch (e) {
      debugPrint('[Analytics]Error logging magic link request: $e');
    }
  }

  /// Log successful authentication.
  Future<void> logAuthenticationSuccess(String method) async {
    try {
      await _analytics.logLogin(loginMethod: method);
      debugPrint('[Analytics]Authentication success: $method');
    } catch (e) {
      debugPrint('[Analytics]Error logging authentication success: $e');
    }
  }

  /// Log failed authentication attempt.
  Future<void> logAuthenticationFailed(String method, String reason) async {
    try {
      await _analytics.logEvent(
        name: 'authentication_failed',
        parameters: {
          'method': method,
          'error_reason': reason.length > 100 ? reason.substring(0, 100) : reason,
        },
      );
      debugPrint('[Analytics]Authentication failed: $method - $reason');
    } catch (e) {
      debugPrint('[Analytics]Error logging authentication failure: $e');
    }
  }

  /// Log when user completes onboarding.
  Future<void> logOnboardingCompleted() async {
    try {
      await _analytics.logEvent(name: 'onboarding_completed');
      debugPrint('[Analytics]Onboarding completed');
    } catch (e) {
      debugPrint('[Analytics]Error logging onboarding completion: $e');
    }
  }

  // ============================================================================
  // CONTENT INGESTION EVENTS
  // ============================================================================

  /// Log when content is shared from external app.
  Future<void> logContentShared({
    required String url,
    required String sourceApp,
    String? category,
  }) async {
    try {
      final urlDomain = _extractDomain(url);
      await _analytics.logEvent(
        name: 'content_shared',
        parameters: {
          'source_app': sourceApp,
          'url_domain': urlDomain,
          if (category != null) 'category': category,
        },
      );
      debugPrint('[Analytics]Content shared: $sourceApp -> $urlDomain');
    } catch (e) {
      debugPrint('[Analytics]Error logging content share: $e');
    }
  }

  /// Log successful content ingestion.
  Future<void> logContentIngestionSuccess({
    required String contentId,
    required String category,
    int? readingTimeMinutes,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'content_ingestion_success',
        parameters: {
          'content_id': contentId,
          'category': category,
          if (readingTimeMinutes != null) 'reading_time_minutes': readingTimeMinutes,
        },
      );
      debugPrint('[Analytics]Content ingestion success: $contentId ($category)');
    } catch (e) {
      debugPrint('[Analytics]Error logging content ingestion success: $e');
    }
  }

  /// Log failed content ingestion.
  Future<void> logContentIngestionFailed(String url, String reason) async {
    try {
      final urlDomain = _extractDomain(url);
      await _analytics.logEvent(
        name: 'content_ingestion_failed',
        parameters: {
          'url_domain': urlDomain,
          'error_reason': reason.length > 100 ? reason.substring(0, 100) : reason,
        },
      );
      debugPrint('[Analytics]Content ingestion failed: $urlDomain - $reason');
    } catch (e) {
      debugPrint('[Analytics]Error logging content ingestion failure: $e');
    }
  }

  /// Log when duplicate content is detected.
  Future<void> logDuplicateContentDetected(String url) async {
    try {
      final urlDomain = _extractDomain(url);
      await _analytics.logEvent(
        name: 'duplicate_content_detected',
        parameters: {
          'url_domain': urlDomain,
        },
      );
      debugPrint('[Analytics]Duplicate content detected: $urlDomain');
    } catch (e) {
      debugPrint('[Analytics]Error logging duplicate content: $e');
    }
  }

  // ============================================================================
  // CONTENT ENGAGEMENT EVENTS
  // ============================================================================

  /// Log when user opens content detail screen.
  Future<void> logContentDetailOpened({
    required String contentId,
    required String category,
    required String sourceApp,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'content_detail_opened',
        parameters: {
          'content_id': contentId,
          'category': category,
          'source_app': sourceApp,
        },
      );
      debugPrint('[Analytics]Content detail opened: $contentId');
    } catch (e) {
      debugPrint('[Analytics]Error logging content detail opened: $e');
    }
  }

  /// Log when content is marked as done.
  Future<void> logContentMarkedAsDone(String contentId) async {
    try {
      await _analytics.logEvent(
        name: 'content_marked_as_done',
        parameters: {
          'content_id': contentId,
        },
      );
      debugPrint('[Analytics]Content marked as done: $contentId');
    } catch (e) {
      debugPrint('[Analytics]Error logging content marked as done: $e');
    }
  }

  /// Log when content is deleted.
  Future<void> logContentDeleted(String contentId) async {
    try {
      await _analytics.logEvent(
        name: 'content_deleted',
        parameters: {
          'content_id': contentId,
        },
      );
      debugPrint('[Analytics]Content deleted: $contentId');
    } catch (e) {
      debugPrint('[Analytics]Error logging content deletion: $e');
    }
  }

  /// Log when content is added to a space.
  Future<void> logContentAddedToSpace({
    required String contentId,
    required String spaceId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'content_added_to_space',
        parameters: {
          'content_id': contentId,
          'space_id': spaceId,
        },
      );
      debugPrint('[Analytics]Content added to space: $contentId -> $spaceId');
    } catch (e) {
      debugPrint('[Analytics]Error logging content added to space: $e');
    }
  }

  // ============================================================================
  // SEARCH EVENTS
  // ============================================================================

  /// Log when user submits a search query.
  Future<void> logSearchQuerySubmitted(
    String query, {
    List<String>? categoryFilters,
    List<String>? sourceFilters,
    String? dateRange,
  }) async {
    try {
      await _analytics.logSearch(
        searchTerm: query,
        numberOfNights: null,
        numberOfRooms: null,
        numberOfPassengers: null,
        origin: null,
        destination: null,
        startDate: null,
        endDate: null,
        travelClass: null,
        parameters: {
          'query_length': query.length,
          'has_filters': categoryFilters != null || sourceFilters != null || dateRange != null,
          if (categoryFilters != null && categoryFilters.isNotEmpty)
            'category_filters': categoryFilters.join(','),
          if (sourceFilters != null && sourceFilters.isNotEmpty)
            'source_filters': sourceFilters.join(','),
          if (dateRange != null) 'date_range': dateRange,
        },
      );
      debugPrint('[Analytics]Search query submitted: "$query"');
    } catch (e) {
      debugPrint('[Analytics]Error logging search query: $e');
    }
  }

  /// Log when search results are loaded.
  Future<void> logSearchResultsLoaded(int resultCount) async {
    try {
      await _analytics.logEvent(
        name: 'search_results_loaded',
        parameters: {
          'result_count': resultCount,
        },
      );
      debugPrint('[Analytics]Search results loaded: $resultCount results');
    } catch (e) {
      debugPrint('[Analytics]Error logging search results: $e');
    }
  }

  /// Log when a search filter is applied.
  Future<void> logSearchFilterApplied(String filterType, String filterValue) async {
    try {
      await _analytics.logEvent(
        name: 'search_filter_applied',
        parameters: {
          'filter_type': filterType,
          'filter_value': filterValue,
        },
      );
      debugPrint('[Analytics]Search filter applied: $filterType = $filterValue');
    } catch (e) {
      debugPrint('[Analytics]Error logging search filter: $e');
    }
  }

  /// Log when user clicks a search result.
  Future<void> logSearchResultClicked(String contentId, int position) async {
    try {
      await _analytics.logSelectContent(
        contentType: 'search_result',
        itemId: contentId,
        parameters: {
          'result_position': position,
        },
      );
      debugPrint('[Analytics]Search result clicked: $contentId at position $position');
    } catch (e) {
      debugPrint('[Analytics]Error logging search result click: $e');
    }
  }

  // ============================================================================
  // SPACES/COLLABORATION EVENTS
  // ============================================================================

  /// Log when a new space is created.
  Future<void> logSpaceCreated(String spaceId, String spaceName) async {
    try {
      await _analytics.logEvent(
        name: 'space_created',
        parameters: {
          'space_id': spaceId,
          'space_name': spaceName,
        },
      );
      debugPrint('[Analytics]Space created: $spaceName');
    } catch (e) {
      debugPrint('[Analytics]Error logging space creation: $e');
    }
  }

  /// Log when an invite is sent.
  Future<void> logInviteSent({
    required String spaceId,
    required String inviteMethod,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'invite_sent',
        parameters: {
          'space_id': spaceId,
          'invite_method': inviteMethod,
        },
      );
      debugPrint('[Analytics]Invite sent: $spaceId via $inviteMethod');
    } catch (e) {
      debugPrint('[Analytics]Error logging invite sent: $e');
    }
  }

  /// Log when a space invite link is accepted.
  Future<void> logSpaceInviteLinkAccepted(String spaceId) async {
    try {
      await _analytics.logEvent(
        name: 'space_invite_link_accepted',
        parameters: {
          'space_id': spaceId,
        },
      );
      debugPrint('[Analytics]Space invite accepted: $spaceId');
    } catch (e) {
      debugPrint('[Analytics]Error logging space invite acceptance: $e');
    }
  }

  /// Log when space content is loaded.
  Future<void> logSpaceContentLoaded(String spaceId, int contentCount) async {
    try {
      await _analytics.logEvent(
        name: 'space_content_loaded',
        parameters: {
          'space_id': spaceId,
          'content_count': contentCount,
        },
      );
      debugPrint('[Analytics]Space content loaded: $spaceId ($contentCount items)');
    } catch (e) {
      debugPrint('[Analytics]Error logging space content load: $e');
    }
  }

  // ============================================================================
  // NOTIFICATION EVENTS
  // ============================================================================

  /// Log when an FCM notification is received.
  Future<void> logFcmNotificationReceived({
    required String notificationType,
    String? contentId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'fcm_notification_received',
        parameters: {
          'notification_type': notificationType,
          if (contentId != null) 'content_id': contentId,
        },
      );
      debugPrint('[Analytics]FCM notification received: $notificationType');
    } catch (e) {
      debugPrint('[Analytics]Error logging FCM notification received: $e');
    }
  }

  /// Log when user taps on a notification.
  Future<void> logFcmNotificationTapped(String contentId) async {
    try {
      await _analytics.logEvent(
        name: 'fcm_notification_tapped',
        parameters: {
          'content_id': contentId,
        },
      );
      debugPrint('[Analytics]FCM notification tapped: $contentId');
    } catch (e) {
      debugPrint('[Analytics]Error logging FCM notification tap: $e');
    }
  }

  // ============================================================================
  // BACKGROUND SYNC EVENTS
  // ============================================================================

  /// Log when background sync service is initialized.
  Future<void> logBackgroundSyncInitialized({
    required String platform,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'background_sync_initialized',
        parameters: {
          'platform': platform,
        },
      );
      debugPrint('[Analytics] Background sync initialized: $platform');
    } catch (e) {
      debugPrint('[Analytics] Error logging background sync initialization: $e');
    }
  }

  /// Log when background sync is cancelled.
  Future<void> logBackgroundSyncCancelled({
    required String platform,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'background_sync_cancelled',
        parameters: {
          'platform': platform,
        },
      );
      debugPrint('[Analytics] Background sync cancelled: $platform');
    } catch (e) {
      debugPrint('[Analytics] Error logging background sync cancellation: $e');
    }
  }

  /// Log when background sync is started.
  Future<void> logBackgroundSyncStarted({
    required String platform,
    required int pendingCount,
    required bool hasNetwork,
    required bool hasToken,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'background_sync_started',
        parameters: {
          'platform': platform,
          'pending_count': pendingCount,
          'has_network': hasNetwork,
          'has_token': hasToken,
        },
      );
      debugPrint('[Analytics] Background sync started: $platform ($pendingCount pending)');
    } catch (e) {
      debugPrint('[Analytics] Error logging background sync start: $e');
    }
  }

  /// Log when background sync completes successfully.
  Future<void> logBackgroundSyncCompleted({
    required String platform,
    required int successCount,
    required int failureCount,
    required String syncTier, // 'tier_1', 'tier_2', or 'tier_3'
    required int durationMs,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'background_sync_completed',
        parameters: {
          'platform': platform,
          'success_count': successCount,
          'failure_count': failureCount,
          'sync_tier': syncTier,
          'duration_ms': durationMs,
          'success_rate': successCount > 0
              ? (successCount / (successCount + failureCount) * 100).toInt()
              : 0,
        },
      );
      debugPrint('[Analytics] Background sync completed: $successCount success, $failureCount failed ($durationMs ms)');
    } catch (e) {
      debugPrint('[Analytics] Error logging background sync completion: $e');
    }
  }

  /// Log when background sync fails.
  Future<void> logBackgroundSyncFailed({
    required String platform,
    required String reason,
    required int attemptNumber,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'background_sync_failed',
        parameters: {
          'platform': platform,
          'error_reason': reason.length > 100 ? reason.substring(0, 100) : reason,
          'attempt_number': attemptNumber,
        },
      );
      debugPrint('[Analytics] Background sync failed: $reason (attempt $attemptNumber)');
    } catch (e) {
      debugPrint('[Analytics] Error logging background sync failure: $e');
    }
  }

  /// Log sync latency (time from share to backend receipt).
  Future<void> logSyncLatency({
    required String platform,
    required int latencyMs,
    required String syncTier,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'sync_latency',
        parameters: {
          'platform': platform,
          'latency_ms': latencyMs,
          'sync_tier': syncTier,
          'latency_seconds': (latencyMs / 1000).toInt(),
        },
      );
      debugPrint('[Analytics] Sync latency: ${(latencyMs / 1000).toStringAsFixed(1)}s ($syncTier)');
    } catch (e) {
      debugPrint('[Analytics] Error logging sync latency: $e');
    }
  }

  /// Log when WorkManager job is scheduled.
  Future<void> logWorkManagerScheduled({
    required String platform,
    required String workerId,
  }) async {
    try {
      await _analytics.logEvent(
        name: 'workmanager_scheduled',
        parameters: {
          'platform': platform,
          'worker_id': workerId,
        },
      );
      debugPrint('[Analytics] WorkManager scheduled: $workerId');
    } catch (e) {
      debugPrint('[Analytics] Error logging WorkManager schedule: $e');
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Extract domain from URL for privacy-safe logging.
  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isNotEmpty ? uri.host : 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }
}
