import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/models/user.dart';

void main() {
  group('User.fromJson', () {
    test('parses all fields', () {
      final json = {
        'id': 'user-123',
        'email': 'test@example.com',
        'name': 'Test User',
        'avatar_url': 'https://example.com/avatar.jpg',
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final user = User.fromJson(json);

      expect(user.id, 'user-123');
      expect(user.email, 'test@example.com');
      expect(user.name, 'Test User');
      expect(user.avatarUrl, 'https://example.com/avatar.jpg');
      expect(user.createdAt, DateTime.parse('2024-01-15T10:30:00.000Z'));
    });

    test('avatarUrl is null when absent', () {
      final json = {
        'id': 'user-123',
        'email': 'test@example.com',
        'name': 'Test User',
        'created_at': '2024-01-15T10:30:00.000Z',
      };

      final user = User.fromJson(json);

      expect(user.avatarUrl, isNull);
    });
  });
}
