import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_mobile/widgets/hero_search_bar.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('HeroSearchBar', () {
    testWidgets('renders search icon when collapsed', (tester) async {
      await tester.pumpWidget(_wrap(const HeroSearchBar()));
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('renders placeholder text when collapsed', (tester) async {
      await tester.pumpWidget(_wrap(const HeroSearchBar()));
      expect(find.text('Search your saved content...'), findsOneWidget);
    });

    testWidgets('onTap callback fires when bar is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(
        HeroSearchBar(onTap: () => tapped = true),
      ));
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
      expect(tapped, isTrue);
    });
  });
}
