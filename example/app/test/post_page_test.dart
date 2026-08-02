import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/database_sqlite.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/router_flutter.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server_io.dart';
import 'package:odroe_example/posts_database.dart';
import 'package:odroe_example/routes.dart';
import 'package:odroe_example/server_native.dart' as native_server;

void main() {
  test('native database rejects an empty path', () async {
    await expectLater(
      native_server.createNativeServer(databasePath: ''),
      throwsArgumentError,
    );
  });

  test('native database bootstrap is idempotent and preserves data', () async {
    final database = SqliteDatabase.openInMemory();
    addTearDown(database.close);

    await initializePostsDatabase(database);
    await database.execute(
      BoundSql.raw(
        "UPDATE posts SET title = 'Persisted post 42' WHERE id = 42",
        dialect: SqlDialect.sqlite,
      ),
    );
    await initializePostsDatabase(database);

    final post = await postQueries
        .selectTable(posts, where: posts.id.equals(42))
        .one(database);
    expect(post, (id: 42, title: 'Persisted post 42'));
  });

  testWidgets('generated RPC completes inside the Flutter event loop', (
    tester,
  ) async {
    final application = (await tester.runAsync(_startNativeApplication))!;
    final transport = _realHttpTransport();
    final client = RpcClient(baseUri: application.origin, transport: transport);
    try {
      final cancelled = Completer<void>();
      final value = await tester.runAsync(
        () => routes.posts.postId.readTitle(
          client,
          42,
          cancelled: cancelled.future,
        ),
      );

      expect(value, 'SQLite post 42');
    } finally {
      transport.close();
      await tester.runAsync(application.close);
    }
  });

  testWidgets('generated RPC preserves a typed database miss', (tester) async {
    final application = (await tester.runAsync(_startNativeApplication))!;
    final transport = _realHttpTransport();
    final client = RpcClient(baseUri: application.origin, transport: transport);

    try {
      final error = await tester.runAsync<Object?>(() async {
        try {
          await routes.posts.postId.readTitle(client, 404);
          return null;
        } on Object catch (error) {
          return error;
        }
      });
      expect(
        error,
        isA<NotFound>().having(
          (error) => error.message,
          'message',
          'Post not found.',
        ),
      );
    } finally {
      transport.close();
      await tester.runAsync(application.close);
    }
  });

  testWidgets('malformed stream EOF fails inside the Flutter event loop', (
    tester,
  ) async {
    final failure = await _streamFailure(
      tester,
      ServerResponse.bytes(const <int>[
        0xff,
      ], contentType: 'application/x-ndjson; charset=utf-8'),
    );

    expect(failure, isA<RpcProtocolException>());
  });

  testWidgets('stream body errors complete inside the Flutter event loop', (
    tester,
  ) async {
    final failure = await _streamFailure(
      tester,
      ServerResponse(
        headers: Headers.single(<String, String>{
          'content-type': 'application/x-ndjson; charset=utf-8',
        }),
        body: Stream<List<int>>.error(StateError('response failed')),
      ),
    );

    expect(failure, isA<StateError>());
  });

  testWidgets('post page loads through Query and its generated RPC ref', (
    tester,
  ) async {
    final application = (await tester.runAsync(_startNativeApplication))!;
    final transport = _realHttpTransport();
    final query = QueryClient(
      options: const QueryClientOptions(
        queries: QueryPolicy(
          gcTime: Duration(minutes: 1),
          retry: QueryRetry.never(),
        ),
      ),
    );
    try {
      final client = RpcClient(
        baseUri: application.origin,
        transport: transport,
      );
      await _pumpPostPageWithModule(
        tester,
        RpcModule(client),
        query: query,
        waitForRealAsync: true,
        expectedText: 'SQLite post 42; preview=true; tags=one,two',
      );

      expect(
        find.text('SQLite post 42; preview=true; tags=one,two'),
        findsOneWidget,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      query.clear();
      transport.close();
      await tester.runAsync(application.close);
    }
  });

  testWidgets('post page retries a failed RPC query', (tester) async {
    final transport = await _pumpPostPage(tester, failures: 1);

    expect(find.text('Unable to load post.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(transport.requests, hasLength(1));

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await _pumpUntil(tester, find.text('Post 42; preview=true; tags=one,two'));

    expect(find.text('Post 42; preview=true; tags=one,two'), findsOneWidget);
    expect(transport.requests, hasLength(2));
  });
}

final class _ExampleTransport implements RpcTransport {
  _ExampleTransport({int failures = 0}) : _failures = failures;

  final List<ServerRequest> requests = <ServerRequest>[];
  int _failures;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    requests.add(request);
    if (_failures > 0) {
      _failures--;
      throw StateError('Example RPC failure.');
    }
    final payload =
        jsonDecode(request.uri.queryParameters['payload']!)
            as Map<String, Object?>;
    return ServerResponse.json(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': 'Post ${payload['data']}',
    });
  }
}

final class _StaticResponseTransport implements RpcTransport {
  const _StaticResponseTransport(this.response);

  final ServerResponse response;

  @override
  Future<ServerResponse> send(ServerRequest request) async => response;
}

Future<Object?> _streamFailure(
  WidgetTester tester,
  ServerResponse response,
) async {
  final client = RpcClient(
    baseUri: Uri.parse('https://api.example.com'),
    transport: _StaticResponseTransport(response),
  );
  final cancelled = Completer<void>();
  final stream = await const ServerStreamFunctionRef<NoServerInput, Object?>(
    id: 'watch',
  )(client, const NoServerInput(), cancelled: cancelled.future);
  Object? failure;
  var completed = false;
  unawaited(
    stream.toList().then<void>(
      (_) => completed = true,
      onError: (Object error, StackTrace _) {
        failure = error;
        completed = true;
      },
    ),
  );

  await tester.pump();

  expect(completed, isTrue);
  return failure;
}

Future<_ExampleTransport> _pumpPostPage(
  WidgetTester tester, {
  int failures = 0,
}) async {
  final transport = _ExampleTransport(failures: failures);
  await _pumpPostPageWithModule(
    tester,
    RpcModule(
      RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: transport,
      ),
    ),
    expectedText: failures == 0
        ? 'Post 42; preview=true; tags=one,two'
        : 'Unable to load post.',
    diagnostics: () => 'requests=${transport.requests.length}',
  );
  return transport;
}

