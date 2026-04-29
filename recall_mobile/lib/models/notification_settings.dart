/// Notification settings model.
///
/// Matches backend NotificationSettingsResponse schema.
class NotificationSettings {
  final String userId;
  final bool isEnabled;
  final String notificationTimeUtc; // "HH:MM:SS" format
  final String notificationTimeLocal; // "HH:MM" format
  final int utcOffsetMinutes; // e.g., -300 for EST
  final DateTime? lastNotificationSentAt;

  const NotificationSettings({
    required this.userId,
    required this.isEnabled,
    required this.notificationTimeUtc,
    required this.notificationTimeLocal,
    required this.utcOffsetMinutes,
    this.lastNotificationSentAt,
  });

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      userId: json['user_id'] as String,
      isEnabled: json['is_enabled'] as bool,
      notificationTimeUtc: json['notification_time_utc'] as String,
      notificationTimeLocal: json['notification_time_local'] as String,
      utcOffsetMinutes: json['utc_offset_minutes'] as int,
      lastNotificationSentAt: json['last_notification_sent_at'] != null
          ? DateTime.parse(json['last_notification_sent_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'is_enabled': isEnabled,
      'notification_time_utc': notificationTimeUtc,
      'notification_time_local': notificationTimeLocal,
      'utc_offset_minutes': utcOffsetMinutes,
      'last_notification_sent_at': lastNotificationSentAt?.toIso8601String(),
    };
  }

  /// Create default settings (disabled, 1 PM UTC).
  factory NotificationSettings.defaultSettings(String userId) {
    return NotificationSettings(
      userId: userId,
      isEnabled: false,
      notificationTimeUtc: '13:00:00',
      notificationTimeLocal: '13:00',
      utcOffsetMinutes: 0,
      lastNotificationSentAt: null,
    );
  }

  NotificationSettings copyWith({
    String? userId,
    bool? isEnabled,
    String? notificationTimeUtc,
    String? notificationTimeLocal,
    int? utcOffsetMinutes,
    DateTime? lastNotificationSentAt,
  }) {
    return NotificationSettings(
      userId: userId ?? this.userId,
      isEnabled: isEnabled ?? this.isEnabled,
      notificationTimeUtc: notificationTimeUtc ?? this.notificationTimeUtc,
      notificationTimeLocal: notificationTimeLocal ?? this.notificationTimeLocal,
      utcOffsetMinutes: utcOffsetMinutes ?? this.utcOffsetMinutes,
      lastNotificationSentAt: lastNotificationSentAt ?? this.lastNotificationSentAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is NotificationSettings &&
        other.userId == userId &&
        other.isEnabled == isEnabled &&
        other.notificationTimeUtc == notificationTimeUtc &&
        other.notificationTimeLocal == notificationTimeLocal &&
        other.utcOffsetMinutes == utcOffsetMinutes &&
        other.lastNotificationSentAt == lastNotificationSentAt;
  }

  @override
  int get hashCode {
    return userId.hashCode ^
        isEnabled.hashCode ^
        notificationTimeUtc.hashCode ^
        notificationTimeLocal.hashCode ^
        utcOffsetMinutes.hashCode ^
        lastNotificationSentAt.hashCode;
  }
}
