/// User's AI usage statistics
class UsageStats {
  final int aiSummariesUsed;
  final int monthlyLimit;
  final String plan;

  UsageStats({
    required this.aiSummariesUsed,
    required this.monthlyLimit,
    required this.plan,
  });

  factory UsageStats.fromJson(Map<String, dynamic> json) {
    return UsageStats(
      aiSummariesUsed: json['ai_summaries_used'],
      monthlyLimit: json['monthly_limit'],
      plan: json['plan'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ai_summaries_used': aiSummariesUsed,
      'monthly_limit': monthlyLimit,
      'plan': plan,
    };
  }

  /// Get usage percentage (0-100)
  double get usagePercentage {
    if (monthlyLimit == 0) return 0;
    return (aiSummariesUsed / monthlyLimit) * 100;
  }

  /// Check if user is approaching limit (>80%)
  bool get isApproachingLimit => usagePercentage > 80;

  /// Check if user has exceeded limit
  bool get hasExceededLimit => aiSummariesUsed >= monthlyLimit;

  /// Get remaining summaries
  int get remainingSummaries => monthlyLimit - aiSummariesUsed;
}
