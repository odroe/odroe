import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' hide PageRoute;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/server.dart';

typedef _Params = ({int postId});
typedef _Search = ({bool preview});
typedef _ParentParams = ({String teamId});

final class _Fixture {
  _Fixture(this.route, this.targets, this.label, this.uri);

  final RouteNode route;
  final Map<String, Destination> targets;
  final String label;
  final Uri uri;
}

_Fixture _fixture(String kind) {
  if (kind == 'nested' || kind == 'nested shell') {
    final parent = AppRoute<_ParentParams, NoSearch, NoData>(
      path: '/teams/:teamId',
      params: PathParams<_ParentParams>.codec(
        decode: (input) => (teamId: input.requiredString('teamId')),
        encode: (value, output) => output.string('teamId', value.teamId),
      ),
      terminal: false,
    );
    final definition = AppRoute<_Params, _Search, NoData>(
      params: PathParams<_Params>.codec(
        decode: (input) => (postId: input.requiredInt('postId')),
        encode: (value, output) => output.integer('postId', value.postId),
      ),
      search: SearchParams<_Search>.codec(
        keys: const <String>{'preview'},
        defaults: (preview: false),
        decode: (input) => (preview: input.boolean('preview') ?? false),
        encode: (value, output) =>
            output.boolean('preview', value.preview, omitIf: false),
      ),
    );
    final page = definition
        .page(
          build: (context) => Text(
            'POST ${context.params.postId} ${context.search.preview} '
            '${context.match(parent)!.params.teamId}',
          ),
        )
        .compiled(path: 'posts/:postId', terminal: true);
    final compiled = definition.compiled(path: 'posts/:postId', terminal: true);
    Destination target(TypedRoute<_Params, _Search, NoData> route) => parent
        .ref(params: (teamId: 'alpha/beta'))
        .then(route.ref(params: (postId: 42), search: (preview: true)))
        .destination;
    final RouteNode tree = kind == 'nested shell'
        ? parent
              .shell(build: (_, child) => child)
              .compiled(
                path: parent.path!,
                terminal: false,
                children: <RouteNode>[page],
              )
        : parent.withChildren(<RouteNode>[page]);
    return _Fixture(
      tree,
      <String, Destination>{
        'definition': target(compiled),
        'page': target(page),
        'server': target(compiled.server()),
        'original': Destination.forRoute(
          route: definition,
          uri: target(page).uri,
        ),
      },
      'POST 42 true alpha/beta',
      Uri.parse('/teams/alpha%2Fbeta/posts/42?preview=true'),
    );
  }

  final original = AppRoute<NoParams, NoSearch, NoData>(
    path: kind == 'compiled' ? null : '/about',
  );
  var definition = original;
  var page = original.page(build: (_) => const Text('ABOUT'));
  RouteNode registered = page;
  if (kind == 'compiled') {
    definition = original.compiled(path: '/about', terminal: true);
    page = page.compiled(path: '/about', terminal: true);
    registered = page;
  } else if (kind == 'withChildren') {
    registered = page.withChildren(<RouteNode>[
      AppRoute<NoParams, NoSearch, NoData>(
        path: 'child',
      ).page(build: (_) => const Text('CHILD')),
    ]);
  } else if (kind == 'shell') {
    registered = original
        .shell(build: (_, child) => child)
        .withPage(page)
        .compiled(path: '/about', terminal: true);
  }
  return _Fixture(
    registered,
    <String, Destination>{
      'definition': definition.to(),
      'page': page.to(),
      'server': definition.server().to(),
      if (kind == 'compiled')
        'original': Destination.forRoute(route: original, uri: page.to().uri),
      if (kind == 'shell')
        'shell': (registered as ShellRoute<NoParams, NoSearch, NoData>).to(),
    },
    'ABOUT',
    Uri.parse('/about'),
  );
}

PageRoute<NoParams, NoSearch, NoData> _page(String path, String label) =>
    AppRoute<NoParams, NoSearch, NoData>(
      path: path,
    ).page(build: (_) => Text(label));

Future<void> _mount(WidgetTester tester, AppRouter router) async {
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  expect(find.text('HOME'), findsOneWidget);
}

