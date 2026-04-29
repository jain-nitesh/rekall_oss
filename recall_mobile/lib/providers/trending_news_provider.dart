import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trending_news_item.dart';
import '../services/api_service.dart';

final trendingNewsProvider =
    FutureProvider<List<TrendingNewsItem>>((ref) async {
  final rawItems = await ApiService().getTrendingNews();
  return rawItems
      .map((json) => TrendingNewsItem.fromJson(json))
      .toList();
});
