import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router.dart';

void main() {
  testWidgets('uses server loader data for the first Flutter route', (
    tester,
  ) async {
    var loaderCalls = 0;
    final route = AppRoute<NoParams, NoSearch, String>(
      path: '/',
      load: (_) {
        loaderCalls++;
        return 'client';
      },
    ).page(build: (context) => Text(context.data));
    final router = OdroeRouter(
      routes: <RouteNode>[route],
      initialState: RouterInitialState(
        location: Uri.parse('/'),
        loads: const <RouteLoadResult>[RouteLoadResult.data('server')],
      ),
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('server'), findsOneWidget);
    expect(loaderCalls, 0);
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
      routes: <RouteNode>[home, slow, fast],
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
}
