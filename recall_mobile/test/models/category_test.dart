import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/models/category.dart';

void main() {
  group('Category.fromJson', () {
    test('parses id, name, color', () {
      final json = {
        'id': 'cat-1',
        'name': 'Technology',
        'color': '#FF5733',
        'usage_count': 42,
      };

      final category = Category.fromJson(json);

      expect(category.id, 'cat-1');
      expect(category.name, 'Technology');
      expect(category.color, '#FF5733');
      expect(category.usageCount, 42);
    });

    test('color is null when absent', () {
      final json = {
        'id': 'cat-2',
        'name': 'Other',
      };

      final category = Category.fromJson(json);

      expect(category.color, isNull);
      expect(category.usageCount, 0);
    });
  });
}
