import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/content_item.dart';
import 'source_app_detector.dart';
import 'dart:convert';

/// Service to process shares that were saved while app was closed
class PendingSharesService {
  static const String _keyPendingShares = 'pending_shares';  // Flutter adds 'flutter.' prefix automatically

  /// Check for pending shares and return them (atomic operation: read and clear)
  /// Also deduplicates URLs before returning
  Future<List<ContentItem>> processPendingShares(String userId) async {
    debugPrint('╔════════════════════════════════════════════════════╗');
    debugPrint('║  PENDING SHARES SERVICE                           ║');
    debugPrint('╚════════════════════════════════════════════════════╝');
    debugPrint('Reading SharedPreferences key: $_keyPendingShares');
    debugPrint('User ID: $userId');

    try {
      await SourceAppDetector.initialize();
      final prefs = await SharedPreferences.getInstance();
      debugPrint('✓ SharedPreferences instance obtained');

      // CRITICAL: Reload from disk to invalidate cache
      // When ShareActivity writes while Flutter app is running, the in-memory cache
      // is not updated. We must reload from disk to see the new data.
      debugPrint('Reloading SharedPreferences from disk to bypass cache...');
      await prefs.reload();
      debugPrint('✓ SharedPreferences reloaded from disk');

      // DEBUG: List all keys in SharedPreferences
      final allKeys = prefs.getKeys();
      debugPrint('DEBUG: All keys in SharedPreferences (after reload):');
      if (allKeys.isEmpty) {
        debugPrint('  (no keys found)');
      } else {
        for (final key in allKeys) {
          final value = prefs.get(key);
          final preview = value.toString().length > 100
              ? '${value.toString().substring(0, 100)}...'
              : value.toString();
          debugPrint('  - $key = $preview');
        }
      }

      // Flutter automatically adds 'flutter.' prefix, so 'pending_shares' becomes 'flutter.pending_shares'
      // This matches what ShareActivity saves
      debugPrint('Reading key: "$_keyPendingShares" (stored as "flutter.$_keyPendingShares")');

      // Atomic operation: read and clear in one transaction
      final pendingSharesJson = prefs.getString(_keyPendingShares);

      if (pendingSharesJson == null) {
        debugPrint('✓ No data found for key "$_keyPendingShares" (null)');
        debugPrint('This means no shares were saved by ShareActivity.');
        return [];
      }

      if (pendingSharesJson.isEmpty) {
        debugPrint('✓ Data found but empty string for key "$_keyPendingShares"');
        return [];
      }

      debugPrint('✓ Found pending shares data: ${pendingSharesJson.length} characters');
      debugPrint('Raw data preview (first 200 chars):');
      debugPrint(pendingSharesJson.length > 200
          ? '${pendingSharesJson.substring(0, 200)}...'
          : pendingSharesJson);

      // Clear immediately after reading to prevent concurrent reads
      await prefs.remove(_keyPendingShares);
      debugPrint('✓ Cleared SharedPreferences key "$_keyPendingShares" (atomic read+clear)');

      // Parse JSON array (new format) or migrate from old format
      List<dynamic> sharesArray;
      try {
        sharesArray = jsonDecode(pendingSharesJson) as List<dynamic>;
        debugPrint('✓ Parsed as JSON array: ${sharesArray.length} item(s)');
      } catch (e) {
        debugPrint('⚠️ Not valid JSON, attempting to migrate from old format...');
        sharesArray = _migrateOldFormat(pendingSharesJson);
        debugPrint('✓ Migrated ${sharesArray.length} item(s) from old format');
      }

      final contentItems = <ContentItem>[];
      final seenUrls = <String>{}; // Track URLs to deduplicate

      for (int i = 0; i < sharesArray.length; i++) {
        debugPrint('─────────────────────────────────────────────────');
        debugPrint('Processing share ${i + 1}/${sharesArray.length}');

        try {
          final shareObj = sharesArray[i] as Map<String, dynamic>;
          final timestamp = shareObj['timestamp'] as int;
          final content = shareObj['content'] as String;

          debugPrint('Timestamp: $timestamp');
          debugPrint('Content preview: ${content.length > 100 ? "${content.substring(0, 100)}..." : content}');

          final mediaType = shareObj['type'] as String?; // 'image' or 'video' for iOS media shares
          final contentItem = _createContentItem(
            userId,
            content,
            timestamp,
            packageName: shareObj['package_name'] as String?,
            appName: shareObj['app_name'] as String?,
            mediaType: mediaType,
          );

          debugPrint('✓ Parsed successfully:');
          debugPrint('  URL: ${contentItem.url}');
          debugPrint('  Title: ${contentItem.title}');
          debugPrint('  Source: ${contentItem.sourceApp}');
          debugPrint('  Category: ${contentItem.category}');

          // Deduplicate by URL - skip if we've already seen this URL
          if (contentItem.url != null && !seenUrls.contains(contentItem.url)) {
            seenUrls.add(contentItem.url!);
            contentItems.add(contentItem);
            debugPrint('✓ Added to results (unique URL)');
          } else {
            debugPrint('⊘ Skipping - duplicate URL already processed');
          }
        } catch (e, stackTrace) {
          debugPrint('❌ Error parsing share: $e');
          debugPrint('Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
          // Skip invalid entries
        }
      }

      debugPrint('─────────────────────────────────────────────────');
      debugPrint('SUMMARY:');
      debugPrint('  Total shares: ${sharesArray.length}');
      debugPrint('  Successfully parsed: ${contentItems.length}');
      debugPrint('  Duplicates skipped: ${sharesArray.length - contentItems.length}');
      debugPrint('╚════════════════════════════════════════════════════╝');

      return contentItems;
    } catch (e, stackTrace) {
      debugPrint('❌ CRITICAL ERROR in processPendingShares: $e');
      debugPrint('Stack trace:');
      debugPrint(stackTrace.toString());
      return [];
    }
  }

  /// Save a pending share (for retry after failure)
  Future<void> savePendingShare(String url, int timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJsonStr = prefs.getString(_keyPendingShares);

      List<dynamic> sharesArray;
      if (existingJsonStr != null && existingJsonStr.isNotEmpty) {
        try {
          sharesArray = jsonDecode(existingJsonStr) as List<dynamic>;
        } catch (e) {
          // Old format - migrate it
          sharesArray = _migrateOldFormat(existingJsonStr);
        }
      } else {
        sharesArray = [];
      }

      // Add new share
      sharesArray.add({
        'timestamp': timestamp,
        'content': url,
      });

      // Save back as JSON
      await prefs.setString(_keyPendingShares, jsonEncode(sharesArray));
    } catch (e) {
      debugPrint('Error saving pending share: $e');
    }
  }

