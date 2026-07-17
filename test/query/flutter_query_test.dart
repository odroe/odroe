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
}
