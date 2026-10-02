import 'dart:async';

import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  for (final infinite in [false, true]) {
    for (final paging in infinite ? [false, true] : [false]) {
      for (final policy in QueryRefetchPolicy.values) {
        for (final obeyCancel in [false, true]) {
          test(
            'immediate remount replaces cancelled work: infinite=$infinite, '
            'paging=$paging, policy=$policy, obeyCancel=$obeyCancel',
            () async {
              final client = QueryClient();
              final calls = <Completer<int>>[];
              final tokens = <QueryCancelToken>[];
              Future<int> run(QueryCancelToken token) {
                token.markConsumed();
                tokens.add(token);
                final gate = Completer<int>();
                calls.add(gate);
                if (obeyCancel) {
                  token.whenCancelled.then((reason) {
                    if (!gate.isCompleted) gate.completeError(reason);
                  });
                }
                return gate.future;
              }

              final ordinary = QueryOptions<int>(
                key: QueryKey('ordinary'),
                policy: QueryPolicy(refetchOnMount: policy),
                query: (context) => run(context.cancelToken),
              );
              final pages = InfiniteQueryOptions<int, int>(
                key: QueryKey('infinite'),
                policy: QueryPolicy(refetchOnMount: policy),
                initialPageParam: 0,
                query: (context) => run(context.query.cancelToken),
                getNextPageParam: (_, _, last, _) => last + 1,
              );
              final query = infinite
                  ? client.query(pages.queryOptions)
                  : client.query(ordinary);
              // Use real observer detach/subscribe with no await between them.
              final observer = infinite
                  ? client.observe(pages.queryOptions)
                  : client.observe(ordinary);
              final remove = observer.subscribe((_) {});
              if (paging) {
                calls.single.complete(10);
                await query.promise;
                unawaited(
                  query
                      .fetch(
                        meta: const QueryFetchMeta(kind: 'infinite.forward'),
                      )
                      .then<void>((_) {}, onError: (_) {}),
                );
              }
              final oldRequest = query.promise!;
              final oldGate = calls.last;
              final oldToken = tokens.last;
              remove();
              final removeAgain = observer.subscribe((_) {});
              expect(oldToken.isCancelled, isTrue);
              expect(query.promise, isNot(same(oldRequest)));
              final restarts = !paging || policy != QueryRefetchPolicy.never;
              expect(calls, hasLength((paging ? 2 : 1) + (restarts ? 1 : 0)));
              await expectLater(
                oldRequest,
                throwsA(isA<QueryCancelledException>()),
              );
              if (!obeyCancel) oldGate.complete(99);
              if (restarts) {
                expect(query.state.fetchStatus, QueryFetchStatus.fetching);
                calls.last.complete(20);
                await query.promise;
              } else {
                expect(query.promise, isNull);
                expect(query.state.fetchStatus, QueryFetchStatus.idle);
                await Future<void>.value();
              }
              expect(
                infinite
                    ? (query.state.data as InfiniteData<int, int>).pages
                    : query.state.data,
                infinite ? [restarts ? 20 : 10] : 20,
              );
              removeAgain();
              observer.dispose();
              client.clear();
            },
          );
        }
      }
    }
  }
}
