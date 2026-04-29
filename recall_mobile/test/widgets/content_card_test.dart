import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/models/content_item.dart';
import 'package:recall_mobile/providers/auth_provider.dart';
import 'package:recall_mobile/providers/content_provider.dart';
import 'package:recall_mobile/providers/spaces_provider.dart';
import 'package:recall_mobile/providers/time_based_content_provider.dart';
import 'package:recall_mobile/widgets/content_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _testItem = ContentItem(
  id: 'test-id',
  userId: 'user-id',
  title: 'Test Article Title',
  summary: 'Test summary',
  tags: [],
  sourceApp: SourceApp.other,
  category: ContentCategory.technology,
  createdAt: DateTime.now(),
  isDone: false,
  isFavorite: false,
);

/// Wrap widget with ProviderScope overrides that prevent network calls.
Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith(
        (ref) => AuthNotifier()..state = AuthState.unauthenticated(),
      ),
      contentProvider.overrideWith(
        (ref) => ContentNotifier(ref)..state = ContentState(items: const []),
      ),
      spacesProvider.overrideWith(
        (ref) => SpacesNotifier(ref)..state = SpacesState.initial(),
      ),
      justInContentProvider.overrideWith(
        (ref) => TimeBasedContentNotifier('just_in')..state = TimeBasedContentState(isLoading: false),
      ),
      todayContentProvider.overrideWith(
        (ref) => TimeBasedContentNotifier('today')..state = TimeBasedContentState(isLoading: false),
      ),
      yesterdayContentProvider.overrideWith(
        (ref) => TimeBasedContentNotifier('yesterday')..state = TimeBasedContentState(isLoading: false),
      ),
      olderContentProvider.overrideWith(
        (ref) => TimeBasedContentNotifier('older')..state = TimeBasedContentState(isLoading: false),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ContentCard', () {
    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(_wrap(
        ContentCard(item: _testItem, enableSwipeToDismiss: false),
      ));
      await tester.pump();
      expect(find.text('Test Article Title'), findsOneWidget);
    });

    testWidgets('shows no Image.network when thumbnailUrl is null', (tester) async {
      await tester.pumpWidget(_wrap(
        ContentCard(item: _testItem, enableSwipeToDismiss: false),
      ));
      await tester.pump();
      // No thumbnail URL means effectiveThumbnailUrl is null → no Image.network
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('onTap callback fires when card is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        ContentCard(
          item: _testItem,
          enableSwipeToDismiss: false,
          onTap: () => tapped = true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
