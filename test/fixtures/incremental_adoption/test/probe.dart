import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/query_flutter.dart';

// These imports also run after copying the fixture into an independent app.
// ignore: avoid_relative_lib_imports
import '../lib/greeting.dart';
// ignore: avoid_relative_lib_imports
import '../lib/main.dart';
// ignore: avoid_relative_lib_imports
import '../lib/main_query.dart' as query;
// ignore: avoid_relative_lib_imports
import '../lib/main_routed.dart' as routed;

void main() {
  testWidgets('Query preserves the existing counter across rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(query.queryApp());
    await tester.pumpAndSettle();
    expect(find.text('Hello from local data'), findsOneWidget);
    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('Existing count: 1'), findsOneWidget);
    final client = QueryClientProvider.of(
      tester.element(find.text('Hello from local data')),
    );
    client.setQueryData(query.greeting.key, (_) => 'Cached greeting');
    await tester.pumpWidget(query.queryApp());
    await tester.pumpAndSettle();
    expect(find.text('Existing count: 1'), findsOneWidget);
    expect(find.text('Cached greeting'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('manual routing keeps the same query cache', (tester) async {
    await tester.pumpWidget(routed.routedApp());
    await tester.pumpAndSettle();
    final client = QueryClientProvider.of(
      tester.element(find.text('Hello from local data')),
    );
    client.setQueryData(routed.greeting.key, (_) => 'Cached across routes');
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    expect(find.text('Back home'), findsOneWidget);
    await tester.tap(find.text('Back home'));
    await tester.pumpAndSettle();
    expect(find.text('Cached across routes'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the same page can read a real HTTP server without generation', (
    tester,
  ) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previous);
    final origin = Uri.parse(const String.fromEnvironment('ODROE_RPC_ORIGIN'));
    await tester.pumpWidget(RemoteApp(origin: origin));
    await tester.runAsync(() async {
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        if (find.text('Hello from the real server').evaluate().isNotEmpty) {
          return;
        }
      }
      fail('The local HTTP server did not provide the greeting.');
    });
    await tester.pumpAndSettle();
    expect(find.text('Hello from the real server'), findsOneWidget);
    await tester.tap(find.text('Increment'));
    await tester.pump();
    expect(find.text('Existing count: 1'), findsOneWidget);
    expect(readGreeting.id, 'greeting.read');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
