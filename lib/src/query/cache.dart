import 'managers.dart';
import 'query.dart';

/// Why a query cache subscription was notified.
enum QueryCacheEventType {
  /// A query entered the cache.
  added,

  /// A query left the cache.
  removed,

  /// A cached query state changed.
  updated,

  /// An observer started watching a query.
  observerAdded,

  /// An observer stopped watching a query.
  observerRemoved,
}

/// One query cache change.
final class QueryCacheEvent {
  /// Creates a cache event for [query].
  const QueryCacheEvent(this.type, this.query);

  /// The kind of cache change.
  final QueryCacheEventType type;

  /// The query affected by the change.
  final Query<dynamic> query;
}

/// Storage and event boundary for query state machines.
final class QueryCache {
  final Map<String, Query<dynamic>> _queries = <String, Query<dynamic>>{};
  final Set<void Function(QueryCacheEvent)> _listeners =
      <void Function(QueryCacheEvent)>{};

  /// Returns a cached query when its data type matches [T].
  Query<T>? get<T>(String canonicalKey) {
    final query = _queries[canonicalKey];
    return query is Query<T> ? query : null;
  }

  /// Returns a cached query without checking its data type.
  Query<dynamic>? getAny(String canonicalKey) => _queries[canonicalKey];

  /// All queries currently in the cache.
  Iterable<Query<dynamic>> get all => _queries.values;

  /// Adds [query] unless its key is already cached.
  void add(Query<dynamic> query) {
    if (_queries.putIfAbsent(query.key.canonical, () => query) == query) {
      notify(QueryCacheEvent(QueryCacheEventType.added, query));
    }
  }

  /// Removes and destroys [query] when it is the cached instance.
  void remove(Query<dynamic> query) {
    if (identical(_queries[query.key.canonical], query)) {
      query.destroy();
      _queries.remove(query.key.canonical);
      notify(QueryCacheEvent(QueryCacheEventType.removed, query));
    }
  }

  /// Removes every cached query.
  void clear() {
    for (final query in List<Query<dynamic>>.of(_queries.values)) {
      remove(query);
    }
  }

  /// Subscribes to cache events.
  QueryDispose subscribe(void Function(QueryCacheEvent event) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Sends [event] to current subscribers.
  void notify(QueryCacheEvent event) {
    for (final listener in List<void Function(QueryCacheEvent)>.of(
      _listeners,
    )) {
      listener(event);
    }
  }
}
