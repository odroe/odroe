import 'package:odroe/query.dart';

final QueryKey<int> countKey = QueryKey<int>('count');

final QueryOptions<int> countOptions = QueryOptions<int>(
  key: countKey,
  query: (_) => 1,
);

final QueryOptions<int> contextualCountOptions = QueryOptions<int>(
  key: QueryKey('contextual-count'),
  query: (_) => 1,
);

int? readCount(QueryClient client) => client.getQueryData(countKey);

QueryState<int>? readCountState(QueryClient client) =>
    client.getQueryState(countKey);

int writeCount(QueryClient client) =>
    client.setQueryData(countKey, (previous) => (previous ?? 0) + 1);

Future<int> fetchCountExplicit(QueryClient client) =>
    client.fetchQuery<int>(countOptions);

Future<void> discardCount(QueryClient client) =>
    client.fetchQuery(countOptions);