  /// Get count of pending shares without processing
  Future<int> getPendingCount(String? userId) async {
    if (userId == null) return 0;

    final prefs = await SharedPreferences.getInstance();
    final pendingSharesJson = prefs.getString(_keyPendingShares);

    if (pendingSharesJson == null || pendingSharesJson.isEmpty) {
      return 0;
    }

    try {
      final List<dynamic> sharesArray = jsonDecode(pendingSharesJson);
      return sharesArray.length;
    } catch (e) {
      debugPrint('[PendingShares] Error getting count: $e');
      return 0;
    }
  }

  /// Mark specific URLs as synced (remove from pending)
  Future<void> markAsSynced(List<String> urls) async {
    if (urls.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final pendingSharesJson = prefs.getString(_keyPendingShares);

    if (pendingSharesJson == null || pendingSharesJson.isEmpty) {
      return;
    }

    try {
      List<dynamic> sharesArray = jsonDecode(pendingSharesJson);

      // Remove shares with matching URLs
      sharesArray.removeWhere((item) {
        final content = item['content']?.toString() ?? '';
        return urls.any((url) => content.contains(url));
      });

      // Save updated array
      if (sharesArray.isEmpty) {
        await prefs.remove(_keyPendingShares);
        debugPrint('[PendingShares] All pending shares cleared');
      } else {
        await prefs.setString(_keyPendingShares, jsonEncode(sharesArray));
        debugPrint('[PendingShares] Marked ${urls.length} URL(s) as synced, ${sharesArray.length} remaining');
      }
    } catch (e) {
      debugPrint('[PendingShares] Error marking as synced: $e');
    }
  }

  /// Migrate old pipe-separated format to JSON format
  List<dynamic> _migrateOldFormat(String oldData) {
    final result = <Map<String, dynamic>>[];

    try {
      final lines = oldData.split('\n').where((l) => l.isNotEmpty);
      for (final line in lines) {
        final parts = line.split('|');
        if (parts.length >= 2) {
          final timestamp = int.tryParse(parts[0]) ?? DateTime.now().millisecondsSinceEpoch;
          final content = parts.sublist(1).join('|');
          result.add({'timestamp': timestamp, 'content': content});
        } else if (line.startsWith('http://') || line.startsWith('https://')) {
          // Orphaned URL without timestamp
          result.add({
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'content': line,
          });
        }
      }
    } catch (e) {
      debugPrint('Error migrating old format: $e');
    }

    return result;
  }

  ContentItem _createContentItem(
    String userId,
    String text,
    int timestamp, {
    String? packageName,
    String? appName,
    String? mediaType, // 'image' or 'video' for iOS media shares
  }) {
    // iOS media shares: text is a file path, not a URL
    if (mediaType == 'image' || mediaType == 'video') {
      return ContentItem(
        id: 'content-$timestamp',
        userId: userId,
        url: text,  // file path in the app group container
        title: 'Shared ${mediaType == 'video' ? 'Video' : 'Photo'}',
        summary: 'Media shared from external app. Processing...',
        tags: ['Media', mediaType!],
        sourceApp: SourceApp.other,
        category: ContentCategory.other,
        createdAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    }

    final url = _extractUrl(text) ?? text;
    final detection = _detectSourceApp(
      url,
      packageName: packageName,
      appName: appName,
    );
    final title = _extractTitleFromUrl(url);
    final category = _detectCategory(url, detection.sourceApp);

    return ContentItem(
      id: 'content-$timestamp',
      userId: userId,
      url: url,
      title: title,
      summary: 'Shared from external app. Processing...',
      tags: ['Shared'],
      sourceApp: detection.sourceApp,
      sourceAppName: detection.appName,
      sourceAppPackage: detection.packageName,
      category: category,
      createdAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      readingTimeMinutes: 5,
    );
  }

  String? _extractUrl(String text) {
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
        // Check if it's a Twitter/X URL
        if (urlLower.contains('twitter.com') || urlLower.contains('x.com')) {
          // Extract clean Twitter URL (remove query params that might contain JS)
          return _cleanTwitterUrl(url);
        }
      }
    }

    // Otherwise, return the first valid URL
    final firstMatch = matches.first.group(0);
    if (firstMatch != null) {
      return _cleanUrl(firstMatch);
    }

    return null;
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

  String _extractTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();

      if (segments.isNotEmpty) {
        final lastSegment = segments.last;
        final title = lastSegment
            .replaceAll('-', ' ')
            .replaceAll('_', ' ')
            .replaceAll('.html', '')
            .trim();

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

  ContentCategory _detectCategory(String url, SourceApp sourceApp) {
    final urlLower = url.toLowerCase();

    if (urlLower.contains('tech') ||
        urlLower.contains('programming') ||
        urlLower.contains('software') ||
        urlLower.contains('ai') ||
        urlLower.contains('coding') ||
        sourceApp == SourceApp.github ||
        sourceApp == SourceApp.hackerNews) {
      return ContentCategory.technology;
    }

    if (urlLower.contains('design') ||
        urlLower.contains('ui') ||
        urlLower.contains('ux')) {
      return ContentCategory.design;
    }

    if (urlLower.contains('business') ||
        urlLower.contains('startup') ||
        urlLower.contains('entrepreneur') ||
        sourceApp == SourceApp.productHunt) {
      return ContentCategory.business;
    }

    return ContentCategory.other;
  }
}
