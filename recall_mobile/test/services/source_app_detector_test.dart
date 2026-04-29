import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/services/source_app_detector.dart';
import 'package:recall_mobile/models/content_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SourceAppDetector.detectSourceApp', () {
    test('YouTube URL returns youtube', () {
      final result = SourceAppDetector.detectSourceApp(
          'https://www.youtube.com/watch?v=abc123');
      expect(result.sourceApp, equals(SourceApp.youtube));
    });

    test('Reddit URL returns reddit', () {
      final result =
          SourceAppDetector.detectSourceApp('https://www.reddit.com/r/flutter');
      expect(result.sourceApp, equals(SourceApp.reddit));
    });

    test('Twitter URL returns twitter', () {
      final result = SourceAppDetector.detectSourceApp(
          'https://twitter.com/user/status/123');
      expect(result.sourceApp, equals(SourceApp.twitter));
    });

    test('GitHub URL returns github', () {
      final result = SourceAppDetector.detectSourceApp(
          'https://github.com/flutter/flutter');
      expect(result.sourceApp, equals(SourceApp.github));
    });

    test('Unknown URL returns other', () {
      final result = SourceAppDetector.detectSourceApp(
          'https://unknowndomain.io/article');
      expect(result.sourceApp, equals(SourceApp.other));
    });
  });
}
