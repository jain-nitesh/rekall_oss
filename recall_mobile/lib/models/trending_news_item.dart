class TrendingNewsItem {
  final String title;
  final String summary;
  final String url;
  final String source;

  const TrendingNewsItem({
    required this.title,
    required this.summary,
    required this.url,
    required this.source,
  });

  factory TrendingNewsItem.fromJson(Map<String, dynamic> json) {
    return TrendingNewsItem(
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      url: json['url'] as String? ?? '',
      source: json['source'] as String? ?? '',
    );
  }

  bool get isSaveable => url.isNotEmpty;
}
