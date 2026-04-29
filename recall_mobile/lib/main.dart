import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:app_links/app_links.dart';
import 'router/app_router.dart';
import 'models/content_item.dart';
import 'services/share_handler_service.dart';
import 'services/api_service.dart';
import 'services/fcm_service.dart';
import 'services/analytics_service.dart';
import 'services/google_auth_service.dart';
import 'services/background_sync_service.dart';
import 'services/shared_storage_service.dart';
import 'config/environment.dart';
import 'providers/content_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/ui_providers.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';
import 'utils/toast_helper.dart';
import 'widgets/save_toast_notification.dart';

/// Background message handler for Firebase Messaging.
///
/// MUST be a top-level function (not inside a class).
/// Called when a notification arrives while app is in background/terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();

  debugPrint('[FCM Background] Notification received: ${message.notification?.title}');
  // No UI updates here - just logging
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use the Android Photo Picker (no READ_MEDIA_* permissions required)
  final ImagePickerPlatform imagePickerImplementation = ImagePickerPlatform.instance;
  if (imagePickerImplementation is ImagePickerAndroid) {
    imagePickerImplementation.useAndroidPhotoPicker = true;
  }

  // Only initialize Firebase before runApp - it's required for auth state.
  // ALL other services initialize AFTER runApp to prevent iOS hangs
  // (iOS cannot show permission dialogs before the root view controller exists).
  try {
    debugPrint('[Firebase] Initializing Firebase Core...');
    await Firebase.initializeApp()
        .timeout(const Duration(seconds: 10), onTimeout: () {
      debugPrint('[Firebase] Initialization timed out after 10s — continuing without Firebase');
      throw TimeoutException('[Firebase] initializeApp timed out');
    });
    debugPrint('[Firebase] Firebase Core initialized');
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('[Firebase] Initialization failed: $e');
  }

  final shareHandler = ShareHandlerService();

  // Launch the app FIRST - UI must render before requesting permissions
  runApp(
    ProviderScope(
      child: MyApp(shareHandler: shareHandler),
    ),
  );

  // Initialize remaining services AFTER runApp (non-blocking).
  // This ensures the root view controller exists before iOS permission dialogs.
  _initializeServicesPostLaunch(shareHandler);
}

/// Initialize services that must run AFTER the UI is ready.
/// On iOS, requesting notification permissions before the root view controller
/// exists causes the permission dialog to never appear, hanging main() forever.
Future<void> _initializeServicesPostLaunch(ShareHandlerService shareHandler) async {
  try {
    // Sync API base URL
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', Environment.apiBaseUrl);
    debugPrint('[Environment] API base URL synced: ${Environment.apiBaseUrl}');

    // Sync auth token + API URL to iOS app group for Share Extension background uploads
    const secureStorage = FlutterSecureStorage();
    final token = await secureStorage.read(key: AppConstants.keyAuthToken);
    if (token != null && token.isNotEmpty) {
      await SharedStorageService.syncToAppGroup(token, Environment.apiBaseUrl);
    }
  } catch (e) {
    debugPrint('[Environment] Failed to sync API base URL: $e');
  }

  try {
    debugPrint('[FCM] Initializing FCM Service...');
    await FCMService().initialize();
    debugPrint('[FCM] FCM Service initialized');
  } catch (e) {
    debugPrint('[FCM] Initialization failed: $e');
  }

  try {
    debugPrint('[Analytics] Initializing Analytics Service...');
    await AnalyticsService().initialize();
    debugPrint('[Analytics] Analytics Service initialized');
  } catch (e) {
    debugPrint('[Analytics] Initialization failed: $e');
  }

  try {
    await GoogleAuthService().initialize();
  } catch (e) {
    debugPrint('[GoogleAuth] Initialization failed: $e');
  }

  try {
    await BackgroundSyncService.initialize();
  } catch (e) {
    debugPrint('[BackgroundSync] Initialization failed: $e');
  }

  try {
    shareHandler.initialize();
  } catch (e) {
    debugPrint('[ShareHandler] Initialization failed: $e');
  }
}

class MyApp extends ConsumerStatefulWidget {
  final ShareHandlerService shareHandler;

  const MyApp({
    super.key,
    required this.shareHandler,
  });

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  BuildContext? _overlayContext;
  int _resumeRetryCount = 0;
  late AppLinks _appLinks;

  /// Track file paths already processed in this session to prevent duplicate uploads.
  /// When a media share arrives via receive_sharing_intent, the same share can be
  /// delivered multiple times (stream + getInitialMedia). After the first upload
  /// replaces the optimistic item with the backend item (url=""), the dedup check
  /// on state.items no longer catches duplicates by file path.
  final Set<String> _processedSharePaths = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupShareHandlerListener();
    _setupNotificationNavigation();
    _initDeepLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.shareHandler.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('App lifecycle state changed: $state');

