import 'dart:async';

import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('hydrate restores data without replacing newer client data', () async {
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
    Query<Map<String, Object?>>? reentered;
    final replacementEvents = <QueryCacheEventType>[];
    final unsubscribe = target.queryCache.subscribe((event) {
      if (event.query.key.canonical != options.key.canonical) return;
      if (event.type
          case QueryCacheEventType.removed || QueryCacheEventType.added) {
        replacementEvents.add(event.type);
      }
      if (event.type == QueryCacheEventType.removed) {
        reentered = target.query(clientOptions);
      }
    });

    expect(await target.fetchQuery(clientOptions), <String, Object?>{
      'name': 'Ada',
    });
    expect(calls, 0);
    expect(reentered, same(target.query(clientOptions)));
    expect(replacementEvents, <QueryCacheEventType>[
      QueryCacheEventType.removed,
      QueryCacheEventType.added,
    ]);
    unsubscribe();

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
  });

  test('rejects incompatible hydrated data without removing it', () {
    final source = QueryClient();
    final sourceKey = QueryKey<String>('typed-hydration');
    source.query(
      QueryOptions<String>(
        key: sourceKey,
        query: (_) => 'server',
        initialData: const QueryInitialData<String>('server'),
      ),
    );

    final target = QueryClient();
    hydrate(target, dehydrate(source));
    final placeholder = target.queryCache.getAny(sourceKey.canonical)!;
    expect(placeholder.dataType, dynamic);
    expect(target.getQueryData(sourceKey), 'server');
    expect(target.getQueryState(sourceKey)!.requireData, 'server');

    final targetOptions = QueryOptions<int>(
      key: QueryKey<int>('typed-hydration'),
      query: (_) => 1,
    );
    expect(
      () => target.getQueryData(targetOptions.key),
      throwsA(isA<StateError>()),
    );
    expect(
      () => target.query(targetOptions),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('not int'),
        ),
      ),
    );
    expect(target.queryCache.getAny(sourceKey.canonical), same(placeholder));
    expect(placeholder.state.data, 'server');
  });

  test('does not announce an adopted entry replaced by a removed listener', () {
    final key = QueryKey<int>('replace-reentry');
    final source = QueryClient();
    source.query(
      QueryOptions<int>(
        key: key,
        query: (_) => 1,
        initialData: const QueryInitialData<int>(1),
      ),
    );

    final target = QueryClient();
    hydrate(target, dehydrate(source));
    final firstOptions = QueryOptions<int>(key: key, query: (_) => 1);
    final secondOptions = QueryOptions<int>(key: key, query: (_) => 2);
    final added = <Query<dynamic>>[];
    late Query<int> surviving;
    final unsubscribe = target.queryCache.subscribe((event) {
      if (event.query.key.canonical != key.canonical) return;
      if (event.type == QueryCacheEventType.added) added.add(event.query);
      if (event.type == QueryCacheEventType.removed &&
          event.query.dataType == dynamic) {
        target.queryCache.remove(target.queryCache.getAny(key.canonical)!);
        surviving = target.query(secondOptions);
      }
    });

    final obsolete = target.query(firstOptions);

    expect(target.queryCache.getAny(key.canonical), same(surviving));
    expect(obsolete, isNot(same(surviving)));
    expect(added, hasLength(1));
    expect(added.single, same(surviving));
    unsubscribe();
  });

  test('transfers a pending hydration future during typed adoption', () async {
    final gate = Completer<int>();
    final source = QueryClient();
    final sourceOptions = QueryOptions<int>(
      key: QueryKey<int>('pending-hydration'),
      query: (_) => gate.future,
    );
    final sourceFuture = source.fetchQuery(sourceOptions);

    final target = QueryClient();
    hydrate(target, dehydrate(source, includePending: true));
    var targetCalls = 0;
    final targetOptions = QueryOptions<int>(
      key: QueryKey<int>('pending-hydration'),
      policy: const QueryPolicy(retry: QueryRetry.never()),
      query: (_) {
        targetCalls++;
        return 0;
      },
    );
    final adopted = target.query(targetOptions);
    final transferred = adopted.promise!;

    expect(adopted.dataType, int);
    expect(target.queryCache.getAny(adopted.key.canonical), same(adopted));
    expect(adopted.isFetching, isTrue);
    expect(targetCalls, 0);

    gate.complete(42);
    expect(await sourceFuture, 42);
    expect(await transferred, 42);
    expect(adopted.state.requireData, 42);
    expect(targetCalls, 0);
  });

  test('fails a pending hydration future with incompatible data', () async {
    final gate = Completer<String>();
    final source = QueryClient();
    final sourceOptions = QueryOptions<String>(
      key: QueryKey<String>('pending-mismatch'),
      query: (_) => gate.future,
    );
    final sourceFuture = source.fetchQuery(sourceOptions);

    final target = QueryClient();
    hydrate(target, dehydrate(source, includePending: true));
    var targetCalls = 0;
    final adopted = target.query(
      QueryOptions<int>(
        key: QueryKey<int>('pending-mismatch'),
        policy: const QueryPolicy(retry: QueryRetry.never()),
        query: (_) {
          targetCalls++;
          return 0;
        },
      ),
    );
    final transferred = adopted.promise!;

    gate.complete('wrong');
    expect(await sourceFuture, 'wrong');
    await expectLater(
      transferred,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('not int'),
        ),
      ),
    );
    expect(adopted.state.status, QueryStatus.error);
    expect(adopted.state.error, isA<StateError>());
    expect(targetCalls, 0);
  });
}
