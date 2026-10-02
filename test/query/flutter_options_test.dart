import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/query_flutter.dart';

void main() {
  for (final view in _View.values) {
    testWidgets('$view disabling and re-enabling preserves active work', (
      tester,
    ) async {
      final host = _Host(view);
      await host.mount(tester);
      host.policy = const QueryPolicy(enabled: false);
      await host.rebuild(tester);
      expect(host.calls.single.token.isCancelled, isFalse);
      expect(host.fetching, isTrue);
      host.policy = const QueryPolicy();
      await host.rebuild(tester);
      expect(host.calls, hasLength(1));
      expect(host.calls.single.token.isCancelled, isFalse);
      host.calls.single.gate.complete(10);
      await _pump(tester);
      expect(host.data, [10]);
      await host.close(tester);
    });

    for (final policy in QueryRefetchPolicy.values) {
      testWidgets('$view same-key rebuild preserves requests ($policy)', (
        tester,
      ) async {
        final host = _Host(view, policy: QueryPolicy(refetchOnMount: policy));
        await host.mount(tester);
        final cached = host.client.queryCache.all.single;
        final events = <QueryCacheEventType>[];
        final stop = host.client.queryCache.subscribe((event) {
          if (event.type == QueryCacheEventType.observerAdded ||
              event.type == QueryCacheEventType.observerRemoved) {
            events.add(event.type);
          }
        });

        await host.rebuild(tester, freshOptions: false);
        await host.rebuild(tester);
        expect(host.calls, hasLength(1));
        expect(host.calls.single.token.isCancelled, isFalse);
        expect(host.client.queryCache.all.single, same(cached));
        host.calls.single.gate.complete(10);
        await _pump(tester);
        expect(host.data, [10]);

        await host.rebuild(tester);
        await host.rebuild(tester);
        expect(host.calls, hasLength(1));
        expect(host.data, [10]);
        expect(events, isEmpty);

        final refresh = view == _View.infinite
            ? host.next!()
            : host.client.refetchQueries();
        expect(host.calls, hasLength(2));
        expect(host.calls.last.version, host.version);
        host.calls.last.gate.complete(20);
        await _pump(tester);
        await refresh;
        expect(host.data, view == _View.infinite ? [10, 20] : [20]);
        stop();
        await host.close(tester);
      });
    }

    for (final transition in ['key', 'client', 'account']) {
      testWidgets('$view $transition change isolates old requests', (
        tester,
      ) async {
        final host = _Host(view);
        await host.mount(tester);
        final oldClient = host.client;
        final oldCall = host.calls.single;
        switch (transition) {
          case 'key':
            host.name = 'other';
          case 'client':
            host.client = QueryClient();
          case 'account':
            host.account++;
            host.client = QueryClient();
        }
        await host.rebuild(tester);
        expect(oldCall.token.isCancelled, isTrue);
        expect(host.calls, hasLength(2));
        expect(host.data, isNull);
        oldCall.gate.complete(99);
        await _pump(tester);
        expect(host.data, isNull);
        expect(host.fetching, isTrue);
        host.calls.last.gate.complete(20);
        await _pump(tester);
        expect(host.data, [20]);
        await host.close(tester);
        oldClient.clear();
      });
    }

    for (final policy in QueryRefetchPolicy.values) {
      testWidgets('$view enable and real remount honor $policy', (
        tester,
      ) async {
        final host = _Host(
          view,
          policy: QueryPolicy(enabled: false, refetchOnMount: policy),
        );
        await host.mount(tester);
        expect(host.calls, isEmpty);
        host.policy = QueryPolicy(refetchOnMount: policy);
        await host.rebuild(tester);
        expect(host.calls, hasLength(1));
        host.calls.last.gate.complete(10);
        await _pump(tester);

        host.policy = QueryPolicy(enabled: false, refetchOnMount: policy);
        await host.rebuild(tester);
        host.policy = QueryPolicy(refetchOnMount: policy);
        await host.rebuild(tester);
        final count = policy == QueryRefetchPolicy.never ? 1 : 2;
        expect(host.calls, hasLength(count));
        if (count == 2) {
          host.calls.last.gate.complete(20);
          await _pump(tester);
        }
        host.policy = QueryPolicy(
          refetchOnMount: policy,
          freshness: const QueryFreshness.never(),
        );
        await host.rebuild(tester);
        expect(host.calls, hasLength(count));
        await tester.pumpWidget(const SizedBox.shrink());
        await host.mount(tester);
        expect(
          host.calls,
          hasLength(count + (policy == QueryRefetchPolicy.always ? 1 : 0)),
        );
        if (policy == QueryRefetchPolicy.always) {
          host.calls.last.gate.complete(30);
          await _pump(tester);
        }
        await host.close(tester);
      });
    }
  }

  for (final policy in QueryRefetchPolicy.values) {
    testWidgets('infinite rebuild retains a page request ($policy)', (
      tester,
    ) async {
      final host = _Host(
        _View.infinite,
        policy: QueryPolicy(refetchOnMount: policy),
      );
      await host.mount(tester);
      host.calls.single.gate.complete(10);
      await _pump(tester);
      final page = host.next!();
      await _pump(tester);
      expect(host.paging, isTrue);
      await host.rebuild(tester);
      expect(host.calls, hasLength(2));
      expect(host.calls.last.token.isCancelled, isFalse);
      expect(host.paging, isTrue);
      host.calls.last.gate.complete(11);
      await _pump(tester);
      await page;
      expect(host.data, [10, 11]);
      final next = host.next!();
      expect(host.calls.last.page, 2);
      expect(host.calls.last.version, host.version);
      host.calls.last.gate.complete(12);
      await _pump(tester);
      await next;
      expect(host.data, [10, 11, 12]);
      await host.close(tester);
    });
  }
}

