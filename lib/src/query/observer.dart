import 'dart:async';

import 'client.dart';
import 'managers.dart';
import 'options.dart';
import 'query.dart';
import 'state.dart';

/// UI-facing projection of a query's two state axes.
final class QueryResult<T> {
  /// Creates a UI projection from [state] and freshness.
  const QueryResult({required this.state, required this.isStale});

  /// The complete cached state.
  final QueryState<T> state;

  /// Whether the current data is stale.
  final bool isStale;

  /// Whether a data value is present.
  bool get hasData => state.hasData;

  /// The current data value.
  T? get data => state.data;

  /// Returns current data or throws when absent.
  T get requireData => state.requireData;

  /// The latest query error.
  Object? get error => state.error;

  /// The stack trace for [error].
  StackTrace? get errorStackTrace => state.errorStackTrace;

  /// Whether no successful result has been stored yet.
  bool get isPending => state.status == QueryStatus.pending;

  /// Whether the query holds a successful result.
  bool get isSuccess => state.status == QueryStatus.success;

  /// Whether the latest fetch failed.
  bool get isError => state.status == QueryStatus.error;

  /// Whether a fetch is running.
  bool get isFetching => state.fetchStatus == QueryFetchStatus.fetching;

  /// Whether a fetch is paused.
  bool get isPaused => state.fetchStatus == QueryFetchStatus.paused;

  /// Whether the initial fetch is running.
  bool get isLoading => isPending && isFetching;

  /// Whether a fetch is running after data was stored.
  bool get isRefetching => isFetching && !isPending;

  /// Whether the initial fetch failed without data.
  bool get isLoadingError => isError && !hasData;

  /// Whether a refetch failed while retaining data.
  bool get isRefetchError => isError && hasData;

  @override
  bool operator ==(Object other) =>
      other is QueryResult<T> &&
      identical(other.state, state) &&
      other.isStale == isStale;

  @override
  int get hashCode => Object.hash(identityHashCode(state), isStale);
}

/// Reactive lifecycle around one [Query] cache entry.
final class QueryObserver<T> implements QueryObserverHandle {
  /// Creates an observer for [options] on [client].
  QueryObserver(this.client, QueryOptions<T> options) : _options = options {
    _query = client.query(options);
    _resolved = _query.options;
    _result = _createResult();
  }

  /// The client that owns the observed query.
  final QueryClient client;
  QueryOptions<T> _options;
  late ResolvedQueryOptions<T> _resolved;
  late Query<T> _query;
  late QueryResult<T> _result;
  final Set<void Function(QueryResult<T>)> _listeners =
      <void Function(QueryResult<T>)>{};
  Timer? _staleTimer;
  Timer? _refetchTimer;
  bool _disposed = false;

  /// The current query definition.
  QueryOptions<T> get options => _options;

  /// The current UI-facing result.
  QueryResult<T> get current => _listeners.isEmpty ? _createResult() : _result;

  @override
  bool get enabled => _resolved.enabled;

  @override
  bool get isStatic => _resolved.freshness is QueryStaticData;

  /// Subscribes to results and starts observer-driven fetching.
  QueryDispose subscribe(void Function(QueryResult<T> result) listener) {
    if (_disposed) throw StateError('QueryObserver is disposed.');
    final first = _listeners.isEmpty;
    _listeners.add(listener);
    if (first) {
      _query.addObserver(this);
      _updateTimers();
      if (_shouldFetchOnMount()) {
        unawaited(
          _query
              .fetch(options: _resolved, cancelRefetch: false)
              .then<void>((_) {}, onError: (_) {}),
        );
      }
    }
    listener(_result);
    return () {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        _clearTimers();
        _query.removeObserver(this);
      }
    };
  }

  /// Rebinds this observer to [value].
  void setOptions(QueryOptions<T> value) {
    if (_disposed) throw StateError('QueryObserver is disposed.');
    final oldQuery = _query;
    _options = value;
    _query = client.query(value);
    _resolved = _query.options;
    if (!identical(oldQuery, _query) && _listeners.isNotEmpty) {
      oldQuery.removeObserver(this);
      _query.addObserver(this);
    }
    _updateResult();
    _updateTimers();
    if (_listeners.isNotEmpty && _shouldFetchOnMount()) {
      unawaited(
        _query
            .fetch(options: _resolved, cancelRefetch: false)
            .then<void>((_) {}, onError: (_) {}),
      );
    }
  }

  /// Fetches the query and returns the resulting state projection.
  Future<QueryResult<T>> refetch({bool cancelRefetch = true}) async {
    try {
      await _query.fetch(options: _resolved, cancelRefetch: cancelRefetch);
    } on Object {
      // The returned result carries the error state.
    }
    return _result;
  }

  @override
  bool shouldRefetchOnFocus() => _shouldRefetch(_resolved.refetchOnFocus);

  @override
  bool shouldRefetchOnReconnect() =>
      _shouldRefetch(_resolved.refetchOnReconnect);

  @override
  void fetchForSignal() {
    unawaited(
      _query
          .fetch(options: _resolved, cancelRefetch: false)
          .then<void>((_) {}, onError: (_) {}),
    );
  }

  bool _shouldFetchOnMount() {
    if (!enabled) return false;
    if (!_query.state.hasData) return true;
    return _shouldRefetch(_resolved.refetchOnMount);
  }

  bool _shouldRefetch(QueryRefetchPolicy policy) {
    if (!enabled || _resolved.freshness is QueryStaticData) return false;
    return switch (policy) {
      QueryRefetchPolicy.never => false,
      QueryRefetchPolicy.stale => _query.isStale(_resolved.freshness),
      QueryRefetchPolicy.always => true,
    };
  }

  @override
  void onQueryUpdate() {
    _updateResult();
    _updateTimers();
  }

  QueryResult<T> _createResult() => QueryResult<T>(
    state: _query.state,
    isStale: _query.isStale(_resolved.freshness),
  );

  void _updateResult() {
    final next = _createResult();
    if (next == _result) return;
    _result = next;
    for (final listener in List<void Function(QueryResult<T>)>.of(_listeners)) {
      listener(next);
    }
  }

  void _updateTimers() {
    _staleTimer?.cancel();
    _staleTimer = null;
    _refetchTimer?.cancel();
    _refetchTimer = null;
    if (_listeners.isEmpty || client.options.environment.isServer) return;

    final freshness = _resolved.freshness;
    if (!_query.isStale(freshness) && freshness is QueryStaleAfter) {
      final updatedAt = _query.state.dataUpdatedAt!;
      final elapsed = client.scheduler.now().difference(updatedAt);
      final remaining =
          freshness.duration - elapsed + const Duration(milliseconds: 1);
      _staleTimer = client.scheduler.timer(remaining, _updateResult);
    }

    final interval = _resolved.refetchInterval;
    if (enabled && interval != null && interval > Duration.zero) {
      _refetchTimer = client.scheduler.timer(interval, _poll);
    }
  }

  void _poll() {
    if (_listeners.isEmpty || !enabled) return;
    if (_resolved.refetchInBackground || client.focusManager.isFocused) {
      unawaited(
        _query.fetch(options: _resolved).then<void>((_) {}, onError: (_) {}),
      );
    }
    _updateTimers();
  }

  void _clearTimers() {
    _staleTimer?.cancel();
    _refetchTimer?.cancel();
    _staleTimer = null;
    _refetchTimer = null;
  }

  /// Releases timers and query subscriptions held by this observer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearTimers();
    if (_listeners.isNotEmpty) _query.removeObserver(this);
    _listeners.clear();
  }
}