    // When app comes to foreground, check for pending shares and new shares
    if (state == AppLifecycleState.resumed) {
      debugPrint('App RESUMED - starting pending shares processing...');
      _resumeRetryCount = 0;

      // Use postFrameCallback to ensure UI is ready
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          debugPrint('Widget not mounted, aborting processing');
          return;
        }

        // Try processing immediately, then with retries
        await _processPendingSharesWithRetry();
      });
    }
  }

  /// Process pending shares with retry mechanism
  Future<void> _processPendingSharesWithRetry() async {
    debugPrint('Attempt #${_resumeRetryCount + 1} to process pending shares');

    // NOTE: We intentionally do NOT call recheckForShares() here.
    // On iOS, the custom share extension saves to SharedPreferences (handled by
    // processPendingSharesImmediately below). On Android, the receive_sharing_intent
    // stream handles shares automatically. Calling recheckForShares() would cause
    // getInitialMedia() to return an already-processed share, leading to duplicate
    // uploads and error toasts.

    try {
      final authState = ref.read(authProvider);
      final currentUser = ref.read(currentUserProvider);

      debugPrint('Auth state: ${authState.status}');
      debugPrint('Current user: ${currentUser?.id ?? "NULL"}');

      if (authState.status != AuthStatus.authenticated) {
        debugPrint('❌ User not authenticated (status: ${authState.status})');
        debugPrint('Cannot process pending shares - user needs to login');
        return;
      }

      if (currentUser == null) {
        debugPrint('⚠️  Auth status is authenticated but currentUser is null!');

        // Retry with increasing delays: 200ms, 500ms, 1000ms
        if (_resumeRetryCount < 3) {
          _resumeRetryCount++;
          final delay = _resumeRetryCount == 1 ? 200 : (_resumeRetryCount == 2 ? 500 : 1000);
          debugPrint('Retrying in ${delay}ms... (attempt $_resumeRetryCount/3)');

          if (!mounted) return;
          await Future.delayed(Duration(milliseconds: delay));
          if (!mounted) return;

          await _processPendingSharesWithRetry();
          return;
        } else {
          debugPrint('❌ Failed after 3 retries - currentUser still null');
          return;
        }
      }

      debugPrint('✓ User authenticated and ready: ${currentUser.id}');
      debugPrint('Calling processPendingSharesImmediately()...');

      await ref.read(contentProvider.notifier).processPendingSharesImmediately();

      debugPrint('✓ processPendingSharesImmediately() completed');
      debugPrint('═══════════════════════════════════════════════════');
    } catch (e, stackTrace) {
      debugPrint('❌ Error processing pending shares on resume: $e');
      debugPrint('Stack trace: $stackTrace');

      // Retry on error (up to 3 times)
      if (_resumeRetryCount < 3) {
        _resumeRetryCount++;
        final delay = 500 * _resumeRetryCount;
        debugPrint('Error occurred, retrying in ${delay}ms... (attempt $_resumeRetryCount/3)');

        if (!mounted) return;
        await Future.delayed(Duration(milliseconds: delay));
        if (!mounted) return;

        await _processPendingSharesWithRetry();
      } else {
        debugPrint('❌ Failed after 3 retries due to errors');
        debugPrint('═══════════════════════════════════════════════════');
      }
    }
  }

  void _setupNotificationNavigation() {
    // Set up FCM notification tap handler to navigate to content detail
    FCMService().onNotificationTapped = (String contentItemId) {
      debugPrint('[FCM] Notification tapped, navigating to content: $contentItemId');

      // Use postFrameCallback to ensure router is ready and widget is mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          debugPrint('[FCM] Widget not mounted, cannot navigate');
          return;
        }

        try {
          // Get router from provider
          final router = ref.read(appRouterProvider);
          debugPrint('[FCM] Router obtained, pushing to /content/$contentItemId');
          router.push('/content/$contentItemId');
        } catch (e) {
          debugPrint('[FCM] Error navigating to content: $e');
        }
      });
    };
    debugPrint('[FCM] Notification navigation handler set up');
  }

  /// Initialize universal link handling for space invitations
  ///
  /// Handles HTTPS universal links: https://YOUR_BACKEND_DOMAIN/invite/TOKEN
  ///
  /// Universal links are verified via:
  /// - iOS: apple-app-site-association file (served at /.well-known/)
  /// - Android: assetlinks.json file (served at /.well-known/)
  ///
  /// Benefits of universal links:
  /// - Works even if app isn't installed (shows web fallback page)
  /// - Opens app directly without "Open with?" dialog
  /// - More professional and trustworthy (uses your domain)
  /// - Shareable anywhere (email, social media, SMS)
  void _initDeepLinks() {
    _appLinks = AppLinks();

    // Handle initial link if app was opened from a link (cold start)
    _appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        debugPrint('[DeepLink] Initial link detected: $uri');
        _handleDeepLink(uri);
      } else {
        debugPrint('[DeepLink] No initial link');
      }
    }).catchError((err) {
      debugPrint('[DeepLink] Failed to get initial link: $err');
    });

    // Handle links while app is running (warm start)
    _appLinks.uriLinkStream.listen((Uri uri) {
      debugPrint('[DeepLink] Received link while app running: $uri');
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('[DeepLink] Error in link stream: $err');
    });

    debugPrint('[DeepLink] Universal link handling initialized');
  }

  /// Handle incoming deep link by extracting invite token and navigating
  ///
  /// Supports two formats:
  /// - Custom scheme: rekall://invite/TOKEN
  /// - Universal link: https://YOUR_BACKEND_DOMAIN/invite/TOKEN
  void _handleDeepLink(Uri uri) {
    debugPrint('[DeepLink] Processing link: ${uri.toString()}');
    debugPrint('[DeepLink] Scheme: ${uri.scheme}');
    debugPrint('[DeepLink] Host: ${uri.host}');
    debugPrint('[DeepLink] Path: ${uri.path}');
    debugPrint('[DeepLink] Path segments: ${uri.pathSegments}');

    String? token;

    // Handle custom URL scheme: rekall://invite/TOKEN
    if (uri.scheme == 'rekall') {
      if (uri.host == 'invite' && uri.pathSegments.isNotEmpty) {
        // Format: rekall://invite/TOKEN
        token = uri.pathSegments[0];
        debugPrint('[DeepLink] ✓ Extracted token from custom scheme');
      } else if (uri.host == 'invite') {
        // No path segments, invalid format
        debugPrint('[DeepLink] ❌ Invalid custom scheme format (expected rekall://invite/TOKEN)');
        return;
      }
    }
    // Handle universal link: https://YOUR_BACKEND/invite/TOKEN
    else if (uri.scheme == 'https' && uri.host == 'YOUR_BACKEND_DOMAIN') {
      // Extract token from path: /invite/TOKEN
      // Expected format: pathSegments = ['invite', 'TOKEN']
      if (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'invite') {
        token = uri.pathSegments[1];
        debugPrint('[DeepLink] ✓ Extracted token from universal link');
      } else {
        debugPrint('[DeepLink] ❌ Invalid universal link format (expected /invite/TOKEN)');
        debugPrint('[DeepLink] Path segments: ${uri.pathSegments}');
        return;
      }
    }
    // Unknown scheme
    else {
      debugPrint('[DeepLink] ⚠️ Unsupported deep link scheme: ${uri.scheme}://${uri.host}');
      debugPrint('[DeepLink] Expected: rekall://invite/TOKEN or https://YOUR_BACKEND_DOMAIN/invite/TOKEN');
      return;
    }

    // Validate token
    if (token == null || token.isEmpty) {
      debugPrint('[DeepLink] ❌ Empty or missing invite token. Ignoring.');
      return;
    }

    // Navigate to invite handler screen
    debugPrint('[DeepLink] Preparing to navigate to invite screen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        debugPrint('[DeepLink] Widget not mounted, cannot navigate');
        return;
      }

      try {
        final router = ref.read(appRouterProvider);
        debugPrint('[DeepLink] ✓ Navigating to invite screen');
        router.go('/invite/$token');
      } catch (e) {
        debugPrint('[DeepLink] ❌ Error navigating to invite: $e');
      }
    });
  }

  void _setupShareHandlerListener() {
    // Listen to shared content from other apps
    widget.shareHandler.sharedContentStream.listen((contentItem) async {
      debugPrint('Received shared content: ${contentItem.url}');

      // Log analytics event for content shared
      AnalyticsService().logContentShared(
        url: contentItem.url ?? '',
        sourceApp: contentItem.sourceAppName ?? 'unknown',
      );

      // Get current user ID
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) {
        debugPrint('User not logged in, cannot save shared content');
        return;
      }

      final sharePath = contentItem.url ?? '';

      try {
        // Check if this share was already processed in this session.
        // After the first upload, the optimistic item is replaced with the backend
        // item (url=""), so the state-based dedup below won't catch a second delivery
        // of the same file path from receive_sharing_intent.
        if (_processedSharePaths.contains(sharePath)) {
          debugPrint('Share already processed in this session, skipping: $sharePath');
          return;
        }

        // Check if URL was already uploaded (before adding optimistically)
        final contentState = ref.read(contentProvider);
        if (contentState.items.any((item) => item.url == contentItem.url)) {
          debugPrint('Content with URL already exists, skipping: ${contentItem.url}');

          // Log analytics event for duplicate content
          AnalyticsService().logDuplicateContentDetected(contentItem.url ?? '');

          return;
        }

        // Optimistically add to UI immediately for better UX
        ref.read(contentProvider.notifier).addContentOptimistically(contentItem);

        // Mark as processed BEFORE the async upload so duplicate stream events
        // arriving during the upload are caught by the session dedup above.
        _processedSharePaths.add(sharePath);

        debugPrint('Sending shared content to backend: ${contentItem.url}');
        debugPrint('  - title: ${contentItem.title}');

        final isMediaFile = contentItem.tags.contains('Media') ||
            !(contentItem.url?.startsWith('http') ?? true);

        final ContentItem savedItem;
        if (isMediaFile) {
          // Media file shared from another app — upload as multipart
          final path = contentItem.url ?? '';
          final isVideo = contentItem.tags.contains('video') ||
              path.endsWith('.mp4') || path.endsWith('.mov');
          debugPrint('Uploading shared media file: $path');

          // Verify the file is accessible before uploading (content URIs and
          // missing temp files can cause a FileSystemException that is NOT a
          // DioException and would reach the generic catch block below).
          final file = File(path);
          if (!await file.exists()) {
            debugPrint('Media file not found at path: $path');
            ref.read(contentProvider.notifier).removeOptimisticItem(contentItem.id);
            ToastHelper.showError('Could not access the shared image. Please try again.');
            return;
          }

          savedItem = await ApiService().uploadMedia(
            filePath: path,
            contentType: isVideo ? 'video' : 'image',
          );
        } else {
          // URL/text share — ingest as URL
          debugPrint('  - summary (sharedText): ${contentItem.summary.length > 200 ? '${contentItem.summary.substring(0, 200)}...' : contentItem.summary}');
          // Call backend API to ingest the URL - returns ContentItem with correct timestamp
          savedItem = await ApiService().ingestContent(
            url: contentItem.url ?? '',
            title: contentItem.title,
            sourceAppName: contentItem.sourceAppName,
            sourceAppPackage: contentItem.sourceAppPackage,
            sharedText: contentItem.summary,
          );
        }

        debugPrint('Successfully saved shared content to backend: ${savedItem.id}');

        // Log analytics event for successful ingestion
        AnalyticsService().logContentIngestionSuccess(
          contentId: savedItem.id,
          category: savedItem.category.name,
          readingTimeMinutes: savedItem.readingTimeMinutes,
        );

        // Mark URL as uploaded only after successful backend upload
        ref.read(contentProvider.notifier).markUrlAsUploaded(contentItem.url ?? '');

        // Replace optimistic item with backend item.
        // For media shares url is null on the backend, so pass the optimistic ID
        // so the matcher can find it even without a URL match.
        ref.read(contentProvider.notifier).replaceOptimisticItem(
          savedItem,
          optimisticId: isMediaFile ? contentItem.id : null,
        );

        // Show minimalist toast notification with haptic feedback
        if (_overlayContext != null && _overlayContext!.mounted) {
          SaveToastNotification.show(
            context: _overlayContext!,
            sourceApp: savedItem.sourceApp,
            category: savedItem.category,
            categoryName: savedItem.categoryName,
            categoryColorHex: savedItem.categoryColor,
            sourceAppName: savedItem.sourceAppName,
          );
        }

      } catch (e) {
        debugPrint('Failed to save shared content to backend: $e');
        debugPrint('Error details: ${e.toString()}');

        // Allow retry by removing from session dedup set
        _processedSharePaths.remove(sharePath);

        // Log analytics event for failed ingestion
        AnalyticsService().logContentIngestionFailed(contentItem.url ?? '', e.toString());

        // Remove the optimistic item so the feed isn't left in a stale state
        ref.read(contentProvider.notifier).removeOptimisticItem(contentItem.id);

        final isMediaShare = contentItem.tags.contains('Media');
        if (isMediaShare) {
          ToastHelper.showError('Failed to save image. Please try again.');
        } else {
          ToastHelper.showError('Failed to save content. Will retry later.');
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'ReKall - Your internet, organized',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Store context for toast notifications
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            _overlayContext = context;
            // Set context for ToastHelper
            ToastHelper.setContext(context);
          }
        });
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
