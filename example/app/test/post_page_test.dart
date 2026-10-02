import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/database_sqlite.dart';
import 'package:odroe/odroe_flutter.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/rpc.dart';
import 'package:odroe/server_io.dart';
import 'package:odroe_example/posts.dart';
import 'package:odroe_example/posts_database.dart';
import 'package:odroe_example/routes.dart';
import 'package:odroe_example/server_native.dart' as native_server;

void main() {
  test(
    'native startup validates public origin before creating SQLite state',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'odroe-origin-invalid-',
      );
      addTearDown(() => root.delete(recursive: true));
      final state = Directory('${root.path}/state');
      await expectLater(
        native_server.createNativeServer(
          databasePath: '${state.path}/app.sqlite3',
          publicOrigin: Uri.parse('https://public.example/not-an-origin'),
        ),
        throwsArgumentError,
      );
      expect(state.existsSync(), isFalse);
    },
  );

  test(
    'native factory passes the fixed public origin to the generated server',
    () async {
      final root = await Directory.systemTemp.createTemp('odroe-origin-valid-');
      addTearDown(() => root.delete(recursive: true));
      final server = await native_server.createNativeServer(
        databasePath: '${root.path}/app.sqlite3',
        publicOrigin: Uri.parse('https://public.example:8443/'),
      );
      addTearDown(server.close);
      expect(server.publicOrigin, Uri.parse('https://public.example:8443'));
    },
  );

  test('native database rejects an empty path', () async {
    await expectLater(
      native_server.createNativeServer(databasePath: ''),
      throwsArgumentError,
    );
  });

  test('native database rejects an empty migration path', () async {
    await expectLater(
      native_server.createNativeServer(
        databasePath: '.odroe/test.sqlite3',
        migrationsPath: '',
      ),
      throwsArgumentError,
    );
  });

  test('native database preserves created posts across restart', () async {
    final state = await Directory.systemTemp.createTemp('odroe-posts-test-');
    final path = '${state.path}/app.sqlite3';
    final migrations = readSqliteMigrations(
      Directory('migrations').absolute.path,
    );
    SqliteDatabase? database;
    try {
      database = SqliteDatabase.open(path);
      await database.applyMigrations(migrations);
      final created = await postQueries
          .insert(posts, <SqlAssignment>[posts.title.set('Persisted post')])
          .returning(posts.projection)
          .one(database);
      await database.close();
      database = null;

      database = SqliteDatabase.open(path);
      await database.applyMigrations(migrations);
      final persisted = await postQueries
          .selectTable(
            posts,
            where: posts.id.isIn(<int>[42, created.id]),
            orderBy: <SqlOrder>[posts.id.ascending],
          )
          .all(database);
      expect(persisted, <Post>[(id: 42, title: 'Odroe post 42'), created]);
    } finally {
      await database?.close();
      if (state.existsSync()) await state.delete(recursive: true);
    }
  });

  test(
    'shared migrations adopt the previous native starter without data loss',
    () async {
      final state = await Directory.systemTemp.createTemp(
        'odroe-legacy-posts-test-',
      );
      final path = '${state.path}/app.sqlite3';
      SqliteDatabase? database;
      try {
        database = SqliteDatabase.open(path);
        await database.execute(
          BoundSql.raw('''
CREATE TABLE posts (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL
) STRICT
''', dialect: SqlDialect.sqlite),
        );
        await database.execute(
          BoundSql.raw(
            "INSERT INTO posts (id, title) VALUES (42, 'SQLite post 42')",
            dialect: SqlDialect.sqlite,
          ),
        );
        await database.execute(
          BoundSql.raw(
            "INSERT INTO posts (id, title) VALUES (43, 'Existing post')",
            dialect: SqlDialect.sqlite,
          ),
        );
        await database.close();
        database = SqliteDatabase.open(path);

        final migrations = readSqliteMigrations(
          Directory('migrations').absolute.path,
        );
        expect(await database.applyMigrations(migrations), 2);
        expect(await database.applyMigrations(migrations), 0);
        expect(
          await postQueries
              .selectTable(posts, orderBy: <SqlOrder>[posts.id.ascending])
              .all(database),
          <Post>[
            (id: 42, title: 'Odroe post 42'),
            (id: 43, title: 'Existing post'),
          ],
        );
      } finally {
        await database?.close();
        if (state.existsSync()) await state.delete(recursive: true);
      }
    },
  );

  testWidgets('generated RPC completes inside the Flutter event loop', (
    tester,
  ) async {
    final application = (await tester.runAsync(_startNativeApplication))!;
    final transport = _realHttpTransport();
    final client = RpcClient(baseUri: application.origin, transport: transport);
    try {
      final cancelled = Completer<void>();
      final post = await tester.runAsync(
        () => routes.posts.postId.readPost(
          client,
          42,
          cancelled: cancelled.future,
        ),
      );

      expect(post, (id: 42, title: 'Odroe post 42'));
    } finally {
      transport.close();
      await tester.runAsync(application.close);
    }
  });

  testWidgets('generated RPC lists, creates, and reads typed posts', (
    tester,
  ) async {
    final application = (await tester.runAsync(
      () => _startNativeApplication(extraPosts: 3),
    ))!;
    final transport = _realHttpTransport();
    final client = RpcClient(baseUri: application.origin, transport: transport);
    try {
      final initial = (await tester.runAsync(
        () => routes.posts.listPosts(client, (
          cursor: null,
          ids: const <int>[],
          limit: 2,
          sort: PostSort.newest,
        )),
      ))!;
      expect(initial.items.map((post) => post.id), <int>[45, 44]);
      expect(initial.nextCursor, 44);

      final next = (await tester.runAsync(
        () => routes.posts.listPosts(client, (
          cursor: initial.nextCursor,
          ids: const <int>[],
          limit: 2,
          sort: PostSort.newest,
        )),
      ))!;
      expect(next.items.map((post) => post.id), <int>[43, 42]);
      expect(next.nextCursor, isNull);

      final oldest = (await tester.runAsync(
        () => routes.posts.listPosts(client, (
          cursor: 42,
          ids: const <int>[],
          limit: 2,
          sort: PostSort.oldest,
        )),
      ))!;
      expect(oldest.items.map((post) => post.id), <int>[43, 44]);
      expect(oldest.nextCursor, 44);

      final oldestTail = (await tester.runAsync(
        () => routes.posts.listPosts(client, (
          cursor: oldest.nextCursor,
          ids: const <int>[],
          limit: 2,
          sort: PostSort.oldest,
        )),
      ))!;
      expect(oldestTail.items.map((post) => post.id), <int>[45]);
      expect(oldestTail.nextCursor, isNull);

      final selected = (await tester.runAsync(
        () => routes.posts.listPosts(client, (
          cursor: null,
          ids: <int>[42, 404],
          limit: 2,
          sort: PostSort.newest,
        )),
      ))!;
      expect(selected.items, <Post>[(id: 42, title: 'Odroe post 42')]);
      expect(selected.nextCursor, isNull);

      final oversizedError = await tester.runAsync<Object?>(() async {
        try {
          await routes.posts.listPosts(client, (
            cursor: null,
            ids: List<int>.generate(101, (index) => index),
            limit: 20,
            sort: PostSort.newest,
          ));
          return null;
        } on Object catch (error) {
          return error;
        }
      });
      expect(
        oversizedError,
        isA<RemoteServerException>()
            .having((error) => error.status, 'status', 400)
            .having(
              (error) => error.message,
              'message',
              'Post ID filter cannot contain more than 100 values.',
            ),
      );

      for (final invalidLimit in <int>[0, 51]) {
        final limitError = await tester.runAsync<Object?>(() async {
          try {
            await routes.posts.listPosts(client, (
              cursor: null,
              ids: const <int>[],
              limit: invalidLimit,
              sort: PostSort.newest,
            ));
            return null;
          } on Object catch (error) {
            return error;
          }
        });
        expect(
          limitError,
          isA<RemoteServerException>()
              .having((error) => error.status, 'status', 400)
              .having(
                (error) => error.message,
                'message',
                'Post page limit must be between 1 and 50.',
              ),
        );
      }

      const invalidSort = ServerFunctionRef<Map<String, Object?>, Object?>(
        id: 'posts.list',
        method: HttpMethod.get,
      );
      final sortError = await tester.runAsync<Object?>(() async {
        try {
          await invalidSort(client, <String, Object?>{
            'cursor': null,
            'ids': const <int>[],
            'limit': 20,
            'sort': 'popular',
          });
          return null;
        } on Object catch (error) {
          return error;
        }
      });
      expect(
        sortError,
        isA<RemoteServerException>()
            .having((error) => error.status, 'status', 400)
            .having(
              (error) => error.message,
              'message',
              'Invalid server function payload.',
            ),
      );

      final created = (await tester.runAsync(
        () => routes.posts.createPost(client, (title: '  Created post  ')),
      ))!;
      expect(created.title, 'Created post');
      expect(created.id, isNot(42));

      final post = (await tester.runAsync(
        () => routes.posts.postId.readPost(client, created.id),
      ))!;
      expect(post, created);

      final ordered = (await tester.runAsync(
        () => routes.posts.listPosts(client, (
          cursor: null,
          ids: const <int>[],
          limit: 20,
          sort: PostSort.newest,
        )),
      ))!;
      expect(ordered.items.first, created);
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
          await routes.posts.postId.readPost(client, 404);
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
        expectedText: 'Odroe post 42; preview=true; tags=one,two',
      );

      expect(
        find.text('Odroe post 42; preview=true; tags=one,two'),
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

  testWidgets('posts page creates a post and refreshes the list', (
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
      await tester.pumpWidget(
        App(
          modules: <Module>[
            QueryModule(client: query),
            RpcModule(
              RpcClient(baseUri: application.origin, transport: transport),
            ),
            RouterModule(
              routes: routeTree,
              initialLocation: Uri.parse('/posts'),
            ),
          ],
          builder: (app) =>
              MaterialApp.router(routerConfig: app.read(routerKey)),
        ),
      );
      await tester.pump();
      await _pumpUntilReal(tester, find.text('Odroe post 42'));

      await tester.enterText(find.byType(TextField), '  Created from UI  ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Create'));
      await tester.pump();
      await _pumpUntilReal(
        tester,
        find.text('Created from UI'),
        reason: () {
          final state = query.getQueryState<InfiniteData<PostPage, int?>>(
            QueryKey('posts.list', <Object?>['newest']),
          );
          return 'status=${state?.status}; fetch=${state?.fetchStatus}; '
              'data=${state?.data}; error=${state?.error}';
        },
      );

      expect(find.text('Created from UI'), findsOneWidget);
      expect(find.text('Odroe post 42'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      query.clear();
      transport.close();
      await tester.runAsync(application.close);
    }
  });

  testWidgets('posts page normalizes unknown URL sort across rebuilds', (
    tester,
  ) async {
    final transport = _ControlledPostsTransport();
    final query = QueryClient(
      options: const QueryClientOptions(
        queries: QueryPolicy(
          gcTime: Duration(minutes: 1),
          retry: QueryRetry.never(),
        ),
      ),
    );
    try {
      await tester.pumpWidget(
        App(
          modules: <Module>[
            QueryModule(client: query),
            RpcModule(
              RpcClient(
                baseUri: Uri.parse('https://api.example.com'),
                transport: transport,
              ),
            ),
            RouterModule(
              routes: routeTree,
              initialLocation: Uri.parse('/posts?sort=popular'),
            ),
          ],
          builder: (app) => _RebuildHost(routerConfig: app.read(routerKey)),
        ),
      );
      await tester.pump();
      await _pumpUntil(tester, find.text('Existing post'));
      expect(transport.listRequests, 1);
      expect(transport.sorts, <String>['newest']);

      tester.state<_RebuildHostState>(find.byType(_RebuildHost)).rebuild();
      await tester.pump();
      expect(transport.listRequests, 1);

      await tester.enterText(find.byType(TextField), 'Stable created');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pump();
      expect(transport.createRequests, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      tester.state<_RebuildHostState>(find.byType(_RebuildHost)).rebuild();
      await tester.pump();
      expect(transport.createRequests, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      transport.completeCreate();
      for (var frame = 0; frame < 100 && transport.listRequests < 2; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(transport.createRequests, 1);
      expect(transport.listRequests, 2);
      expect(transport.sorts, <String>['newest', 'newest']);
      expect(find.text('Stable created'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      query.clear();
    }
  });

  testWidgets('posts page appends and refreshes typed cursor pages', (
    tester,
  ) async {
    final transport = _PagedPostsTransport();
    final query = QueryClient(
      options: const QueryClientOptions(
        queries: QueryPolicy(
          gcTime: Duration(minutes: 1),
          retry: QueryRetry.never(),
        ),
      ),
    );
    try {
      await tester.pumpWidget(
        App(
          modules: <Module>[
            QueryModule(client: query),
            RpcModule(
              RpcClient(
                baseUri: Uri.parse('https://api.example.com'),
                transport: transport,
              ),
            ),
            RouterModule(
              routes: routeTree,
              initialLocation: Uri.parse('/posts'),
            ),
          ],
          builder: (app) =>
              MaterialApp.router(routerConfig: app.read(routerKey)),
        ),
      );
      await tester.pump();
      await _pumpUntil(tester, find.text('New post'));

      expect(find.text('Middle post'), findsOneWidget);
      expect(find.text('Old post'), findsNothing);
      expect(find.text('Load more'), findsOneWidget);
      expect(transport.cursors, <int?>[null]);

      await tester.tap(find.text('Load more'));
      await tester.pump();
      await _pumpUntil(tester, find.text('Old post'));

      expect(find.text('New post'), findsOneWidget);
      expect(find.text('Middle post'), findsOneWidget);
      expect(find.text('Old post'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(transport.cursors, <int?>[null, 2]);

      await tester.enterText(find.byType(TextField), 'Created paged post');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pump();
      await _pumpUntil(tester, find.text('Created paged post'));

      expect(find.text('New post'), findsOneWidget);
      expect(find.text('Middle post'), findsOneWidget);
      expect(find.text('Old post'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(transport.cursors, <int?>[null, 2, null, 3]);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      query.clear();
    }
  });

  testWidgets('posts page reports and retries a failed refresh', (
    tester,
  ) async {
    final application = (await tester.runAsync(_startNativeApplication))!;
    final http = _realHttpTransport();
    final transport = _FailingRefreshTransport(http);
    final query = QueryClient(
      options: const QueryClientOptions(
        queries: QueryPolicy(
          gcTime: Duration(minutes: 1),
          retry: QueryRetry.never(),
        ),
      ),
    );
    try {
      await tester.pumpWidget(
        App(
          modules: <Module>[
            QueryModule(client: query),
            RpcModule(
              RpcClient(baseUri: application.origin, transport: transport),
            ),
            RouterModule(
              routes: routeTree,
              initialLocation: Uri.parse('/posts'),
            ),
          ],
          builder: (app) =>
              MaterialApp.router(routerConfig: app.read(routerKey)),
        ),
      );
      await tester.pump();
      await _pumpUntilReal(tester, find.text('Odroe post 42'));

      await tester.enterText(find.byType(TextField), 'Created after retry');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pump();
      await _pumpUntilReal(tester, find.text('Posts may be out of date.'));

      expect(transport.failedRefresh, isTrue);
      expect(find.text('Odroe post 42'), findsOneWidget);
      expect(find.text('Created after retry'), findsNothing);

      await tester.tap(find.text('Retry refresh'));
      await tester.pump();
      await _pumpUntilReal(tester, find.text('Created after retry'));

      expect(find.text('Posts may be out of date.'), findsNothing);
      expect(find.text('Created after retry'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      query.clear();
      http.close();
      await tester.runAsync(application.close);
    }
  });

  testWidgets('post page retries a failed RPC query', (tester) async {
    final transport = await _pumpPostPage(tester, failing: true);

    expect(find.text('Unable to load post.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final failedRequests = transport.requests.length;
    expect(failedRequests, greaterThan(0));

    transport.allowSuccess();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await _pumpUntil(tester, find.text('Post 42; preview=true; tags=one,two'));

    expect(find.text('Post 42; preview=true; tags=one,two'), findsOneWidget);
    expect(transport.requests.length, greaterThan(failedRequests));
  });

  testWidgets('post page reports and retries a failed background refresh', (
    tester,
  ) async {
    final transport = _FailingDetailRefreshTransport(_ExampleTransport());
    final query = QueryClient(
      options: const QueryClientOptions(
        queries: QueryPolicy(
          gcTime: Duration(minutes: 1),
          retry: QueryRetry.never(),
        ),
      ),
    );
    final key = QueryKey<Post>('posts.detail', <Object?>[42]);
    await _pumpPostPageWithModule(
      tester,
      RpcModule(
        RpcClient(
          baseUri: Uri.parse('https://api.example.com'),
          transport: transport,
        ),
      ),
      query: query,
      expectedText: 'Post 42; preview=true; tags=one,two',
    );

    transport.failRefresh();
    await query.invalidateQueries(QueryFilter(key: key, exact: true));
    await tester.pump();
    await _pumpUntil(tester, find.text('Post may be out of date.'));

    expect(find.text('Post 42; preview=true; tags=one,two'), findsOneWidget);
    final failedRequests = transport.requests;
    expect(failedRequests, greaterThan(1));

    transport.allowSuccess();
    await tester.tap(find.text('Retry refresh'));
    await tester.pump();
    for (
      var frame = 0;
      frame < 100 &&
          find.text('Post may be out of date.').evaluate().isNotEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    expect(find.text('Post may be out of date.'), findsNothing);
    expect(find.text('Post 42; preview=true; tags=one,two'), findsOneWidget);
    expect(transport.requests, greaterThan(failedRequests));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    query.clear();
  });
}

final class _ExampleTransport implements RpcTransport {
  _ExampleTransport({bool failing = false}) : _failing = failing;

  final List<ServerRequest> requests = <ServerRequest>[];
  bool _failing;

  void allowSuccess() => _failing = false;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    requests.add(request);
    if (_failing) {
      throw StateError('Example RPC failure.');
    }
    final payload =
        jsonDecode(request.uri.queryParameters['payload']!)
            as Map<String, Object?>;
    return ServerResponse.json(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': <String, Object?>{
        'id': payload['data'],
        'title': 'Post ${payload['data']}',
      },
    });
  }
}

final class _StaticResponseTransport implements RpcTransport {
  const _StaticResponseTransport(this.response);

  final ServerResponse response;

  @override
  Future<ServerResponse> send(ServerRequest request) async => response;
}

final class _FailingRefreshTransport implements RpcTransport {
  _FailingRefreshTransport(this.inner);

  final RpcTransport inner;
  bool _created = false;
  bool failedRefresh = false;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    final path = request.uri.path;
    if (_created &&
        !failedRefresh &&
        request.method == HttpMethod.get &&
        path.endsWith('/posts.list')) {
      failedRefresh = true;
      throw StateError('Post list refresh failed.');
    }
    final response = await inner.send(request);
    if (request.method == HttpMethod.post && path.endsWith('/posts.create')) {
      _created = true;
    }
    return response;
  }
}

final class _FailingDetailRefreshTransport implements RpcTransport {
  _FailingDetailRefreshTransport(this.inner);

  final RpcTransport inner;
  var requests = 0;
  var _failing = false;

  void failRefresh() => _failing = true;
  void allowSuccess() => _failing = false;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    if (request.uri.path.endsWith('/posts.read')) {
      requests++;
      if (_failing) {
        throw StateError('Post detail refresh failed.');
      }
    }
    return inner.send(request);
  }
}

final class _PagedPostsTransport implements RpcTransport {
  final List<int?> cursors = <int?>[];
  var _created = false;

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    if (request.uri.path.endsWith('/posts.create')) {
      _created = true;
      return ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 4, 'title': 'Created paged post'},
      });
    }
    if (!request.uri.path.endsWith('/posts.list')) {
      throw StateError('Unexpected request: ${request.uri}');
    }
    final payload =
        jsonDecode(request.uri.queryParameters['payload']!)
            as Map<String, Object?>;
    final input = payload['data']! as Map<String, Object?>;
    expect(input['limit'], 20);
    expect(input['sort'], 'newest');
    final cursor = input['cursor'] as int?;
    cursors.add(cursor);

    final (items, nextCursor) = switch ((_created, cursor)) {
      (false, null) => (
        <Object?>[
          <String, Object?>{'id': 3, 'title': 'New post'},
          <String, Object?>{'id': 2, 'title': 'Middle post'},
        ],
        2,
      ),
      (false, 2) => (
        <Object?>[
          <String, Object?>{'id': 1, 'title': 'Old post'},
        ],
        null,
      ),
      (true, null) => (
        <Object?>[
          <String, Object?>{'id': 4, 'title': 'Created paged post'},
          <String, Object?>{'id': 3, 'title': 'New post'},
        ],
        3,
      ),
      (true, 3) => (
        <Object?>[
          <String, Object?>{'id': 2, 'title': 'Middle post'},
          <String, Object?>{'id': 1, 'title': 'Old post'},
        ],
        null,
      ),
      _ => throw StateError(
        'Unexpected cursor state: created=$_created; cursor=$cursor',
      ),
    };
    return ServerResponse.json(<String, Object?>{
      'version': 1,
      'type': 'data',
      'data': <String, Object?>{'items': items, 'nextCursor': nextCursor},
    });
  }
}

final class _ControlledPostsTransport implements RpcTransport {
  final _create = Completer<void>();
  final List<String> sorts = <String>[];
  var listRequests = 0;
  var createRequests = 0;
  var _created = false;

  void completeCreate() => _create.complete();

  @override
  Future<ServerResponse> send(ServerRequest request) async {
    if (request.uri.path.endsWith('/posts.list')) {
      listRequests++;
      final payload =
          jsonDecode(request.uri.queryParameters['payload']!)
              as Map<String, Object?>;
      final input = payload['data']! as Map<String, Object?>;
      sorts.add(input['sort']! as String);
      return ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{
          'items': <Object?>[
            <String, Object?>{'id': 1, 'title': 'Existing post'},
            if (_created) <String, Object?>{'id': 2, 'title': 'Stable created'},
          ],
          'nextCursor': null,
        },
      });
    }
    if (request.uri.path.endsWith('/posts.create')) {
      createRequests++;
      await _create.future;
      _created = true;
      return ServerResponse.json(<String, Object?>{
        'version': 1,
        'type': 'data',
        'data': <String, Object?>{'id': 2, 'title': 'Stable created'},
      });
    }
    throw StateError('Unexpected request: ${request.uri}');
  }
}

final class _RebuildHost extends StatefulWidget {
  const _RebuildHost({required this.routerConfig});

  final RouterConfig<Object> routerConfig;

  @override
  State<_RebuildHost> createState() => _RebuildHostState();
}

final class _RebuildHostState extends State<_RebuildHost> {
  var _dark = false;

  void rebuild() => setState(() => _dark = !_dark);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: widget.routerConfig,
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
  );
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
  bool failing = false,
}) async {
  final transport = _ExampleTransport(failing: failing);
  await _pumpPostPageWithModule(
    tester,
    RpcModule(
      RpcClient(
        baseUri: Uri.parse('https://api.example.com'),
        transport: transport,
      ),
    ),
    expectedText: failing
        ? 'Unable to load post.'
        : 'Post 42; preview=true; tags=one,two',
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
      final state = resolvedQuery.getQueryState<Post>(
        QueryKey('posts.detail', <Object?>[42]),
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
        'state=${resolvedQuery.getQueryState<Post>(QueryKey('posts.detail', <Object?>[42]))?.status}; '
        'fetch=${resolvedQuery.getQueryState<Post>(QueryKey('posts.detail', <Object?>[42]))?.fetchStatus}; '
        'error=${resolvedQuery.getQueryState<Post>(QueryKey('posts.detail', <Object?>[42]))?.error}',
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

Future<_NativeApplication> _startNativeApplication({int extraPosts = 0}) async {
  final state = await Directory.systemTemp.createTemp('odroe-example-state-');
  Server? server;
  try {
    final databasePath = '${state.path}/app.sqlite3';
    if (extraPosts > 0) {
      final database = SqliteDatabase.open(databasePath);
      try {
        await database.applyMigrations(
          readSqliteMigrations(Directory('migrations').absolute.path),
        );
        await postQueries
            .insertMany(posts, <List<SqlAssignment>>[
              for (var index = 0; index < extraPosts; index++)
                <SqlAssignment>[posts.title.set('Seeded post ${index + 1}')],
            ])
            .execute(database);
      } finally {
        await database.close();
      }
    }
    server = await native_server.createNativeServer(
      databasePath: databasePath,
      migrationsPath: Directory('migrations').absolute.path,
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

Future<void> _pumpUntilReal(
  WidgetTester tester,
  Finder finder, {
  String Function()? reason,
}) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget, reason: reason?.call());
}
