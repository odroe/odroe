import 'dart:async';

import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('infinite options update paging controls and future requests', () async {
    final client = QueryClient();
    final calls = <_PageCall>[];
    InfiniteQueryOptions<int, int> options(
      int revision, {
      bool enabled = true,
    }) => InfiniteQueryOptions<int, int>(
      key: QueryKey('feed', [
        <String, Object?>{'account': 1},
      ]),
      initialPageParam: revision == 0 ? 0 : 5,
      policy: QueryPolicy(enabled: enabled),
      maxPages: revision == 0 ? null : 2,
      meta: {'revision': revision},
      query: (context) {
        final call = _PageCall(context, revision);
        calls.add(call);
        return call.gate.future;
      },
      getNextPageParam: (_, _, last, _) => revision == 0 ? null : last + 2,
      getPreviousPageParam: revision == 0
          ? null
          : (_, _, first, _) => first - 2,
    );

    final observer = InfiniteQueryObserver(client, options(0, enabled: false));
    addTearDown(client.clear);
    addTearDown(observer.dispose);
    final results = <InfiniteQueryResult<int, int>>[];
    final remove = observer.subscribe(results.add);
    observer.setOptions(options(1));
    expect(calls.single.context.pageParam, 5);
    expect(calls.single.context.query.meta, {'revision': 1});
    calls.single.gate.complete(50);
    await client.query(options(1).queryOptions).promise;
    expect(results.last.query.requireData.pages, [50]);

    observer.setOptions(options(0));
    expect(calls, hasLength(1));
    expect(results.last.hasNextPage, isFalse);
    expect(results.last.hasPreviousPage, isFalse);
    observer.setOptions(options(1));
    expect(results.last.hasNextPage, isTrue);
    expect(results.last.hasPreviousPage, isTrue);
    expect(calls, hasLength(1));

    final forward = observer.fetchNextPage();
    observer.setOptions(options(0));
    expect(calls.last.context.query.cancelToken.isCancelled, isFalse);
    expect(calls.last.context.pageParam, 7);
    expect(results.last.isFetchingNextPage, isTrue);
    calls.last.gate.complete(70);
    await forward;
    expect(results.last.query.requireData.pages, [50, 70]);

    observer.setOptions(options(2));
    final backward = observer.fetchPreviousPage();
    expect(calls.last.context.pageParam, 3);
    expect(calls.last.context.direction, InfiniteDirection.backward);
    expect(calls.last.revision, 2);
    observer.setOptions(options(0));
    calls.last.gate.complete(30);
    await backward;
    // The active request retains its captured maxPages even after an update.
    expect(results.last.query.requireData.pages, [30, 50]);
    expect(results.last.query.requireData.pageParams, [3, 5]);
    remove();
  });

  for (final paging in [false, true]) {
    test(
      'infinite observers share work until the last detaches: paging=$paging',
      () async {
        final client = QueryClient();
        final calls = <_PageCall>[];
        InfiniteQueryOptions<int, int> options(int revision) =>
            InfiniteQueryOptions(
              key: QueryKey('shared'),
              initialPageParam: 0,
              query: (context) {
                final call = _PageCall(context, revision);
                calls.add(call);
                return call.gate.future;
              },
              getNextPageParam: (_, _, last, _) => last + 1,
            );
        final first = InfiniteQueryObserver(client, options(0));
        final second = InfiniteQueryObserver(client, options(1));
        addTearDown(client.clear);
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        final removeFirst = first.subscribe((_) {});
        final removeSecond = second.subscribe((_) {});
        expect(calls, hasLength(1));
        Future<Object?>? page;
        if (paging) {
          calls.single.gate.complete(10);
          await client.query(options(1).queryOptions).promise;
          page = first.fetchNextPage();
        }
        first.setOptions(options(2));
        final active = calls.last;
        removeFirst();
        expect(active.context.query.cancelToken.isCancelled, isFalse);
        expect(second.current.query.isFetching, isTrue);
        expect(calls, hasLength(paging ? 2 : 1));
        removeSecond();
        expect(active.context.query.cancelToken.isCancelled, isTrue);
        await page;
        active.gate.complete(99);
        // Drain cancelled/late transport continuations; no clock-based waiting.
        await Future<void>.value();
        await Future<void>.value();
        expect(second.current.query.data?.pages, paging ? [10] : null);
        expect(second.current.query.isFetching, isFalse);
        expect(second.current.query.isError, isFalse);
      },
    );
  }

  test(
    'ordinary observers retain independent functions and signal policies',
    () async {
      final client = QueryClient();
      final gate = Completer<int>();
      late QueryCancelToken token;
      var calls = 0;
      final key = QueryKey<int>('shared');
      final first = client.observe(
        QueryOptions(
          key: key,
          query: (context) {
            calls++;
            token = context.cancelToken..markConsumed();
            return gate.future;
          },
        ),
      );
      final second = client.observe(
        QueryOptions(
          key: key,
          query: (_) {
            calls++;
            return 20;
          },
        ),
      );
      addTearDown(client.clear);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final removeFirst = first.subscribe((_) {});
      final removeSecond = second.subscribe((_) {});
      first.setOptions(
        QueryOptions(
          key: QueryKey('shared'),
          policy: const QueryPolicy(
            refetchOnFocus: QueryRefetchPolicy.never,
            refetchOnReconnect: QueryRefetchPolicy.never,
          ),
          query: (_) {
            calls++;
            return 30;
          },
        ),
      );
      expect(token.isCancelled, isFalse);
      expect(calls, 1);
      gate.complete(10);
      await client.queryCache.get<int>(key.canonical)!.promise;
      expect(first.shouldRefetchOnFocus(), isFalse);
      expect(first.shouldRefetchOnReconnect(), isFalse);
      expect(second.shouldRefetchOnFocus(), isTrue);
      expect(second.shouldRefetchOnReconnect(), isTrue);
      expect((await second.refetch()).data, 20);
      expect((await first.refetch()).data, 30);
      removeFirst();
      removeSecond();
    },
  );

  test(
    'unsubscribed infinite updates do not fetch and disposed updates fail',
    () async {
      final client = QueryClient();
      var calls = 0;
      InfiniteQueryOptions<int, int> options(String name) =>
          InfiniteQueryOptions(
            key: QueryKey(name),
            initialPageParam: 0,
            query: (_) => ++calls,
            getNextPageParam: (_, _, _, _) => null,
          );
      final observer = InfiniteQueryObserver(client, options('one'));
      addTearDown(client.clear);
      observer.setOptions(options('two'));
      expect(calls, 0);
      final remove = observer.subscribe((_) {});
      await client.query(observer.options.queryOptions).promise;
      expect(calls, 1);
      remove();
      observer.setOptions(options('three'));
      expect(calls, 1);
      observer.dispose();
      expect(() => observer.setOptions(options('four')), throwsStateError);
      expect(observer.options.key, QueryKey<InfiniteData<int, int>>('three'));
    },
  );
}

final class _PageCall {
  _PageCall(this.context, this.revision) {
    context.query.cancelToken.markConsumed();
  }

  final InfinitePageContext<int, int> context;
  final int revision;
  final gate = Completer<int>();
}
