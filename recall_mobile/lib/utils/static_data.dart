import '../models/user.dart';
import '../models/content_item.dart';

class StaticData {
  static final User currentUser = User(
    id: 'user-001',
    email: 'demo@rekallhq.com',
    name: 'Nitesh Jain',
    createdAt: DateTime.now().subtract(const Duration(days: 365)),
  );

  static List<ContentItem> getAllContent() {
    return [
      // 1 day ago
      ContentItem(
        id: 'content-001',
        userId: currentUser.id,
        url: 'https://techcrunch.com/ai-future',
        title: 'The Future of AI in 2024',
        summary: 'Exploring the latest developments in artificial intelligence and their impact on society.',
        tags: ['AI', 'Technology', 'Future'],
        sourceApp: SourceApp.news,
        category: ContentCategory.technology,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        readingTimeMinutes: 5,
      ),
      // 7 days ago
      ContentItem(
        id: 'content-002',
        userId: currentUser.id,
        url: 'https://medium.com/design-thinking',
        title: 'Design Thinking for Product Teams',
        summary: 'A comprehensive guide to applying design thinking principles in product development.',
        tags: ['Design', 'Product', 'UX'],
        sourceApp: SourceApp.medium,
        category: ContentCategory.design,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        readingTimeMinutes: 8,
      ),
      // 30 days ago
      ContentItem(
        id: 'content-003',
        userId: currentUser.id,
        url: 'https://www.youtube.com/watch?v=flutter',
        title: 'Flutter 3.0: What\'s New',
        summary: 'Overview of new features and improvements in Flutter 3.0.',
        tags: ['Flutter', 'Mobile', 'Development'],
        sourceApp: SourceApp.youtube,
        category: ContentCategory.technology,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        readingTimeMinutes: 15,
      ),
    ];
  }
}
