import 'package:flutter/material.dart';
import '../models/content_item.dart';

/// App-wide constants for ReKall
class AppConstants {
  // API Configuration
  static const String apiBaseUrl = '<YOUR_API_URL>';
  static const int apiTimeout = 30000; // 30 seconds
  static const String appDeepLinkUrl = '<YOUR_DEEP_LINK_URL>'; // Deep link URL for invite links

  // Spacing (8pt grid system for precision - optimized for screen space)
  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingXM = 20.0;  // New: intermediate spacing
  static const double spacingL = 24.0;
  static const double spacingXL = 24.0;   // Reduced from 32px for better space usage
  static const double spacingXXL = 32.0;  // Reduced from 48px for better space usage

  // Border Radius (Soft UI - 12px-16px range)
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 14.0;
  static const double radiusXL = 16.0;

  // ══════════════════════════════════════════════════════════════════
  // ReKall Brand Color Palette (Mockup Design)
  // ══════════════════════════════════════════════════════════════════

  // Brand Colors - Updated from mockup
  static const Color primaryBlueCyan = Color(0xFF13A4EC);    // Primary Brand from mockup - Bright cyan/blue
  static const Color synapseIndigo = Color(0xFF4F46E5);     // Secondary Brand - Buttons, logo, active states
  static const Color recallCyan = Color(0xFF06B6D4);        // Action/Accent - Save confirmations, highlights

  // Dark Theme Colors from Mockup
  static const Color backgroundDark = Color(0xFF101C22);    // Main dark background from mockup
  static const Color surfaceDark = Color(0xFF1C2327);       // Card/surface dark from mockup
  static const Color deepSpace = Color(0xFF0F172A);         // Alternative background dark

  // Text Colors
  static const Color starlight = Color(0xFFF8FAFC);         // Text Light - Primary text on dark backgrounds
  static const Color slateGray = Color(0xFF94A3B8);         // Text Secondary - Subtitles, metadata, timestamps

  // Light Mode Colors
  static const Color softWhite = Color(0xFFF5F5F7);          // Background light
  static const Color white = Color(0xFFFFFFFF);              // Surface light

  // Accent Variations
  static const Color synapseIndigoLight = Color(0xFF818CF8); // Hover/Active
  static const Color synapseIndigoDark = Color(0xFF4338CA);  // Pressed

  // Gradient Definitions (Premium Visual Polish)
  static const List<Color> primaryGradient = [
    Color(0xFF4F46E5), // Synapse Indigo
    Color(0xFF6366F1), // Lighter indigo for gradient
  ];

  static const List<Color> accentGradient = [
    Color(0xFF06B6D4), // Recall Cyan
    Color(0xFF0EA5E9), // Sky blue for gradient
  ];

  static const List<Color> surfaceGradient = [
    Color(0xFFFAFAFA), // Ultra-light gray
    Color(0xFFFFFFFF), // White
  ];

  // Enhanced 3-stop gradients for premium feel
  static const List<Color> primaryGradientEnhanced = [
    Color(0xFF4F46E5), // Synapse Indigo
    Color(0xFF6366F1), // Vibrant Purple
    Color(0xFF818CF8), // Electric Blue
  ];

  static const List<Color> accentGradientEnhanced = [
    Color(0xFF06B6D4), // Recall Cyan
    Color(0xFF0EA5E9), // Sky Blue
    Color(0xFF3B82F6), // Azure
  ];

  static const List<Color> surfaceGradientEnhanced = [
    Color(0xFFFFFFFF), // Pure White
    Color(0xFFFAFAFA), // Ultra-light gray
    Color(0xFFF5F5F7), // Soft White
  ];

  // Overlay colors for depth hierarchy
  static const Color overlayLight = Color(0x0F000000); // 6% black
  static const Color overlayDark = Color(0x1A000000);  // 10% black

  // Semantic Colors (muted to maintain premium feel)
  static const Color errorColor = Color(0xFFEF4444);         // Red 500
  static const Color successColor = Color(0xFF10B981);       // Green 500
  static const Color warningColor = Color(0xFFF59E0B);       // Amber 500

