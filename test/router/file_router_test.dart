import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router.dart';
import 'package:odroe/router_compiler.dart';

// ignore: avoid_relative_lib_imports
import '../../example/router_app/lib/routes.dart' as fixture;

void main() {
  final project = Directory('example/router_app').absolute;

  test('checked-in Flutter app is exactly the compiler output', () {
    final compiler = FileRouteCompiler(projectRoot: project);
    final output = compiler.compile();

    expect(output.diagnostics, isEmpty);
    expect(output.routeCount, 9);
    expect(output.source, compiler.outputFile.readAsStringSync());
    expect(output.source, isNot(contains('server.dart')));
  });

  test('generated references preserve inherited params and typed search', () {
    final defaults = fixture.routes.posts.postId.to(params: (postId: 42));
    final populated = fixture.routes.posts.postId.to(
      params: (postId: 42),
      postsSearch: (sort: 'oldest'),
      search: (preview: true, tags: const <String>['flutter', 'dart']),
    );

    expect(defaults.uri.toString(), '/posts/42');
    expect(
      populated.uri.toString(),
      '/posts/42?sort=oldest&preview=true&tags=flutter&tags=dart',
    );
    final matches = RouteMatcher(fixture.routeTree).match(populated.uri)!;
    expect(matches.routes.length, 3);
    expect(matches.routes.last.identity, same(populated.route.identity));
  });

  test('catch-all params are typed as path segments', () {
    final destination = fixture.routes.docs.restSlug.to(
      params: (slug: const <String>['guides', 'router']),
    );

    expect(destination.uri.toString(), '/docs/guides/router');
    expect(RouteMatcher(fixture.routeTree).match(destination.uri), isNotNull);
  });

  test('route groups organize references without changing the URL', () {
    expect(fixture.routes.account.settings.to().uri.toString(), '/settings');
    expect(fixture.routes.marketing.pricing.to().uri.toString(), '/pricing');
  });

  testWidgets('shell.dart owns a real nested navigator', (tester) async {
    final router = OdroeRouter(
      routes: fixture.routeTree,
      initialLocation: Uri.parse('/posts/42?preview=true&tags=flutter'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    expect(find.text('Odroe Router'), findsOneWidget);
    expect(find.text('Post 42; preview=true; tags=flutter'), findsOneWidget);
    expect(find.byType(Navigator), findsNWidgets(2));

    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(router.location.toString(), '/posts?preview=true&tags=flutter');
    expect(find.text('Posts'), findsOneWidget);
    expect(find.text('Odroe Router'), findsOneWidget);
  });

  testWidgets(
    'push can cross a shared shell without duplicate navigator keys',
    (tester) async {
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

      expect(await router.routerDelegate.popRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(await result, isNull);
      expect(router.location.path, '/');
    },
  );
}
