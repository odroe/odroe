import 'dart:async';

import 'package:odroe/query_core.dart';
import 'package:test/test.dart';

void main() {
  group('QueryKey', () {
    test('is deterministic and supports prefix matching', () {
      final first = QueryKey('posts', <Object?>[
        <String, Object?>{'page': 2, 'status': 'draft'},
      ]);
      final reordered = QueryKey('posts', <Object?>[
        <String, Object?>{'status': 'draft', 'page': 2},
      ]);

      expect(first, reordered);
      expect(first.startsWith(QueryKey('posts')), isTrue);
      expect(first.startsWith(QueryKey('users')), isFalse);
      expect(QueryKey.fromJson(first.toJson()), first);
    });

    test('rejects unstable values', () {
      expect(
        () => QueryKey('bad', <Object?>[DateTime.now()]),
        throwsArgumentError,
      );
      expect(
        () => QueryKey('bad', <Object?>[
          <Object?, Object?>{1: 'not a string key'},
        ]),
        throwsArgumentError,
      );
    });
  });

  group('QueryClient', () {
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

    test('retries with the configured policy', () async {
      var calls = 0;
      final client = QueryClient();
      final value = await client.fetchQuery(
        QueryOptions<int>(
          key: QueryKey('retry'),
          policy: QueryPolicy(
            retry: QueryRetry.times(2),
            retryDelay: (_, _) => Duration.zero,
          ),
          query: (_) {
            calls++;
            if (calls < 3) throw StateError('temporary');
            return 7;
          },
        ),
      );

      expect(value, 7);
      expect(calls, 3);
    });

    test('pauses online queries until connectivity returns', () async {
      final online = QueryOnlineManager(online: false);
      final client = QueryClient(onlineManager: online);
      var calls = 0;
      final future = client.fetchQuery(
        QueryOptions<int>(key: QueryKey('online'), query: (_) => ++calls),
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
      expect(
        client.getQueryState<int>(QueryKey('online'))!.fetchStatus,
        QueryFetchStatus.paused,
      );

      online.isOnline = true;
      expect(await future, 1);
    });

    test(
      'cancels a consumed operation when its last observer leaves',
      () async {
        final client = QueryClient();
        final started = Completer<void>();
        final options = QueryOptions<int>(
          key: QueryKey('cancel'),
          query: (context) async {
            final cancellation = context.cancelToken;
            started.complete();
            await cancellation.whenCancelled;
            cancellation.throwIfCancelled();
            return 1;
          },
        );
        final observer = client.observe(options);
        final remove = observer.subscribe((_) {});
        await started.future;

        remove();
        await Future<void>.delayed(Duration.zero);

        final state = client.getQueryState<int>(QueryKey('cancel'))!;
        expect(state.status, QueryStatus.pending);
        expect(state.fetchStatus, QueryFetchStatus.idle);
        observer.dispose();
      },
    );

    test(
      'static data ignores invalidation while never-stale data does not',
      () async {
        final client = QueryClient();
        var staticCalls = 0;
        var neverCalls = 0;
        final staticOptions = QueryOptions<int>(
          key: QueryKey('static'),
          policy: const QueryPolicy(freshness: QueryFreshness.static()),
          query: (_) => ++staticCalls,
        );
        final neverOptions = QueryOptions<int>(
          key: QueryKey('never'),
          policy: const QueryPolicy(freshness: QueryFreshness.never()),
          query: (_) => ++neverCalls,
        );
        await client.fetchQuery(staticOptions);
        await client.fetchQuery(neverOptions);

        await client.invalidateQueries(QueryFilter(key: QueryKey('static')));
        await client.invalidateQueries(QueryFilter(key: QueryKey('never')));

        expect(staticCalls, 1);
        expect(neverCalls, 1);
        expect(client.query(staticOptions).isStale(), isFalse);
        expect(client.query(neverOptions).isStale(), isTrue);
      },
    );
  });
}
