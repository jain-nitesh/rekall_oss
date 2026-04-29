import 'content_item.dart';

/// Represents a section in the memory feed (7 days, 30 days, 1 year ago)
class MemoryFeedSection {
  final String title;
  final int daysAgo;
  final List<ContentItem> items;

  const MemoryFeedSection({
    required this.title,
    required this.daysAgo,
    required this.items,
  });

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get itemCount => items.length;

  MemoryFeedSection copyWith({
    String? title,
    int? daysAgo,
    List<ContentItem>? items,
  }) {
    return MemoryFeedSection(
      title: title ?? this.title,
      daysAgo: daysAgo ?? this.daysAgo,
      items: items ?? this.items,
    );
  }

  @override
  String toString() {
    return 'MemoryFeedSection(title: $title, daysAgo: $daysAgo, itemCount: $itemCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MemoryFeedSection &&
        other.title == title &&
        other.daysAgo == daysAgo &&
        _listEquals(other.items, items);
  }

  @override
  int get hashCode => title.hashCode ^ daysAgo.hashCode ^ items.hashCode;

  bool _listEquals(List<ContentItem> a, List<ContentItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
