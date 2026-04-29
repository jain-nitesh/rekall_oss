import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/content_item.dart';
import 'source_app_detector.dart';
import 'dart:async';

/// Service for handling shared content from other apps
class ShareHandlerService {
  static final ShareHandlerService _instance = ShareHandlerService._internal();
  factory ShareHandlerService() => _instance;
  ShareHandlerService._internal();

  final _sharedContentController = StreamController<ContentItem>.broadcast();
  Stream<ContentItem> get sharedContentStream => _sharedContentController.stream;

  StreamSubscription? _mediaStreamSubscription;

  /// Initialize share handler listeners
  void initialize() {
    debugPrint('Initializing ShareHandlerService...');
    // Load any cached source mappings
    SourceAppDetector.initialize();
    
    // Listen for ALL shared content (text, URLs, and media)
    // In v1.8.1+, everything comes through getMediaStream() as SharedMediaFile objects
    // This stream works even when app is in background (as long as app process is alive)
    _mediaStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      (files) {
        debugPrint('ShareHandlerService: Received ${files.length} share(s) via stream');
        _handleSharedMedia(files);
      },
      onError: (error) {
        debugPrint('Error receiving shared content: $error');
      },
      cancelOnError: false, // Keep listening even if there's an error
    );

    // Check for content shared when app was not running
    _checkInitialSharedContent();
  }

  /// Check for content shared when app was not running
  Future<void> _checkInitialSharedContent() async {
    debugPrint('Checking for initial shared content...');
    
    // Check for initial shares (text, URLs, and media all come through getInitialMedia)
    try {
      final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty) {
        debugPrint('Found ${initialMedia.length} initial share(s)');
        _handleSharedMedia(initialMedia);
      }
    } catch (e) {
      debugPrint('Error getting initial shares: $e');
    }

    // Reset to avoid processing the same content again
    ReceiveSharingIntent.instance.reset();
  }

  /// Re-check for shares (useful when app resumes from background)
  Future<void> recheckForShares() async {
    debugPrint('Re-checking for shared content...');
    await _checkInitialSharedContent();
  }


  /// Handle shared media (text, URLs, images, files)
  /// In v1.8.1+, ALL content types come through this method as SharedMediaFile objects
  void _handleSharedMedia(List<SharedMediaFile> files) {
    if (files.isEmpty) {
      debugPrint('No shared files received');
      return;
    }

    debugPrint('Received ${files.length} shared file(s)');

    try {
      // Process each shared item
      for (final file in files) {
        debugPrint('Processing shared file: type=${file.type}, path=${file.path}');
        debugPrint('File path length: ${file.path.length}');
        debugPrint('File path first 100 chars: ${file.path.length > 100 ? file.path.substring(0, 100) : file.path}');

        // Early check: Reject deep link URLs (should be handled by deep link handler)
        if (_isDeepLinkUrl(file.path)) {
          debugPrint('⚠️ Detected deep link URL, rejecting from share handler: ${file.path}');
          debugPrint('Deep links should be handled by the app_links deep link handler, not as shared content');
          continue;
        }

        // Check if this is text/URL share
        // Text shares can be identified by:
        // 1. file.path starts with http:// or https:// (URL shares)
        // 2. file.path doesn't look like a file path (no file system separators)
        // 3. file.path is relatively short (URLs/text are usually < 2000 chars)
        final path = file.path;
        final isUrl = path.startsWith('http://') || path.startsWith('https://');
        final looksLikeFile = path.contains('/') || path.contains('\\') || path.contains('file://');
        final isShort = path.length < 2000;

        final isTextOrUrl = isUrl || (!looksLikeFile && isShort);

        if (isTextOrUrl) {
          // Handle as URL/text
          final url = path; // For text shares, path contains the URL or text
          debugPrint('Detected text/URL share: $url');
          try {
            final contentItem = _processSharedContent(url);
            _sharedContentController.add(contentItem);
          } catch (e) {
            debugPrint('Failed to process shared content: $e');
            debugPrint('Skipping invalid share (no valid URL found)');
            // Don't add to stream if URL extraction failed
          }
        } else {
          // Handle as media file
          debugPrint('Detected media file share: ${file.path}');
          final contentItem = _processSharedMedia(file);
          _sharedContentController.add(contentItem);
        }
      }
    } catch (e) {
      debugPrint('Error processing shared content: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  /// Process shared text/URL into ContentItem
  ContentItem _processSharedContent(String text, {String? packageName, String? appName}) {
    // Extract and clean URL, filtering out JavaScript
    final url = _extractUrl(text);

    // If no valid URL found, log and skip
    if (url == null || url.isEmpty) {
      debugPrint('Warning: No valid URL found in shared text. Text preview: ${text.length > 100 ? text.substring(0, 100) : text}');
      // Return a placeholder that will fail validation
      throw Exception('No valid URL found in shared content');
    }

    final sourceDetection = _detectSourceApp(url, packageName: packageName, appName: appName);
    final title = _extractTitleFromUrl(url);
    final category = _detectCategory(url, sourceDetection.sourceApp);

    // Use the full shared text as summary (for backend to extract title from)
    // Remove the URL from the text to avoid duplication
    String sharedText = text.trim();
    if (sharedText.contains(url)) {
      sharedText = sharedText.replaceAll(url, '').trim();
    }
    // If text is empty after removing URL, use placeholder
    final summary = sharedText.isNotEmpty ? sharedText : 'Shared from external app. Processing...';

    debugPrint('Extracted shared text (${summary.length} chars): ${summary.length > 100 ? '${summary.substring(0, 100)}...' : summary}');

    return ContentItem(
      id: 'content-${DateTime.now().millisecondsSinceEpoch}',
      userId: 'current-user', // Will be set by provider
      url: url,
      title: title,
      summary: summary,  // ✅ Now contains actual shared text!
      tags: ['Shared'],
      sourceApp: sourceDetection.sourceApp,
      sourceAppName: sourceDetection.appName,
      sourceAppPackage: sourceDetection.packageName,
      category: category,
      createdAt: DateTime.now(),
      readingTimeMinutes: 5,
    );
  }

  /// Process shared media into ContentItem
  ContentItem _processSharedMedia(SharedMediaFile file) {
    final path = file.path;
    final type = file.type;

    final detection = SourceAppDetector.detectSourceApp(
      path,
      packageName: null,
      appName: null,
    );

    return ContentItem(
      id: 'content-${DateTime.now().millisecondsSinceEpoch}',
      userId: 'current-user',
      url: path,
      title: 'Shared ${type.name}',
      summary: 'Media file shared from external app.',
      tags: ['Media', type.name],
      sourceApp: detection.sourceApp,
      sourceAppName: detection.appName,
      sourceAppPackage: detection.packageName,
      category: ContentCategory.other,
      createdAt: DateTime.now(),
      thumbnailUrl: type == SharedMediaType.image ? path : null,
    );
  }

  /// Extract URL from text, filtering out JavaScript and invalid content
  String? _extractUrl(String text) {
    // Filter out deep link URLs (these should be handled by deep link handler, not ingested as content)
    if (_isDeepLinkUrl(text)) {
      debugPrint('Detected deep link URL, rejecting from content ingestion: $text');
      return null;
    }

    // First, try to find all URLs in the text
    final urlPattern = RegExp(
      r'https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    );

    // Find all matches
    final matches = urlPattern.allMatches(text);

    if (matches.isEmpty) {
      return null;
    }

    // Prefer Twitter/X URLs if present
    for (final match in matches) {
      final url = match.group(0);
      if (url != null) {
        final urlLower = url.toLowerCase();

        // Filter out deep link URLs
        if (_isDeepLinkUrl(url)) {
          debugPrint('Detected deep link URL in shared text, skipping: $url');
          continue;
        }

        // Check if it's a Twitter/X URL
        if (urlLower.contains('twitter.com') || urlLower.contains('x.com')) {
          // Extract clean Twitter URL (remove query params that might contain JS)
          return _cleanTwitterUrl(url);
        }
      }
    }

    // Otherwise, return the first valid URL (that's not a deep link)
    for (final match in matches) {
      final url = match.group(0);
      if (url != null && !_isDeepLinkUrl(url)) {
        return _cleanUrl(url);
      }
    }

    return null;
  }

  /// Check if URL is a deep link that should be handled by the deep link handler
  /// and not ingested as content
  ///
  /// Supports both custom scheme and universal links:
  /// - Custom scheme: rekall://invite/TOKEN
  /// - Universal link: https://YOUR_BACKEND_DOMAIN/invite/TOKEN
  bool _isDeepLinkUrl(String url) {
    final urlLower = url.toLowerCase().trim();

    // Check for custom scheme deep links
    // Format: rekall://invite/TOKEN or rekall://...
    if (urlLower.startsWith('rekall://')) {
      return true;
    }

    // Check for universal link invite URLs
    // Format: https://YOUR_BACKEND_DOMAIN/invite/TOKEN
    if (urlLower.startsWith('https://YOUR_BACKEND_DOMAIN/invite')) {
      return true;
    }

    return false;
  }

  /// Clean Twitter/X URL to remove JavaScript and invalid query params
  String _cleanTwitterUrl(String url) {
    try {
      final uri = Uri.parse(url);
      
      // Rebuild URL with only essential parts
      // Twitter/X URLs should be in format: https://twitter.com/username/status/123456
      // or https://x.com/username/status/123456
      final pathSegments = uri.pathSegments;
      
      // Check if it's a status URL
      if (pathSegments.length >= 3 && 
          (pathSegments[pathSegments.length - 2] == 'status' || 
           pathSegments[pathSegments.length - 2] == 'i' && pathSegments[pathSegments.length - 1] == 'web')) {
        // Reconstruct clean URL
        return '${uri.scheme}://${uri.host}${uri.path}';
      }
      
      // For other Twitter URLs, just remove query params
      return '${uri.scheme}://${uri.host}${uri.path}';
    } catch (e) {
      // If parsing fails, try to extract just the base URL
      final baseUrlMatch = RegExp(r'(https?://[^/?\s]+)').firstMatch(url);
      return baseUrlMatch?.group(1) ?? url;
    }
  }

  /// Clean URL to remove JavaScript and invalid characters
  String _cleanUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Rebuild URL without query params that might contain JS
      // Keep only essential query params
      final cleanQueryParams = <String, String>{};
      
      if (uri.queryParameters.isNotEmpty) {
        // Only keep safe query parameters (avoid JS injection)
        final safeParams = ['id', 'status', 't', 's', 'ref', 'utm_source', 'utm_medium', 'utm_campaign'];
        for (final key in uri.queryParameters.keys) {
          if (safeParams.contains(key.toLowerCase())) {
            final value = uri.queryParameters[key];
            if (value != null && !value.contains('<script') && !value.contains('javascript:')) {
              cleanQueryParams[key] = value;
            }
          }
        }
      }
      
      // Rebuild URI with cleaned query params
      final cleanUri = uri.replace(queryParameters: cleanQueryParams.isEmpty ? null : cleanQueryParams);
      return cleanUri.toString();
    } catch (e) {
      // If parsing fails, try to extract just the base URL
      final baseUrlMatch = RegExp(r'(https?://[^/?\s]+)').firstMatch(url);
      return baseUrlMatch?.group(1) ?? url;
    }
  }

  /// Detect source app from URL using shared detector
  SourceDetectionResult _detectSourceApp(
    String url, {
    String? packageName,
    String? appName,
  }) {
    return SourceAppDetector.detectSourceApp(
      url,
      packageName: packageName,
      appName: appName,
    );
  }

  /// Extract title from URL (basic implementation)
  String _extractTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;

      // Get the last segment of the path
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final lastSegment = segments.last;
        // Replace hyphens and underscores with spaces
        final title = lastSegment
            .replaceAll('-', ' ')
            .replaceAll('_', ' ')
            .replaceAll('.html', '')
            .trim();

        // Capitalize first letter of each word
        return title.split(' ').map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        }).join(' ');
      }

      return uri.host;
    } catch (e) {
      return 'Shared Content';
    }
  }

  /// Detect category based on URL and source
  ContentCategory _detectCategory(String url, SourceApp sourceApp) {
    final urlLower = url.toLowerCase();

    // Tech keywords
    if (urlLower.contains('tech') ||
        urlLower.contains('programming') ||
        urlLower.contains('software') ||
        urlLower.contains('ai') ||
        urlLower.contains('coding') ||
        sourceApp == SourceApp.github ||
        sourceApp == SourceApp.hackerNews) {
      return ContentCategory.technology;
    }

    // Design keywords
    if (urlLower.contains('design') ||
        urlLower.contains('ui') ||
        urlLower.contains('ux')) {
      return ContentCategory.design;
    }

    // Business keywords
    if (urlLower.contains('business') ||
        urlLower.contains('startup') ||
        urlLower.contains('entrepreneur') ||
        sourceApp == SourceApp.productHunt) {
      return ContentCategory.business;
    }

    // Science keywords
    if (urlLower.contains('science') ||
        urlLower.contains('research') ||
        urlLower.contains('study')) {
      return ContentCategory.science;
    }

    // Productivity keywords
    if (urlLower.contains('productivity') ||
        urlLower.contains('workflow') ||
        urlLower.contains('tips')) {
      return ContentCategory.productivity;
    }

    // Education keywords
    if (urlLower.contains('learn') ||
        urlLower.contains('tutorial') ||
        urlLower.contains('course') ||
        urlLower.contains('education')) {
      return ContentCategory.education;
    }

    // Entertainment keywords
    if (urlLower.contains('entertainment') ||
        urlLower.contains('movie') ||
        urlLower.contains('game') ||
        sourceApp == SourceApp.youtube) {
      return ContentCategory.entertainment;
    }

    return ContentCategory.other;
  }

  /// Dispose listeners
  void dispose() {
    _mediaStreamSubscription?.cancel();
    _sharedContentController.close();
  }
}
