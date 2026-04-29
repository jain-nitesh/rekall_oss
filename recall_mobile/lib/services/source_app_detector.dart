import 'package:recall_mobile/models/content_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

/// Provides last-known source app info from platform (best-effort).
class SourceAppInfoProvider {
  static const _channel = MethodChannel('com.rekallhq/source_app');
  static bool _loaded = false;
  static String? lastBundleId;
  static String? lastAppName;

  static Future<void> load() async {
    if (_loaded) return;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>?>('getLastSourceApp');
      if (result != null) {
        lastBundleId = result['bundleId'] as String?;
        lastAppName = result['appName'] as String?;
      }
    } catch (_) {
      // ignore channel failures
    } finally {
      _loaded = true;
    }
  }
}

/// Result of source detection with optional metadata.
class SourceDetectionResult {
  final SourceApp sourceApp;
  final String? appName;
  final String? packageName;

  const SourceDetectionResult({
    required this.sourceApp,
    this.appName,
    this.packageName,
  });
}

/// Shared utility for detecting source apps from URLs.
///
/// Uses proper URL parsing instead of simple substring matching.
/// This consolidates source app detection logic that was duplicated
/// across multiple files.
class SourceAppDetector {
  static const String _prefsKey = 'source_domain_names';
  static bool _initialized = false;
  static final Map<String, String> _domainAppNames = {};

  /// Platform domain to SourceApp mapping
  static const Map<String, SourceApp> _platformDomains = {
    'youtube.com': SourceApp.youtube,
    'youtu.be': SourceApp.youtube,
    'github.com': SourceApp.github,
    'reddit.com': SourceApp.reddit,
    'twitter.com': SourceApp.twitter,
    'x.com': SourceApp.twitter,
    'linkedin.com': SourceApp.linkedin,
    'medium.com': SourceApp.medium,
    'news.ycombinator.com': SourceApp.hackerNews,
    'producthunt.com': SourceApp.productHunt,
  };

  /// News site domains
  static const Set<String> _newsDomains = {
    'cnn.com',
    'bbc.com',
    'bbc.co.uk',
    'theverge.com',
    'techcrunch.com',
    'reuters.com',
    'bloomberg.com',
    'nytimes.com',
    'washingtonpost.com',
    'theguardian.com',
    'wsj.com',
    'ft.com',
    'economist.com',
  };

  /// Initialize mappings from persistent storage. Must be awaited once at app start.
  static Future<void> initialize() async {
    if (_initialized) return;
    await SourceAppInfoProvider.load();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey);
    if (stored != null) {
      for (final entry in stored) {
        final parts = entry.split('|');
        if (parts.length == 2) {
          _domainAppNames[parts[0]] = parts[1];
        }
      }
    }
    _initialized = true;
  }

  static Future<void> _persistMappings() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _domainAppNames.entries.map((e) => '${e.key}|${e.value}').toList();
    await prefs.setStringList(_prefsKey, list);
  }

  /// Detect source app from URL using domain parsing and learned mappings.
  ///
  /// Uses Uri.parse to extract and normalize the domain, prefers runtime-learned
  /// mappings (package/app names), and falls back to lightweight heuristics.
  ///
  /// Args:
  ///   url: The URL to analyze
  ///
  /// Returns:
  ///   SourceDetectionResult with enum and optional app metadata
  ///
  /// Examples:
  ///   "https://www.youtube.com/watch?v=..." → SourceApp.youtube
  ///   "https://news.ycombinator.com/item?id=..." → SourceApp.hackerNews
  ///   "https://example.com/article" → SourceApp.other
  static SourceDetectionResult detectSourceApp(
    String url, {
    String? packageName,
    String? appName,
  }) {
    try {
      if (!_initialized) {
        // Lazy init to keep callers synchronous; fire-and-forget.
        initialize();
      }
    } catch (_) {
      // ignore init errors, continue best-effort
    }

    SourceApp detected = SourceApp.other;
    String? detectedAppName = appName ?? SourceAppInfoProvider.lastAppName;

    try {
      // Parse URL to extract domain
      final uri = Uri.parse(url);
      var netloc = uri.host.toLowerCase();

      // Remove port if present (e.g., "example.com:8080" → "example.com")
      if (netloc.contains(':')) {
        netloc = netloc.split(':')[0];
      }

      // Remove www. prefix for matching (but check with it first for priority)
      final domainWithWww = netloc;
      final domainWithoutWww = netloc.startsWith('www.')
          ? netloc.substring(4)
          : netloc;

      // Prefer learned mappings (domain -> app name)
      if (_domainAppNames.containsKey(domainWithWww)) {
        detectedAppName = _domainAppNames[domainWithWww];
      } else if (_domainAppNames.containsKey(domainWithoutWww)) {
        detectedAppName = _domainAppNames[domainWithoutWww];
      } else {
        // For nested domains, try suffix match
        for (final entry in _domainAppNames.entries) {
          if (netloc.contains(entry.key)) {
            detectedAppName = entry.value;
            break;
          }
        }
      }

      // Check platform domains
      for (final entry in _platformDomains.entries) {
        if (domainWithoutWww == entry.key || domainWithoutWww.endsWith('.${entry.key}')) {
          detected = entry.value;
          break;
        }
      }

      // Check news domains
      final domainParts = domainWithoutWww.split('.');
      if (domainParts.length >= 2) {
        final baseDomain = domainParts.sublist(domainParts.length - 2).join('.');
        if (_newsDomains.contains(baseDomain)) {
          detected = SourceApp.news;
        }
      }

      // Check for generic news patterns in domain
      if (netloc.contains('news') ||
          _newsDomains.any((newsDomain) => netloc.contains(newsDomain))) {
        detected = SourceApp.news;
      }
    } catch (e) {
      // If parsing fails, keep defaults
    }

    // Learn new mapping when we have appName and a domain
    if (appName != null && appName.isNotEmpty) {
      try {
        final uri = Uri.parse(url);
        final host = uri.host.toLowerCase();
        final domain = host.startsWith('www.') ? host.substring(4) : host;
        if (domain.isNotEmpty) {
          _domainAppNames[domain] = appName;
          _persistMappings();
        }
      } catch (_) {
        // ignore learning errors
      }
    }

    return SourceDetectionResult(
      sourceApp: detected,
      appName: detectedAppName,
      packageName: packageName,
    );
  }
}