void _pop(AppRouter router, [String? result]) {
  final delegate = router.routerDelegate as PopNavigatorRouterDelegateMixin;
  delegate.navigatorKey!.currentState!.pop(result);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The browser consumer instruments only its temporary external-navigation
  // copy, recording calls through this Zone key without leaving the test page.
  final external = <({Uri uri, bool replace})>[];
  final reportedLocations = <Map<Object?, Object?>>[];
  T controlled<T>(T Function() action) => runZoned(
    action,
    zoneValues: <Object, Object>{
      #odroeRouteIdentityExternal: (Uri uri, bool replace) {
        external.add((uri: uri, replace: replace));
      },
    },
  );
  setUp(() {
    external.clear();
    reportedLocations.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, (call) async {
          if (call.method == 'routeInformationUpdated') {
            reportedLocations.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.navigation, null);
  });

  for (final kind in <String>[
    'page',
    'withChildren',
    'compiled',
    'nested',
    'shell',
    'nested shell',
  ]) {
    for (final wrapper in _fixture(kind).targets.keys) {
      for (final operation in <String>['go', 'push', 'replace']) {
        testWidgets('$kind $wrapper $operation uses registered identity', (
          tester,
        ) async {
          final fixture = _fixture(kind);
          final destination = fixture.targets[wrapper]!;
          expect(destination, fixture.targets['page']);
          expect(destination.uri, fixture.uri);
          final home = _page('/', 'HOME');
          final middle = _page('/middle', 'MIDDLE');
          final router = AppRouter(
            routes: <RouteNode>[home, middle, fixture.route],
            initialLocation: Uri.parse('/'),
          );
          await _mount(tester, router);

          Future<String?>? result;
          if (operation == 'replace') {
            result = router.push<String>(middle.to());
            await tester.pumpAndSettle();
            expect(find.text('MIDDLE'), findsOneWidget);
          }
          controlled(() {
            switch (operation) {
              case 'go':
                router.go(destination);
              case 'push':
                result = router.push<String>(destination);
              case 'replace':
                router.replace(destination);
            }
          });
          await tester.pumpAndSettle();
          expect(external, isEmpty);
          expect(tester.takeException(), isNull);
          expect(find.text(fixture.label), findsOneWidget);
          expect(router.location, fixture.uri);
          expect(router.routeInformationProvider!.value.uri, fixture.uri);
          expect(reportedLocations.last, <String, Object?>{
            'uri': fixture.uri.toString(),
            'state': null,
            'replace': operation == 'replace',
          });

          if (operation == 'go') {
            expect(find.text('HOME', skipOffstage: false), findsNothing);
          } else {
            expect(find.text('HOME', skipOffstage: false), findsOneWidget);
            if (operation == 'replace') {
              expect(await result, isNull);
              expect(find.text('MIDDLE', skipOffstage: false), findsNothing);
            }
            _pop(router, 'done');
            await tester.pumpAndSettle();
            if (operation == 'push') expect(await result, 'done');
            expect(find.text('HOME'), findsOneWidget);
            expect(router.location, Uri.parse('/'));
            expect(reportedLocations.last['uri'], '/');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  for (final kind in <String>[
    'unregistered definition',
    'unregistered server',
    'same pathname',
    'registered neutral definition',
    'registered server',
    'neutral descendant of page',
  ]) {
    for (final operation in <String>['go', 'push', 'replace']) {
      testWidgets('$kind $operation retains external fallback', (tester) async {
        if (kIsWeb) {
          expect(
            const bool.fromEnvironment('ODROE_TEST_CONTROLLED_EXTERNAL'),
            isTrue,
            reason:
                'Run test/support/router_navigation_consumer_smoke.py '
                'for controlled browser external navigation.',
          );
        }
        final home = _page('/', 'HOME');
        final local = _page('/about', 'ABOUT');
        final definition = AppRoute<NoParams, NoSearch, NoData>(
          path: kind == 'same pathname' ? '/about' : '/server',
        );
        final routes = <RouteNode>[home, local];
        final destination = kind.contains('server')
            ? definition.server().to()
            : definition.to();
        if (kind == 'registered neutral definition') routes.add(definition);
        if (kind == 'registered server') routes.add(definition.server());
        if (kind == 'neutral descendant of page') {
          routes.add(
            _page('/parent', 'PARENT').withChildren(<RouteNode>[definition]),
          );
        }
        if (kind == 'same pathname') {
          expect(destination.uri, local.to().uri);
          expect(destination, isNot(local.to()));
        }
        final router = AppRouter(
          routes: routes,
          initialLocation: Uri.parse('/'),
        );
        await _mount(tester, router);
        Future<String?>? result;
        void navigate() {
          switch (operation) {
            case 'go':
              router.go(destination);
            case 'push':
              result = router.push<String>(destination);
            case 'replace':
              router.replace(destination);
          }
        }

        if (kIsWeb) {
          controlled(navigate);
          expect(external, <({Uri uri, bool replace})>[
            (uri: destination.uri, replace: operation == 'replace'),
          ]);
          if (operation == 'push') expect(await result, isNull);
        } else {
          expect(
            navigate,
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Route ${destination.uri} has no Flutter page on this platform.',
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('HOME'), findsOneWidget);
        expect(router.location, Uri.parse('/'));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final operation in <String>['go', 'push', 'replace']) {
    testWidgets('unregistered page $operation remains local not found', (
      tester,
    ) async {
      final router = AppRouter(
        routes: <RouteNode>[_page('/', 'HOME')],
        initialLocation: Uri.parse('/'),
        notFound: (_) => const Text('NOT FOUND'),
      );
      await _mount(tester, router);
      final destination = _page('/missing', 'MISSING').to();
      controlled(() {
        switch (operation) {
          case 'go':
            router.go(destination);
          case 'push':
            unawaited(router.push<void>(destination));
          case 'replace':
            router.replace(destination);
        }
      });
      await tester.pumpAndSettle();
      expect(external, isEmpty);
      expect(find.text('NOT FOUND'), findsOneWidget);
      expect(router.location, destination.uri);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('router owns one snapshot of a single-use route iterable', (
    tester,
  ) async {
    final home = _page('/', 'HOME');
    final definition = AppRoute<NoParams, NoSearch, NoData>(path: '/about');
    final page = definition.page(build: (_) => const Text('ABOUT'));
    final source = <RouteNode>[home, page];
    var iterations = 0;
    final routes = _SingleUseRoutes(source, () => iterations++);
    final router = AppRouter(routes: routes, initialLocation: Uri.parse('/'));
    expect(iterations, 1);
    source
      ..clear()
      ..add(_page('/late', 'LATE'));
    await _mount(tester, router);
    controlled(() => router.go(definition.to()));
    await tester.pumpAndSettle();
    expect(external, isEmpty);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(router.location, Uri.parse('/about'));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _SingleUseRoutes extends IterableBase<RouteNode> {
  _SingleUseRoutes(this.source, this.onIterate);

  final List<RouteNode> source;
  final void Function() onIterate;
  bool _used = false;

  @override
  Iterator<RouteNode> get iterator {
    if (_used) throw StateError('Route iterable was consumed twice.');
    _used = true;
    onIterate();
    return source.iterator;
  }
}
