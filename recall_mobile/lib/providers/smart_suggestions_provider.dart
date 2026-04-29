import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import 'content_provider.dart';

/// Smart suggestion model
class SmartSuggestion {
  final String displayText;
  final String query;
  final IconData icon;
  final SourceApp? sourceApp;
  final ContentCategory? category;

  const SmartSuggestion({
    required this.displayText,
    required this.query,
    required this.icon,
    this.sourceApp,
    this.category,
  });
}

/// Provider for smart suggestions based on recent tags and content
final smartSuggestionsProvider = Provider<List<SmartSuggestion>>((ref) {
  final allContent = ref.watch(allContentProvider);

  if (allContent.isEmpty) {
    return [];
  }

  final suggestions = <SmartSuggestion>[];

  // Get all tags from recent content (last 30 items)
  final recentContent = allContent.take(30).toList();
  final tagFrequency = <String, int>{};
  final sourceFrequency = <SourceApp, int>{};
  final categoryFrequency = <ContentCategory, int>{};
  final dynamicCategoryFrequency = <String, int>{};

  for (final item in recentContent) {
    // Count tags
    for (final tag in item.tags) {
      tagFrequency[tag] = (tagFrequency[tag] ?? 0) + 1;
    }

    // Count sources
    sourceFrequency[item.sourceApp] = (sourceFrequency[item.sourceApp] ?? 0) + 1;

    // Count categories
    categoryFrequency[item.category] = (categoryFrequency[item.category] ?? 0) + 1;
    if (item.categoryName != null && item.categoryName!.isNotEmpty) {
      final name = item.categoryName!;
      dynamicCategoryFrequency[name] = (dynamicCategoryFrequency[name] ?? 0) + 1;
    }
  }

  // Sort tags by frequency
  final sortedTags = tagFrequency.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // Add top 3 tag-based suggestions
  for (final entry in sortedTags.take(3)) {
    final tag = entry.key;
    suggestions.add(SmartSuggestion(
      displayText: 'Articles about #$tag',
      query: tag,
      icon: Icons.tag,
    ));
  }

  // Sort sources by frequency
  final sortedSources = sourceFrequency.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // Add top 2 source-based suggestions
  for (final entry in sortedSources.take(2)) {
    final source = entry.key;
    final sourceName = const {
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
    }[source];

    suggestions.add(SmartSuggestion(
      displayText: 'Content from $sourceName',
      query: '',
      icon: Icons.public,
      sourceApp: source,
    ));
  }

  // Sort categories by frequency (enum)
  final sortedCategories = categoryFrequency.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  // Add top enum category suggestion
  if (sortedCategories.isNotEmpty) {
    final category = sortedCategories.first.key;
    final categoryName = const {
      ContentCategory.technology: 'Technology',
      ContentCategory.design: 'Design',
      ContentCategory.business: 'Business',
      ContentCategory.science: 'Science',
      ContentCategory.productivity: 'Productivity',
      ContentCategory.education: 'Education',
      ContentCategory.entertainment: 'Entertainment',
      ContentCategory.other: 'Other',
    }[category];

    suggestions.add(SmartSuggestion(
      displayText: '$categoryName articles',
      query: '',
      icon: Icons.category,
      category: category,
    ));
  }

  // Add top dynamic category suggestion (backend-driven names)
  final sortedDynamic = dynamicCategoryFrequency.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (sortedDynamic.isNotEmpty) {
    final dynamicName = sortedDynamic.first.key;
    suggestions.add(SmartSuggestion(
      displayText: '$dynamicName articles',
      query: '',
      icon: Icons.category,
      category: ContentCategory.other,
    ));
  }

  return suggestions.take(6).toList();
});
