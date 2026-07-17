import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router.dart';

typedef _IdParams = ({int id});

PathParams<_IdParams> get _idParams => PathParams<_IdParams>.codec(
  decode: (input) => (id: input.requiredInt('id')),
  encode: (value, output) => output.integer('id', value.id),
);

void main() {
  testWidgets('runs typed loaders and renders Navigator pages', (tester) async {
    final home = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
    ).page(build: (_) => const Text('home'));
    final post = AppRoute<_IdParams, NoSearch, String>(
      path: '/posts/[id]',
      params: _idParams,
      load: (context) => 'post-${context.params.id}',
    ).page(build: (context) => Text('${context.params.id}:${context.data}'));
    final router = OdroeRouter(
      routes: <AnyAppRoute>[home, post],
      initialLocation: Uri.parse('/'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    router.go(post.to(params: (id: 42)));
    await tester.pumpAndSettle();

    expect(find.text('42:post-42'), findsOneWidget);
    expect(router.location.path, '/posts/42');
  });

  testWidgets('only the latest navigation can publish loader data', (
    tester,
  ) async {
    final slowLoad = Completer<String>();
    final home = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
    ).page(build: (_) => const Text('home'));
    final slow =
        AppRoute<NoParams, NoSearch, String>(
          path: '/slow',
          load: (_) => slowLoad.future,
        ).page(
          pending: (_) => const Text('slow-pending'),
          build: (context) => Text(context.data),
        );
    final fast = AppRoute<NoParams, NoSearch, String>(
      path: '/fast',
      load: (_) => 'fast-data',
    ).page(build: (context) => Text(context.data));
    final router = OdroeRouter(
      routes: <AnyAppRoute>[home, slow, fast],
      initialLocation: Uri.parse('/'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go(slow.to());
    await tester.pumpAndSettle();
    expect(find.text('slow-pending'), findsOneWidget);

    router.go(fast.to());
    await tester.pumpAndSettle();
    expect(find.text('fast-data'), findsOneWidget);

    slowLoad.complete('stale-data');
    await tester.pumpAndSettle();
    expect(find.text('fast-data'), findsOneWidget);
    expect(find.text('stale-data'), findsNothing);
  });

  testWidgets('push completes with the popped result', (tester) async {
    final home = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
    ).page(build: (_) => const Text('home'));
    final details =
        AppRoute<_IdParams, NoSearch, NoData>(
          path: '/details/[id]',
          params: _idParams,
        ).page(
          build: (context) => TextButton(
            onPressed: () => Navigator.pop(context.buildContext, 'done'),
            child: Text('close-${context.params.id}'),
          ),
        );
    final router = OdroeRouter(
      routes: <AnyAppRoute>[home, details],
      initialLocation: Uri.parse('/'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final result = router.push<String>(details.to(params: (id: 7)));
    await tester.pumpAndSettle();
    expect(find.text('close-7'), findsOneWidget);

    await tester.tap(find.text('close-7'));
    await tester.pumpAndSettle();

    expect(await result, 'done');
    expect(find.text('home'), findsOneWidget);
    expect(router.location.path, '/');
  });

  testWidgets('popping a nested page restores its terminal parent', (
    tester,
  ) async {
    final child =
        AppRoute<_IdParams, NoSearch, NoData>(
          path: '[id]',
          params: _idParams,
        ).page(
          build: (context) => TextButton(
            onPressed: () => Navigator.pop(context.buildContext),
            child: Text('item-${context.params.id}'),
          ),
        );
    final items = AppRoute<NoParams, NoSearch, NoData>(path: '/items')
        .page(build: (_) => const Text('items'))
        .withChildren(<AnyAppRoute>[child]);
    final router = OdroeRouter(
      routes: <AnyAppRoute>[items],
      initialLocation: Uri.parse('/items/9'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('item-9'), findsOneWidget);

    await tester.tap(find.text('item-9'));
    await tester.pumpAndSettle();

    expect(router.location.path, '/items');
    expect(find.text('items'), findsOneWidget);
  });

  testWidgets('renders router-level not found UI', (tester) async {
    final router = OdroeRouter(
      routes: <AnyAppRoute>[
        AppRoute<NoParams, NoSearch, NoData>(
          path: '/',
        ).page(build: (_) => const Text('home')),
      ],
      initialLocation: Uri.parse('/missing'),
      notFound: (_) => const Text('not-found'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('not-found'), findsOneWidget);
  });
}
