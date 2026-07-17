// ignore_for_file: public_member_api_docs

import 'managers.dart';
import 'query.dart';

/// Why a query cache subscription was notified.
enum QueryCacheEventType {
  added,
  removed,
  updated,
  observerAdded,
  observerRemoved,
}

/// One query cache change.
final class QueryCacheEvent {
  const QueryCacheEvent(this.type, this.query);

  final QueryCacheEventType type;
  final Query<dynamic> query;
}

/// Storage and event boundary for query state machines.
final class QueryCache {
  final Map<String, Query<dynamic>> _queries = <String, Query<dynamic>>{};
  final Set<void Function(QueryCacheEvent)> _listeners =
      <void Function(QueryCacheEvent)>{};

  Query<T>? get<T>(String canonicalKey) {
    final query = _queries[canonicalKey];
    return query is Query<T> ? query : null;
  }

  Query<dynamic>? getAny(String canonicalKey) => _queries[canonicalKey];

  List<Query<dynamic>> get all =>
      List<Query<dynamic>>.unmodifiable(_queries.values);

  void add(Query<dynamic> query) {
    if (_queries.putIfAbsent(query.key.canonical, () => query) == query) {
      notify(QueryCacheEvent(QueryCacheEventType.added, query));
    }
  }

  void remove(Query<dynamic> query) {
    if (identical(_queries[query.key.canonical], query)) {
      query.destroy();
      _queries.remove(query.key.canonical);
      notify(QueryCacheEvent(QueryCacheEventType.removed, query));
    }
  }

  void clear() {
    for (final query in List<Query<dynamic>>.of(_queries.values)) {
      remove(query);
    }
  }

  QueryDispose subscribe(void Function(QueryCacheEvent event) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void notify(QueryCacheEvent event) {
    for (final listener in List<void Function(QueryCacheEvent)>.of(
      _listeners,
    )) {
      listener(event);
    }
  }
}
