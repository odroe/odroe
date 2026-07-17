import 'dart:async';

import 'package:odroe/query_core.dart';
import 'package:odroe/router_core.dart';
import 'package:test/test.dart';

void main() {
  test('matched loaders share one QueryClient and deduplicate work', () async {
    final gate = Completer<String>();
    var calls = 0;
    final shared = QueryOptions<String>(
      key: QueryKey('route-data'),
      query: (_) {
        calls++;
        return gate.future;
      },
    );
    final parent = AppRoute<NoParams, NoSearch, String>(
      path: '/',
      terminal: false,
      load: (context) => context.query.ensureQueryData(shared),
    );
    final child = AppRoute<NoParams, NoSearch, String>(
      path: 'child',
      load: (context) => context.query.ensureQueryData(shared),
    );
    final matches = RouteMatcher(<AnyAppRoute>[
      parent.withChildren(<AnyAppRoute>[child]),
    ]).match(Uri.parse('/child'))!;
    final client = QueryClient();

    final loading = matches.loadAll(query: client);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    gate.complete('shared');
    final results = await loading;
    expect(results[parent.identity]!.data, 'shared');
    expect(results[child.identity]!.data, 'shared');
  });
}
