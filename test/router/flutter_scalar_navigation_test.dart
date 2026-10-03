import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router_flutter.dart';

import '../fixtures/router_scalar/scalar_app.dart' as scalar;
import '../fixtures/router_scalar/explicit_app.dart' as explicit;
import '../support/router_history_stub.dart'
    if (dart.library.js_interop) '../support/router_history_web.dart';

void main() {
  disableBrowserHistory();
  TestWidgetsFlutterBinding.ensureInitialized();
  final reported = <Map<Object?, Object?>>[];
  setUp(() {
    reported.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          if (call.method == 'routeInformationUpdated') {
            reported.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null),
  );

  void business(String label, Widget Function(String location) app) {
    AppRouter router(WidgetTester tester) =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).routerConfig!
            as AppRouter;
    Future<void> tap(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(TextButton, label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      '$label: two static pages, filters, detail push/replace/pop and typed identity',
      (tester) async {
        await tester.pumpWidget(app('/'));
        await tester.pumpAndSettle();
        expect(find.text('Home'), findsOneWidget);
        await tap(tester, 'About');
        expect(find.text('A small publishing app.'), findsOneWidget);
        expect(router(tester).location.toString(), '/about');
        await tap(tester, 'Home');
        await tap(tester, 'Browse posts');
        expect(router(tester).location.toString(), '/posts');
        await tap(tester, 'Alice');
        expect(router(tester).location.toString(), '/posts?authorId=7');
        expect(find.text('Working with routes'), findsNothing);
        await tap(tester, 'Shipping the first post');
        expect(find.text('Post 1'), findsOneWidget);
        expect(router(tester).location.toString(), '/posts/1');
        await tap(tester, 'Next post');
        expect(find.text('Post 2'), findsOneWidget);
        expect(router(tester).location.toString(), '/posts/2');
        expect(reported.last, {
          'uri': '/posts/2',
          'state': null,
          'replace': true,
        });
        await tap(tester, 'Back');
        expect(router(tester).location.toString(), '/posts?authorId=7');
        expect(find.text('Author 7'), findsOneWidget);
        await tap(tester, 'Bob');
        expect(find.text('Working with routes'), findsOneWidget);
        expect(find.text('Shipping the first post'), findsNothing);
        await tap(tester, 'All authors');
        expect(router(tester).location.toString(), '/posts');
        expect(find.text('Shipping the first post'), findsOneWidget);
        expect(find.text('Working with routes'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    for (final scenario in [
      ('/posts/007', 'Post 7', '/posts/7'),
      ('/posts/-1', 'Post -1 does not exist.', '/posts/-1'),
      ('/posts/nope', 'Page not found', '/posts/nope'),
      (
        '/posts?authorId=bad&utm=campaign#top',
        'Invalid author filter; showing all posts.',
        '/posts?utm=campaign#top',
      ),
      (
        '/posts?authorId=7&authorId=8',
        'Invalid author filter; showing all posts.',
        '/posts',
      ),
    ]) {
      testWidgets('$label: deep link ${scenario.$1}', (tester) async {
        await tester.pumpWidget(app(scenario.$1));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(scenario.$2), findsOneWidget);
        expect(router(tester).location.toString(), scenario.$3);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  business(
    'explicit codecs',
    (location) => explicit.PostsDemo(initialLocation: location),
  );
  business(
    'scalar helpers',
    (location) => scalar.PostsDemo(initialLocation: location),
  );
}