Future<void> _pumpPostPageWithModule(
  WidgetTester tester,
  RpcModule rpc, {
  required String expectedText,
  String Function()? diagnostics,
  QueryClient? query,
  bool waitForRealAsync = false,
}) async {
  final resolvedQuery =
      query ??
      QueryClient(
        options: const QueryClientOptions(
          queries: QueryPolicy(
            gcTime: Duration.zero,
            retry: QueryRetry.never(),
          ),
        ),
      );
  addTearDown(resolvedQuery.clear);

  await tester.pumpWidget(
    App(
      modules: <Module>[
        QueryModule(client: resolvedQuery),
        rpc,
        RouterModule(
          routes: routeTree,
          initialLocation: Uri.parse(
            '/posts/42?preview=true&tags=one&tags=two',
          ),
        ),
      ],
      builder: (app) => MaterialApp.router(routerConfig: app.read(routerKey)),
    ),
  );
  await tester.pump();
  if (waitForRealAsync) {
    for (var attempt = 0; attempt < 100; attempt++) {
      final state = resolvedQuery.getQueryState<String>(
        QueryKey('post-title', <Object?>[42]),
      );
      if (state != null &&
          state.status != QueryStatus.pending &&
          state.fetchStatus == QueryFetchStatus.idle) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }
  await _pumpUntil(
    tester,
    find.text(expectedText),
    reason: () =>
        '${diagnostics?.call() ?? ''}; '
        'state=${resolvedQuery.getQueryState<String>(QueryKey('post-title', <Object?>[42]))?.status}; '
        'fetch=${resolvedQuery.getQueryState<String>(QueryKey('post-title', <Object?>[42]))?.fetchStatus}; '
        'error=${resolvedQuery.getQueryState<String>(QueryKey('post-title', <Object?>[42]))?.error}',
  );
}

HttpTransport _realHttpTransport() => HttpOverrides.runWithHttpOverrides(
  () => HttpTransport(),
  _RealHttpOverrides(),
);

final class _RealHttpOverrides extends HttpOverrides {}

final class _NativeApplication {
  const _NativeApplication(this.server, this.httpServer, this.state);

  final Server server;
  final HttpServer httpServer;
  final Directory state;

  Uri get origin => Uri(
    scheme: 'http',
    host: httpServer.address.address,
    port: httpServer.port,
  );

  Future<void> close() async {
    try {
      await IoServer.close(httpServer);
    } finally {
      try {
        await server.close();
      } finally {
        if (state.existsSync()) await state.delete(recursive: true);
      }
    }
  }
}

Future<_NativeApplication> _startNativeApplication() async {
  final state = await Directory.systemTemp.createTemp('odroe-example-state-');
  Server? server;
  try {
    server = await native_server.createNativeServer(
      databasePath: '${state.path}/app.sqlite3',
    );
    final httpServer = await IoServer.bind(server.handler, port: 0);
    return _NativeApplication(server, httpServer, state);
  } on Object {
    await server?.close();
    if (state.existsSync()) await state.delete(recursive: true);
    rethrow;
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  String Function()? reason,
}) async {
  for (var frame = 0; frame < 100 && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(finder, findsOneWidget, reason: reason?.call());
}
