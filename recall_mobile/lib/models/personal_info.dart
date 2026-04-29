/// Personal information about the user (self-entity).
class PersonalInfo {
  final String? entityId;
  final String name;
  final String? bio;
  final Map<String, String>? socialLinks;
  final Map<String, dynamic>? enrichedData;
  final DateTime? lastRefreshedAt;

  PersonalInfo({
    this.entityId,
    required this.name,
    this.bio,
    this.socialLinks,
    this.enrichedData,
    this.lastRefreshedAt,
  });

  factory PersonalInfo.fromJson(Map<String, dynamic> json) {
    return PersonalInfo(
      entityId: json['entity_id'],
      name: json['name'] ?? '',
      bio: json['bio'],
      socialLinks: json['social_links'] != null
          ? Map<String, String>.from(json['social_links'])
          : null,
      enrichedData: json['enriched_data'] != null
          ? Map<String, dynamic>.from(json['enriched_data'])
          : null,
      lastRefreshedAt: json['last_refreshed_at'] != null
          ? DateTime.parse(json['last_refreshed_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entity_id': entityId,
      'name': name,
      'bio': bio,
      'social_links': socialLinks,
      'enriched_data': enrichedData,
      'last_refreshed_at': lastRefreshedAt?.toIso8601String(),
    };
  }

  PersonalInfo copyWith({
    String? entityId,
    String? name,
    String? bio,
    Map<String, String>? socialLinks,
    Map<String, dynamic>? enrichedData,
    DateTime? lastRefreshedAt,
  }) {
    return PersonalInfo(
      entityId: entityId ?? this.entityId,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      socialLinks: socialLinks ?? this.socialLinks,
      enrichedData: enrichedData ?? this.enrichedData,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
    );
  }

  bool get hasBeenSeeded => entityId != null;
  bool get hasSocialLinks => socialLinks != null && socialLinks!.isNotEmpty;
  bool get hasEnrichedData =>
      enrichedData != null &&
      enrichedData!.values.any((v) => v is Map && !v.containsKey('error'));
}
