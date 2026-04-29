class Category {
  final String id;
  final String name;
  final String? description;
  final String? color;
  final int usageCount;

  const Category({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.usageCount = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      color: json['color'] as String?,
      usageCount: json['usage_count'] as int? ?? 0,
    );
  }
}


