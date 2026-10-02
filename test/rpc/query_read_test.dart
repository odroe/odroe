import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:odroe/query_rpc.dart';
import 'package:test/test.dart';

import '../fixtures/query_rpc/account.dart';
import '../fixtures/query_rpc/definitions.dart';
import '../fixtures/query_rpc/posts.dart';

const scope = ['tenant', 'alice'];

void main() {
  test('raw responses are rejected before encoding or transport use', () async {
    final transport = CaptureTransport();
    final rpc = RpcClient(
      baseUri: Uri.parse('https://example.test'),
      transport: transport,
    );
    var encodes = 0;
    final raw = ServerFunctionRef<int, ServerResponse>(
      id: 'download',
      encodeInput: (value) {
        encodes++;
        return value;
      },
    );
    final ServerFunctionRef<int, Object?> widened = raw;
    final diagnostic = throwsA(
      isA<UnsupportedError>().having(
        (error) => error.message,
        'message',
        contains('Use RpcClient.call'),
      ),
    );
    expect(() => raw.read(rpc, 1, scope: scope), diagnostic);
    expect(() => raw.readAt(rpc, 1, scope: scope), diagnostic);
    expect(() => raw.reads(rpc, scope: scope), diagnostic);
    expect(() => widened.read(rpc, 1, scope: scope), diagnostic);
    expect(encodes, 0);
    expect(transport.uris, isEmpty);
    // Direct raw RPC retains its existing single-use response contract.
    final response = await raw(rpc, 1);
    expect(await response.body.expand((chunk) => chunk).toList(), isNotEmpty);
    expect(encodes, 1);
    expect(transport.uris, hasLength(1));
  });

  test(
    'native relative endpoints are not guessed from the working directory',
    () {
      final rpc = RpcClient(baseUri: Uri(), transport: CaptureTransport());
      const ref = ServerFunctionRef<int, int>(id: 'read');
      expect(
        () => ref.read(rpc, 1, scope: scope),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('explicit server baseUri'),
          ),
        ),
      );
      expect(() => ref.reads(rpc, scope: scope), throwsArgumentError);
    },
  );

  test(
    'null values remain cacheable; decoder-produced raw bodies are rejected and cancelled',
    () async {
      final rpc = RpcClient(
        baseUri: Uri.parse('https://example.test'),
        transport: CaptureTransport(),
      );
      final cache = QueryClient();
      addTearDown(cache.clear);
      const nullRef = ServerFunctionRef<int, Null>(id: 'nullable');
      expect(
        await cache.fetchQuery(nullRef.read(rpc, 1, scope: scope)),
        isNull,
      );
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final resource = ServerFunctionRef<int, Object?>(
        id: 'bad-decoder',
        decodeOutput: (_) => ServerResponse(body: body.stream),
      );
      final options = resource.read(
        rpc,
        1,
        scope: scope,
        policy: const QueryPolicy(retry: QueryRetry.never()),
      );
      await expectLater(
        cache.fetchQuery(options),
        throwsA(isA<UnsupportedError>()),
      );
      expect(cancelled, isTrue);
      expect(cache.getQueryState(options.key)!.hasData, isFalse);
      await body.close();
    },
  );

  test(
    'one codec/serializer snapshot binds list/map/adapter bytes to key',
    () async {
      final adapter = BoxAdapter();
      final transport = CaptureTransport();
      final rpc = RpcClient(
        baseUri: Uri.parse('https://example.test/base/'),
        functionPath: 'rpc',
        transport: transport,
        serializer: Serializer(adapters: [adapter]),
      );
      final ref =
          ServerFunctionRef<
            ({List<int> ids, Map<String, Object?> fields, Box box}),
            Object?
          >(
            id: 'echo',
            encodeInput: (i) => {
              'ids': i.ids,
              'fields': i.fields,
              'box': i.box,
            },
          );
      final ids = [1];
      final fields = <String, Object?>{
        'z': [2],
        'a': 3,
      };
      final box = Box(4);
      final mutableScope = [...scope];
      final options = ref.read(rpc, (
        ids: ids,
        fields: fields,
        box: box,
      ), scope: mutableScope);
      final same = ref.read(rpc, (
        ids: [1],
        fields: {
          'a': 3,
          'z': [2],
        },
        box: Box(4),
      ), scope: scope);
      expect(options.key, same.key);
      final encodes = adapter.encodes;
      ids.add(99);
      (fields['z'] as List).add(88);
      box.value = 77;
      mutableScope[1] = 'bob';
      final cache = QueryClient();
      addTearDown(cache.clear);
      await cache.fetchQuery(options);
      await cache.refetchQueries();
      expect(adapter.encodes, encodes);
      expect(transport.payloads[0], transport.payloads[1]);
      expect(jsonDecode(transport.payloads.first), options.key.parts.last);
      expect(jsonDecode(transport.payloads.first)['data'], {
        'ids': [1],
        'fields': {
          'a': 3,
          'z': [2],
        },
        'box': {r'$type': 'Box', r'$value': 4},
      });
      expect(options.key.parts[1], scope);
      expect(
        transport.uris.first.toString(),
        'https://example.test/base/rpc/echo',
      );
    },
  );

  test('GET and escaped maps preserve canonical encoded identity', () async {
    final transport = CaptureTransport();
    final rpc = RpcClient(
      baseUri: Uri.parse('https://example.test'),
      transport: transport,
    );
    const ref = ServerFunctionRef<Map<String, Object?>, Object?>(
      id: 'echo',
      method: HttpMethod.get,
    );
    final left = ref.read(rpc, {
      r'$type': 'business',
      r'$value': 1,
      'other': 2,
    }, scope: scope);
    final right = ref.read(rpc, {
      'other': 2,
      r'$value': 1,
      r'$type': 'business',
    }, scope: scope);
    expect(left.key, right.key);
    final cache = QueryClient();
    addTearDown(cache.clear);
    await cache.fetchQuery(left);
    expect(jsonDecode(transport.payloads.single), left.key.parts.last);
    expect(
      (rpc.serializer.decodeJson(transport.payloads.single) as Map)['data'],
      {r'$type': 'business', r'$value': 1, 'other': 2},
    );
  });

  test('key dimensions, exact filters and strict O conflicts', () {
    final transport = CaptureTransport();
    RpcClient rpc(String base, [String path = 'rpc']) => RpcClient(
      baseUri: Uri.parse(base),
      functionPath: path,
      transport: transport,
    );
    final a = rpc('https://example.test/a/');
    const ref = ServerFunctionRef<int, int>(id: 'count');
    final options = ref.read(a, 1, scope: scope);
    expect(
      options.key,
      ref.read(rpc('https://example.test/a/'), 1, scope: scope).key,
    );
    expect(
      options.key,
      isNot(ref.read(rpc('https://example.test/b/'), 1, scope: scope).key),
    );
    expect(
      options.key,
      isNot(
        ref.read(rpc('https://example.test/a/', '/other'), 1, scope: scope).key,
      ),
    );
    expect(options.key, isNot(ref.read(a, 1, scope: ['tenant', 'bob']).key));
    expect(options.key, isNot(ref.read(a, 1, scope: ['other', 'alice']).key));
    expect(options.key, isNot(ref.read(a, 2, scope: scope).key));
    expect(
      options.key,
      isNot(
        const ServerFunctionRef<int, int>(
          id: 'other',
        ).read(a, 1, scope: scope).key,
      ),
    );
    expect(
      options.key,
      isNot(
        const ServerFunctionRef<int, int>(
          id: 'count',
          method: HttpMethod.get,
        ).read(a, 1, scope: scope).key,
      ),
    );
    final cache = QueryClient();
    addTearDown(cache.clear);
    cache.query(options);
    cache.query(ref.read(a, 2, scope: scope));
    final pageKey = QueryKey<InfiniteData<int, int>>('rpc', [
      ...options.key.parts.take(4),
      'infinite',
      options.key.parts.last,
    ]);
    cache.query(
      QueryOptions(
        key: pageKey,
        query: (_) => InfiniteData(pages: [1], pageParams: [1]),
      ),
    );
    expect(cache.findAll(ref.reads(a, scope: scope)).length, 2);
    expect(cache.findAll(ref.readAt(a, 1, scope: scope)).length, 1);
    expect(cache.findAll(ref.readAt(a, 3, scope: scope)), isEmpty);
    // The cache rejects exact runtime type changes, including covariant num.
    expect(
      () => cache.query(
        const ServerFunctionRef<int, num>(id: 'count').read(a, 1, scope: scope),
      ),
      throwsStateError,
    );
    expect(
      () => cache.query(
        const ServerFunctionRef<int, Object?>(
          id: 'count',
        ).read(a, 1, scope: scope),
      ),
      throwsStateError,
    );
    expect(
      () => cache.query(
        QueryOptions<InfiniteData<int, int>>(
          key: QueryKey.fromJson(options.key.toJson()),
          query: (_) => InfiniteData(pages: [], pageParams: []),
        ),
      ),
      throwsStateError,
    );
    expect(() => ref.read(a, 1, scope: []), throwsArgumentError);
  });

  test(
    'negative baseline: frozen key does not freeze mutable payload',
    () async {
      final transport = CaptureTransport();
      final rpc = RpcClient(
        baseUri: Uri.parse('https://example.test'),
        transport: transport,
      );
      const ref = ServerFunctionRef<List<int>, Object?>(id: 'echo');
      final input = [1];
      final options = QueryOptions<Object?>(
        key: QueryKey('baseline', [
          rpc.serializer.encode({'data': input}),
        ]),
        query: (_) => ref(rpc, input),
      );
      input.add(2);
      final cache = QueryClient();
      addTearDown(cache.clear);
      await cache.fetchQuery(options);
      expect(options.key.parts.single, {
        'data': [1],
      });
      expect(jsonDecode(transport.payloads.single), {
        'data': [1, 2],
      });
    },
  );

  test(
    'refresh rejects switched owners and superseded same-owner results',
    () async {
      final transport = CaptureTransport();
      Account account(String id) => Account(
        tenant: 'tenant',
        id: id,
        baseUri: Uri.parse('https://example.test/'),
        transport: transport,
        token: '$id-v1',
      );
      final alice = account('alice');
      final bob = account('bob');
      var active = alice;
      final old = Completer<String>();
      final pending = refreshAccountToken(() => active, (_) => old.future);
      active = bob;
      old.complete('alice-stale');
      expect(await pending, isFalse);
      expect(bob.token, 'bob-v1');
      expect(alice.token, 'alice-v1');
      active = alice;
      final older = Completer<String>();
      final newer = Completer<String>();
      final first = refreshAccountToken(() => active, (_) => older.future);
      final second = refreshAccountToken(() => active, (_) => newer.future);
      newer.complete('alice-v3');
      expect(await second, isTrue);
      older.complete('alice-v2');
      expect(await first, isFalse);
      expect(alice.token, 'alice-v3');
    },
  );

  group('real HTTP', () {
    late PostsServer server;
    late WireClient wire;
    late HttpTransport transport;
    late QueryClient cache;
    setUp(() async {
      server = PostsServer();
      await server.start();
      wire = WireClient();
      transport = HttpTransport(client: wire);
      cache = QueryClient();
    });
    tearDown(() async {
      cache.clear();
      wire.close();
      await server.close();
    });
    Account account(String id, [String backend = 'a']) => Account(
      tenant: 'tenant',
      id: id,
      baseUri: server.origin.resolve('/$backend/'),
      transport: transport,
      token: '$id-v1',
    );

    for (final bridged in [false, true]) {
      test(
        'native pagination/save/return with small read bridge=$bridged',
        () async {
          final owner = account('alice');
          final api = bridged ? RpcReadPosts(owner) : ManualPosts(owner);
          final list = InfiniteQueryObserver(cache, api.list(2));
          final stop = list.subscribe((_) {});
          await eventually(() => list.current.query.hasData);
          await list.fetchNextPage();
          expect(list.current.query.data!.pages.length, 2);
          await cache.fetchQuery(api.detail(1));
          final save = cache.observeMutation(api.save());
          await save.mutate((id: 1, title: 'Updated'));
          expect(cache.getQueryState(api.detail(1).key)!.isInvalidated, isTrue);
          expect((await cache.fetchQuery(api.detail(1))).title, 'Updated');
          expect(
            list.current.query.data!.pages.first.items.first.title,
            'Updated',
          );
          final count = server.calls.length;
          stop();
          list.dispose();
          final returned = InfiniteQueryObserver(cache, api.list(2));
          final remove = returned.subscribe((_) {});
          expect(returned.current.query.data!.pages.length, 2);
          expect(server.calls.length, count);
          await expectLater(
            save.mutate((id: 1, title: '')),
            throwsA(isA<RemoteServerException>()),
          );
          expect(save.current.isError, isTrue);
          remove();
          returned.dispose();
          save.dispose();
        },
      );
    }

    test(
      'same-owner token refresh is used by existing options without changing keys',
      () async {
        final alice = account('alice');
        var active = alice;
        final options = RpcReadPosts(alice).detail(1);
        await cache.fetchQuery(options);
        expect(
          server.requests['a/alice/posts.get']!.headers.value('authorization'),
          'Bearer alice-v1',
        );
        expect(
          await refreshAccountToken(() => active, (_) async => 'alice-v2'),
          isTrue,
        );
        await cache.refetchQueries(
          getPost.reads(alice.rpc, scope: alice.scope),
        );
        expect(
          server.requests['a/alice/posts.get']!.headers.value('authorization'),
          'Bearer alice-v2',
        );
        expect(options.key, RpcReadPosts(alice).detail(1).key);
        expect(options.key.canonical, isNot(contains('alice-v')));
        active = account('bob');
        await cache.refetchQueries(
          getPost.reads(alice.rpc, scope: alice.scope),
        );
        expect(
          server.requests['a/alice/posts.get']!.headers.value('authorization'),
          'Bearer alice-v2',
        );
        expect(server.calls.where((c) => c.account == 'bob'), isEmpty);
      },
    );

    test(
      'same in-flight definition can retry with refreshed own-account credentials',
      () async {
        final alice = account('alice');
        var active = alice;
        server.failures.add('a/alice/posts.get');
        final gate = server.gates['a/alice/posts.get'] = Completer<void>();
        final options = getPost.read(
          alice.rpc,
          (id: 1),
          scope: alice.scope,
          policy: QueryPolicy(
            retry: QueryRetry.times(1),
            retryDelay: (_, _) => Duration.zero,
          ),
        );
        final observer = cache.observe(options);
        final stop = observer.subscribe((_) {});
        await eventually(() => server.calls.isNotEmpty);
        expect(
          server.requests['a/alice/posts.get']!.headers.value('authorization'),
          'Bearer alice-v1',
        );
        cache.onlineManager.isOnline = false;
        gate.complete();
        await eventually(() => observer.current.state.fetchFailureCount == 1);
        await refreshAccountToken(() => active, (_) async => 'alice-v2');
        active = account('bob');
        server.failures.clear();
        cache.onlineManager.isOnline = true;
        await eventually(() => observer.current.hasData);
        expect(server.calls.length, 2);
        expect(
          server.requests['a/alice/posts.get']!.headers.value('authorization'),
          'Bearer alice-v2',
        );
        expect(server.calls.every((c) => c.account == 'alice'), isTrue);
        stop();
        observer.dispose();
      },
    );

    test(
      'native mutation finishing after account switch invalidates its old owner only',
      () async {
        final owners = [
          account('alice'),
          account('bob'),
          account('alice', 'b'),
        ];
        final apis = owners.map(RpcReadPosts.new).toList();
        final details = apis.map((a) => cache.observe(a.detail(1))).toList();
        final lists = apis
            .map((a) => InfiniteQueryObserver(cache, a.list(2)))
            .toList();
        final stops = [
          for (final o in details) o.subscribe((_) {}),
          for (final o in lists) o.subscribe((_) {}),
        ];
        await eventually(
          () =>
              details.every((o) => o.current.hasData) &&
              lists.every((o) => o.current.query.hasData),
        );
        final gate = server.gates['a/alice/posts.save'] = Completer<void>();
        final save = cache.observeMutation(apis[0].save());
        final pending = save.mutate((id: 1, title: 'Alice saved'));
        await eventually(() => server.calls.any((c) => c.id == 'posts.save'));
        save.setOptions(apis[1].save());
        gate.complete();
        await pending;
        expect(details[0].current.data!.title, 'Alice saved');
        expect(
          lists[0].current.query.data!.pages.first.items.first.title,
          'Alice saved',
        );
        expect(details[1].current.data!.title, 'a-bob Post 1');
        expect(details[2].current.data!.title, 'b-alice Post 1');
        expect(server.calls.where((c) => c.account == 'bob').length, 2);
        expect(server.calls.where((c) => c.backend == 'b').length, 2);
        for (final s in stops) {
          s();
        }
        for (final o in details) {
          o.dispose();
        }
        for (final o in lists) {
          o.dispose();
        }
        save.dispose();
      },
    );

    test(
      'client abort reaches real HTTP and excludes late results; server signal is best effort',
      () async {
        final alice = account('alice');
        final options = RpcReadPosts(alice).detail(1);
        final gate = server.gates['a/alice/posts.get'] = Completer<void>();
        final pending = cache.fetchQuery(options);
        final failure = expectLater(
          pending,
          throwsA(isA<QueryCancelledException>()),
        );
        await eventually(() => server.calls.isNotEmpty);
        await cache.cancelQueries(
          getPost.readAt(alice.rpc, (id: 1), scope: alice.scope),
        );
        await failure;
        await eventually(() => wire.aborts == 1);
        gate.complete();
        await eventually(() => server.completed.contains('a/alice/posts.get'));
        expect(cache.getQueryState(options.key)!.hasData, isFalse);
        // Deliberately no assertion that IoServer must observe peer disconnect.
      },
    );
  });
}

Future<void> eventually(bool Function() ready) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!ready()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('condition did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

final class Box {
  Box(this.value);
  int value;
}

final class BoxAdapter implements SerializationAdapter<Box> {
  int encodes = 0;
  @override
  String get tag => 'Box';
  @override
  bool canEncode(Object value) => value is Box;
  @override
  Object? encode(Box value, Serializer serializer) {
    encodes++;
    return value.value;
  }

  @override
  Box decode(Object? value, Serializer serializer) => Box(value as int);
}

final class CaptureTransport implements RpcTransport {
  final payloads = <String>[];
  final uris = <Uri>[];
  @override
  Future<ServerResponse> send(ServerRequest request) async {
    uris.add(request.uri);
    payloads.add(
      request.method == HttpMethod.get
          ? request.uri.queryParameters['payload']!
          : utf8.decode(await request.readBytes()),
    );
    return ServerResponse.json({'version': 1, 'type': 'data', 'data': null});
  }
}

final class WireClient extends http.BaseClient {
  final http.Client inner = http.Client();
  int aborts = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await inner.send(request);
    } on http.RequestAbortedException {
      aborts++;
      rethrow;
    }
  }

  @override
  void close() => inner.close();
}
