/// Filter option model for search filters.
///
/// This file contains data models for representing filter options
/// returned from the backend's /filter-options endpoint.
library;

/// Single filter option with count
class FilterOption {
  final String value;
  final String displayName;
  final int count;
  final String? color;

  const FilterOption({
    required this.value,
    required this.displayName,
    required this.count,
    this.color,
  });

  /// Create FilterOption from JSON
  factory FilterOption.fromJson(Map<String, dynamic> json) {
    return FilterOption(
      value: json['value'] as String,
      displayName: json['display_name'] as String,
      count: json['count'] as int,
      color: json['color'] as String?,
    );
  }

  /// Convert FilterOption to JSON
  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'display_name': displayName,
      'count': count,
      'color': color,
    };
  }

  @override
  String toString() {
    return 'FilterOption(value: $value, displayName: $displayName, count: $count, color: $color)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterOption &&
        other.value == value &&
        other.displayName == displayName &&
        other.count == count &&
        other.color == color;
  }

  @override
  int get hashCode {
    return Object.hash(value, displayName, count, color);
  }
}

/// Container for all filter options
class FilterOptions {
  final List<FilterOption> categories;
  final List<FilterOption> userCategories;
  final List<FilterOption> sources;

  const FilterOptions({
    required this.categories,
    required this.userCategories,
    required this.sources,
  });

  /// Create FilterOptions from JSON
  factory FilterOptions.fromJson(Map<String, dynamic> json) {
    return FilterOptions(
      categories: (json['categories'] as List<dynamic>)
          .map((e) => FilterOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      userCategories: (json['user_categories'] as List<dynamic>)
          .map((e) => FilterOption.fromJson(e as Map<String, dynamic>))
          .toList(),
      sources: (json['sources'] as List<dynamic>)
          .map((e) => FilterOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Convert FilterOptions to JSON
  Map<String, dynamic> toJson() {
    return {
      'categories': categories.map((e) => e.toJson()).toList(),
      'user_categories': userCategories.map((e) => e.toJson()).toList(),
      'sources': sources.map((e) => e.toJson()).toList(),
    };
  }

  /// Get total number of filter options available
  int get totalCount {
    return categories.length + userCategories.length + sources.length;
  }

  /// Check if there are any filter options available
  bool get hasOptions {
    return categories.isNotEmpty ||
        userCategories.isNotEmpty ||
        sources.isNotEmpty;
  }

  @override
  String toString() {
    return 'FilterOptions(categories: ${categories.length}, userCategories: ${userCategories.length}, sources: ${sources.length})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterOptions &&
        _listEquals(other.categories, categories) &&
        _listEquals(other.userCategories, userCategories) &&
        _listEquals(other.sources, sources);
  }

  @override
  int get hashCode {
    return Object.hash(
      Object.hashAll(categories),
      Object.hashAll(userCategories),
      Object.hashAll(sources),
    );
  }

  /// Helper method to compare lists
  bool _listEquals(List<FilterOption> a, List<FilterOption> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
