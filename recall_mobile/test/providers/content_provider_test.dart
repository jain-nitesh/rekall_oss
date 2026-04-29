import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:recall_mobile/providers/content_provider.dart';
import 'package:recall_mobile/models/content_item.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ContentState factories', () {
    test('initial() has isLoading=true and empty items', () {
      final state = ContentState.initial();
      expect(state.isLoading, isTrue);
      expect(state.items, isEmpty);
      expect(state.errorMessage, isNull);
    });

    test('loaded() has isLoading=false and contains provided items', () {
      final item = _makeItem('1');
      final state = ContentState.loaded(
        items: [item],
        currentPage: 1,
        hasMore: false,
        totalItems: 1,
      );
      expect(state.isLoading, isFalse);
      expect(state.items, hasLength(1));
      expect(state.items.first.id, equals('1'));
      expect(state.errorMessage, isNull);
    });

    test('error() has isLoading=false and errorMessage set', () {
      final state = ContentState.error('network error');
      expect(state.isLoading, isFalse);
      expect(state.items, isEmpty);
      expect(state.errorMessage, equals('network error'));
    });
  });

  group('ContentState.copyWith', () {
    test('preserves existing fields when nothing overridden', () {
      final item = _makeItem('2');
      final original = ContentState(items: [item], isLoading: false, totalItems: 1);
      final copy = original.copyWith(isLoading: true);
      expect(copy.items, hasLength(1));
      expect(copy.isLoading, isTrue);
      expect(copy.totalItems, equals(1));
    });
  });

  group('contentProvider — initial state', () {
    test('initial state is loading', () {
      // ContentNotifier starts with ContentState.initial() which has isLoading=true.
      // We use a simple StateProvider override so no real notifier (and no ApiService
      // calls) are executed during this assertion.
      final container = ProviderContainer(
        overrides: [
          contentProvider.overrideWith((ref) => _FakeContentNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(contentProvider);
      expect(state.isLoading, isTrue);
    });
  });

  group('contentProvider — state transitions via FakeContentNotifier', () {
    test('after loadContent succeeds, state is loaded with items', () async {
      final container = ProviderContainer(
        overrides: [
          contentProvider.overrideWith((ref) => _FakeContentNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(contentProvider.notifier) as _FakeContentNotifier;
      await notifier.simulateLoad(items: [_makeItem('a'), _makeItem('b')]);

      final state = container.read(contentProvider);
      expect(state.isLoading, isFalse);
      expect(state.items, hasLength(2));
      expect(state.errorMessage, isNull);
    });

    test('after loadContent fails, state has errorMessage', () async {
      final container = ProviderContainer(
        overrides: [
          contentProvider.overrideWith((ref) => _FakeContentNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(contentProvider.notifier) as _FakeContentNotifier;
      await notifier.simulateError('Failed to load content: connection refused');

      final state = container.read(contentProvider);
      expect(state.isLoading, isFalse);
      expect(state.items, isEmpty);
      expect(state.errorMessage, contains('Failed to load content'));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ContentItem _makeItem(String id) => ContentItem(
      id: id,
      userId: 'u1',
      title: 'Title $id',
      summary: 'Summary',
      tags: const [],
      sourceApp: SourceApp.other,
      category: ContentCategory.other,
      createdAt: DateTime(2024),
    );

/// A fake notifier that starts in loading state and exposes helpers to
/// simulate success/failure without touching ApiService or auth.
class _FakeContentNotifier extends StateNotifier<ContentState>
    implements ContentNotifier {
  _FakeContentNotifier() : super(ContentState.initial());

  Future<void> simulateLoad({required List<ContentItem> items}) async {
    state = ContentState.loaded(
      items: items,
      currentPage: 1,
      hasMore: false,
      totalItems: items.length,
    );
  }

  Future<void> simulateError(String message) async {
    state = ContentState.error(message);
  }

  // Satisfy ContentNotifier interface — all no-ops in tests
  @override
  Ref get ref => throw UnimplementedError();
  @override
  Future<void> loadContent() async => simulateLoad(items: []);
  @override
  Future<void> loadMoreContent() async {}
  @override
  Future<void> addContent(ContentItem item) async {}
  @override
  void removeOptimisticItem(String itemId) {}
  @override
  void addContentLocally(ContentItem item) {}
  @override
  Future<void> addContentOptimistically(ContentItem item) async {}
  @override
  Future<void> markUrlAsUploaded(String url) async {}
  @override
  void replaceOptimisticItem(ContentItem backendItem, {String? optimisticId}) {}
  @override
  Future<void> deleteContent(String contentId) async {}
  @override
  Future<void> markAsDone(String contentId) async {}
  @override
  Future<void> undoMarkAsDone(String contentId) async {}
  @override
  Future<void> setReadStatusFilter(ReadStatusFilter filter) async {}
  @override
  Future<void> toggleFavorite(String contentId) async {}
  @override
  Future<void> updateNotes(String contentId, String notes) async {}
  @override
  ContentItem? getContentById(String id) => null;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> processPendingSharesImmediately() async {}
  @override
  Future<void> clearUploadedUrls() async {}
  @override
  Future<void> refreshContentItem(String contentId) async {}
}
