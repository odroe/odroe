import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('mutation optimistic context can roll query data back', () async {
    final client = QueryClient();
    final todos = QueryOptions<List<String>>(
      key: QueryKey('todos'),
      policy: const QueryPolicy(freshness: QueryFreshness.never()),
      query: (_) => <String>['existing'],
    );
    await client.fetchQuery(todos);
    final order = <String>[];

    final mutation = MutationOptions<void, String, List<String>>(
      key: QueryKey('addTodo'),
      mutation: (_, _) {
        order.add('mutation');
        throw StateError('write failed');
      },
      onMutate: (title, context) async {
        order.add('mutate');
        final previous = context.client.getQueryData<List<String>>(todos.key)!;
        context.client.setQueryData<List<String>>(
          todos.key,
          (current) => <String>[...current!, title],
        );
        return previous;
      },
      onError: (error, stackTrace, variables, previous, context) {
        order.add('error');
        context.client.setQueryData<List<String>>(todos.key, (_) => previous!);
      },
      onSettled: (_, _, _, _, _) => order.add('settled'),
    );

    await expectLater(
      client.executeMutation<void, String, List<String>>(mutation, 'new'),
      throwsStateError,
    );
    expect(client.getQueryData<List<String>>(todos.key), <String>['existing']);
    expect(order, <String>['mutate', 'mutation', 'error', 'settled']);
  });

  test('infinite query shares cache and refetches pages in order', () async {
    final client = QueryClient();
    final requested = <int>[];
    final options = InfiniteQueryOptions<List<int>, int>(
      key: QueryKey('feed'),
      initialPageParam: 0,
      maxPages: 2,
      query: (context) {
        requested.add(context.pageParam);
        return <int>[context.pageParam];
      },
      getNextPageParam: (_, _, last, _) => last >= 2 ? null : last + 1,
    );
    final observer = InfiniteQueryObserver<List<int>, int>(client, options);

    await client.fetchQuery(options.queryOptions);
    await observer.fetchNextPage();
    await observer.fetchNextPage();

    expect(observer.current.query.requireData.pages, <List<int>>[
      <int>[1],
      <int>[2],
    ]);
    expect(observer.current.hasNextPage, isFalse);

    requested.clear();
    if (observer.current.query.isStale) {
      await client.refetchQueries(QueryFilter(key: options.key, exact: true));
    }
    expect(requested, <int>[1, 2]);
    observer.dispose();
  });
}
