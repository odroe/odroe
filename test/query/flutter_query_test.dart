import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/query.dart';

void main() {
  testWidgets('QueryBuilder fetches through the inherited client', (
    tester,
  ) async {
    final client = QueryClient();
    final options = QueryOptions<int>(
      key: QueryKey('widget'),
      policy: const QueryPolicy(gcTime: Duration.zero),
      query: (_) => 42,
    );

    await tester.pumpWidget(
      QueryClientProvider(
        client: client,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: QueryBuilder<int>(
            options: options,
            builder: (context, result) =>
                Text(result.hasData ? '${result.requireData}' : 'loading'),
          ),
        ),
      ),
    );
    expect(find.text('loading'), findsOneWidget);

    await tester.pump();
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('QuerySelector ignores changes outside its selection', (
    tester,
  ) async {
    final client = QueryClient();
    final options = QueryOptions<Map<String, int>>(
      key: QueryKey('selection'),
      policy: const QueryPolicy(freshness: QueryFreshness.never()),
      query: (_) => <String, int>{'count': 1, 'other': 1},
    );
    await client.fetchQuery(options);
    var builds = 0;

    await tester.pumpWidget(
      QueryClientProvider(
        client: client,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: QuerySelector<Map<String, int>, int>(
            options: options,
            select: (result) => result.requireData['count']!,
            builder: (context, count) {
              builds++;
              return Text('$count');
            },
          ),
        ),
      ),
    );
    expect(builds, 1);

    client.setQueryData<Map<String, int>>(
      options.key,
      (_) => <String, int>{'count': 1, 'other': 2},
    );
    await tester.pump();
    expect(builds, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    client.clear();
  });

  testWidgets('MutationBuilder uses replacement options', (tester) async {
    final client = QueryClient();
    late Future<int> Function(int) mutate;

    Widget app(MutationOptions<int, int, void> options) => QueryClientProvider(
      client: client,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MutationBuilder<int, int, void>(
          options: options,
          builder: (context, state, run, reset) {
            mutate = run;
            return Text(state.status.name);
          },
        ),
      ),
    );

    await tester.pumpWidget(
      app(
        MutationOptions<int, int, void>(
          gcTime: Duration.zero,
          mutation: (value, _) => value + 1,
        ),
      ),
    );
    expect(await mutate(1), 2);

    await tester.pumpWidget(
      app(
        MutationOptions<int, int, void>(
          gcTime: Duration.zero,
          mutation: (value, _) => value + 10,
        ),
      ),
    );
    expect(await mutate(1), 11);
  });

  testWidgets('InfiniteQueryBuilder uses replacement options', (tester) async {
    final client = QueryClient();

    Widget app(InfiniteQueryOptions<int, int> options) => QueryClientProvider(
      client: client,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: InfiniteQueryBuilder<int, int>(
          options: options,
          builder: (context, result, next, previous) => Text(
            result.query.hasData
                ? '${result.query.requireData.pages.single}'
                : 'loading',
          ),
        ),
      ),
    );

    InfiniteQueryOptions<int, int> options(String key, int value) =>
        InfiniteQueryOptions<int, int>(
          key: QueryKey(key),
          policy: const QueryPolicy(gcTime: Duration.zero),
          initialPageParam: 0,
          query: (_) => value,
          getNextPageParam: (_, _, _, _) => null,
        );

    await tester.pumpWidget(app(options('first-infinite', 1)));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(app(options('second-infinite', 2)));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
  });
}