enum _View { query, selector, infinite }

final class _Call {
  _Call(this.version, this.token, this.page) {
    token.markConsumed();
  }

  final int version;
  final QueryCancelToken token;
  final int? page;
  final gate = Completer<int>();
}

final class _Host {
  _Host(this.view, {this.policy = const QueryPolicy()}) {
    addTearDown(client.clear);
  }

  final _View view;
  QueryClient client = QueryClient();
  QueryPolicy policy;
  String name = 'feed';
  int account = 0;
  int version = 0;
  final calls = <_Call>[];
  List<int>? data;
  bool fetching = false;
  bool paging = false;
  Future<Object?> Function()? next;
  late StateSetter _rebuild;
  late Object _options;

  Object _makeOptions() {
    final revision = version;
    Future<int> run(QueryCancelToken token, [int? page]) {
      final call = _Call(revision, token, page);
      calls.add(call);
      return call.gate.future;
    }

    // A fresh map/list/key each time, with the same typed canonical identity.
    final parts = <Object?>[
      <String, Object?>{
        'account': account,
        'filter': [1, 2],
      },
    ];
    return view == _View.infinite
        ? InfiniteQueryOptions<int, int>(
            key: QueryKey(name, parts),
            policy: policy,
            initialPageParam: 0,
            query: (context) =>
                run(context.query.cancelToken, context.pageParam),
            getNextPageParam: (_, _, last, _) => last + 1,
          )
        : QueryOptions<int>(
            key: QueryKey(name, parts),
            policy: policy,
            query: (context) => run(context.cancelToken),
          );
  }

  Widget _child() => switch (view) {
    _View.query => QueryBuilder<int>(
      options: _options as QueryOptions<int>,
      builder: (_, result) {
        _update(result);
        return const SizedBox();
      },
    ),
    _View.selector => QuerySelector<int, QueryResult<int>>(
      options: _options as QueryOptions<int>,
      select: (result) => result,
      builder: (_, result) {
        _update(result);
        return const SizedBox();
      },
    ),
    _View.infinite => InfiniteQueryBuilder<int, int>(
      options: _options as InfiniteQueryOptions<int, int>,
      builder: (_, result, fetchNext, _) {
        data = result.query.data?.pages;
        fetching = result.query.isFetching;
        paging = result.isFetchingNextPage;
        next = fetchNext;
        return const SizedBox();
      },
    ),
  };

  void _update(QueryResult<int> result) {
    data = result.hasData ? [result.requireData] : null;
    fetching = result.isFetching;
  }

  Future<void> mount(WidgetTester tester) async {
    _options = _makeOptions();
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (_, setState) {
          _rebuild = setState;
          return QueryClientProvider.value(client: client, child: _child());
        },
      ),
    );
    await _pump(tester);
  }

  Future<void> rebuild(WidgetTester tester, {bool freshOptions = true}) async {
    addTearDown(client.clear);
    _rebuild(() {
      if (freshOptions) {
        version++;
        _options = _makeOptions();
      }
    });
    await _pump(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    client.clear();
    await _pump(tester);
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