  // ══════════════════════════════════════════════════════════════════
  // Legacy mappings for backward compatibility
  // ══════════════════════════════════════════════════════════════════
  static const Color electricIndigo = synapseIndigo;
  static const Color electricIndigoLight = synapseIndigoLight;
  static const Color electricIndigoDark = synapseIndigoDark;
  static const Color deepCharcoal = deepSpace;
  static const Color primaryColor = synapseIndigo;
  static const Color secondaryColor = synapseIndigoLight;
  static const Color accentColor = recallCyan;
  static const Color backgroundColor = softWhite;
  static const Color surfaceColor = white;

  // Text Colors
  static const Color textPrimary = deepSpace;                // Main text on light backgrounds
  static const Color textSecondary = slateGray;              // Subtitles, metadata
  static const Color textTertiary = Color(0xFF9CA3AF);       // Gray 400 - Disabled text
  static const Color textInverse = starlight;                // Text on dark backgrounds
  static const Color textInversePrimary = starlight;         // Primary text on dark
  static const Color textInverseSecondary = slateGray;       // Secondary text on dark

  // Border & Divider (subtle)
  static const Color borderColor = Color(0xFFE5E7EB);        // Gray 200
  static const Color dividerColor = Color(0xFFF3F4F6);       // Gray 100

  // Border Width (Soft UI - subtle 1px borders)
  static const double borderWidthThin = 1.0;
  static const double borderWidthMedium = 1.5;

  // Elevation (minimal - prefer borders over shadows)
  static const double elevationNone = 0.0;
  static const double elevationLow = 1.0;
  static const double elevationMedium = 2.0;

  // Glassmorphism blur values
  static const double blurSurface = 10.0;       // Main content cards
  static const double blurElevated = 16.0;      // Modal sheets, dialogs
  static const double blurFloating = 20.0;      // FABs, toasts

  // Icon sizes
  static const double iconTiny = 16.0;
  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 32.0;
  static const double iconHuge = 48.0;
  static const double iconMassive = 64.0;

  // Source App Colors (muted, premium palette)
  static const Map<SourceApp, Color> sourceAppColors = {
    SourceApp.linkedin: synapseIndigo,          // Synapse Indigo
    SourceApp.reddit: Color(0xFFF97316),        // Orange 500
    SourceApp.twitter: Color(0xFF3B82F6),       // Blue 500
    SourceApp.medium: deepSpace,                // Deep Space
    SourceApp.youtube: Color(0xFFEF4444),       // Red 500
    SourceApp.hackerNews: Color(0xFFF59E0B),    // Amber 500
    SourceApp.productHunt: Color(0xFFEC4899),   // Pink 500
    SourceApp.github: deepSpace,                // Deep Space
    SourceApp.news: synapseIndigo,              // Synapse Indigo
    SourceApp.other: Color(0xFF9CA3AF),         // Gray 400
  };

  // Category Colors (cohesive with brand palette)
  static const Map<ContentCategory, Color> categoryColors = {
    ContentCategory.technology: synapseIndigo,      // Synapse Indigo
    ContentCategory.design: Color(0xFFA855F7),      // Purple 500
    ContentCategory.business: Color(0xFF10B981),    // Green 500
    ContentCategory.science: recallCyan,            // Recall Cyan
    ContentCategory.productivity: Color(0xFFF59E0B), // Amber 500
    ContentCategory.education: Color(0xFF3B82F6),   // Blue 500
    ContentCategory.entertainment: Color(0xFFEC4899), // Pink 500
    ContentCategory.other: Color(0xFF9CA3AF),       // Gray 400
  };

  // Source App Icons
  static const Map<SourceApp, IconData> sourceAppIcons = {
    SourceApp.linkedin: Icons.work,
    SourceApp.reddit: Icons.forum,
    SourceApp.twitter: Icons.tag,
    SourceApp.medium: Icons.article,
    SourceApp.youtube: Icons.play_circle_filled,
    SourceApp.hackerNews: Icons.code,
    SourceApp.productHunt: Icons.rocket_launch,
    SourceApp.github: Icons.code_outlined,
    SourceApp.news: Icons.newspaper,
    SourceApp.other: Icons.link,
  };

