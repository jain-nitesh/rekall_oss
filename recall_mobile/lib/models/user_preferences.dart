/// User preferences for app settings
class UserPreferences {
  final String summaryStyle; // bullet_points, paragraph, concise
  final bool autoCategorize;
  final List<String> connectedSources;
  final bool dailyGemsEnabled;
  final String dailyGemsTime;

  UserPreferences({
    required this.summaryStyle,
    required this.autoCategorize,
    required this.connectedSources,
    this.dailyGemsEnabled = false,
    this.dailyGemsTime = '9:00 AM',
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      summaryStyle: json['summary_style'],
      autoCategorize: json['auto_categorize'],
      connectedSources: List<String>.from(json['connected_sources'] ?? []),
      dailyGemsEnabled: json['daily_gems_enabled'] ?? false,
      dailyGemsTime: json['daily_gems_time'] ?? '9:00 AM',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary_style': summaryStyle,
      'auto_categorize': autoCategorize,
      'connected_sources': connectedSources,
      'daily_gems_enabled': dailyGemsEnabled,
      'daily_gems_time': dailyGemsTime,
    };
  }

  /// Create a copy with updated fields
  UserPreferences copyWith({
    String? summaryStyle,
    bool? autoCategorize,
    List<String>? connectedSources,
    bool? dailyGemsEnabled,
    String? dailyGemsTime,
  }) {
    return UserPreferences(
      summaryStyle: summaryStyle ?? this.summaryStyle,
      autoCategorize: autoCategorize ?? this.autoCategorize,
      connectedSources: connectedSources ?? this.connectedSources,
      dailyGemsEnabled: dailyGemsEnabled ?? this.dailyGemsEnabled,
      dailyGemsTime: dailyGemsTime ?? this.dailyGemsTime,
    );
  }

  /// Get display name for summary style
  String get summaryStyleDisplayName {
    switch (summaryStyle) {
      case 'bullet_points':
        return 'Bullet Points';
      case 'paragraph':
        return 'Paragraph';
      case 'concise':
        return 'Concise';
      default:
        return 'Unknown';
    }
  }
}
