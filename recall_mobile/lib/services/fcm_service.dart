import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'api_service.dart';
import 'analytics_service.dart';

/// Firebase Cloud Messaging service for push notifications.
///
/// Responsibilities:
/// - Initialize Firebase Messaging
/// - Request notification permissions (iOS)
/// - Get and register FCM token with backend
/// - Handle foreground/background/terminated notifications
/// - Provide notification tap callbacks for navigation
class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final ApiService _apiService = ApiService();

  // Callback for when notification is tapped
  Function(String contentItemId)? onNotificationTapped;

  // Callback for when a connection notification is tapped
  Function(String connectionId, String sourceItemId, String targetItemId)? onConnectionNotificationTapped;

  // Track initialization state
  bool _isInitialized = false;

  FCMService._internal();

  /// Initialize FCM and set up notification handlers.
  ///
  /// Call this during app startup (in main.dart).
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('[FCM] Already initialized, skipping');
      return;
    }

    try {
      debugPrint('[FCM] Initializing Firebase Cloud Messaging...');

      // 1. Request permissions (iOS only, Android auto-grants)
      await _requestPermissions();

      // 2. Initialize local notifications for foreground display
      await _initializeLocalNotifications();

      // 3. Get and register FCM token
      await _registerToken();

      // 4. Set up notification handlers
      _setupNotificationHandlers();

      // 5. Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen(_onTokenRefresh);

      _isInitialized = true;
      debugPrint('[FCM] Initialization complete');
    } catch (e) {
      debugPrint('[FCM] Initialization error: $e');
      // Don't throw - allow app to continue without notifications
    }
  }

  /// Request notification permissions.
  ///
  /// - iOS: Always requires explicit permission request
  /// - Android 13+: Requires explicit runtime permission request
  /// - Android <13: Permissions auto-granted
  Future<void> _requestPermissions() async {
    debugPrint('[FCM] Requesting notification permissions...');

    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('[FCM] Notification permissions granted');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      debugPrint('[FCM] Provisional permissions granted');
    } else {
      debugPrint('[FCM] Notification permissions denied');
    }
  }

  /// Initialize local notifications for foreground display.
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // Create Android notification channel
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'recall_gems', // Must match backend FCM channel ID
        'Daily Gems',
        description: 'Daily content reminders from ReKall',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Get FCM token and register with backend.
  Future<void> _registerToken() async {
    try {
      // Get FCM token
      final token = await _firebaseMessaging.getToken();

      if (token == null) {
        debugPrint('[FCM] Failed to get token');
        return;
      }

      debugPrint('[FCM] Token received: ${token.substring(0, 20)}...');

      // Save token locally
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString(AppConstants.keyFcmToken);

      // Only register if token changed or not registered
      if (savedToken != token) {
        await _sendTokenToBackend(token);
        await prefs.setString(AppConstants.keyFcmToken, token);
        debugPrint('[FCM] Token registered with backend');
      } else {
        debugPrint('[FCM] Token unchanged, skipping registration');
      }
    } catch (e) {
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  /// Send FCM token to backend.
  Future<void> _sendTokenToBackend(String token) async {
    try {
      const secureStorage = FlutterSecureStorage();
      final authToken = await secureStorage.read(key: AppConstants.keyAuthToken);

      // Only register if user is logged in
      if (authToken == null) {
        debugPrint('[FCM] User not logged in, skipping token registration');
        return;
      }

      // Get device info
      final platform = Platform.isIOS ? 'ios' : 'android';
      final deviceName = Platform.isIOS ? 'iPhone' : 'Android Device';

      // Register with backend
      await _apiService.registerFcmToken(
        fcmToken: token,
        platform: platform,
        deviceName: deviceName,
      );

      debugPrint('[FCM] Token sent to backend successfully');
    } catch (e) {
      debugPrint('[FCM] Failed to send token to backend: $e');
      // Don't throw - allow app to continue
    }
  }

  /// Handle token refresh.
  void _onTokenRefresh(String token) async {
    debugPrint('[FCM] Token refreshed: ${token.substring(0, 20)}...');
    await _sendTokenToBackend(token);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyFcmToken, token);
  }

  /// Set up notification handlers for different app states.
  void _setupNotificationHandlers() {
    // 1. Foreground messages (app open)
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 2. Background/terminated messages (notification tapped)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // 3. Check for initial notification (app opened from terminated state)
    _checkInitialNotification();
  }

  /// Handle notification received while app is in foreground.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM] Foreground message: ${message.notification?.title}');

    // Log analytics event
    AnalyticsService().logFcmNotificationReceived(
      notificationType: message.data['type'] ?? 'gem',
      contentId: message.data['content_item_id'],
    );

    // Display local notification
    final notification = message.notification;

    if (notification != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'recall_gems',
            'Daily Gems',
            channelDescription: 'Daily content reminders from ReKall',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: message.data['content_item_id'],
      );
    }
  }

  /// Handle notification tap (app in background or terminated).
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[FCM] Notification tapped: ${message.data}');

    final notificationType = message.data['type'] ?? 'daily_gem';

    if (notificationType == 'daily_connection') {
      // Connection notification — navigate to connection detail
      final connectionId = message.data['connection_id'];
      final sourceItemId = message.data['source_item_id'];
      final targetItemId = message.data['target_item_id'];

      if (connectionId != null && sourceItemId != null && targetItemId != null) {
        AnalyticsService().logFcmNotificationTapped(connectionId);

        if (onConnectionNotificationTapped != null) {
          onConnectionNotificationTapped!(connectionId, sourceItemId, targetItemId);
        }
      }
    } else {
      // Regular gem notification — navigate to content detail
      final contentItemId = message.data['content_item_id'];
      if (contentItemId != null) {
        AnalyticsService().logFcmNotificationTapped(contentItemId);

        if (onNotificationTapped != null) {
          onNotificationTapped!(contentItemId);
        }
      }
    }
  }

  /// Handle local notification tap.
  void _onLocalNotificationTapped(NotificationResponse response) {
    debugPrint('[FCM] Local notification tapped: ${response.payload}');

    if (response.payload != null) {
      // Log analytics event
      AnalyticsService().logFcmNotificationTapped(response.payload!);

      if (onNotificationTapped != null) {
        onNotificationTapped!(response.payload!);
      }
    }
  }

  /// Check if app was opened from a notification (terminated state).
  Future<void> _checkInitialNotification() async {
    final initialMessage = await _firebaseMessaging.getInitialMessage();

    if (initialMessage != null) {
      debugPrint('[FCM] App opened from notification: ${initialMessage.data}');
      _handleNotificationTap(initialMessage);
    }
  }

  /// Force token refresh and re-registration.
  ///
  /// Call this after user logs in to ensure token is registered.
  Future<void> refreshToken() async {
    try {
      // Delete old token
      await _firebaseMessaging.deleteToken();

      // Get new token and register
      await _registerToken();
    } catch (e) {
      debugPrint('[FCM] Token refresh failed: $e');
    }
  }

  /// Unregister token from backend.
  ///
  /// Call this when user logs out.
  Future<void> unregisterToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AppConstants.keyFcmToken);

      if (token != null) {
        // TODO: Call backend API to unregister token
        // await _apiService.unregisterFcmToken(token);

        await prefs.remove(AppConstants.keyFcmToken);
        debugPrint('[FCM] Token unregistered');
      }
    } catch (e) {
      debugPrint('[FCM] Token unregistration failed: $e');
    }
  }
}
