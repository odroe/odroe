import 'package:odroe/query.dart';
import 'package:test/test.dart';

void main() {
  test('hydrate restores data without replacing newer client data', () async {
    final source = QueryClient();
    final options = QueryOptions<Map<String, Object?>>(
      key: QueryKey('profile', <Object?>[7]),
      policy: const QueryPolicy(
        freshness: QueryFreshness.staleAfter(Duration(minutes: 5)),
      ),
      query: (_) => <String, Object?>{'name': 'Ada'},
    );
    await source.fetchQuery(options);
    final encoded = dehydrate(source).toJson();

    var calls = 0;
    final target = QueryClient();
    hydrate(target, DehydratedState.fromJson(encoded));
    final clientOptions = QueryOptions<Map<String, Object?>>(
      key: options.key,
      policy: options.policy,
      query: (_) {
        calls++;
        return <String, Object?>{'name': 'network'};
      },
    );

    expect(await target.fetchQuery(clientOptions), <String, Object?>{
      'name': 'Ada',
    });
    expect(calls, 0);

    target.setQueryData<Map<String, Object?>>(
      options.key,
      (_) => <String, Object?>{'name': 'newer'},
      updatedAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    hydrate(target, DehydratedState.fromJson(encoded));
    expect(
      target.getQueryData<Map<String, Object?>>(options.key),
      <String, Object?>{'name': 'newer'},
    );
  });
}
