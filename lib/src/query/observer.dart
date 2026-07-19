// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'client.dart';
import 'managers.dart';
import 'options.dart';
import 'query.dart';
import 'state.dart';

/// UI-facing projection of a query's two state axes.
final class QueryResult<T> {
  const QueryResult({required this.state, required this.isStale});

  final QueryState<T> state;
  final bool isStale;

  bool get hasData => state.hasData;
  T? get data => state.data;
  T get requireData => state.requireData;
  Object? get error => state.error;
  StackTrace? get errorStackTrace => state.errorStackTrace;
  bool get isPending => state.status == QueryStatus.pending;
  bool get isSuccess => state.status == QueryStatus.success;
  bool get isError => state.status == QueryStatus.error;
  bool get isFetching => state.fetchStatus == QueryFetchStatus.fetching;
  bool get isPaused => state.fetchStatus == QueryFetchStatus.paused;
  bool get isLoading => isPending && isFetching;
  bool get isRefetching => isFetching && !isPending;
  bool get isLoadingError => isError && !hasData;
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
  QueryObserver(this.client, QueryOptions<T> options) : _options = options {
    _query = client.query(options);
    _resolved = _query.options;
    _result = _createResult();
  }

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

  QueryOptions<T> get options => _options;
  QueryResult<T> get current => _listeners.isEmpty ? _createResult() : _result;

  @override
  bool get enabled => _resolved.enabled;

  @override
  bool get isStatic => _resolved.freshness is QueryStaticData;

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

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearTimers();
    if (_listeners.isNotEmpty) _query.removeObserver(this);
    _listeners.clear();
  }
}
