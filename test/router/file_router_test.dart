import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router.dart';
import 'package:odroe/src/router_compiler/compiler.dart';

// ignore: avoid_relative_lib_imports
import '../../example/app/lib/routes.dart' as fixture;

void main() {
  final project = Directory('example/app').absolute;

  test('checked-in Flutter app is exactly the compiler output', () {
    final compiler = FileRouteCompiler(projectRoot: project);
    final output = compiler.compile();

    expect(output.diagnostics, isEmpty);
    expect(output.routeCount, 10);
    expect(output.hasFlutter, isTrue);
    expect(
      output.staticRoutes,
      unorderedEquals(<String>[
        '/',
        '/about',
        '/posts',
        '/pricing',
        '/settings',
      ]),
    );
    expect(output.source, compiler.outputFile.readAsStringSync());
    expect(output.serverSource, compiler.serverOutputFile.readAsStringSync());
    expect(
      output.source,
      isNot(contains("import 'routes/posts/[postId]/server.dart'")),
    );
    expect(
      output.serverSource,
      contains("import 'routes/posts/[postId]/server.dart'"),
    );
    expect(output.source, contains("import 'package:odroe/route.dart';"));
    expect(output.source, contains("import 'package:odroe/rpc.dart';"));
    expect(output.serverSource, contains('OdroeServer createServer('));
    expect(output.serverSource, contains('hasFlutterPage: true'));
  });

  testWidgets('push crosses a real filesystem shell', (tester) async {
    final router = OdroeRouter(
      routes: fixture.routeTree,
      initialLocation: Uri.parse('/'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final result = router.push<Object?>(
      fixture.routes.posts.postId.to(params: (postId: 7)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Odroe Router'), findsOneWidget);
    expect(find.text('Post 7; preview=false; tags='), findsOneWidget);
    expect(find.byType(Navigator), findsNWidgets(2));

    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(router.location.path, '/');
  });
}
