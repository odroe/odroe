import 'package:odroe/query_core.dart';

Future<void> main() async {
  final client = QueryClient();
  final options = QueryOptions<int>(
    key: QueryKey('post', <Object?>[42]),
    query: (_) => 42,
    policy: const QueryPolicy(freshness: QueryFreshness.never()),
  );
  await client.ensureQueryData(options);

  _run('QueryClient.getQueryData', 1000000, () {
    if (client.getQueryData<int>(options.key) != 42) {
      throw StateError('Unexpected cache value.');
    }
  });
  _run('QueryKey canonicalization', 100000, () {
    QueryKey('post', <Object?>[
      42,
      <String, Object?>{'preview': true, 'page': 2},
    ]).canonical;
  });

  final pending = QueryOptions<int>(
    key: QueryKey('deduplicated'),
    query: (_) async => 1,
  );
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < 10000; index++) {
    client.removeQueries(QueryFilter(key: pending.key, exact: true));
    await Future.wait<int>(<Future<int>>[
      client.fetchQuery(pending),
      client.fetchQuery(pending),
      client.fetchQuery(pending),
    ]);
  }
  stopwatch.stop();
  _print('3-way fetch deduplication', stopwatch.elapsed, 10000);
}

void _run(String name, int iterations, void Function() operation) {
  for (var index = 0; index < iterations ~/ 10; index++) {
    operation();
  }
  final stopwatch = Stopwatch()..start();
  for (var index = 0; index < iterations; index++) {
    operation();
  }
  stopwatch.stop();
  _print(name, stopwatch.elapsed, iterations);
}

void _print(String name, Duration elapsed, int iterations) {
  final nanoseconds = elapsed.inMicroseconds * 1000 / iterations;
  print('$name: ${nanoseconds.toStringAsFixed(1)} ns/op');
}
