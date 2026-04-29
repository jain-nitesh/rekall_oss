import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/services/pending_shares_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper to seed SharedPreferences with a pending shares JSON array.
Future<void> _seedShares(List<Map<String, dynamic>> shares) async {
  SharedPreferences.setMockInitialValues({
    'pending_shares': jsonEncode(shares),
  });
}

void main() {
  final service = PendingSharesService();
  const userId = 'test-user';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ShareHandlerService — URL processing via PendingSharesService', () {
    test('valid URL shared → content save flow produces ContentItem with URL', () async {
      await _seedShares([
        {
          'timestamp': 1700000000000,
          'content': 'https://example.com/some-article',
        }
      ]);

      final results = await service.processPendingShares(userId);

      expect(results, hasLength(1));
      expect(results.first.url, equals('https://example.com/some-article'));
      expect(results.first.userId, equals(userId));
    });

    test('non-URL text shared → handled gracefully, falls back to raw text', () async {
      const plainText = 'Just some plain text without any URL';
      await _seedShares([
        {
          'timestamp': 1700000000001,
          'content': plainText,
        }
      ]);

      // Should not throw; falls back to using the raw text as the URL field.
      final results = await service.processPendingShares(userId);

      expect(results, hasLength(1));
      expect(results.first.url, equals(plainText));
    });

    test('duplicate URLs in pending shares → only one item returned', () async {
      const url = 'https://example.com/duplicate-article';
      await _seedShares([
        {'timestamp': 1700000000002, 'content': url},
        {'timestamp': 1700000000003, 'content': url},
      ]);

      final results = await service.processPendingShares(userId);

      expect(results, hasLength(1));
      expect(results.first.url, equals(url));
    });
  });
}