  // Source App Names
  static const Map<SourceApp, String> sourceAppNames = {
    SourceApp.linkedin: 'LinkedIn',
    SourceApp.reddit: 'Reddit',
    SourceApp.twitter: 'Twitter',
    SourceApp.medium: 'Medium',
    SourceApp.youtube: 'YouTube',
    SourceApp.hackerNews: 'Hacker News',
    SourceApp.productHunt: 'Product Hunt',
    SourceApp.github: 'GitHub',
    SourceApp.news: 'News',
    SourceApp.other: 'Other',
  };

  // Category Names
  static const Map<ContentCategory, String> categoryNames = {
    ContentCategory.technology: 'Technology',
    ContentCategory.design: 'Design',
    ContentCategory.business: 'Business',
    ContentCategory.science: 'Science',
    ContentCategory.productivity: 'Productivity',
    ContentCategory.education: 'Education',
    ContentCategory.entertainment: 'Entertainment',
    ContentCategory.other: 'Other',
  };

  // Category Icons
  static const Map<ContentCategory, IconData> categoryIcons = {
    ContentCategory.technology: Icons.computer,
    ContentCategory.design: Icons.palette,
    ContentCategory.business: Icons.business,
    ContentCategory.science: Icons.science,
    ContentCategory.productivity: Icons.check_circle,
    ContentCategory.education: Icons.school,
    ContentCategory.entertainment: Icons.movie,
    ContentCategory.other: Icons.more_horiz,
  };

  // Cluster category colors (for connections screen color accents)
  static const Map<String, Color> _clusterCategoryColors = {
    'technology': Color(0xFF3B82F6),   // Blue
    'business':   Color(0xFF10B981),   // Emerald
    'design':     Color(0xFF8B5CF6),   // Purple
    'science':    Color(0xFFF59E0B),   // Amber
    'culture':    Color(0xFFF43F5E),   // Rose
    'health':     Color(0xFF14B8A6),   // Teal
    'productivity': Color(0xFFF59E0B), // Amber
    'education':  Color(0xFF3B82F6),   // Blue
    'entertainment': Color(0xFFEC4899),// Pink
  };

  /// Get color for a cluster category string (case-insensitive).
  static Color clusterColorFor(String? category) {
    if (category == null || category.isEmpty) return primaryBlueCyan;
    return _clusterCategoryColors[category.toLowerCase()] ?? primaryBlueCyan;
  }

  /// Resolve category color preferring backend-provided hex values.
  static Color categoryColorFor(ContentCategory category, {String? hexColor}) {
    final parsed = _parseHexColor(hexColor);
    if (parsed != null) return parsed;
    return categoryColors[category] ?? categoryColors[ContentCategory.other]!;
  }

  /// Resolve category display name preferring backend-provided names.
  static String categoryNameFor(ContentCategory category, {String? overrideName}) {
    if (overrideName != null && overrideName.isNotEmpty) return overrideName;
    return categoryNames[category] ?? 'Other';
  }

  static Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var value = hex.replaceAll('#', '');
    if (value.length == 6) {
      value = 'FF$value'; // add alpha
    }
    if (value.length != 8) return null;
    try {
      final intColor = int.parse(value, radix: 16);
      return Color(intColor);
    } catch (_) {
      return null;
    }
  }

  // Memory Feed
  static const List<int> memoryFeedDays = [7, 30, 365];
  static const Map<int, String> memoryFeedTitles = {
    7: '7 days ago',
    30: '30 days ago',
    365: '1 year ago',
  };

  // SharedPreferences Keys
  static const String keyAuthToken = 'auth_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyUserEmail = 'user_email';
  static const String keyUserName = 'user_name';
  static const String keyUserAvatarUrl = 'user_avatar_url';
  static const String keyThemeMode = 'theme_mode';
  static const String keyFcmToken = 'fcm_token';
  static const String keyPendingInviteToken = 'pending_invite_token';

  // Default Values
  static const int defaultReadingTimeMinutes = 5;
  static const int recentSavesLimit = 15;
  static const int searchResultsLimit = 50;
}
