import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/models/content_item.dart';

void main() {
  final fullJson = {
    'id': 'test-id-123',
    'user_id': 'user-id-456',
    'content_type': 'url',
    'url': 'https://example.com/article',
    'title': 'Test Article',
    'summary': 'Test summary text',
    'tags': ['flutter', 'dart'],
    'source_app': 'github',
    'category': 'technology',
    'created_at': '2024-01-15T10:30:00.000Z',
    'is_done': false,
    'is_favorite': true,
    'thumbnail_url': 'https://example.com/thumb.jpg',
    'reading_time_minutes': 5,
  };

  final minimalJson = {
    'id': 'min-id',
    'user_id': 'min-user',
    'title': 'Minimal',
    'summary': 'summary',
    'tags': <String>[],
    'source_app': 'other',
    'category': 'other',
    'created_at': '2024-01-15T10:30:00.000Z',
    'is_done': false,
    'is_favorite': false,
  };

  group('ContentItem.fromJson', () {
    test('parses all fields correctly', () {
      final item = ContentItem.fromJson(fullJson);

      expect(item.id, 'test-id-123');
      expect(item.userId, 'user-id-456');
      expect(item.url, 'https://example.com/article');
      expect(item.title, 'Test Article');
      expect(item.tags, ['flutter', 'dart']);
      expect(item.sourceApp, SourceApp.github);
      expect(item.category, ContentCategory.technology);
      expect(item.isDone, false);
      expect(item.isFavorite, true);
      expect(item.thumbnailUrl, 'https://example.com/thumb.jpg');
      expect(item.readingTimeMinutes, 5);
    });

    test('optional fields are null when absent', () {
      final item = ContentItem.fromJson(minimalJson);

      expect(item.url, isNull);
      expect(item.thumbnailUrl, isNull);
      expect(item.heroImageUrl, isNull);
      expect(item.keyTakeaways, isNull);
      expect(item.readingTimeMinutes, isNull);
      expect(item.notes, isNull);
      expect(item.aiStatus, isNull);
      expect(item.mediaUrl, isNull);
      expect(item.ocrText, isNull);
    });

    test('round-trip preserves key fields', () {
      final original = ContentItem.fromJson(fullJson);
      final roundTripped = ContentItem.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.userId, original.userId);
      expect(roundTripped.url, original.url);
      expect(roundTripped.title, original.title);
      expect(roundTripped.tags, original.tags);
      expect(roundTripped.sourceApp, original.sourceApp);
      expect(roundTripped.category, original.category);
      expect(roundTripped.isDone, original.isDone);
      expect(roundTripped.isFavorite, original.isFavorite);
      expect(roundTripped.thumbnailUrl, original.thumbnailUrl);
      expect(roundTripped.readingTimeMinutes, original.readingTimeMinutes);
    });
  });
}
