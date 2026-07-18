import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router.dart';
import 'package:odroe/router_compiler.dart';
import 'package:odroe/start.dart';

// ignore: avoid_relative_lib_imports
import '../../example/router_app/lib/routes.dart' as fixture;
// ignore: avoid_relative_lib_imports
import '../../example/router_app/lib/routes.server.dart' as server_fixture;
// ignore: avoid_relative_lib_imports
import '../../example/router_app/lib/models.dart' as models;

final class _PostIdAdapter implements StartSerializationAdapter<models.PostId> {
  const _PostIdAdapter();

  @override
  String get tag => 'PostId';

  @override
  bool canEncode(Object value) => value is models.PostId;

  @override
  Object? encode(models.PostId value, StartSerializer serializer) =>
      value.value;

  @override
  models.PostId decode(Object? value, StartSerializer serializer) =>
      models.PostId(value! as int);
}

void main() {
  final project = Directory('example/router_app').absolute;

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
    expect(output.serverSource, contains("baseHref: '/'"));
    expect(output.serverSource, contains('hasFlutterPage: true'));
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

  test('generated function refs bind the server-only manifest', () async {
    final serializer = StartSerializer(
      adapters: const <StartSerializationAdapter<dynamic>>[_PostIdAdapter()],
    );
    final client = StartRpcClient(
      baseUri: Uri.parse('http://localhost'),
      transport: InMemoryStartTransport(
        server_fixture.createStartApplication(serializer: serializer).handle,
      ),
      serializer: serializer,
    );

    expect(
      await fixture.routes.posts.postId.readTitle.call(client, 7),
      'Post 7',
    );
    final views = await fixture.routes.posts.postId.watchViews.call(
      client,
      const NoServerInput(),
    );
    expect(await views.toList(), <int>[1, 2, 3]);
    expect(
      await fixture.routes.posts.postId.doubleValues.call(client, const <int>[
        2,
        4,
      ]),
      <int>[4, 8],
    );
    expect(
      await fixture.routes.posts.postId.normalizePost.call(
        client,
        const models.PostId(-9),
      ),
      const models.PostId(9),
    );
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
