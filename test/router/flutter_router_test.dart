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
  testWidgets('publishes loader completion on the same Navigator page', (
    tester,
  ) async {
    final completion = Completer<String>();
    final route =
        AppRoute<NoParams, NoSearch, String>(
          path: '/slow',
          load: (_) => completion.future,
        ).page(
          pending: (_) => const Text('pending'),
          build: (context) => Text(context.data),
        );
    final router = OdroeRouter(
      routes: <AnyAppRoute>[route],
      initialLocation: Uri.parse('/slow'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    expect(find.text('pending'), findsOneWidget);

    completion.complete('ready');
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
    expect(find.text('pending'), findsNothing);
  });

  testWidgets('updates typed search on the same route page', (tester) async {
    final route = AppRoute<NoParams, ({int page}), NoData>(
      path: '/posts',
      search: SearchParams<({int page})>.codec(
        keys: const <String>{'page'},
        defaults: (page: 1),
        decode: (input) => (page: input.integer('page') ?? 1),
        encode: (value, output) =>
            output.integer('page', value.page, omitIf: 1),
      ),
    ).page(build: (context) => Text('page-${context.search.page}'));
    final router = OdroeRouter(
      routes: <AnyAppRoute>[route],
      initialLocation: Uri.parse('/posts?page=01'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('page-1'), findsOneWidget);
    expect(router.location.toString(), '/posts');

    router.go(route.to(search: (page: 2)));
    await tester.pumpAndSettle();
    expect(find.text('page-2'), findsOneWidget);
    expect(find.text('page-1'), findsNothing);
  });

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

  testWidgets('advanced pages receive typed state and navigator settings', (
    tester,
  ) async {
    final custom =
        AppRoute<NoParams, NoSearch, String>(
          path: '/custom',
          load: (_) => 'ready',
        ).page(
          page: (state, settings) => MaterialPage<Object?>(
            key: settings.key,
            name: settings.name,
            onPopInvoked: settings.onPopInvoked,
            child: Text(state.data),
          ),
        );
    final router = OdroeRouter(
      routes: <AnyAppRoute>[custom],
      initialLocation: Uri.parse('/custom'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('ready'), findsOneWidget);
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

  testWidgets('replace completes the replaced push and preserves its parent', (
    tester,
  ) async {
    final home = AppRoute<NoParams, NoSearch, NoData>(
      path: '/',
    ).page(build: (_) => const Text('home'));
    final first = AppRoute<NoParams, NoSearch, NoData>(
      path: '/first',
    ).page(build: (_) => const Text('first'));
    final second = AppRoute<NoParams, NoSearch, NoData>(
      path: '/second',
    ).page(build: (_) => const Text('second'));
    final router = OdroeRouter(
      routes: <AnyAppRoute>[home, first, second],
      initialLocation: Uri.parse('/'),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    final replaced = router.push<String>(first.to());
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    router.replace(second.to());
    await tester.pumpAndSettle();
    expect(await replaced, isNull);
    expect(find.text('second'), findsOneWidget);

    expect(await router.routerDelegate.popRoute(), isTrue);
    await tester.pumpAndSettle();
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
