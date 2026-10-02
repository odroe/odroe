import 'dart:async';

import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('deduplicates concurrent requests and respects freshness', () async {
    final gate = Completer<int>();
    var calls = 0;
    final options = QueryOptions<int>(
      key: QueryKey('answer'),
      policy: const QueryPolicy(
        freshness: QueryFreshness.staleAfter(Duration(minutes: 1)),
      ),
      query: (_) {
        calls++;
        return gate.future;
      },
    );
    final client = QueryClient();

    final first = client.fetchQuery(options);
    final second = client.fetchQuery(options);
    expect(identical(first, second), isTrue);
    expect(calls, 1);

    gate.complete(42);
    expect(await first, 42);
    expect(await client.fetchQuery(options), 42);
    expect(calls, 1);
  });

  test('rejects a different type without removing an active query', () {
    final client = QueryClient();
    final intKey = QueryKey<int>('shared');
    final query = client.query(QueryOptions<int>(key: intKey, query: (_) => 1));
    final observer = _EnabledObserver();
    query.addObserver(observer);

    final stringKey = QueryKey<String>('shared');
    final stringOptions = QueryOptions<String>(
      key: stringKey,
      query: (_) => 'wrong',
    );

    expect(() => client.query(stringOptions), throwsA(isA<StateError>()));
    expect(() => client.getQueryData(stringKey), throwsA(isA<StateError>()));
    expect(() => client.getQueryState(stringKey), throwsA(isA<StateError>()));
    expect(
      () => client.setQueryData(stringKey, (_) => 'wrong'),
      throwsA(isA<StateError>()),
    );
    expect(client.queryCache.getAny(intKey.canonical), same(query));
    expect(query.isActive, isTrue);

    query.removeObserver(observer);
  });

  test('uses exact key types across covariant int and num views', () {
    final client = QueryClient();
    final intKey = QueryKey<int>('count');
    client.query(
      QueryOptions<int>(
        key: intKey,
        query: (_) => 1,
        initialData: const QueryInitialData<int>(1),
      ),
    );

    final QueryKey<num> widenedKey = intKey;
    expect(
      () => client.query(QueryOptions<num>(key: widenedKey, query: (_) => 1.5)),
      throwsA(isA<StateError>()),
    );
    expect(
      () => client.getQueryData<num>(widenedKey),
      throwsA(isA<StateError>()),
    );
    expect(
      () => client.setQueryData<num>(widenedKey, (_) => 1.5),
      throwsA(isA<StateError>()),
    );
    expect(client.getQueryData(intKey), 1);
  });

  test('keeps the options type when a Future<void> consumes fetch', () async {
    final gate = Completer<int>();
    final client = QueryClient();
    final options = QueryOptions<int>(
      key: QueryKey<int>('discarded-result'),
      query: (_) => gate.future,
    );

    final Future<void> discarded = client.fetchQuery(options);
    expect(client.queryCache.getAny(options.key.canonical)!.dataType, int);

    gate.complete(7);
    await discarded;
    expect(client.getQueryData(options.key), 7);
  });

  test(
    'keeps the contextual key type when Future<void> consumes ensure',
    () async {
      final gate = Completer<int>();
      final client = QueryClient();
      final options = QueryOptions<int>(
        key: QueryKey('ensured-result'),
        query: (_) => gate.future,
      );

      expect(options.key.dataType, int);
      final Future<void> discarded = client.ensureQueryData(options);
      expect(client.queryCache.getAny(options.key.canonical)!.dataType, int);

      gate.complete(8);
      await discarded;
      expect(client.getQueryData(options.key), 8);
    },
  );
}

final class _EnabledObserver implements QueryObserverHandle {
  @override
  bool get enabled => true;

  @override
  bool get isStatic => false;

  @override
  void fetchForSignal() {}

  @override
  void onQueryUpdate() {}

  @override
  bool shouldRefetchOnFocus() => false;

  @override
  bool shouldRefetchOnReconnect() => false;
}
