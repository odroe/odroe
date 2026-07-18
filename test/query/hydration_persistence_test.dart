import 'dart:async';

import 'package:odroe/query_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'hydrate restores data without refetching and preserves newer data',
    () async {
      final source = QueryClient();
      final options = QueryOptions<Map<String, Object?>>(
        key: QueryKey('profile', <Object?>[7]),
        policy: const QueryPolicy(
          freshness: QueryFreshness.staleAfter(Duration(minutes: 5)),
        ),
        query: (_) => <String, Object?>{'name': 'Ada'},
      );
      await source.fetchQuery(options);
      final encoded = dehydrate(source).toJson();

      var calls = 0;
      final target = QueryClient();
      hydrate(target, DehydratedState.fromJson(encoded));
      final clientOptions = QueryOptions<Map<String, Object?>>(
        key: options.key,
        policy: options.policy,
        query: (_) {
          calls++;
          return <String, Object?>{'name': 'network'};
        },
      );

      expect(await target.fetchQuery(clientOptions), <String, Object?>{
        'name': 'Ada',
      });
      expect(calls, 0);

      target.setQueryData<Map<String, Object?>>(
        options.key,
        (_) => <String, Object?>{'name': 'newer'},
        updatedAt: DateTime.now().add(const Duration(minutes: 1)),
      );
      hydrate(target, DehydratedState.fromJson(encoded));
      expect(
        target.getQueryData<Map<String, Object?>>(options.key),
        <String, Object?>{'name': 'newer'},
      );
    },
  );

  test('persistence checks buster and coalesces cache writes', () async {
    final persister = _MemoryPersister();
    final source = QueryClient();
    final persistence = QueryPersistence(
      client: source,
      persister: persister,
      buster: 'v1',
      writeDelay: Duration.zero,
    );
    await persistence.restoreAndListen();
    final options = QueryOptions<int>(
      key: QueryKey('counter'),
      query: (_) => 1,
    );
    await source.fetchQuery(options);
    await persistence.flush();
    expect(persister.saved, 1);

    final target = QueryClient();
    final restore = QueryPersistence(
      client: target,
      persister: persister,
      buster: 'v1',
    );
    await restore.restoreAndListen();
    expect(target.getQueryData<int>(options.key), 1);

    final busted = QueryPersistence(
      client: QueryClient(),
      persister: persister,
      buster: 'v2',
    );
    await busted.restoreAndListen();
    expect(persister.removed, 1);

    persistence.dispose();
    restore.dispose();
    busted.dispose();
  });

  test(
    'persistence serializes asynchronous snapshots in creation order',
    () async {
      final persister = _OrderedPersister();
      final client = QueryClient();
      final persistence = QueryPersistence(
        client: client,
        persister: persister,
        writeDelay: const Duration(days: 1),
      );
      await persistence.restoreAndListen();
      final options = QueryOptions<int>(
        key: QueryKey('ordered'),
        query: (_) => 0,
      );
      await client.fetchQuery(options);
      client.setQueryData<int>(options.key, (_) => 1);
      final firstSave = persistence.save();
      client.setQueryData<int>(options.key, (_) => 2);
      final secondSave = persistence.save();

      await Future<void>.delayed(Duration.zero);
      expect(persister.values, <int>[1]);
      persister.first.complete();
      await firstSave;
      await secondSave;
      expect(persister.values, <int>[1, 2]);
      persistence.dispose();
    },
  );

  test('late server errors never replace client data', () {
    final key = QueryKey('late-error');
    final client = QueryClient();
    client.query(QueryOptions<int>(key: key, query: (_) => 1));
    client.setQueryData<int>(key, (_) => 7);
    final now = DateTime.now();

    hydrate(
      client,
      DehydratedState(
        queries: <DehydratedQuery>[
          DehydratedQuery(
            key: key,
            dehydratedAt: now,
            meta: const <String, Object?>{},
            state: <String, Object?>{
              'status': 'error',
              'hasData': false,
              'error': 'failed',
              'errorUpdatedAt': now.millisecondsSinceEpoch,
              'dataUpdateCount': 0,
              'errorUpdateCount': 1,
              'fetchFailureCount': 1,
              'isInvalidated': false,
            },
          ),
        ],
        mutations: const <DehydratedMutation>[],
      ),
    );

    expect(client.getQueryData<int>(key), 7);
    expect(client.getQueryState<int>(key)!.status, QueryStatus.success);
  });
}

final class _MemoryPersister implements QueryPersister {
  PersistedQueryClient? value;
  int saved = 0;
  int removed = 0;

  @override
  FutureOr<void> remove() {
    removed++;
    value = null;
  }

  @override
  FutureOr<PersistedQueryClient?> restore() => value;

  @override
  FutureOr<void> save(PersistedQueryClient client) {
    saved++;
    value = client;
  }
}

final class _OrderedPersister implements QueryPersister {
  final Completer<void> first = Completer<void>();
  final List<int> values = <int>[];

  @override
  FutureOr<void> remove() {}

  @override
  FutureOr<PersistedQueryClient?> restore() => null;

  @override
  Future<void> save(PersistedQueryClient client) async {
    final value = client.state.queries.single.state['data']! as int;
    values.add(value);
    if (values.length == 1) await first.future;
  }
}
