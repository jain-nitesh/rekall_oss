import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/providers/search_provider.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mock Firebase Core pigeon channel so Firebase.initializeApp() works.
    setupFirebaseCoreMocks();

    // Swallow Firebase Analytics method calls.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/firebase_analytics'),
      (call) async => null,
    );

    // Initialize a fake default Firebase app so FirebaseAnalytics.instance
    // doesn't throw when AnalyticsService is first accessed.
    await Firebase.initializeApp();
  });

  group('SearchNotifier — query state', () {
    test('initial query is empty string', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(searchProvider).query, equals(''));
    });

    test('setQuery("") leaves query empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).setQuery('');
      expect(container.read(searchProvider).query, equals(''));
    });

    test('setQuery("flutter") updates query to "flutter"', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).setQuery('flutter');
      expect(container.read(searchProvider).query, equals('flutter'));
    });

    test('clearQuery resets query to empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).setQuery('dart');
      container.read(searchProvider.notifier).clearQuery();
      expect(container.read(searchProvider).query, equals(''));
    });
  });

  group('SearchNotifier — category filters', () {
    test('toggleCategoryFilter adds category when not present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).toggleCategoryFilter('technology');
      expect(container.read(searchProvider).categoryFilters, contains('technology'));
    });

    test('toggleCategoryFilter removes category when already present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).toggleCategoryFilter('technology');
      container.read(searchProvider.notifier).toggleCategoryFilter('technology');
      expect(container.read(searchProvider).categoryFilters, isEmpty);
    });

    test('multiple categories can be active simultaneously', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).toggleCategoryFilter('technology');
      container.read(searchProvider.notifier).toggleCategoryFilter('design');
      final filters = container.read(searchProvider).categoryFilters;
      expect(filters, containsAll(['technology', 'design']));
    });
  });

  group('SearchNotifier — clearFilters', () {
    test('clearFilters resets all state to defaults', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).setQuery('flutter');
      container.read(searchProvider.notifier).toggleCategoryFilter('technology');
      container.read(searchProvider.notifier).toggleSourceAppFilter('Twitter');
      container.read(searchProvider.notifier).setDateRangeFilter(DateRange.lastWeek);

      container.read(searchProvider.notifier).clearFilters();

      final state = container.read(searchProvider);
      expect(state.query, equals(''));
      expect(state.categoryFilters, isEmpty);
      expect(state.sourceAppFilters, isEmpty);
      expect(state.dateRangeFilter, equals(DateRange.allTime));
    });
  });

  group('SearchNotifier — source app filters', () {
    test('toggleSourceAppFilter adds source app', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).toggleSourceAppFilter('Twitter');
      expect(container.read(searchProvider).sourceAppFilters, contains('Twitter'));
    });

    test('toggleSourceAppFilter removes source app when already present', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).toggleSourceAppFilter('Reddit');
      container.read(searchProvider.notifier).toggleSourceAppFilter('Reddit');
      expect(container.read(searchProvider).sourceAppFilters, isEmpty);
    });
  });

  group('SearchNotifier — date range filter', () {
    test('setDateRangeFilter updates dateRangeFilter', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).setDateRangeFilter(DateRange.lastMonth);
      expect(container.read(searchProvider).dateRangeFilter, equals(DateRange.lastMonth));
    });
  });

  group('SearchState.hasQuery / hasFilters', () {
    test('hasQuery is false for empty query', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(searchProvider).hasQuery, isFalse);
    });

    test('hasQuery is true for non-empty query', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).setQuery('test');
      expect(container.read(searchProvider).hasQuery, isTrue);
    });

    test('hasFilters is false when no filters set', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(searchProvider).hasFilters, isFalse);
    });

    test('hasFilters is true after category filter added', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(searchProvider.notifier).toggleCategoryFilter('science');
      expect(container.read(searchProvider).hasFilters, isTrue);
    });
  });
}
