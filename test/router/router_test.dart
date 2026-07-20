import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router_flutter.dart';

void main() {
  testWidgets('uses server loader data for the first Flutter route', (
    tester,
  ) async {
    var loaderCalls = 0;
    final route = AppRoute<NoParams, NoSearch, String>(path: '/').page(
      load: (_) {
        loaderCalls++;
        return 'client';
      },
      build: (context) => Text(context.data),
    );
    final router = AppRouter(
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
    final slow = AppRoute<NoParams, NoSearch, String>(path: '/slow').page(
      load: (_) => slowLoad.future,
      pending: (_) => const Text('slow-pending'),
      build: (context) => Text(context.data),
    );
    final fast = AppRoute<NoParams, NoSearch, String>(
      path: '/fast',
    ).page(load: (_) => 'fast-data', build: (context) => Text(context.data));
    final router = AppRouter(
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
