import 'dart:async';

import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
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
}
