import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:odroe/query_flutter.dart';
import 'package:odroe/query_rpc.dart';

import '../fixtures/query_rpc/account.dart';
import '../fixtures/query_rpc/consumer.dart';
import '../fixtures/query_rpc/definitions.dart';
import '../fixtures/query_rpc/posts.dart';

final class RealHttp extends HttpOverrides {}

void main() {
  late PostsServer server;
  late HttpTransport transport;
  late IOClient httpClient;
  late QueryClient client;
  Account connection(String id, [String backend = 'a']) => Account(
    tenant: 'tenant',
    id: id,
    token: '$id-v1',
    baseUri: server.origin.resolve('/$backend/'),
    transport: transport,
  );

  setUp(() async {
    client = QueryClient();
    httpClient = IOClient(
      HttpOverrides.runWithHttpOverrides(() => HttpClient(), RealHttp()),
    );
    transport = HttpTransport(client: httpClient);
    server = PostsServer();
  });
  tearDown(() async {
    client.clear();
    transport.close();
    httpClient.close();
    await server.close();
  });

  void business(String name, PostsQueries Function(Account) api) {
    testWidgets('$name real route, pagination, errors, save and switches', (
      tester,
    ) async {
      await tester.runAsync(server.start);
      final active = ValueNotifier(connection('alice'));
      var account = 'alice';
      var backend = 'a';
      final gate = server.gates['a/alice/posts.list'] = Completer<void>();
      server.failures.add('a/alice/posts.list');
      await tester.pumpWidget(
        PostsApp(
          client: client,
          account: active,
          api: api,
          switchAccount: () {
            account = account == 'alice' ? 'bob' : 'alice';
            active.value = connection(account, backend);
          },
          switchBackend: () {
            backend = backend == 'a' ? 'b' : 'a';
            active.value = connection(account, backend);
          },
        ),
      );
      expect(find.text('Loading posts…'), findsOneWidget);
      await tester.runAsync(() async {
        gate.complete();
      });
      await until(
        tester,
        () =>
            find.textContaining('Could not load posts:').evaluate().isNotEmpty,
      );
      expect(find.text('a-alice Post 1'), findsNothing);
      server.failures.clear();
      await tester.tap(find.text('Refresh posts'));
      await until(
        tester,
        () => find.text('a-alice Post 1').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('More posts'));
      await until(
        tester,
        () => find.text('a-alice Post 3').evaluate().isNotEmpty,
      );
      expect(server.calls.where((c) => c.id == 'posts.list').length, 3);
      await tester.tap(find.text('a-alice Post 1'));
      await until(
        tester,
        () => find.byType(EditableText).evaluate().isNotEmpty,
      );
      await tester.enterText(find.byType(EditableText), '');
      await tester.tap(find.text('Save'));
      await until(
        tester,
        () => find.textContaining('Save failed:').evaluate().isNotEmpty,
      );
      expect(find.byType(EditableText), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'Edited title');
      await tester.tap(find.text('Save'));
      await until(tester, () => find.text('Saved').evaluate().isNotEmpty);
      expect(find.text('Server title: Edited title'), findsOneWidget);
      await tester.tap(find.text('Back to posts'));
      await until(
        tester,
        () =>
            find.text('Edited title').evaluate().isNotEmpty &&
            find.text('a-alice Post 3').evaluate().isNotEmpty,
      );
      final count = server.calls.length;
      // Actual list is disposed by maintainState:false. Returning with fresh
      // options keeps both cached pages when the cache is still fresh.
      await tester.tap(find.text('Edited title'));
      await until(
        tester,
        () => find.byType(EditableText).evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Back to posts'));
      await until(
        tester,
        () => find.text('a-alice Post 3').evaluate().isNotEmpty,
      );
      expect(server.calls.length, count);
      server.failures.add('a/alice/posts.list');
      await tester.tap(find.text('Refresh posts'));
      await until(
        tester,
        () =>
            find.textContaining('Could not load posts:').evaluate().isNotEmpty,
      );
      expect(find.text('Edited title'), findsOneWidget);
      expect(find.text('Saved posts may be out of date'), findsOneWidget);
      server.failures.clear();
      await tester.tap(find.text('Switch account'));
      await until(
        tester,
        () => find.text('a-bob Post 1').evaluate().isNotEmpty,
      );
      expect(find.text('Edited title'), findsNothing);
      await tester.tap(find.text('Switch backend'));
      await until(
        tester,
        () => find.text('b-bob Post 1').evaluate().isNotEmpty,
      );
      expect(find.text('a-bob Post 1'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      active.dispose();
      client.clear();
      transport.close();
      httpClient.close();
    });
  }

  business('manual', ManualPosts.new);
  business('rpc read', RpcReadPosts.new);

  for (final endpoint in [false, true]) {
    testWidgets(
      'switch while HTTP is pending isolates late result: endpoint=$endpoint',
      (tester) async {
        await tester.runAsync(server.start);
        var active = connection('alice');
        late StateSetter rebuild;
        Post? data;
        final oldGate = server.gates['a/alice/posts.get'] = Completer<void>();
        final newKey = endpoint ? 'b/alice/posts.get' : 'a/bob/posts.get';
        final newGate = server.gates[newKey] = Completer<void>();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: StatefulBuilder(
              builder: (_, setState) {
                rebuild = setState;
                return QueryBuilder<Post>(
                  client: client,
                  options: getPost.read(
                    active.rpc,
                    (id: 1),
                    scope: active.scope,
                    policy: postPolicy,
                  ),
                  builder: (_, result) {
                    data = result.data;
                    return Text(data?.title ?? 'loading');
                  },
                );
              },
            ),
          ),
        );
        await until(tester, () => server.calls.length == 1);
        rebuild(() {
          active = endpoint ? connection('alice', 'b') : connection('bob');
        });
        await until(tester, () => server.calls.length == 2);
        expect(data, isNull);
        await tester.runAsync(() async {
          oldGate.complete();
        });
        await until(
          tester,
          () => server.completed.contains('a/alice/posts.get'),
        );
        expect(data, isNull);
        await tester.runAsync(() async {
          newGate.complete();
        });
        await until(tester, () => data != null);
        expect(data!.title, endpoint ? 'b-alice Post 1' : 'a-bob Post 1');
        await tester.pumpWidget(const SizedBox.shrink());
        client.clear();
        httpClient.close();
      },
    );
  }

  testWidgets(
    'fresh ordinary read options keep inflight and use the new decoder',
    (tester) async {
      await tester.runAsync(server.start);
      final owner = connection('alice');
      final gate = server.gates['a/alice/posts.get'] = Completer<void>();
      var version = 1;
      late StateSetter rebuild;
      Post? data;
      final lifecycle = <QueryCacheEventType>[];
      final stop = client.queryCache.subscribe((event) {
        if (event.type == QueryCacheEventType.observerAdded ||
            event.type == QueryCacheEventType.observerRemoved) {
          lifecycle.add(event.type);
        }
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              final captured = version;
              final ref = ServerFunctionRef<PostInput, Post>(
                id: getPost.id,
                encodeInput: getPost.encodeInput,
                decodeOutput: (wire) {
                  final post = getPost.decodeOutput!(wire);
                  return (id: post.id, title: '${post.title}:v$captured');
                },
              );
              return QueryBuilder<Post>(
                client: client,
                options: ref.read(
                  owner.rpc,
                  (id: 1),
                  scope: owner.scope,
                  policy: const QueryPolicy(
                    refetchOnMount: QueryRefetchPolicy.always,
                    retry: QueryRetry.never(),
                  ),
                ),
                builder: (_, result) {
                  data = result.data;
                  return Text(data?.title ?? 'loading');
                },
              );
            },
          ),
        ),
      );
      await until(tester, () => server.calls.length == 1);
      for (var i = 0; i < 5; i++) {
        rebuild(() => version = 2);
        await tester.pump();
      }
      expect(server.calls.length, 1);
      expect(lifecycle, [QueryCacheEventType.observerAdded]);
      await tester.runAsync(() async {
        gate.complete();
      });
      await until(tester, () => data != null);
      expect(data!.title, endsWith(':v1'));
      rebuild(() {});
      await tester.pump();
      expect(server.calls.length, 1);
      final refresh = client.refetchQueries();
      await until(tester, () => data!.title.endsWith(':v2'));
      await refresh;
      expect(server.calls.length, 2);
      expect(lifecycle, [QueryCacheEventType.observerAdded]);
      await tester.pumpWidget(const SizedBox.shrink());
      stop();
      client.clear();
      httpClient.close();
    },
  );
}

Future<void> until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 400; i++) {
    await tester.pump();
    if (done()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  throw TimeoutException('widget did not settle');
}
