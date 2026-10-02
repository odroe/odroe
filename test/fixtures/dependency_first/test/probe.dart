import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';

// This fixture is also copied into a consumer with a different package name.
// ignore: avoid_relative_lib_imports
import '../lib/main.dart';

void main() {
  testWidgets('direct dependency supports Query and manual routes', (
    tester,
  ) async {
    await tester.pumpWidget(createApp());
    await tester.pumpAndSettle();
    expect(find.text('Hello from Odroe'), findsOneWidget);
    final app = tester.element(find.text('Hello from Odroe')).appContext;
    final router = app.read(routerKey);
    final client = app.read(queryClientKey);
    client.setQueryData(greeting.key, (_) => 'Cached greeting');

    router.go(Destination.forRoute(route: about, uri: Uri.parse('/about')));
    await tester.pumpAndSettle();
    expect(find.text('About this app'), findsOneWidget);

    router.go(Destination.forRoute(route: home, uri: Uri.parse('/')));
    await tester.pumpAndSettle();
    expect(find.text('Cached greeting'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
